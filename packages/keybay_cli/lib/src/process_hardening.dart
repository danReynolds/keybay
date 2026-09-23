import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Keeps crash artifacts from persisting an open session's secrets.
///
/// A session holds its store key, and the TUI may hold revealed plaintext, so a
/// core file would outlive the operation that authorized them. Every command
/// sets its soft core-file limit to zero; on Linux the process also becomes
/// non-dumpable, which prevents kernel core dumps even through a core-pattern
/// pipe and denies same-user ptrace and `/proc/PID/mem`. The hard limit is
/// unchanged so `keybay run` can hand its program the caller's original soft
/// limit immediately before `execve`, which itself restores dumpability.
abstract final class ProcessHardening {
  static int? _callerSoftCoreLimit;

  /// Applies the process policy once and remembers the caller's soft limit.
  static void apply() {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final limit = calloc<_Rlimit>();
    try {
      if (_getrlimit(_rlimitCore, limit) != 0) return;
      _callerSoftCoreLimit ??= limit.ref.current;
      limit.ref.current = 0;
      _setrlimit(_rlimitCore, limit);
    } finally {
      calloc.free(limit);
    }
    if (Platform.isLinux) _prctl(_prSetDumpable, 0, 0, 0, 0);
  }

  /// Gives an exec'd program the caller's original soft core limit.
  static void restoreForExec() => _setSoftCoreLimit(_callerSoftCoreLimit);

  /// Reinstates the policy when `execve` fails and Keybay continues.
  static void reapplyAfterFailedExec() => _setSoftCoreLimit(0);

  /// The current soft core-file limit, for regression tests.
  static int? get softCoreLimit {
    if (!Platform.isMacOS && !Platform.isLinux) return null;
    final limit = calloc<_Rlimit>();
    try {
      return _getrlimit(_rlimitCore, limit) == 0 ? limit.ref.current : null;
    } finally {
      calloc.free(limit);
    }
  }

  /// Linux dumpability (0 when disabled), for regression tests.
  static int? get dumpable =>
      Platform.isLinux ? _prctl(_prGetDumpable, 0, 0, 0, 0) : null;

  static void _setSoftCoreLimit(int? soft) {
    if (soft == null) return;
    final limit = calloc<_Rlimit>();
    try {
      if (_getrlimit(_rlimitCore, limit) != 0) return;
      limit.ref.current = soft;
      _setrlimit(_rlimitCore, limit);
    } finally {
      calloc.free(limit);
    }
  }
}

// RLIMIT_CORE is 4 on both Darwin and Linux; rlim_t is 64-bit on every
// supported ABI. PR_GET_DUMPABLE/PR_SET_DUMPABLE are Linux prctl options.
const int _rlimitCore = 4;
const int _prGetDumpable = 3;
const int _prSetDumpable = 4;

final class _Rlimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

final DynamicLibrary _libc = DynamicLibrary.process();

final int Function(int, Pointer<_Rlimit>) _getrlimit = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_Rlimit>),
      int Function(int, Pointer<_Rlimit>)
    >('getrlimit');

final int Function(int, Pointer<_Rlimit>) _setrlimit = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_Rlimit>),
      int Function(int, Pointer<_Rlimit>)
    >('setrlimit');

// glibc declares `int prctl(int option, ...)` and reads four unsigned longs.
final int Function(int, int, int, int, int) _prctl = _libc
    .lookupFunction<
      Int32 Function(
        Int32,
        VarArgs<(UnsignedLong, UnsignedLong, UnsignedLong, UnsignedLong)>,
      ),
      int Function(int, int, int, int, int)
    >('prctl');

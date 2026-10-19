import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:keybay/keybay.dart';

/// Keeps crash artifacts from persisting an open session's secrets.
///
/// A session holds its store key, and the TUI may hold revealed plaintext, so a
/// core file would outlive the operation that authorized them. Every command
/// applies the SDK's [Keybay.hardenProcess] before anything else. This class
/// adds only the `keybay run` hand-off: the SDK leaves the hard core limit
/// unchanged, so the program gets the caller's original soft limit immediately
/// before `execve`, which itself restores dumpability.
abstract final class ProcessHardening {
  static int? _callerSoftCoreLimit;

  /// Remembers the caller's soft core limit once, then hardens the process.
  /// Callers must not handle secrets when the result has failed.
  static KeybayProcessHardening apply() {
    _callerSoftCoreLimit ??= _softCoreLimit();
    return Keybay.hardenProcess();
  }

  /// Gives an exec'd program the caller's original soft core limit.
  static void restoreForExec() {
    final soft = _callerSoftCoreLimit;
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

  /// Reinstates the policy when `execve` fails and Keybay continues.
  static void reapplyAfterFailedExec() => Keybay.hardenProcess();

  /// The error a command prints before refusing a failed [hardening].
  static List<String> failureLines(KeybayProcessHardening hardening) => [
    'error: could not harden this process.',
    for (final (name, measure) in [
      ('core dumps', hardening.coreDumps),
      ('debugger attach', hardening.debuggerAttach),
    ])
      if (measure.status == KeybayHardeningStatus.failed)
        '  $name: ${measure.detail}.',
  ];

  static int? _softCoreLimit() {
    if (!Platform.isMacOS && !Platform.isLinux) return null;
    final limit = calloc<_Rlimit>();
    try {
      return _getrlimit(_rlimitCore, limit) == 0 ? limit.ref.current : null;
    } finally {
      calloc.free(limit);
    }
  }
}

// RLIMIT_CORE is 4 on both Darwin and Linux; rlim_t is 64-bit on every
// supported ABI.
const int _rlimitCore = 4;

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

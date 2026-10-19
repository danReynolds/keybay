import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Whether one protection is in effect after `Keybay.hardenProcess()`.
enum KeybayHardeningStatus {
  /// Keybay applied the protection and confirmed that it is in effect.
  applied,

  /// Keybay attempted the protection and it is not in effect. Do not handle
  /// secrets as though it were.
  failed,

  /// Keybay does not attempt this protection on this platform. The detail
  /// says what governs it instead.
  notAttempted,
}

/// One protection reported by [KeybayProcessHardening].
final class KeybayHardeningMeasure {
  const KeybayHardeningMeasure._(this.status, this.detail);

  /// Whether the protection is in effect.
  final KeybayHardeningStatus status;

  /// What Keybay did, or why the protection is not in effect. For logs and
  /// diagnostics; branch on [status].
  final String detail;

  @override
  String toString() => '${status.name} ($detail)';
}

/// What `Keybay.hardenProcess()` changed in the current process, and what it
/// observed about the session around it.
///
/// Keybay reports a failure and never substitutes a weaker policy. The
/// application decides whether to continue; [failed] is true when it should
/// not handle secrets.
final class KeybayProcessHardening {
  const KeybayProcessHardening._({
    required this.coreDumps,
    required this.debuggerAttach,
    required this.ptraceScope,
    required this.ptraceUnrestricted,
    required this.x11Session,
  });

  /// Whether a crash can write this process's memory to a core file.
  ///
  /// Applied on macOS (soft `RLIMIT_CORE` 0) and on Linux (non-dumpable plus
  /// soft `RLIMIT_CORE` 0). The hard limit is unchanged.
  final KeybayHardeningMeasure coreDumps;

  /// Whether other programs running as the same user can attach a debugger
  /// or read this process's memory through `/proc/<pid>/mem`.
  ///
  /// Applied on Linux only, by `prctl(PR_SET_DUMPABLE, 0)`. Failed if a
  /// process was already tracing this one, since that attachment survives.
  /// Not attempted on macOS, where the code signature's Hardened Runtime
  /// decides debugger access.
  final KeybayHardeningMeasure debuggerAttach;

  /// Linux Yama `kernel.yama.ptrace_scope`: 0 lets any program running as the
  /// same user attach to any of that user's processes that are still
  /// dumpable; 1 limits attach to a process's ancestors; 2 to administrators;
  /// 3 forbids it. Null off Linux, or when Yama is absent or its setting
  /// cannot be read.
  final int? ptraceScope;

  /// On Linux, true unless Yama is confirmed to restrict ptrace (scope 1 or
  /// higher). Without that restriction, any program running as the same user
  /// can attach to this process before `hardenProcess` runs, and an
  /// attachment made then survives the call. Always false off Linux.
  final bool ptraceUnrestricted;

  /// Whether this is a Linux X11 session, where any X client can read the
  /// keystrokes typed into another. Warn before asking for a passphrase or a
  /// security key's PIN.
  ///
  /// True when `XDG_SESSION_TYPE` is `x11`, or `DISPLAY` is set and
  /// `WAYLAND_DISPLAY` is not. Always false off Linux.
  final bool x11Session;

  /// Whether a protection Keybay attempted on this platform is not in effect.
  bool get failed =>
      coreDumps.status == KeybayHardeningStatus.failed ||
      debuggerAttach.status == KeybayHardeningStatus.failed;

  @override
  String toString() =>
      'KeybayProcessHardening(coreDumps: ${coreDumps.status.name}, '
      'debuggerAttach: ${debuggerAttach.status.name}, '
      'ptraceScope: $ptraceScope, x11Session: $x11Session)';
}

/// Applies Keybay's process policy and reports the result. Never throws.
///
/// macOS: soft `RLIMIT_CORE` 0. Linux: `prctl(PR_SET_DUMPABLE, 0)` and soft
/// `RLIMIT_CORE` 0; a non-dumpable process is never dumped, even through a
/// core-pattern pipe, which ignores the size limit, and same-user ptrace and
/// `/proc/<pid>/mem` need `CAP_SYS_PTRACE`. iOS and Android: nothing; the
/// operating system governs app processes. The hard core limit is left
/// unchanged, so a host that execs another program can restore its soft limit.
KeybayProcessHardening applyProcessHardening() {
  if (Platform.isLinux) {
    final dumpable = _attempt(() {
      _prctl(_prSetDumpable, 0, 0, 0, 0);
      return _prctl(_prGetDumpable, 0, 0, 0, 0);
    });
    // Belt and braces for the file core pattern; dumpability is decisive.
    _attempt(() => _setSoftCoreLimit(0));
    final applied = dumpable == 0;
    // Non-dumpability refuses new attachments; one made earlier survives.
    final tracer = linuxTracerPid();
    final scope = linuxPtraceScope();
    return KeybayProcessHardening._(
      coreDumps: applied
          ? const KeybayHardeningMeasure._(
              KeybayHardeningStatus.applied,
              'non-dumpable (PR_SET_DUMPABLE 0) with soft RLIMIT_CORE 0',
            )
          : KeybayHardeningMeasure._(
              KeybayHardeningStatus.failed,
              'PR_SET_DUMPABLE 0 did not take effect (dumpable: $dumpable), '
              'so a core-pattern pipe can still dump this process',
            ),
      debuggerAttach: !applied
          ? KeybayHardeningMeasure._(
              KeybayHardeningStatus.failed,
              'PR_SET_DUMPABLE 0 did not take effect (dumpable: $dumpable)',
            )
          : tracer == null
          ? const KeybayHardeningMeasure._(
              KeybayHardeningStatus.failed,
              'could not read TracerPid from /proc/self/status, so a '
              'debugger attached before the call cannot be ruled out',
            )
          : tracer != 0
          ? KeybayHardeningMeasure._(
              KeybayHardeningStatus.failed,
              'process $tracer was already tracing this process and stays '
              'attached',
            )
          : const KeybayHardeningMeasure._(
              KeybayHardeningStatus.applied,
              'non-dumpable (PR_SET_DUMPABLE 0) and untraced: same-user '
              'ptrace and /proc/<pid>/mem need CAP_SYS_PTRACE',
            ),
      ptraceScope: scope,
      ptraceUnrestricted: scope == null || scope == 0,
      x11Session: isX11Session(Platform.environment),
    );
  }
  if (Platform.isMacOS) {
    final soft = _attempt(() {
      _setSoftCoreLimit(0);
      return softCoreLimit;
    });
    return KeybayProcessHardening._(
      coreDumps: soft == 0
          ? const KeybayHardeningMeasure._(
              KeybayHardeningStatus.applied,
              'soft RLIMIT_CORE 0',
            )
          : KeybayHardeningMeasure._(
              KeybayHardeningStatus.failed,
              'soft RLIMIT_CORE is ${soft ?? 'unreadable'}, not 0',
            ),
      debuggerAttach: const KeybayHardeningMeasure._(
        KeybayHardeningStatus.notAttempted,
        'on macOS the code signature decides debugger access: a Hardened '
        'Runtime build without get-task-allow refuses same-user debuggers. '
        'Keybay does not use PT_DENY_ATTACH, which does not stop task-port '
        'memory reads',
      ),
      ptraceScope: null,
      ptraceUnrestricted: false,
      x11Session: false,
    );
  }
  final platform = Platform.isIOS || Platform.isAndroid
      ? 'the operating system governs app processes on '
            '${Platform.operatingSystem}; Keybay changes nothing'
      : 'Keybay does not support ${Platform.operatingSystem}';
  return KeybayProcessHardening._(
    coreDumps: KeybayHardeningMeasure._(
      KeybayHardeningStatus.notAttempted,
      platform,
    ),
    debuggerAttach: KeybayHardeningMeasure._(
      KeybayHardeningStatus.notAttempted,
      platform,
    ),
    ptraceScope: null,
    ptraceUnrestricted: false,
    x11Session: false,
  );
}

/// Whether [environment] describes an X11 session. Linux callers only.
bool isX11Session(Map<String, String> environment) {
  bool present(String name) => (environment[name] ?? '').isNotEmpty;
  return environment['XDG_SESSION_TYPE'] == 'x11' ||
      present('DISPLAY') && !present('WAYLAND_DISPLAY');
}

/// Yama's `ptrace_scope` as returned by [read], or null if it is absent,
/// unreadable or out of range.
int? linuxPtraceScope({String Function() read = _readPtraceScope}) {
  try {
    final scope = int.tryParse(read().trim());
    return scope != null && scope >= 0 && scope <= 3 ? scope : null;
  } on Object {
    return null;
  }
}

String _readPtraceScope() =>
    File('/proc/sys/kernel/yama/ptrace_scope').readAsStringSync();

/// The `TracerPid` in `/proc/self/status` as returned by [read]: 0 when no
/// process traces this one, or null if it is absent or unreadable.
int? linuxTracerPid({String Function() read = _readStatus}) {
  try {
    for (final line in read().split('\n')) {
      if (!line.startsWith('TracerPid:')) continue;
      final tracer = int.tryParse(line.substring('TracerPid:'.length).trim());
      return tracer != null && tracer >= 0 ? tracer : null;
    }
    return null;
  } on Object {
    return null;
  }
}

String _readStatus() => File('/proc/self/status').readAsStringSync();

/// The current soft core-file limit on macOS and Linux, otherwise null. For
/// regression tests.
int? get softCoreLimit {
  if (!Platform.isMacOS && !Platform.isLinux) return null;
  final limit = calloc<_Rlimit>();
  try {
    return _getrlimit(_rlimitCore, limit) == 0 ? limit.ref.current : null;
  } finally {
    calloc.free(limit);
  }
}

/// Linux dumpability (0 when disabled), otherwise null. For regression tests.
int? get linuxDumpable =>
    Platform.isLinux ? _prctl(_prGetDumpable, 0, 0, 0, 0) : null;

T? _attempt<T>(T Function() action) {
  try {
    return action();
  } on Object {
    return null;
  }
}

void _setSoftCoreLimit(int soft) {
  final limit = calloc<_Rlimit>();
  try {
    if (_getrlimit(_rlimitCore, limit) != 0) return;
    limit.ref.current = soft;
    _setrlimit(_rlimitCore, limit);
  } finally {
    calloc.free(limit);
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

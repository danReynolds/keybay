import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Whether one protection is in effect after `Keybay.hardenProcess()`.
enum KeybayHardeningStatus {
  /// Keybay applied the protection and confirmed that it is in effect.
  applied,

  /// Keybay attempted the protection and could not confirm that it is in
  /// effect. Do not handle secrets as though it were.
  failed,

  /// Keybay does not attempt this protection on this platform. The detail
  /// says what governs it instead.
  notAttempted,
}

/// Why a protection is [KeybayHardeningStatus.failed], for applications that
/// knowingly accept one cause, such as a Flatpak app and [userNamespace].
enum KeybayHardeningCause {
  /// The kernel did not keep Keybay's setting: the process stayed dumpable, or
  /// the soft core-file limit is not 0.
  settingRejected,

  /// Keybay could not read what it needs to confirm the protection.
  unreadable,

  /// A process was already tracing one of this process's threads, and that
  /// attachment survives.
  traced,

  /// The process runs in a user namespace (Flatpak, toolbox, a container).
  /// Programs its owner runs outside it keep `CAP_SYS_PTRACE` over this
  /// process. Keybay reports this cause only when nothing else failed.
  userNamespace,
}

/// One protection reported by [KeybayProcessHardening].
final class KeybayHardeningMeasure {
  const KeybayHardeningMeasure._(this.status, this.detail, [this.cause]);

  /// Whether the protection is in effect.
  final KeybayHardeningStatus status;

  /// Why the protection failed; null unless [status] is
  /// [KeybayHardeningStatus.failed].
  final KeybayHardeningCause? cause;

  /// What Keybay did, or why the protection is not confirmed in effect. For
  /// logs and diagnostics; branch on [status].
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
    required this.yamaUnrestricted,
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
  /// Applied on Linux only, by `prctl(PR_SET_DUMPABLE, 0)`. Failed when a
  /// process was already tracing one of this process's threads, since that
  /// attachment survives, and in a user namespace such as Flatpak's, whose
  /// owner's programs outside it keep `CAP_SYS_PTRACE` over this process. Not
  /// attempted on macOS, where the code signature's Hardened Runtime decides
  /// debugger access.
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
  /// attachment made then survives the call. Inside a user namespace Yama
  /// does not restrict its owner's programs outside it; see [debuggerAttach].
  /// Always false off Linux.
  final bool yamaUnrestricted;

  /// Whether this is a Linux X11 session, where any X client can read the
  /// keystrokes typed into another. Warn before asking for a passphrase or a
  /// security key's PIN.
  ///
  /// True when `XDG_SESSION_TYPE` is `x11`, or `DISPLAY` is set and
  /// `WAYLAND_DISPLAY` is not. Always false off Linux.
  final bool x11Session;

  /// Whether a protection Keybay attempted on this platform is not confirmed
  /// in effect.
  bool get failed =>
      coreDumps.status == KeybayHardeningStatus.failed ||
      debuggerAttach.status == KeybayHardeningStatus.failed;

  @override
  String toString() =>
      'KeybayProcessHardening(coreDumps: $coreDumps, '
      'debuggerAttach: $debuggerAttach, ptraceScope: $ptraceScope, '
      'yamaUnrestricted: $yamaUnrestricted, x11Session: $x11Session)';
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
    // Read after the process is non-dumpable, so no new tracer can slip in.
    return linuxHardeningResult(
      dumpable: dumpable,
      initialUserNamespace: linuxInitialUserNamespace(),
      tracer: linuxTracerPid(),
      ptraceScope: linuxPtraceScope(),
      environment: Platform.environment,
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
              soft == null
                  ? KeybayHardeningCause.unreadable
                  : KeybayHardeningCause.settingRejected,
            ),
      debuggerAttach: const KeybayHardeningMeasure._(
        KeybayHardeningStatus.notAttempted,
        'on macOS the code signature decides debugger access: a Hardened '
        'Runtime build without get-task-allow refuses same-user debuggers. '
        'Keybay does not use PT_DENY_ATTACH, which does not stop task-port '
        'memory reads',
      ),
      ptraceScope: null,
      yamaUnrestricted: false,
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
    yamaUnrestricted: false,
    x11Session: false,
  );
}

/// The Linux result for what the process observed after `PR_SET_DUMPABLE`:
/// its [dumpable] value, whether it is in the [initialUserNamespace], the
/// first nonzero [tracer] of any of its threads, Yama's [ptraceScope] and its
/// [environment]. Null means unreadable.
KeybayProcessHardening linuxHardeningResult({
  required int? dumpable,
  required bool? initialUserNamespace,
  required int? tracer,
  required int? ptraceScope,
  required Map<String, String> environment,
}) {
  final nonDumpable = dumpable == 0;
  final dumpableCause = dumpable == null
      ? KeybayHardeningCause.unreadable
      : KeybayHardeningCause.settingRejected;
  KeybayHardeningMeasure failed(KeybayHardeningCause cause, String detail) =>
      KeybayHardeningMeasure._(KeybayHardeningStatus.failed, detail, cause);
  // The namespace is checked last, so its cause means nothing else failed.
  return KeybayProcessHardening._(
    coreDumps: nonDumpable
        ? const KeybayHardeningMeasure._(
            KeybayHardeningStatus.applied,
            'non-dumpable (PR_SET_DUMPABLE 0) with soft RLIMIT_CORE 0',
          )
        : failed(
            dumpableCause,
            'PR_SET_DUMPABLE 0 did not take effect (dumpable: $dumpable), '
            'so a core-pattern pipe can still dump this process',
          ),
    debuggerAttach: !nonDumpable
        ? failed(
            dumpableCause,
            'the process is still dumpable (dumpable: $dumpable)',
          )
        : tracer == null
        ? failed(
            KeybayHardeningCause.unreadable,
            'could not read TracerPid for every thread, so a debugger '
            'attached before the call cannot be ruled out',
          )
        : tracer != 0
        ? failed(
            KeybayHardeningCause.traced,
            'process $tracer was already tracing a thread of this process '
            'and stays attached',
          )
        : initialUserNamespace == null
        ? failed(
            KeybayHardeningCause.unreadable,
            'could not read /proc/self/uid_map, so a user namespace whose '
            'owner keeps CAP_SYS_PTRACE over this process cannot be ruled out',
          )
        : !initialUserNamespace
        ? failed(
            KeybayHardeningCause.userNamespace,
            'this process runs in a user namespace; programs its owner runs '
            'outside it keep CAP_SYS_PTRACE over this process. The owner is '
            'you in Flatpak, toolbox or a rootless container, and root in '
            'LXD, Incus or userns-remapped Docker; Keybay cannot tell which',
          )
        : const KeybayHardeningMeasure._(
            KeybayHardeningStatus.applied,
            'non-dumpable (PR_SET_DUMPABLE 0) and untraced: same-user ptrace '
            'and /proc/<pid>/mem need CAP_SYS_PTRACE',
          ),
    ptraceScope: ptraceScope,
    yamaUnrestricted: ptraceScope == null || ptraceScope == 0,
    x11Session: isX11Session(environment),
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

/// Whether the `uid_map` returned by [read] is the initial user namespace's
/// identity map, or null if it is unreadable. In any other user namespace,
/// programs its owner runs outside it hold every capability inside it.
bool? linuxInitialUserNamespace({String Function() read = _readUidMap}) {
  try {
    final lines = read()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.length == 1 &&
        lines.single.split(RegExp(r'\s+')).join(' ') == '0 0 4294967295';
  } on Object {
    return null;
  }
}

String _readUidMap() =>
    latin1.decode(File('/proc/self/uid_map').readAsBytesSync());

/// The first nonzero `TracerPid` among the thread [statuses], 0 when no
/// process traces any thread, or null if any is unreadable or none was read.
///
/// ptrace attaches to one thread at a time, and a tracer holding any thread
/// can read the whole address space, so every thread is checked.
int? linuxTracerPid({List<String> Function() statuses = _threadStatuses}) {
  try {
    final all = statuses();
    if (all.isEmpty) return null;
    var tracer = 0;
    for (final status in all) {
      final value = _tracerPid(status);
      if (value == null) return null;
      if (tracer == 0) tracer = value;
    }
    return tracer;
  } on Object {
    return null;
  }
}

int? _tracerPid(String status) {
  for (final line in status.split('\n')) {
    if (!line.startsWith('TracerPid:')) continue;
    final tracer = int.tryParse(line.substring('TracerPid:'.length).trim());
    return tracer != null && tracer >= 0 ? tracer : null;
  }
  return null;
}

// Status files are read as bytes: the Name line holds the executable's name
// cut at 15 bytes, which need not be valid UTF-8.
List<String> _threadStatuses() {
  final statuses = <String>[];
  for (final task in Directory('/proc/self/task').listSync()) {
    try {
      statuses.add(
        latin1.decode(File('${task.path}/status').readAsBytesSync()),
      );
    } on FileSystemException catch (error) {
      // A thread that exited after the listing has no tracer left to report.
      final code = error.osError?.errorCode;
      if (code == _enoent || code == _esrch) continue;
      rethrow;
    }
  }
  return statuses;
}

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
const int _enoent = 2;
const int _esrch = 3;

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

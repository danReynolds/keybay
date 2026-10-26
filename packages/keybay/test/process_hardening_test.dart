@Tags(['unit'])
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/process_hardening.dart';
import 'package:test/test.dart';

typedef C = KeybayHardeningCause;

void main() {
  test('a release build disables core files and, on Linux, dumpability', () {
    // Start from a caller that allows core files and, on Linux, is dumpable;
    // a default limit of 0 would let every expectation pass even if nothing
    // were changed.
    final hard = _preserveProcessState();
    if (hard == 0) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    final caller = hard > 0 && hard < 1 << 20 ? hard : 1 << 20;
    _setSoftCoreLimit(caller);
    if (Platform.isLinux) {
      expect(_prctl(_prSetDumpable, 1, 0, 0, 0), 0);
      expect(linuxDumpable, 1);
      // A child running as the same user reads a dumpable parent's /proc
      // entries; that read is the positive control for the one below.
      expect(_childReads('/proc/$pid/environ'), isTrue);
    }

    final result = applyProcessHardening(release: true);

    expect(result.debugBuild, isFalse);
    expect(result.coreDumps.status, KeybayHardeningStatus.applied);
    expect(softCoreLimit, 0);
    expect(_coreLimits().$2, hard, reason: 'the hard limit is unchanged');
    if (Platform.isLinux) {
      expect(linuxDumpable, 0);
      // A user namespace's root keeps CAP_SYS_PTRACE over its processes, so
      // the denials hold only in the initial one.
      if (linuxInitialUserNamespace() == true) {
        expect(_childReads('/proc/$pid/environ'), isFalse);
        // Opening mem needs attach rights, which Yama may already refuse a
        // child, so only the denial is asserted.
        expect(_childOpens('/proc/$pid/mem'), isFalse);
      }
      // A user namespace (toolbox, a rootless container) cannot confirm it.
      expect(
        result.debuggerAttach.status,
        linuxInitialUserNamespace() == true
            ? KeybayHardeningStatus.applied
            : KeybayHardeningStatus.failed,
        reason: '$result',
      );
    } else {
      expect(result.failed, isFalse, reason: '$result');
      expect(result.debuggerAttach.status, KeybayHardeningStatus.notAttempted);
      expect(result.debuggerAttach.detail, contains('PT_DENY_ATTACH'));
    }

    // Repeating the call is harmless and reports the same policy.
    final again = applyProcessHardening(release: true);
    expect(again.coreDumps.status, result.coreDumps.status);
    expect(again.debuggerAttach.status, result.debuggerAttach.status);
  }, testOn: 'mac-os || linux');

  test('this debug test run leaves debuggers allowed', () {
    expect(releaseBuild, isFalse, reason: 'dart test runs JIT');
    expect(hardeningEnabled, isTrue);
    final hard = _preserveProcessState();
    if (hard == 0) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    _setSoftCoreLimit(hard > 0 && hard < 1 << 20 ? hard : 1 << 20);
    if (Platform.isLinux) expect(_prctl(_prSetDumpable, 1, 0, 0, 0), 0);

    // The defaults are this build's: a JIT test run is a debug build.
    final result = applyProcessHardening();

    expect(result.debugBuild, isTrue);
    expect(result.disabled, isFalse);
    expect(result.failed, isFalse, reason: '$result');
    expect(softCoreLimit, 0);
    expect(result.debuggerAttach.status, KeybayHardeningStatus.notAttempted);
    if (Platform.isLinux) {
      expect(linuxDumpable, 1, reason: 'debuggers can still attach');
      expect(result.coreDumps.status, KeybayHardeningStatus.notAttempted);
      expect(result.ptraceScope, linuxPtraceScope());
      expect(
        result.yamaUnrestricted,
        result.ptraceScope == null || result.ptraceScope == 0,
      );
    } else {
      expect(result.coreDumps.status, KeybayHardeningStatus.applied);
      expect(result.ptraceScope, isNull);
      expect(result.yamaUnrestricted, isFalse);
    }
    // The logged form carries each measure's reason.
    expect(result.toString(), contains(result.coreDumps.detail));
    expect(result.toString(), contains(result.debuggerAttach.detail));
  }, testOn: 'mac-os || linux');

  test('open hardens the process before anything else', () async {
    final hard = _preserveProcessState();
    if (hard == 0) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    _setSoftCoreLimit(hard > 0 && hard < 1 << 20 ? hard : 1 << 20);
    // A method ID without a credential fails before any platform access.
    await expectLater(
      Keybay.open(methodId: 'not-a-method'),
      throwsA(
        isA<KeybayException>().having(
          (error) => error.code,
          'code',
          KeybayErrorCode.invalidAuthInput,
        ),
      ),
    );
    expect(softCoreLimit, 0);
  }, testOn: 'mac-os || linux');

  test('a build that turns hardening off changes nothing', () {
    final hard = _preserveProcessState();
    final caller = hard == 0
        ? 0
        : (hard > 0 && hard < 1 << 20 ? hard : 1 << 20);
    for (final release in [false, true]) {
      // Other test files share this process and may open, which sets the soft
      // limit, so read it back immediately.
      _setSoftCoreLimit(caller);
      final dumpable = linuxDumpable;
      final result = applyProcessHardening(release: release, enabled: false);
      if (Platform.isMacOS || Platform.isLinux) expect(softCoreLimit, caller);
      expect(linuxDumpable, dumpable);
      expect(result.disabled, isTrue);
      expect(result.failed, isFalse);
      expect(result.coreDumps.status, KeybayHardeningStatus.notAttempted);
      expect(result.debuggerAttach.status, KeybayHardeningStatus.notAttempted);
      expect(result.coreDumps.detail, contains('keybay.process_hardening'));
    }
  });

  test('the status is recorded, and a failure stays recorded', () {
    _preserveProcessState();
    final first = Keybay.processHardening;
    expect(identical(Keybay.processHardening, first), isTrue);

    KeybayProcessHardening linux({int tracer = 0}) => linuxHardeningResult(
      dumpable: 0,
      initialUserNamespace: true,
      tracer: tracer,
      ptraceScope: 1,
    );
    final applied = linux();
    final traced = linux(tracer: 4242);
    expect(worseHardening(null, applied), same(applied));
    expect(worseHardening(applied, traced), same(traced));
    expect(worseHardening(traced, applied), same(traced));
  });

  test('a Linux debug build reports both protections not attempted', () {
    final result = linuxDebugResult(ptraceScope: 0);
    expect(result.debugBuild, isTrue);
    expect(result.failed, isFalse);
    expect(result.coreDumps.status, KeybayHardeningStatus.notAttempted);
    expect(result.coreDumps.detail, contains('stays dumpable'));
    expect(result.debuggerAttach.status, KeybayHardeningStatus.notAttempted);
    expect(result.yamaUnrestricted, isTrue);
  });

  test('the Linux result fails each protection it cannot confirm', () {
    final cases = [
      // dumpable, initial user namespace, tracer: core dumps, debugger attach
      // and its cause.
      (0, true, 0, 'applied', 'applied', null),
      (1, true, 0, 'failed', 'failed', C.settingRejected),
      (null, true, 0, 'failed', 'failed', C.unreadable),
      (0, false, 0, 'applied', 'failed', C.userNamespace),
      (0, null, 0, 'applied', 'failed', C.unreadable),
      (0, true, 4242, 'applied', 'failed', C.traced),
      (0, true, null, 'applied', 'failed', C.unreadable),
      // The namespace is reported only when nothing else failed.
      (0, false, 4242, 'applied', 'failed', C.traced),
      (0, false, null, 'applied', 'failed', C.unreadable),
      (1, false, 0, 'failed', 'failed', C.settingRejected),
    ];
    for (final (dumpable, initial, tracer, core, debugger, cause) in cases) {
      final result = linuxHardeningResult(
        dumpable: dumpable,
        initialUserNamespace: initial,
        tracer: tracer,
        ptraceScope: 1,
      );
      final label = '$dumpable/$initial/$tracer';
      expect(result.coreDumps.status.name, core, reason: label);
      expect(result.debuggerAttach.status.name, debugger, reason: label);
      expect(result.failed, core == 'failed' || debugger == 'failed');
      expect(result.debuggerAttach.cause, cause, reason: label);
      expect(
        result.coreDumps.cause,
        core == 'failed' ? cause : null,
        reason: label,
      );
    }
  });

  test('Yama ptrace_scope parses the four defined scopes only', () {
    for (final (text, scope) in [
      ('0\n', 0),
      ('1\n', 1),
      ('2', 2),
      ('3\n', 3),
      ('4\n', null),
      ('-1\n', null),
      ('', null),
      ('restricted\n', null),
    ]) {
      expect(linuxPtraceScope(read: () => text), scope, reason: text);
    }
    expect(
      linuxPtraceScope(read: () => throw const FileSystemException('absent')),
      isNull,
    );
    for (final (scope, unrestricted) in [(null, true), (0, true), (1, false)]) {
      expect(
        linuxHardeningResult(
          dumpable: 0,
          initialUserNamespace: true,
          tracer: 0,
          ptraceScope: scope,
        ).yamaUnrestricted,
        unrestricted,
      );
    }
  });

  test('only the identity uid_map is the initial user namespace', () {
    for (final (text, initial) in [
      ('         0          0 4294967295\n', true),
      ('0 0 4294967295', true),
      ('         0       1000          1\n', false),
      ('0 0 4294967295\n1000 1000 1\n', false),
      ('0 0 1000\n', false),
      ('', false),
    ]) {
      expect(linuxInitialUserNamespace(read: () => text), initial);
    }
    expect(
      linuxInitialUserNamespace(
        read: () => throw const FileSystemException(''),
      ),
      isNull,
    );
  });

  test('every thread is checked for a tracer', () {
    String status(String tracer) => 'Name:\tdart\nTracerPid:\t$tracer\n';
    for (final (statuses, tracer) in [
      ([status('0')], 0),
      ([status('0'), status('0')], 0),
      ([status('0'), status('4242')], 4242),
      ([status('0'), 'Name:\tworker\n'], null),
      ([status('0'), status('none')], null),
      (<String>[], null),
    ]) {
      expect(linuxTracerPid(statuses: () => statuses), tracer);
    }
    expect(
      linuxTracerPid(statuses: () => throw const FileSystemException('')),
      isNull,
    );
  });

  test('a thread name that is not UTF-8 does not hide the tracer state', () {
    // The kernel cuts Name at 15 bytes regardless of character boundaries.
    final previous = calloc<Uint8>(16);
    final name = calloc<Uint8>(16);
    try {
      expect(_prctl(_prGetName, previous.address, 0, 0, 0), 0);
      name.asTypedList(16).setAll(0, Uint8List.fromList([0x6b, 0xe6, 0x97]));
      expect(_prctl(_prSetName, name.address, 0, 0, 0), 0);
      expect(linuxTracerPid(), 0);
    } finally {
      _prctl(_prSetName, previous.address, 0, 0, 0);
      calloc
        ..free(previous)
        ..free(name);
    }
  }, testOn: 'linux');
}

/// Restores this test runner's soft core limit and, on Linux, dumpability
/// after the test, since other test files share the process. Returns the
/// hard core limit.
int _preserveProcessState() {
  final (soft, hard) = _coreLimits();
  addTearDown(() => _setSoftCoreLimit(soft));
  if (Platform.isLinux) {
    final dumpable = linuxDumpable!;
    addTearDown(() => _prctl(_prSetDumpable, dumpable, 0, 0, 0));
  }
  return hard;
}

/// Whether a child process running as this user can open [path].
bool _childOpens(String path) =>
    Process.runSync('/bin/sh', ['-c', 'exec 3<"\$1"', 'sh', path]).exitCode ==
    0;

/// Whether a child process running as this user can read [path].
bool _childReads(String path) =>
    Process.runSync('/bin/sh', [
      '-c',
      'head -c 1 "\$1" >/dev/null 2>&1',
      'sh',
      path,
    ]).exitCode ==
    0;

// RLIMIT_CORE is 4 on Darwin and Linux, and rlim_t is 64-bit on both.
final class _Rlimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

const _prSetDumpable = 4;
const _prSetName = 15;
const _prGetName = 16;

final _libc = DynamicLibrary.process();
final _getrlimit = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_Rlimit>),
      int Function(int, Pointer<_Rlimit>)
    >('getrlimit');
final _setrlimit = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_Rlimit>),
      int Function(int, Pointer<_Rlimit>)
    >('setrlimit');
final _prctl = _libc
    .lookupFunction<
      Int32 Function(
        Int32,
        VarArgs<(UnsignedLong, UnsignedLong, UnsignedLong, UnsignedLong)>,
      ),
      int Function(int, int, int, int, int)
    >('prctl');

(int, int) _coreLimits() {
  final limit = calloc<_Rlimit>();
  try {
    expect(_getrlimit(4, limit), 0);
    return (limit.ref.current, limit.ref.maximum);
  } finally {
    calloc.free(limit);
  }
}

void _setSoftCoreLimit(int soft) {
  final limit = calloc<_Rlimit>();
  try {
    expect(_getrlimit(4, limit), 0);
    limit.ref.current = soft;
    expect(_setrlimit(4, limit), 0);
  } finally {
    calloc.free(limit);
  }
}

@Tags(['unit'])
@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:keybay/src/process_hardening.dart';
import 'package:keybay_cli/src/entrypoint.dart';
import 'package:keybay_cli/src/process_hardening.dart';
import 'package:keybay_cli/src/tui/native_model.dart' show tuiHardeningStatus;
import 'package:test/test.dart';

void main() {
  test('commands disable core files and restore them only for exec', () {
    final caller = _allowCoreFiles();
    if (caller == null) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    _allowDumping();

    final result = ProcessHardening.apply();
    // This JIT test run is a debug build: only the soft limit is set, and on
    // Linux the process stays dumpable so debuggers work. Release builds of
    // the CLI are checked by tool/test_cli_tui.py and test_cli_exec.py.
    expect(result.debugBuild, isTrue);
    expect(ProcessHardening.refusal(result), isNull, reason: '$result');
    expect(softCoreLimit, 0);
    if (Platform.isLinux) expect(linuxDumpable, 1);

    ProcessHardening.restoreForExec();
    expect(softCoreLimit, caller);

    ProcessHardening.reapplyAfterFailedExec();
    expect(softCoreLimit, 0);
  });

  test('every command hardens the process before it runs', () async {
    if (_allowCoreFiles() == null) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    expect(softCoreLimit, isNot(0));
    KeybayProcessHardening? result;

    final exitCode = await runKeybay([
      '--version',
    ], hardenProcess: () => result = ProcessHardening.apply());

    expect(exitCode, 0, reason: '$result');
    expect(result, isNotNull);
    expect(softCoreLimit, 0);
  });

  test('only core files that stay enabled stop a command', () async {
    KeybayProcessHardening linux({
      int dumpable = 0,
      bool initial = true,
      int tracer = 0,
    }) => linuxHardeningResult(
      dumpable: dumpable,
      initialUserNamespace: initial,
      tracer: tracer,
      ptraceScope: 1,
    );
    for (final (hardening, exitCode) in [
      (linux(dumpable: 1), 1),
      // Toolbox, distrobox and rootless containers keep working.
      (linux(initial: false), 0),
      (linux(tracer: 4242), 0),
      (linux(), 0),
    ]) {
      expect(
        await runKeybay(['--version'], hardenProcess: () => hardening),
        exitCode,
        reason: '$hardening',
      );
    }
    expect(
      ProcessHardening.refusal(linux(dumpable: 1)),
      startsWith(
        'error: could not disable core dumps for this process: '
        'PR_SET_DUMPABLE 0 did not take effect',
      ),
    );
    expect(ProcessHardening.refusal(linux(initial: false)), isNull);
  });

  test('the Security settings summarize the hardening status', () {
    KeybayProcessHardening linux({bool initial = true, int tracer = 0}) =>
        linuxHardeningResult(
          dumpable: 0,
          initialUserNamespace: initial,
          tracer: tracer,
          ptraceScope: 1,
        );
    for (final (hardening, label, complete) in [
      (linux(), 'On', true),
      (linux(initial: false), 'Partial', false),
      (linux(tracer: 4242), 'Partial', false),
      (linuxDebugResult(ptraceScope: 1), 'Debug build', false),
      (applyProcessHardening(enabled: false), 'Off', false),
    ]) {
      final status = tuiHardeningStatus(hardening);
      expect(status.label, label);
      expect(status.complete, complete);
    }
  });
}

/// Makes this process dumpable for the test on Linux, restoring the previous
/// state afterwards; an earlier test may already have made it non-dumpable.
void _allowDumping() {
  if (!Platform.isLinux) return;
  final dumpable = linuxDumpable!;
  addTearDown(() => _prctl(_prSetDumpable, dumpable, 0, 0, 0));
  expect(_prctl(_prSetDumpable, 1, 0, 0, 0), 0);
}

/// Gives this process a nonzero soft core limit for the test, so a default of
/// 0 cannot make every expectation pass. Returns null when the hard limit is 0.
int? _allowCoreFiles() {
  final (original, hard) = _coreLimits();
  if (hard == 0) return null;
  final caller = hard > 0 && hard < 1 << 20 ? hard : 1 << 20;
  _setSoftCoreLimit(caller);
  addTearDown(() => _setSoftCoreLimit(original));
  return caller;
}

// RLIMIT_CORE is 4 on Darwin and Linux, and rlim_t is 64-bit on both.
final class _Rlimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

const _prSetDumpable = 4;

final _libc = DynamicLibrary.process();
final _prctl = _libc
    .lookupFunction<
      Int32 Function(
        Int32,
        VarArgs<(UnsignedLong, UnsignedLong, UnsignedLong, UnsignedLong)>,
      ),
      int Function(int, int, int, int, int)
    >('prctl');
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

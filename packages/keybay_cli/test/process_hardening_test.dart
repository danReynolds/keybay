@Tags(['unit'])
@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:keybay/src/process_hardening.dart';
import 'package:keybay_cli/src/entrypoint.dart';
import 'package:keybay_cli/src/process_hardening.dart';
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
    expect(result.coreDumps.status, KeybayHardeningStatus.applied);
    expect(softCoreLimit, 0);
    if (Platform.isLinux) expect(linuxDumpable, 0);

    ProcessHardening.restoreForExec();
    expect(softCoreLimit, caller);

    ProcessHardening.reapplyAfterFailedExec();
    expect(softCoreLimit, 0);
    if (Platform.isLinux) expect(linuxDumpable, 0);
  });

  test('every command hardens the process before it runs', () async {
    if (_allowCoreFiles() == null) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    expect(softCoreLimit, isNot(0));
    _allowDumping();
    // Pass the real hardening through, so a user namespace (toolbox, a
    // rootless container), where the CLI refuses, still checks the policy.
    KeybayProcessHardening? result;

    final exitCode = await runKeybay([
      '--version',
    ], hardenProcess: () => result = ProcessHardening.apply());

    expect(result, isNotNull);
    expect(exitCode, result!.failed ? 1 : 0, reason: '$result');
    expect(softCoreLimit, 0);
    if (Platform.isLinux) expect(linuxDumpable, 0);
  });

  test('a command stops when hardening fails', () async {
    var hardened = 0;
    for (final (dumpable, tracer) in [(1, 0), (0, 4242)]) {
      expect(
        await runKeybay(
          ['--version'],
          hardenProcess: () {
            hardened++;
            return linuxHardeningResult(
              dumpable: dumpable,
              initialUserNamespace: true,
              tracer: tracer,
              ptraceScope: 1,
              environment: const {},
            );
          },
        ),
        1,
      );
    }
    expect(hardened, 2);
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

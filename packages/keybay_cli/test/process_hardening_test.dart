@Tags(['unit'])
@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:keybay_cli/src/process_hardening.dart';
import 'package:test/test.dart';

void main() {
  test('commands disable core files and restore them only for exec', () {
    // Start from a caller that allows core files; a default limit of 0 would
    // let every expectation pass even if nothing were changed.
    final (original, hard) = _coreLimits();
    if (hard == 0) {
      markTestSkipped('the hard core-file limit is 0 here');
      return;
    }
    final caller = hard > 0 && hard < 1 << 20 ? hard : 1 << 20;
    _setSoftCoreLimit(caller);
    addTearDown(() => _setSoftCoreLimit(original));
    expect(ProcessHardening.softCoreLimit, caller);

    expect(ProcessHardening.apply(), isTrue);
    expect(ProcessHardening.softCoreLimit, 0);
    if (Platform.isLinux) expect(ProcessHardening.dumpable, 0);

    ProcessHardening.restoreForExec();
    expect(ProcessHardening.softCoreLimit, caller);

    ProcessHardening.reapplyAfterFailedExec();
    expect(ProcessHardening.softCoreLimit, 0);
  });
}

// RLIMIT_CORE is 4 on Darwin and Linux, and rlim_t is 64-bit on both.
final class _Rlimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

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

@Tags(['unit'])
@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:keybay_cli/src/ignored_signals.dart';
import 'package:test/test.dart';

typedef _NativeSigaction = Int32 Function(Int32, Pointer<Void>, Pointer<Void>);
typedef _DartSigaction = int Function(int, Pointer<Void>, Pointer<Void>);

void main() {
  test('terminal ownership ignores native SIGTSTP and never SIGCHLD', () {
    // Dart's ProcessSignal numbers are Linux numbering; on Darwin Dart's
    // SIGTSTP (20) is the native SIGCHLD. The guard must use native numbers.
    expect(NativeSignal.tstp, Platform.isMacOS ? 18 : 20);
    final sigaction = DynamicLibrary.process()
        .lookupFunction<_NativeSigaction, _DartSigaction>('sigaction');
    // Reads a disposition without changing it: ignoring SIGCHLD even briefly
    // would let the kernel reap other suites' children in this process.
    int disposition(int number) {
      // sa_handler is the first member of struct sigaction on Darwin and
      // Linux; 256 bytes covers either layout.
      final action = calloc<Uint8>(256);
      try {
        expect(sigaction(number, nullptr, action.cast()), 0);
        return action.cast<IntPtr>().value;
      } finally {
        calloc.free(action);
      }
    }

    final guarded = [
      NativeSignal.quit,
      NativeSignal.tstp,
      NativeSignal.ttin,
      NativeSignal.ttou,
    ];
    final before = {for (final number in guarded) number: disposition(number)};
    final child = Platform.isMacOS ? 20 : 17;
    final childBefore = disposition(child);
    final guard = IgnoredSignals.terminalOwnership()..start();
    try {
      for (final number in guarded) {
        expect(disposition(number), 1, reason: 'signal $number');
      }
      expect(disposition(child), childBefore);
    } finally {
      guard.close();
    }
    for (final number in guarded) {
      expect(disposition(number), before[number], reason: 'signal $number');
    }
  });
}

@Tags(['unit'])
@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:keybay_cli/src/ignored_signals.dart';
import 'package:test/test.dart';

typedef _NativeSignal = Pointer<Void> Function(Int32, Pointer<Void>);
typedef _DartSignal = Pointer<Void> Function(int, Pointer<Void>);

void main() {
  test('terminal ownership ignores native SIGTSTP and never SIGCHLD', () {
    // Dart's ProcessSignal numbers are Linux numbering; on Darwin Dart's
    // SIGTSTP (20) is the native SIGCHLD. The guard must use native numbers.
    final signal = DynamicLibrary.process()
        .lookupFunction<_NativeSignal, _DartSignal>('signal');
    final ignore = Pointer<Void>.fromAddress(1);
    int disposition(int number) {
      final previous = signal(number, ignore);
      signal(number, previous);
      return previous.address;
    }

    final tstp = Platform.isMacOS ? 18 : 20;
    final chld = Platform.isMacOS ? 20 : 17;
    final childBefore = disposition(chld);
    final guard = IgnoredSignals.terminalOwnership()..start();
    try {
      for (final number in [3, tstp, 21, 22]) {
        expect(disposition(number), 1, reason: 'signal $number');
      }
      expect(disposition(chld), childBefore);
    } finally {
      guard.close();
    }
    expect(disposition(tstp), isNot(1));
  });
}

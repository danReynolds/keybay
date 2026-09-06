import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:keybay/keybay.dart';

/// Optional receipt binding used by the physical-device runner. The ordinary
/// simulator/emulator lanes exercise the same tests without producing a receipt.
void registerSecurityMetadata() {
  const nonce = String.fromEnvironment('KEYBAY_SECURITY_NONCE');
  const subject = String.fromEnvironment('KEYBAY_SECURITY_SUBJECT');
  if (nonce.isEmpty && subject.isEmpty) return;
  testWidgets('KEYBAY-SECURITY-METADATA nonce=$nonce subject=$subject', (
    _,
  ) async {
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce), isTrue);
    expect(RegExp(r'^git-commit:[0-9a-f]{40}$').hasMatch(subject), isTrue);
  });
}

/// Exercise each worker's own public singleton and native FFI binding against
/// the one application store, including concurrent first provisioning.
Future<void> checkConcurrentMobileUpdates() async {
  await Keybay.reset();
  KeybaySession? session;
  try {
    await Future.wait([
      for (var worker = 0; worker < 4; worker++)
        Isolate.run(() => _writeBatch(worker)),
    ]);
    session = await Keybay.open();
    final keys = <String>[];
    for (var worker = 0; worker < 4; worker++) {
      for (var index = 0; index < 8; index++) {
        final key = 'worker/$worker/$index';
        keys.add(key);
        expect(await session.get(key), 'value-$worker-$index');
      }
    }
    expect(await session.listKeys(), unorderedEquals(keys));
  } finally {
    await session?.close();
    await Keybay.reset();
  }
}

Future<void> _writeBatch(int worker) async {
  final session = await _retryStoreBusy(Keybay.open);
  try {
    for (var index = 0; index < 8; index++) {
      await _retryStoreBusy(
        () => session.set('worker/$worker/$index', 'value-$worker-$index'),
      );
    }
  } finally {
    await session.close();
  }
}

/// The SDK deliberately bounds each lock acquisition. This test checks that
/// contending workers preserve every update, allowing only that typed refusal
/// to retry within a finite window; it does not require scheduler fairness.
Future<T> _retryStoreBusy<T>(Future<T> Function() operation) async {
  const retryWindow = Duration(seconds: 30);
  const pause = Duration(milliseconds: 50);
  final elapsed = Stopwatch()..start();
  while (true) {
    try {
      return await operation();
    } on KeybayException catch (failure) {
      if (failure.code != KeybayErrorCode.storeBusy ||
          elapsed.elapsed >= retryWindow) {
        rethrow;
      }
      final remaining = retryWindow - elapsed.elapsed;
      await Future<void>.delayed(remaining < pause ? remaining : pause);
      if (elapsed.elapsed >= retryWindow) rethrow;
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/failure.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  test('authentication failures are redacted and map to status 1', () async {
    final store = V2TestKeybay(applicationId: 'dev.keybay.cli-failure-auth');
    addTearDown(store.dispose);
    final session = await store.open();
    final correct = Uint8List.fromList(utf8.encode('correct'));
    await session.auth.add(PassphraseCredential(phrase: correct));
    correct.fillRange(0, correct.length, 0);
    await session.close();

    final required = await _capture(store.open);
    final wrong = Uint8List.fromList(utf8.encode('secret-sentinel'));
    final failed = await _capture(
      () => store.open(credential: PassphraseCredential(phrase: wrong)),
    );
    wrong.fillRange(0, wrong.length, 0);

    for (final error in <KeybayException>[required, failed]) {
      final failure = failureForKeybay(error);
      expect(failure.exitCode, 1);
      expect(failure.lines.first, startsWith('error:'));
      expect(failure.lines.join('\n'), isNot(contains('secret-sentinel')));
    }
  });

  test('caller input failures map to status 2', () async {
    final empty = Uint8List(0);
    final store = V2TestKeybay(applicationId: 'dev.keybay.cli-failure-input');
    addTearDown(store.dispose);
    final invalidAuth = await _capture(
      () => store.open(credential: PassphraseCredential(phrase: empty)),
    );
    final session = await store.open();
    final invalidKey = await _capture(() => session.getBytes('not qualified'));
    await session.close();

    for (final error in <KeybayException>[invalidAuth, invalidKey]) {
      expect(failureForKeybay(error).exitCode, 2);
    }
  });

  test('closed sessions receive non-sensitive recovery guidance', () async {
    final store = V2TestKeybay(applicationId: 'dev.keybay.cli-failure-close');
    addTearDown(store.dispose);
    final session = await store.open();
    await session.close();
    final error = await _capture(session.listKeys);
    final failure = failureForKeybay(error);
    expect(failure.exitCode, 1);
    expect(failure.lines.join('\n'), contains('fresh session'));
  });
}

Future<KeybayException> _capture(Future<Object?> Function() operation) async {
  try {
    await operation();
    fail('expected KeybayException');
  } on KeybayException catch (error) {
    return error;
  }
}

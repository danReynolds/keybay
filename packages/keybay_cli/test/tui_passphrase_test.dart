@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  // The model clears its buffer as soon as a protection change starts. The
  // store must be keyed to the typed bytes, never to that cleared buffer, for
  // example if an adapter ever awaited before the SDK snapshotted the input.
  for (final replacing in [false, true]) {
    test(
      'a TUI ${replacing ? 'update' : 'add'} keys the store to the typed bytes',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        if (replacing) {
          final session = await store.open();
          await session.auth.add(
            PassphraseCredential(phrase: utf8.encode('original')),
          );
          await session.close();
        }
        final model = createNativeTuiModel(
          openSession: store.open,
          resetStore: store.reset,
          authorize: () {},
          onExit: () {},
        );
        await model.open(replacing ? utf8.encode('original') : null);
        model.navigate(TuiView.passphrase);
        final typed = utf8.encode('secret-passphrase');
        await model.changePassphrase(Uint8List.fromList(typed));
        expect(model.protected, isTrue);
        await model.close();
        model.dispose();

        await expectLater(
          store.open(
            credential: PassphraseCredential(phrase: Uint8List(typed.length)),
          ),
          throwsA(isA<KeybayException>()),
        );
        final reopened = await store.open(
          credential: PassphraseCredential(phrase: typed),
        );
        await reopened.close();
      },
    );
  }
}

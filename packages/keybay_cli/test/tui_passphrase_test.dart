@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';
import '../../keybay/test/support/v2_passkey_backend.dart';

void main() {
  for (final withPassphrase in [false, true]) {
    test(
      'TUI offers only its supported auth UI (mixed: $withPassphrase)',
      () async {
        final provider = TestPasskeyProvider();
        final store = V2TestKeybay(keypassClient: provider.client);
        final seeded = await store.open();
        await seeded.auth.add(
          const PasskeyCredential.hardware(rpId: 'vault.example.com'),
        );
        await seeded.set('service/token', 'retained');
        if (withPassphrase) {
          await seeded.auth.add(
            PassphraseCredential(phrase: utf8.encode('correct')),
          );
        }
        await seeded.close();
        final generation = store.files.liveGeneration;
        final model = createNativeTuiModel(
          openSession: store.open,
          resetStore: store.reset,
          authorize: () {},
          onExit: () {},
        );
        addTearDown(() async {
          await model.close();
          model.dispose();
          await store.dispose();
          provider.expectReleased();
          provider.clear();
        });
        await model.open();
        if (withPassphrase) {
          expect(model.view, TuiView.unlock);
          await model.open(utf8.encode('correct'));
          expect(model.view, TuiView.browse);
          expect(model.keys, ['service/token']);
          expect(model.protected, isTrue);
        } else {
          expect(model.view, TuiView.failed);
          expect(model.status, contains('does not yet support passkey unlock'));
          expect(model.hasSession, isFalse);
          expect(model.resetFromFailure, isFalse);
        }
        expect(store.files.liveGeneration, generation);
        expect(provider.operationCount, 1);
      },
    );
  }

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

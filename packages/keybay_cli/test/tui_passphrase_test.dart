@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/store.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';
import '../../keybay/test/support/v2_passkey_backend.dart';

void main() {
  for (final credential in [
    const PasskeyCredential.hardware(rpId: 'vault.example.com'),
    const PasskeyCredential.system(rpId: 'vault.example.com'),
  ]) {
    test(
      'TUI removal requires a usable survivor (${credential.route.name})',
      () async {
        final provider = TestPasskeyProvider();
        final store = V2TestKeybay(keypassClient: provider.client);
        final seeded = await store.open();
        await seeded.auth.add(credential);
        await seeded.auth.add(
          PassphraseCredential(phrase: utf8.encode('correct')),
        );
        await seeded.set('service/token', 'retained');
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
        await model.open(utf8.encode('correct'));
        model.navigate(TuiView.removePassphrase);
        await model.removePassphrase();
        if (credential.route == PasskeyRoute.hardware) {
          expect(model.view, TuiView.security);
          expect(model.hasPassphrase, isFalse);
          final reopened = await store.open(credential: credential);
          expect(await reopened.get('service/token'), 'retained');
          await reopened.close();
          return;
        }
        expect(model.status, contains('cannot unlock the remaining passkeys'));
        expect(store.files.liveGeneration, generation);
        await model.close();
        final reopened = await store.open(
          credential: PassphraseCredential(phrase: utf8.encode('correct')),
        );
        expect(await reopened.get('service/token'), 'retained');
        expect(await reopened.auth.list(), hasLength(2));
        expect(provider.operationCount, 1);
        await reopened.close();
      },
    );
  }

  for (final withPassphrase in [false, true]) {
    test(
      'TUI chooses only when several methods are usable (mixed: $withPassphrase)',
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
          expect(model.view, TuiView.unlockMethods);
          await model.chooseUnlock(
            model.unlockMethods.firstWhere(
              (m) => m.kind == TuiAuthKind.passphrase,
            ),
          );
          await model.open(utf8.encode('correct'));
          expect(model.view, TuiView.browse);
          expect(model.keys, ['service/token']);
          expect(model.hasPassphrase, isTrue);
        } else {
          expect(model.view, TuiView.browse);
          expect(model.unlockMethods.single.kind, TuiAuthKind.hardware);
          expect(model.hasSession, isTrue);
          expect(model.resetFromFailure, isFalse);
        }
        // Successful hardware open persists its assertion counter.
        expect(
          store.files.liveGeneration,
          withPassphrase ? generation : generation! + 1,
        );
        expect(provider.operationCount, withPassphrase ? 1 : 2);
      },
    );
  }

  // The model clears its buffer as soon as a protection change starts. The
  // store must be keyed to the typed bytes, never to that cleared buffer, for
  // example if an adapter ever awaited before the SDK snapshotted the input.
  for (final afterRemoval in [false, true]) {
    test(
      'a TUI ${afterRemoval ? 'add after removal' : 'add'} keys the store to the typed bytes',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        if (afterRemoval) {
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
        await model.open(afterRemoval ? utf8.encode('original') : null);
        if (afterRemoval) {
          model.navigate(TuiView.passphrase);
          expect(model.view, isNot(TuiView.passphrase));
          model.navigate(TuiView.removePassphrase);
          await model.removePassphrase();
          expect(model.hasPassphrase, isFalse);
        }
        model.navigate(TuiView.passphrase);
        final typed = utf8.encode('secret-passphrase');
        await model.addPassphrase(Uint8List.fromList(typed));
        expect(model.hasPassphrase, isTrue);
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

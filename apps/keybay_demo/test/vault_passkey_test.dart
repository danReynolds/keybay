import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_demo/src/vault.dart';
import 'package:keybay_demo/src/vault_backend.dart';

import '../../../packages/keybay/test/support/v2_passkey_backend.dart';
import '../../../packages/keybay/test/support/v2_test_keybay.dart';

void main() {
  for (final credential in [
    const PasskeyCredential.hardware(rpId: 'vault.example.com'),
    const PasskeyCredential.system(rpId: 'vault.example.com'),
  ]) {
    test(
      'demo preserves its last usable method (${credential.route.name})',
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
        final vault = Vault(_Backend(store));
        addTearDown(() async {
          await vault.close();
          vault.dispose();
          await store.dispose();
          provider.expectReleased();
          provider.clear();
        });
        expect(await vault.unlock('correct'), isTrue);
        await expectLater(
          vault.removePassphrase(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('cannot unlock the remaining passkeys'),
            ),
          ),
        );
        expect(store.files.liveGeneration, generation);
        expect(vault.passphraseProtected, isTrue);
        await vault.close();
        expect(await vault.unlock('correct'), isTrue);
        expect(await vault.read('service/token'), 'retained');
        expect(provider.operationCount, 1);
      },
    );
  }

  test(
    'demo changes passphrases only through explicit removal and addition',
    () async {
      final store = V2TestKeybay();
      final vault = Vault(_Backend(store));
      addTearDown(() async {
        await vault.close();
        vault.dispose();
        await store.dispose();
      });
      await vault.open();
      await vault.addPassphrase('original');
      expect(vault.passphraseProtected, isTrue);
      await vault.removePassphrase();
      expect(vault.passphraseProtected, isFalse);
      await vault.addPassphrase('new phrase');
      await vault.close();
      await vault.open();
      expect(vault.stage, VaultStage.locked);
      expect(await vault.unlock('original'), isFalse);
      expect(await vault.unlock('new phrase'), isTrue);
    },
  );

  for (final withPassphrase in [false, true]) {
    test(
      'demo only offers a configured passphrase (mixed: $withPassphrase)',
      () async {
        final provider = TestPasskeyProvider();
        final store = V2TestKeybay(keypassClient: provider.client);
        final seeded = await store.open();
        await seeded.auth.add(
          const PasskeyCredential.system(rpId: 'vault.example.com'),
        );
        await seeded.set('service/token', 'retained');
        if (withPassphrase) {
          await seeded.auth.add(
            PassphraseCredential(phrase: utf8.encode('correct')),
          );
        }
        await seeded.close();
        final generation = store.files.liveGeneration;
        final backend = _Backend(store);
        final vault = Vault(backend);
        addTearDown(() async {
          await vault.close();
          vault.dispose();
          await store.dispose();
          provider.expectReleased();
          provider.clear();
        });
        await vault.open();
        if (withPassphrase) {
          expect(vault.stage, VaultStage.locked);
          expect(await vault.unlock('correct'), isTrue);
          expect(vault.stage, VaultStage.open);
          expect(await vault.read('service/token'), 'retained');
          expect(backend.openCalls, 2);
          expect(vault.passphraseProtected, isTrue);
        } else {
          expect(vault.stage, VaultStage.failed);
          expect(
            vault.message,
            contains('does not yet support passkey unlock'),
          );
          expect(backend.openCalls, 1);
          expect(vault.keys, isEmpty);
        }
        expect(backend.resetCalls, 0);
        expect(store.files.liveGeneration, generation);
        expect(provider.operationCount, 1);
      },
    );
  }
}

final class _Backend implements VaultBackend {
  _Backend(this.store);
  final V2TestKeybay store;
  int openCalls = 0;
  int resetCalls = 0;

  @override
  Future<KeybaySession> open({KeybayCredential? credential}) {
    openCalls++;
    return store.open(credential: credential);
  }

  @override
  Future<void> reset() {
    resetCalls++;
    return store.reset();
  }
}

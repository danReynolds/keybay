import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_demo/src/vault.dart';
import 'package:keybay_demo/src/vault_backend.dart';

import '../../../packages/keybay/test/support/v2_passkey_backend.dart';
import '../../../packages/keybay/test/support/v2_test_keybay.dart';

void main() {
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

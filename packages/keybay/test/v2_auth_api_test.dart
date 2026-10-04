@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngineTestProbe;
import 'package:test/test.dart';

import 'support/v2_passkey_backend.dart';
import 'support/v2_test_keybay.dart';

void main() {
  test(
    'method objects survive reopen but cannot remove a foreign enrollment',
    () async {
      final store = V2TestKeybay();
      final other = V2TestKeybay(applicationId: 'dev.keybay.other-auth-test');
      addTearDown(store.dispose);
      addTearDown(other.dispose);
      final owner = await store.open();
      final method = await owner.auth.add(_phrase(), label: 'Recovery phrase');
      expect(method.label, 'Recovery phrase');
      await owner.close();

      final foreignOwner = await other.open();
      final foreign = await foreignOwner.auth.add(_phrase());
      final reopened = await store.open(
        credential: _phrase(),
        methodId: method.id,
      );
      final listed = (await reopened.auth.list()).single;
      expect(identical(listed, method), isFalse);
      expect(listed.id, method.id);
      expect(listed.label, method.label);
      final generation = store.files.liveGeneration;
      await expectLater(
        reopened.auth.remove(foreign),
        _fails(KeybayErrorCode.authMethodNotConfigured),
      );
      expect(store.files.liveGeneration, generation);
      // Use a descriptor from the previous session, not the newly listed instance.
      await reopened.auth.remove(method);
      expect(await reopened.auth.list(), isEmpty);
      await expectLater(
        reopened.auth.remove(listed),
        _fails(KeybayErrorCode.authMethodNotConfigured),
      );
    },
  );

  test(
    'remove and add are separate commits with fresh IDs and no implicit restore',
    () async {
      final store = V2TestKeybay();
      addTearDown(store.dispose);
      final owner = await store.open();
      final old = await owner.auth.add(_phrase());
      await owner.set('token', 'retained');
      await owner.auth.remove(old);
      final generation = store.files.liveGeneration;
      await expectLater(
        owner.auth.add(PassphraseCredential(phrase: Uint8List(0))),
        _fails(KeybayErrorCode.invalidAuthInput),
      );
      expect(store.files.liveGeneration, generation);
      expect(await owner.auth.list(), isEmpty);
      final platformOnly = await store.open();
      expect(await platformOnly.get('token'), 'retained');
      await platformOnly.close();

      final added = await owner.auth.add(_phrase());
      expect(added.id, isNot(old.id));
      await expectLater(
        owner.auth.remove(old),
        _fails(KeybayErrorCode.authMethodNotConfigured),
      );
      expect((await owner.auth.list()).single.id, added.id);

      await store.reset();
      final fresh = await store.open();
      final current = await fresh.auth.add(_phrase());
      await expectLater(
        fresh.auth.remove(added),
        _fails(KeybayErrorCode.authMethodNotConfigured),
      );
      expect((await fresh.auth.list()).single.id, current.id);
    },
  );

  test(
    'open validates operation selectors before accessing a provider',
    () async {
      final provider = TestPasskeyProvider();
      final store = V2TestKeybay(keypassClient: provider.client);
      addTearDown(() async {
        await store.dispose();
        provider.clear();
      });
      const hardware = PasskeyCredential.hardware(rpId: 'vault.example.com');
      for (final credential in [_phrase(), hardware]) {
        await expectLater(
          store.open(credential: credential, methodId: '0' * 32),
          _fails(KeybayErrorCode.storeNotFound),
        );
        await expectLater(
          store.open(credential: credential, methodId: 'invalid'),
          _fails(KeybayErrorCode.invalidAuthInput),
        );
      }
      await expectLater(
        store.open(methodId: '0' * 32),
        _fails(KeybayErrorCode.invalidAuthInput),
      );
      expect(store.registry.rootCount, 0);
      expect(provider.operationCount, 0);

      final owner = await store.open();
      final phrase = await owner.auth.add(_phrase());
      final key = await owner.auth.add(hardware);
      final operations = provider.operationCount;
      await expectLater(
        store.open(credential: _phrase(), methodId: key.id),
        _fails(KeybayErrorCode.protectionMismatch),
      );
      await expectLater(
        store.open(credential: _phrase(), methodId: '0' * 32),
        _fails(KeybayErrorCode.authMethodNotConfigured),
      );
      final unlocked = await store.open(
        credential: _phrase(),
        methodId: phrase.id,
      );
      await unlocked.close();
      expect(provider.operationCount, operations);
      provider.expectReleased();
    },
  );

  test(
    'hardware PIN is copied at submission and cleared before enrollment staging',
    () async {
      final captured = <Uint8List>[];
      final provider = TestPasskeyProvider();
      final store = V2TestKeybay(
        keypassClient: provider.client,
        probe: V2StoreEngineTestProbe(onOperationInput: captured.add),
      );
      addTearDown(() async {
        await store.dispose();
        provider.clear();
      });
      final owner = await store.open();
      final pin = _pin();
      final credential = PasskeyCredential.hardware(
        rpId: 'vault.example.com',
        pin: pin,
      );
      expect(credential.toString(), 'PasskeyCredential(hardware)');
      final adding = owner.auth.add(credential, label: 'Everyday key');
      expect(captured.single, _pin());
      expect(identical(captured.single, pin), isFalse);
      pin.fillRange(0, pin.length, 0);
      provider.afterNextSecret = () => expect(captured.single, _pin());
      store.files.beforeStageFinish = () =>
          expect(captured.single, everyElement(0));
      final method = await adding;
      store.files.beforeStageFinish = null;
      expect(method.label, 'Everyday key');
      expect(provider.registrations.single.label, method.label);
      expect(captured.single, everyElement(0));
      await owner.close();

      captured.clear();
      final nextPin = _pin();
      final opening = store.open(
        credential: PasskeyCredential.hardware(
          rpId: 'vault.example.com',
          pin: nextPin,
        ),
        methodId: method.id,
      );
      expect(captured.single, _pin());
      nextPin.fillRange(0, nextPin.length, 0);
      provider.afterNextSecret = () => expect(captured.single, _pin());
      final reopened = await opening;
      expect(captured.single, everyElement(0));
      await reopened.close();
      provider.expectReleased();
    },
  );

  test(
    'PIN failures and operation cancellation clear owned input without retries',
    () async {
      final captured = <Uint8List>[];
      final provider = TestPasskeyProvider();
      final store = V2TestKeybay(
        keypassClient: provider.client,
        probe: V2StoreEngineTestProbe(onOperationInput: captured.add),
      );
      addTearDown(() async {
        await store.dispose();
        provider.clear();
      });
      final owner = await store.open();
      final pin = _pin();
      final credential = PasskeyCredential.hardware(
        rpId: 'vault.example.com',
        pin: pin,
      );
      final generation = store.files.liveGeneration;
      provider.nextFailure = PasskeyErrorCode.pinInvalid;
      await expectLater(
        owner.auth.add(credential),
        _passkeyFails(PasskeyErrorCode.pinInvalid),
      );
      expect(provider.operationCount, 1);
      expect(store.files.liveGeneration, generation);
      expect(captured.single, everyElement(0));
      expect(
        pin,
        _pin(),
        reason: 'Caller input is borrowed, never erased by Keybay.',
      );

      captured.clear();
      final cancellation = PasskeyCancellation()..cancel();
      await expectLater(
        owner.auth.add(credential, cancellation: cancellation),
        _passkeyFails(PasskeyErrorCode.cancelled),
      );
      expect(provider.operationCount, 1);
      expect(captured.single, everyElement(0));
      expect(await owner.auth.list(), isEmpty);
      pin.fillRange(0, pin.length, 0);
      provider.expectReleased();
    },
  );

  test('malformed PIN input is rejected before any ceremony', () async {
    final provider = TestPasskeyProvider();
    final store = V2TestKeybay(keypassClient: provider.client);
    addTearDown(() async {
      await store.dispose();
      provider.clear();
    });
    final owner = await store.open();
    for (final pin in [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3]),
      Uint8List(64),
      Uint8List.fromList([1, 2, 3, 0]),
    ]) {
      await expectLater(
        owner.auth.add(
          PasskeyCredential.hardware(rpId: 'vault.example.com', pin: pin),
        ),
        _fails(KeybayErrorCode.invalidAuthInput),
      );
    }
    expect(provider.operationCount, 0);
    expect(await owner.auth.list(), isEmpty);
  });
}

Uint8List _pin() => Uint8List.fromList([49, 50, 51, 52]);
PassphraseCredential _phrase() =>
    PassphraseCredential(phrase: Uint8List.fromList([1, 2, 3]));
Matcher _fails(KeybayErrorCode code) =>
    throwsA(isA<KeybayException>().having((error) => error.code, 'code', code));
Matcher _passkeyFails(PasskeyErrorCode code) => throwsA(
  isA<KeybayException>()
      .having(
        (error) => error.code,
        'code',
        KeybayErrorCode.passkeyOperationFailed,
      )
      .having((error) => error.passkeyCode, 'passkeyCode', code),
);

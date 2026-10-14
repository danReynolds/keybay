@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/format/method_crypto.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:test/test.dart';

void main() {
  final vectors =
      jsonDecode(
            File('test/vectors/method_confirmation.json').readAsStringSync(),
          )
          as Map<String, Object?>;

  for (final name in [
    'passphraseConfirmation',
    'hardwarePasskeyConfirmation',
  ]) {
    test('$name matches the independent reference', () async {
      final vector = vectors[name]! as Map<String, Object?>;
      expect(
        await deriveMethodConfirmation(
          material: _hex(vector['material']),
          salt: _hex(vector['salt']),
          context: _hex(vector['context']),
          publicKey: _hex(vector['publicKey']),
          vaultSecret: _hex(vector['vaultSecret']),
        ),
        _hex(vector['confirmation']),
      );
    });
  }

  test(
    'confirmation covers every input and differs from the private key',
    () async {
      final vector = vectors['passphraseConfirmation']! as Map<String, Object?>;
      final inputs = <String, Uint8List>{
        for (final key in [
          'material',
          'salt',
          'context',
          'publicKey',
          'vaultSecret',
        ])
          key: _hex(vector[key]),
      };
      Future<Uint8List> confirm(Map<String, Uint8List> values) =>
          deriveMethodConfirmation(
            material: values['material']!,
            salt: values['salt']!,
            context: values['context']!,
            publicKey: values['publicKey']!,
            vaultSecret: values['vaultSecret']!,
          );
      final expected = await confirm(inputs);
      for (final key in inputs.keys) {
        final changed = Map.of(inputs)
          ..[key] = (Uint8List.fromList(inputs[key]!)..[0] ^= 1);
        expect(await confirm(changed), isNot(expected), reason: key);
      }
      final privateKey = await deriveMethodPrivateKey(
        material: inputs['material']!,
        salt: inputs['salt']!,
        context: inputs['context']!,
      );
      expect(privateKey, isNot(expected));
    },
  );

  test('confirmation rejects wrong-width inputs', () async {
    final good = Uint8List(32);
    final salt = Uint8List(16);
    final context = Uint8List.fromList([1]);
    for (final call in <Future<Uint8List> Function()>[
      () => deriveMethodConfirmation(
        material: Uint8List(31),
        salt: salt,
        context: context,
        publicKey: good,
        vaultSecret: good,
      ),
      () => deriveMethodConfirmation(
        material: good,
        salt: Uint8List(15),
        context: context,
        publicKey: good,
        vaultSecret: good,
      ),
      () => deriveMethodConfirmation(
        material: good,
        salt: salt,
        context: Uint8List(0),
        publicKey: good,
        vaultSecret: good,
      ),
      () => deriveMethodConfirmation(
        material: good,
        salt: salt,
        context: context,
        publicKey: Uint8List(33),
        vaultSecret: good,
      ),
      () => deriveMethodConfirmation(
        material: good,
        salt: salt,
        context: context,
        publicKey: good,
        vaultSecret: Uint8List(31),
      ),
    ]) {
      expect(call, throwsA(isA<V2CryptoFailure>()));
    }
  });

  group('sealed vault secret', () {
    final vector = vectors['vaultSecret']! as Map<String, Object?>;
    final storeKey = _hex(vector['storeKey']);
    final storeId = _hex(vector['storeId']);
    final epoch = vector['epoch']! as int;
    final secret = _hex(vector['vaultSecret']);

    test('uses the reference subkey and AAD with the store AEAD', () async {
      final nonce = _hex(vector['nonce']);
      final box = await DartXchacha20.poly1305Aead().encrypt(
        secret,
        secretKey: SecretKeyData(_hex(vector['subkey'])),
        nonce: nonce,
        aad: _hex(vector['aad']),
      );
      final sealed = await sealVaultSecret(
        storeKey: storeKey,
        storeId: storeId,
        epoch: epoch,
        vaultSecret: secret,
        nonce: nonce,
      );
      expect(sealed, hasLength(v2SealedVaultSecretBytes));
      expect(sealed, [...nonce, ...box.cipherText, ...box.mac.bytes]);
      expect(
        await openVaultSecret(
          storeKey: storeKey,
          storeId: storeId,
          epoch: epoch,
          sealedVaultSecret: sealed,
        ),
        secret,
      );
    });

    test('fails closed for every byte, key, store and epoch change', () async {
      final sealed = await sealVaultSecret(
        storeKey: storeKey,
        storeId: storeId,
        epoch: epoch,
        vaultSecret: secret,
        nonce: _hex(vector['nonce']),
      );
      Future<Uint8List> open({
        Uint8List? key,
        Uint8List? id,
        int? at,
        Uint8List? bytes,
      }) => openVaultSecret(
        storeKey: key ?? storeKey,
        storeId: id ?? storeId,
        epoch: at ?? epoch,
        sealedVaultSecret: bytes ?? sealed,
      );
      final failed = throwsA(
        isA<V2CryptoFailure>().having(
          (failure) => failure.code,
          'code',
          V2CryptoFailureCode.authenticationFailed,
        ),
      );
      for (var index = 0; index < sealed.length; index++) {
        final changed = Uint8List.fromList(sealed)..[index] ^= 1;
        await expectLater(open(bytes: changed), failed, reason: 'byte $index');
      }
      await expectLater(
        open(key: Uint8List.fromList(storeKey)..[0] ^= 1),
        failed,
      );
      await expectLater(
        open(id: Uint8List.fromList(storeId)..[0] ^= 1),
        failed,
      );
      await expectLater(open(at: epoch + 1), failed);
    });
  });
}

Uint8List _hex(Object? value) {
  final text = value! as String;
  return Uint8List.fromList([
    for (var index = 0; index < text.length; index += 2)
      int.parse(text.substring(index, index + 2), radix: 16),
  ]);
}

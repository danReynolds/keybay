@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/format/method_crypto.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:test/test.dart';

void main() {
  final vectors =
      jsonDecode(File('test/vectors/method_crypto.json').readAsStringSync())
          as Map<String, Object?>;
  final rfc = vectors['rfc9180']! as Map<String, Object?>;
  final keybay = vectors['keybay']! as Map<String, Object?>;
  Uint8List r(String name) => _hex(rfc[name]! as String);
  Uint8List k(String name) => _hex(keybay[name]! as String);
  Uint8List rfcEnvelope() =>
      Uint8List.fromList([...r('enc'), ...r('ciphertext')]);
  Future<Uint8List> open(Uint8List envelope, {Uint8List? context}) =>
      openMethodStoreKey(
        privateKey: k('privateKey'),
        sealedStoreKey: envelope,
        context: context ?? k('hpkeContext'),
      );

  group('published RFC 9180 Appendix A.2.1 base-mode vector', () {
    test('X25519 public key matches the published private key', () async {
      expect(
        await methodPublicKey(privateKey: r('privateKey')),
        r('publicKey'),
      );
    });

    test(
      'single-shot encryption matches the published enc and ciphertext',
      () async {
        expect(
          await sealHpkeBase(
            publicKey: r('publicKey'),
            plaintext: r('plaintext'),
            info: r('info'),
            aad: r('aad'),
            ephemeralSeed: r('ephemeralSeed'),
          ),
          rfcEnvelope(),
        );
      },
    );

    test('opens the published ciphertext', () async {
      expect(
        await openHpkeBase(
          privateKey: r('privateKey'),
          sealed: rfcEnvelope(),
          info: r('info'),
          aad: r('aad'),
        ),
        r('plaintext'),
      );
    });

    for (final field in ['info', 'aad']) {
      test('rejects changed $field independently', () async {
        final info = r('info');
        final aad = r('aad');
        (field == 'info' ? info : aad)[0] ^= 1;
        await expectLater(
          openHpkeBase(
            privateKey: r('privateKey'),
            sealed: rfcEnvelope(),
            info: info,
            aad: aad,
          ),
          _authenticationFailure,
        );
      });
    }
  });

  group('independent Keybay method fixture', () {
    test(
      'credential KDF and derived public key match Python reference',
      () async {
        final key = await deriveMethodPrivateKey(
          material: k('material'),
          salt: k('salt'),
          context: k('context'),
        );
        expect(key, k('privateKey'));
        expect(await methodPublicKey(privateKey: key), k('publicKey'));
      },
    );

    test('store-key envelope matches Python reference and opens', () async {
      final envelope = await sealMethodStoreKey(
        publicKey: k('publicKey'),
        storeKey: k('storeKey'),
        context: k('hpkeContext'),
        ephemeralSeed: k('ephemeralSeed'),
      );
      expect(envelope.length, methodStoreKeyEnvelopeBytes);
      expect(envelope, k('envelope'));
      expect(await open(envelope), k('storeKey'));
    });

    test('every envelope byte is authenticated', () async {
      for (var i = 0; i < methodStoreKeyEnvelopeBytes; i++) {
        final envelope = k('envelope')..[i] ^= 1;
        await expectLater(open(envelope), _authenticationFailure, reason: '$i');
      }
    });

    test('every context byte is bound', () async {
      for (var i = 0; i < k('hpkeContext').length; i++) {
        final context = k('hpkeContext')..[i] ^= 1;
        await expectLater(
          open(k('envelope'), context: context),
          _authenticationFailure,
        );
      }
    });

    for (final field in ['material', 'salt', 'context']) {
      test('method private-key derivation binds $field', () async {
        final material = k('material');
        final salt = k('salt');
        final context = k('context');
        (switch (field) {
          'material' => material,
          'salt' => salt,
          _ => context,
        })[0] ^= 1;
        final derived = await deriveMethodPrivateKey(
          material: material,
          salt: salt,
          context: context,
        );
        expect(derived, isNot(k('privateKey')));
      });
    }

    test(
      'fresh store keys can be sealed with only a surviving public key',
      () async {
        final replacementStoreKey = Uint8List(32)..fillRange(0, 32, 51);
        final epochContext = k('hpkeContext')..[0] ^= 1;
        final newEnvelope = await sealMethodStoreKey(
          publicKey: k('publicKey'),
          storeKey: replacementStoreKey,
          context: epochContext,
          ephemeralSeed: Uint8List(32)..fillRange(0, 32, 91),
        );
        expect(
          await open(newEnvelope, context: epochContext),
          replacementStoreKey,
        );
        await expectLater(
          openMethodStoreKey(
            privateKey: Uint8List(32)..fillRange(0, 32, 71),
            sealedStoreKey: newEnvelope,
            context: epochContext,
          ),
          _authenticationFailure,
        );
        // An old envelope continues to yield only the old store key.
        expect(await open(k('envelope')), isNot(replacementStoreKey));
        await expectLater(
          open(k('envelope'), context: epochContext),
          _authenticationFailure,
        );
      },
    );
  });

  group('validation and borrowed-buffer ownership', () {
    for (final lowOrder in [0, 1]) {
      test('rejects low-order recipient/enc point $lowOrder', () async {
        final point = Uint8List(32)..[0] = lowOrder;
        await expectLater(
          sealMethodStoreKey(
            publicKey: point,
            storeKey: k('storeKey'),
            context: k('hpkeContext'),
            ephemeralSeed: k('ephemeralSeed'),
          ),
          _authenticationFailure,
        );
        final envelope = k('envelope')..setRange(0, 32, point);
        await expectLater(open(envelope), _authenticationFailure);
      });
    }

    test('rejects truncated or extended fixed-size envelopes', () {
      for (final length in [0, 31, 47, 79, 81, 65585]) {
        expect(() => open(Uint8List(length)), _invalidInputFailure);
      }
    });

    test('rejects key, salt and context bounds before crypto', () {
      expect(
        () => deriveMethodPrivateKey(
          material: Uint8List(31),
          salt: k('salt'),
          context: k('context'),
        ),
        _invalidInputFailure,
      );
      expect(
        () => deriveMethodPrivateKey(
          material: k('material'),
          salt: Uint8List(15),
          context: k('context'),
        ),
        _invalidInputFailure,
      );
      expect(
        () => methodPublicKey(privateKey: Uint8List(33)),
        _invalidInputFailure,
      );
      expect(
        () => open(k('envelope'), context: Uint8List(0)),
        _invalidInputFailure,
      );
      expect(
        () => open(k('envelope'), context: Uint8List(65537)),
        _invalidInputFailure,
      );
    });

    test('KDF and public-key calls snapshot inputs synchronously', () async {
      final material = k('material');
      final salt = k('salt');
      final context = k('context');
      final privateKey = k('privateKey');
      final deriving = deriveMethodPrivateKey(
        material: material,
        salt: salt,
        context: context,
      );
      final public = methodPublicKey(privateKey: privateKey);
      for (final bytes in [material, salt, context, privateKey]) {
        bytes.fillRange(0, bytes.length, 0);
      }
      expect(await deriving, k('privateKey'));
      expect(await public, k('publicKey'));
    });

    test('seal and open snapshot all inputs synchronously', () async {
      final publicKey = k('publicKey');
      final privateKey = k('privateKey');
      final storeKey = k('storeKey');
      final context = k('hpkeContext');
      final seed = k('ephemeralSeed');
      final envelope = k('envelope');
      final sealing = sealMethodStoreKey(
        publicKey: publicKey,
        storeKey: storeKey,
        context: context,
        ephemeralSeed: seed,
      );
      final opening = openMethodStoreKey(
        privateKey: privateKey,
        sealedStoreKey: envelope,
        context: context,
      );
      for (final bytes in [
        publicKey,
        privateKey,
        storeKey,
        context,
        seed,
        envelope,
      ]) {
        bytes.fillRange(0, bytes.length, 0);
      }
      expect(await sealing, k('envelope'));
      expect(await opening, k('storeKey'));
    });

    test(
      'successful and rejected opens leave borrowed inputs intact',
      () async {
        final privateKey = k('privateKey');
        final envelope = k('envelope');
        final context = k('hpkeContext');
        await openMethodStoreKey(
          privateKey: privateKey,
          sealedStoreKey: envelope,
          context: context,
        );
        final badContext = Uint8List.fromList(context)..[0] ^= 1;
        await expectLater(
          openMethodStoreKey(
            privateKey: privateKey,
            sealedStoreKey: envelope,
            context: badContext,
          ),
          _authenticationFailure,
        );
        expect(privateKey, k('privateKey'));
        expect(envelope, k('envelope'));
        expect(context, k('hpkeContext'));
      },
    );
  });

  test('pinned HMAC output is writable for explicit HKDF cleanup', () {
    final secret = SecretKeyData(Uint8List(32), overwriteWhenDestroyed: true);
    try {
      final mac = const DartHmac(
        DartSha256(),
      ).calculateMacSync([1, 2, 3], secretKeyData: secret, nonce: const []);
      expect(mac.bytes, isA<Uint8List>());
      mac.bytes.fillRange(0, mac.bytes.length, 0);
      expect(mac.bytes, everyElement(0));
    } finally {
      secret.destroy();
    }
  });

  for (final validTag in [true, false]) {
    test('pinned HPKE AEAD uses owned workspace, valid=$validTag', () async {
      final keyBytes = Uint8List(32)..fillRange(0, 32, 13);
      final key = SecretKeyData(keyBytes, overwriteWhenDestroyed: true);
      final cipher = DartChacha20.poly1305Aead();
      final plaintext = Uint8List(32)..fillRange(0, 32, 19);
      Uint8List? workspace;
      try {
        final box = await cipher.encrypt(
          plaintext,
          secretKey: key,
          nonce: Uint8List(12),
          aad: const [1, 2, 3],
        );
        workspace = Uint8List.fromList(box.cipherText);
        final tag = Uint8List.fromList(box.mac.bytes);
        if (!validTag) tag[0] ^= 1;
        final opening = cipher.decrypt(
          SecretBox(workspace, nonce: box.nonce, mac: Mac(tag)),
          secretKey: key,
          aad: const [1, 2, 3],
          possibleBuffer: workspace,
          chunkSize: -1,
        );
        if (validTag) {
          expect(await opening, same(workspace));
        } else {
          await expectLater(
            opening,
            throwsA(isA<SecretBoxAuthenticationError>()),
          );
        }
        // The dependency writes plaintext before verifying its MAC. The method
        // helper's owned buffer must therefore be wiped in either terminal path.
        expect(workspace, plaintext);
      } finally {
        workspace?.fillRange(0, workspace.length, 0);
        plaintext.fillRange(0, plaintext.length, 0);
        key.destroy();
      }
      expect(workspace, everyElement(0));
      expect(keyBytes, everyElement(0));
    });
  }
}

Matcher get _authenticationFailure => throwsA(
  isA<V2CryptoFailure>().having(
    (e) => e.code,
    'code',
    V2CryptoFailureCode.authenticationFailed,
  ),
);

Matcher get _invalidInputFailure => throwsA(
  isA<V2CryptoFailure>().having(
    (e) => e.code,
    'code',
    V2CryptoFailureCode.invalidInput,
  ),
);

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

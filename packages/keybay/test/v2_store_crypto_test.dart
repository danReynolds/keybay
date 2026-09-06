@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(File('test/vectors/v2_suite1.json').readAsStringSync())
          as Map<String, Object?>;
  final inputs = fixture['inputs']! as Map<String, Object?>;
  final outputs = fixture['outputs']! as Map<String, Object?>;

  Uint8List inputBytes(String name) => _bytes(inputs[name]! as String);
  Uint8List outputBytes(String name) => _bytes(outputs[name]! as String);
  String inputString(String name) => inputs[name]! as String;
  int inputInt(String name) => inputs[name]! as int;

  late Uint8List storageDomain;
  late Uint8List sealedPackage;
  late Uint8List storeId;
  late Uint8List storeKey;
  late Uint8List methodId;
  late Uint8List salt;
  late Uint8List passphraseKey;
  late V2BootstrapCore bootstrapCore;
  late V2Bootstrap bootstrap;

  setUp(() {
    storageDomain = inputBytes('storageDomain');
    sealedPackage = inputBytes('sealedPackage');
    storeId = inputBytes('storeId');
    storeKey = inputBytes('storeKey');
    methodId = inputBytes('methodId');
    salt = inputBytes('salt');
    passphraseKey = inputBytes('passphraseKey');
    bootstrapCore = V2BootstrapCore(inputBytes('providerState'));
    bootstrap = V2Bootstrap(
      core: bootstrapCore,
      sealedPackageLength: sealedPackage.length,
    );
  });

  group('language-neutral suite-1 fixture', () {
    test('records its independent implementation', () {
      expect(fixture['suite'], v2PrimitiveSuite);
      expect(
        fixture['crossReference'],
        contains('golang.org/x/crypto/chacha20poly1305'),
      );
      expect(fixture['referenceSource'], 'tool/v2_suite1_reference_go');
    });

    test('freezes bootstrap, package plaintext, and every AAD transcript', () {
      expect(encodeBootstrapCore(bootstrapCore), outputBytes('bootstrapCore'));
      expect(encodeBootstrap(bootstrap), outputBytes('bootstrap'));
      expect(
        encodeKeyPackage(
          V2PlatformOnlyPackage(
            storeId: storeId,
            epoch: inputInt('epoch'),
            storeKey: storeKey,
          ),
        ),
        outputBytes('platformPackagePlaintext'),
      );
      expect(
        encodePlatformPackageAad(
          storageDomain: storageDomain,
          bootstrapCore: bootstrapCore,
        ),
        outputBytes('packageAad'),
      );
      expect(
        encodeManifestAad(
          storageDomain: storageDomain,
          bootstrap: bootstrap,
          sealedPackage: sealedPackage,
        ),
        outputBytes('manifestAad'),
      );
      expect(
        encodePassphraseEnvelopeAad(
          storeId: storeId,
          epoch: inputInt('epoch'),
          methodId: methodId,
          profileId: v2FirstPassphraseProfile,
          salt: salt,
        ),
        outputBytes('passphraseAad'),
      );
      expect(
        encodeRecordFrameAad(
          storeId: storeId,
          epoch: inputInt('epoch'),
          key: inputString('recordKey'),
        ),
        outputBytes('recordAad'),
      );
    });

    test('freezes both HKDF outputs', () async {
      expect(
        await deriveManifestKey(storeKey: storeKey, storeId: storeId),
        outputBytes('manifestKey'),
      );
      expect(
        await deriveRecordFrameKey(storeKey: storeKey, storeId: storeId),
        outputBytes('recordFrameKey'),
      );
    });

    test('freezes record sealing and exact-frame digest', () async {
      final value = Uint8List.fromList(
        utf8.encode(inputString('recordValueUtf8')),
      );
      final frame = await sealRecordFrame(
        storeKey: storeKey,
        storeId: storeId,
        epoch: inputInt('epoch'),
        key: inputString('recordKey'),
        value: value,
        nonce: inputBytes('recordNonce'),
      );
      expect(frame, outputBytes('recordFrame'));
      expect(digestFrame(frame), outputBytes('recordDigest'));
      expect(
        await openRecordFrame(
          storeKey: storeKey,
          storeId: storeId,
          epoch: inputInt('epoch'),
          key: inputString('recordKey'),
          sealedFrame: frame,
        ),
        value,
      );
    });

    test('freezes manifest sealing and opening', () async {
      final manifest = _fixtureManifest(inputs, outputs);
      expect(encodeManifest(manifest), outputBytes('manifestPlaintext'));
      final sealed = await sealManifest(
        storeKey: storeKey,
        storeId: storeId,
        storageDomain: storageDomain,
        bootstrap: bootstrap,
        sealedPackage: sealedPackage,
        manifest: manifest,
        nonce: inputBytes('manifestNonce'),
      );
      expect(sealed, outputBytes('sealedManifest'));

      final opened = await openManifest(
        storeKey: storeKey,
        storeId: storeId,
        storageDomain: storageDomain,
        bootstrap: bootstrap,
        sealedPackage: sealedPackage,
        sealedManifest: sealed,
      );
      expect(
        opened.entries.single.copyKeyBytes(),
        utf8.encode('service/token'),
      );
      expect(
        opened.entries.single.hasFrameDigest(outputBytes('recordDigest')),
        isTrue,
      );
      opened.clear();
      manifest.clear();
    });

    test('freezes passphrase envelope and package plaintext', () async {
      final envelope = await sealPassphraseEnvelope(
        passphraseKey: passphraseKey,
        storeKey: storeKey,
        storeId: storeId,
        epoch: inputInt('epoch'),
        methodId: methodId,
        profileId: v2FirstPassphraseProfile,
        salt: salt,
        nonce: inputBytes('passphraseNonce'),
      );
      expect(envelope, outputBytes('passphraseEnvelope'));
      expect(
        await openPassphraseEnvelope(
          passphraseKey: passphraseKey,
          storeId: storeId,
          epoch: inputInt('epoch'),
          methodId: methodId,
          profileId: v2FirstPassphraseProfile,
          salt: salt,
          innerEnvelope: envelope,
        ),
        storeKey,
      );
      expect(
        encodeKeyPackage(
          V2PassphrasePackage(
            storeId: storeId,
            epoch: inputInt('epoch'),
            methodId: methodId,
            profileId: v2FirstPassphraseProfile,
            salt: salt,
            innerEnvelope: envelope,
          ),
        ),
        outputBytes('passphrasePackagePlaintext'),
      );
    });
  });

  group('authenticated context', () {
    test('package AAD excludes the not-yet-known package length', () {
      final first = encodePlatformPackageAad(
        storageDomain: storageDomain,
        bootstrapCore: bootstrapCore,
      );
      final differentLength = V2Bootstrap(
        core: bootstrapCore,
        sealedPackageLength: sealedPackage.length + 1,
      );
      expect(
        encodePlatformPackageAad(
          storageDomain: storageDomain,
          bootstrapCore: differentLength.core,
        ),
        first,
      );
    });

    test('manifest AAD requires the exact declared opaque package', () {
      expect(
        () => encodeManifestAad(
          storageDomain: storageDomain,
          bootstrap: bootstrap,
          sealedPackage: Uint8List.sublistView(
            sealedPackage,
            0,
            sealedPackage.length - 1,
          ),
        ),
        throwsA(_cryptoFailure(V2CryptoFailureCode.invalidInput)),
      );
    });

    test('record authentication binds epoch and exact canonical key', () async {
      final frame = outputBytes('recordFrame');
      for (final operation in <Future<Uint8List> Function()>[
        () => openRecordFrame(
          storeKey: storeKey,
          storeId: storeId,
          epoch: inputInt('epoch') + 1,
          key: inputString('recordKey'),
          sealedFrame: frame,
        ),
        () => openRecordFrame(
          storeKey: storeKey,
          storeId: storeId,
          epoch: inputInt('epoch'),
          key: 'service/other',
          sealedFrame: frame,
        ),
      ]) {
        await expectLater(
          operation(),
          throwsA(_cryptoFailure(V2CryptoFailureCode.authenticationFailed)),
        );
      }
    });

    test('manifest authentication binds bootstrap and package bytes', () async {
      final sealed = outputBytes('sealedManifest');
      final changedCore = V2BootstrapCore([0xde, 0xad, 0xbe, 0xee]);
      final changedBootstrap = V2Bootstrap(
        core: changedCore,
        sealedPackageLength: sealedPackage.length,
      );
      await expectLater(
        openManifest(
          storeKey: storeKey,
          storeId: storeId,
          storageDomain: storageDomain,
          bootstrap: changedBootstrap,
          sealedPackage: sealedPackage,
          sealedManifest: sealed,
        ),
        throwsA(_cryptoFailure(V2CryptoFailureCode.authenticationFailed)),
      );

      final changedPackage = Uint8List.fromList(sealedPackage)..[0] ^= 1;
      await expectLater(
        openManifest(
          storeKey: storeKey,
          storeId: storeId,
          storageDomain: storageDomain,
          bootstrap: bootstrap,
          sealedPackage: changedPackage,
          sealedManifest: sealed,
        ),
        throwsA(_cryptoFailure(V2CryptoFailureCode.authenticationFailed)),
      );
    });

    test('passphrase envelope binds all method metadata', () async {
      final envelope = outputBytes('passphraseEnvelope');
      final changedSalt = Uint8List.fromList(salt)..[0] ^= 1;
      await expectLater(
        openPassphraseEnvelope(
          passphraseKey: passphraseKey,
          storeId: storeId,
          epoch: inputInt('epoch'),
          methodId: methodId,
          profileId: v2FirstPassphraseProfile,
          salt: changedSalt,
          innerEnvelope: envelope,
        ),
        throwsA(_cryptoFailure(V2CryptoFailureCode.authenticationFailed)),
      );
    });

    test(
      'a correct digest never substitutes for frame authentication',
      () async {
        final frame = outputBytes('recordFrame')..[30] ^= 1;
        expect(digestFrame(frame), isNot(outputBytes('recordDigest')));
        await expectLater(
          openRecordFrame(
            storeKey: storeKey,
            storeId: storeId,
            epoch: inputInt('epoch'),
            key: inputString('recordKey'),
            sealedFrame: frame,
          ),
          throwsA(_cryptoFailure(V2CryptoFailureCode.authenticationFailed)),
        );
      },
    );
  });

  group('owned input snapshots', () {
    test('record seal snapshots all mutable inputs before returning', () async {
      final mutableStoreKey = Uint8List.fromList(storeKey);
      final mutableStoreId = Uint8List.fromList(storeId);
      final value = Uint8List.fromList(utf8.encode('correct horse'));
      final nonce = inputBytes('recordNonce');
      final future = sealRecordFrame(
        storeKey: mutableStoreKey,
        storeId: mutableStoreId,
        epoch: inputInt('epoch'),
        key: inputString('recordKey'),
        value: value,
        nonce: nonce,
      );
      _zero(mutableStoreKey);
      _zero(mutableStoreId);
      _zero(value);
      _zero(nonce);
      expect(await future, outputBytes('recordFrame'));
    });

    test('record open snapshots key context and sealed bytes', () async {
      final mutableStoreKey = Uint8List.fromList(storeKey);
      final mutableStoreId = Uint8List.fromList(storeId);
      final frame = outputBytes('recordFrame');
      final future = openRecordFrame(
        storeKey: mutableStoreKey,
        storeId: mutableStoreId,
        epoch: inputInt('epoch'),
        key: inputString('recordKey'),
        sealedFrame: frame,
      );
      _zero(mutableStoreKey);
      _zero(mutableStoreId);
      _zero(frame);
      expect(await future, utf8.encode('correct horse'));
    });

    test(
      'record open never reuses caller ciphertext as plaintext storage',
      () async {
        final frame = outputBytes('recordFrame');
        final original = Uint8List.fromList(frame);
        final plaintext = await openRecordFrame(
          storeKey: storeKey,
          storeId: storeId,
          epoch: inputInt('epoch'),
          key: inputString('recordKey'),
          sealedFrame: frame,
        );
        expect(frame, original);
        _zero(frame);
        expect(plaintext, utf8.encode('correct horse'));

        final tampered = Uint8List.fromList(original)..last ^= 1;
        final tamperedCopy = Uint8List.fromList(tampered);
        await expectLater(
          openRecordFrame(
            storeKey: storeKey,
            storeId: storeId,
            epoch: inputInt('epoch'),
            key: inputString('recordKey'),
            sealedFrame: tampered,
          ),
          throwsA(_cryptoFailure(V2CryptoFailureCode.authenticationFailed)),
        );
        expect(tampered, tamperedCopy);
        _zero(plaintext);
      },
    );

    test('manifest seal snapshots nonce and key context', () async {
      final mutableStoreKey = Uint8List.fromList(storeKey);
      final mutableStoreId = Uint8List.fromList(storeId);
      final nonce = inputBytes('manifestNonce');
      final manifest = _fixtureManifest(inputs, outputs);
      final future = sealManifest(
        storeKey: mutableStoreKey,
        storeId: mutableStoreId,
        storageDomain: storageDomain,
        bootstrap: bootstrap,
        sealedPackage: sealedPackage,
        manifest: manifest,
        nonce: nonce,
      );
      _zero(mutableStoreKey);
      _zero(mutableStoreId);
      _zero(nonce);
      expect(await future, outputBytes('sealedManifest'));
      manifest.clear();
    });

    test('byte-key path reseals without decoding a stored String', () async {
      final manifest = _fixtureManifest(inputs, outputs);
      final keyBytes = manifest.entries.single.copyKeyBytes();
      final frame = await sealRecordFrameBytes(
        storeKey: storeKey,
        storeId: storeId,
        epoch: inputInt('epoch'),
        keyBytes: keyBytes,
        value: Uint8List.fromList(utf8.encode('correct horse')),
        nonce: inputBytes('recordNonce'),
      );
      expect(frame, outputBytes('recordFrame'));
      expect(
        await openRecordFrameBytes(
          storeKey: storeKey,
          storeId: storeId,
          epoch: inputInt('epoch'),
          keyBytes: keyBytes,
          sealedFrame: frame,
        ),
        utf8.encode('correct horse'),
      );
      _zero(keyBytes);
      manifest.clear();
    });
  });

  group('structural rejection', () {
    test('rejects wrong key sizes and malformed frame sizes before crypto', () {
      expect(
        () =>
            deriveManifestKey(storeKey: Uint8List(31), storeId: Uint8List(16)),
        throwsA(_cryptoFailure(V2CryptoFailureCode.invalidInput)),
      );
      expect(
        () => openRecordFrame(
          storeKey: storeKey,
          storeId: storeId,
          epoch: 1,
          key: 'a',
          sealedFrame: Uint8List(39),
        ),
        throwsA(_cryptoFailure(V2CryptoFailureCode.invalidInput)),
      );
    });
  });
}

V2Manifest _fixtureManifest(
  Map<String, Object?> inputs,
  Map<String, Object?> outputs,
) => V2Manifest(<V2ManifestEntry>[
  V2ManifestEntry(
    key: inputs['recordKey']! as String,
    frameLength: _bytes(outputs['recordFrame']! as String).length,
    frameDigest: _bytes(outputs['recordDigest']! as String),
  ),
]);

Matcher _cryptoFailure(V2CryptoFailureCode code) => isA<V2CryptoFailure>()
    .having((error) => error.code, 'code', code)
    .having(
      (error) => error.toString(),
      'redacted',
      'V2CryptoFailure(${code.name})',
    );

Uint8List _bytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var index = 0; index < result.length; index++) {
    result[index] = int.parse(
      hex.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}

void _zero(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

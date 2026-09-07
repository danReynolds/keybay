@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:test/test.dart';

void main() {
  test('manifest cleanup clears names but not public frame digests', () {
    final keyBytes = Uint8List.fromList('service/token'.codeUnits);
    final digest = Uint8List.fromList(
      List<int>.generate(V2StoreLimits.digestBytes, (index) => index),
    );
    final expectedDigest = Uint8List.fromList(digest);
    final entry = V2ManifestEntry.fromKeyBytes(
      keyBytes: keyBytes,
      frameLength: V2StoreLimits.sealedFrameOverhead,
      frameDigest: digest,
    );

    keyBytes.fillRange(0, keyBytes.length, 0);
    digest.fillRange(0, digest.length, 0xff);
    expect(entry.copyKeyBytes(), 'service/token'.codeUnits);
    expect(entry.hasFrameDigest(expectedDigest), isTrue);

    final manifest = V2Manifest(<V2ManifestEntry>[entry]);
    manifest.clear();
    entry.clear();
    expect(entry.copyKeyBytes(), everyElement(0));
    expect(entry.hasFrameDigest(expectedDigest), isTrue);
  });

  test('byte-oriented manifest entries validate bounds before ownership', () {
    expect(
      () => V2ManifestEntry.fromKeyBytes(
        keyBytes: List<int>.filled(V2StoreLimits.recordKeyBytes + 1, 0x61),
        frameLength: V2StoreLimits.sealedFrameOverhead,
        frameDigest: Uint8List(V2StoreLimits.digestBytes),
      ),
      throwsA(
        isA<V2FormatFailure>().having(
          (failure) => failure.code,
          'code',
          V2FormatFailureCode.invalidEncoding,
        ),
      ),
    );
  });

  test('passphrase packages release public fields idempotently', () {
    final storeId = _sequence(0x10, V2StoreLimits.storeIdBytes);
    final methodId = _sequence(0x20, V2StoreLimits.methodIdBytes);
    final salt = _sequence(0x30, V2StoreLimits.argonSaltBytes);
    final envelope = _sequence(
      0x40,
      V2StoreLimits.nonceBytes +
          V2StoreLimits.storeKeyBytes +
          V2StoreLimits.tagBytes,
    );
    final expectedStoreId = Uint8List.fromList(storeId);
    final expectedMethodId = Uint8List.fromList(methodId);
    final expectedSalt = Uint8List.fromList(salt);
    final expectedEnvelope = Uint8List.fromList(envelope);
    final package = V2PassphrasePackage(
      storeId: storeId,
      epoch: 2,
      methodId: methodId,
      profileId: v2FirstPassphraseProfile,
      salt: salt,
      innerEnvelope: envelope,
    );

    storeId.fillRange(0, storeId.length, 0);
    methodId.fillRange(0, methodId.length, 0);
    salt.fillRange(0, salt.length, 0);
    envelope.fillRange(0, envelope.length, 0);
    expect(package.storeId, expectedStoreId);
    expect(package.methodId, expectedMethodId);
    expect(package.salt, expectedSalt);
    expect(package.innerEnvelope, expectedEnvelope);

    package.clear();
    package.clear();
    expect(() => package.storeId, throwsStateError);
    expect(() => package.methodId, throwsStateError);
    expect(() => package.salt, throwsStateError);
    expect(() => package.innerEnvelope, throwsStateError);
    expect(() => encodeKeyPackage(package), throwsStateError);
  });

  test('platform-only package release consumes Kstore', () {
    final package = V2PlatformOnlyPackage(
      storeId: Uint8List(V2StoreLimits.storeIdBytes),
      epoch: 1,
      storeKey: Uint8List(V2StoreLimits.storeKeyBytes),
    );

    package.clear();
    package.clear();
    expect(() => package.storeId, throwsStateError);
    expect(package.takeStoreKey, throwsStateError);
    expect(() => encodeKeyPackage(package), throwsStateError);
  });
}

Uint8List _sequence(int start, int length) => Uint8List.fromList(
  List<int>.generate(length, (index) => (start + index) & 0xff),
);

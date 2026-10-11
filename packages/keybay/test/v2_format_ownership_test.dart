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

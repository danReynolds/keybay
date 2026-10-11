@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2PassphraseDeriver, V2StoreEngine;
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_store_fixture.dart';

// Frozen policy-1 package from the former independently cross-checked suite-1
// vector. Retained only as rejected input, not as a codec or migration helper.
const _retiredPackageHex =
    '101112131415161718191a1b1c1d1e1f000000000000000701404142434445464748494a4b4c4d4e4f01505152535455565758595a5b5c5d5e5fb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7d3e0388e6a379e666d2abc41f8e1feddc73f6b8522f8de693190eb47bc946c2ed0539ef2f7c5f6fc7682371404cfdd4c';

void main() {
  test('retired singleton-passphrase policy is unsupported', () {
    expect(
      () => decodeKeyPackage(_retiredPackage()),
      throwsA(
        isA<V2FormatFailure>().having(
          (error) => error.code,
          'code',
          V2FormatFailureCode.unsupportedPolicy,
        ),
      ),
    );
  });

  for (final withCredential in [false, true]) {
    for (final withStaging in [false, true]) {
      test('retired open preserves state (credential=$withCredential, '
          'staging=$withStaging)', () async {
        final fixture = await buildV2StoreFixture(
          records: {
            'service/token': [1, 2, 3],
          },
          epoch: 7,
          storeId: List.generate(16, (i) => 0x10 + i),
          storeKey: List.generate(32, (i) => 0x20 + i),
        );
        addTearDown(fixture.dispose);
        final original = fixture.bytes;
        final oldBootstrap = decodeBootstrap(
          Uint8List.sublistView(original, 0, fixture.bootstrapLength),
        );
        final state = ProviderState(oldBootstrap.core.providerState);
        final domain = fixture.host.binding.domain.copyBytes();
        final aad = encodePlatformPackageAad(
          storageDomain: domain,
          bootstrapCore: oldBootstrap.core,
        );
        final lease = (await fixture.host.protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ))!;
        late Uint8List sealedPackage;
        late Uint8List retiredStore;
        final storeKey = fixture.copyStoreKey();
        V2Manifest? manifest;
        try {
          manifest = await openManifest(
            storeKey: storeKey,
            storeId: fixture.storeId,
            storageDomain: domain,
            bootstrap: oldBootstrap,
            sealedPackage: Uint8List.sublistView(
              original,
              fixture.packageOffset,
              fixture.frameRegionOffset,
            ),
            sealedManifest: Uint8List.sublistView(
              original,
              fixture.manifestOffset,
              fixture.trailerOffset,
            ),
          );
          sealedPackage = await lease.sealPackage(
            plaintext: _retiredPackage(),
            aad: aad,
          );
          final bootstrap = V2Bootstrap(
            core: oldBootstrap.core,
            sealedPackageLength: sealedPackage.length,
          );
          final sealedManifest = await sealManifest(
            storeKey: storeKey,
            storeId: fixture.storeId,
            storageDomain: domain,
            bootstrap: bootstrap,
            sealedPackage: sealedPackage,
            manifest: manifest,
            nonce: Uint8List.fromList(List.filled(24, 0xed)),
          );
          retiredStore =
              (BytesBuilder()
                    ..add(encodeBootstrap(bootstrap))
                    ..add(sealedPackage)
                    ..add(
                      Uint8List.sublistView(
                        original,
                        fixture.frameRegionOffset,
                        fixture.manifestOffset,
                      ),
                    )
                    ..add(sealedManifest)
                    ..add(encodeManifestLength(sealedManifest.length)))
                  .takeBytes();
        } finally {
          manifest?.clear();
          storeKey.fillRange(0, storeKey.length, 0);
          await lease.close();
        }
        fixture.files.replaceLiveBytes(retiredStore);
        fixture.files.hasTransactionArtifacts = withStaging;
        final generation = fixture.files.liveGeneration;
        final deriver = _UnexpectedDeriver();
        final engine = V2StoreEngine(
          fixture.hostPlatform,
          passphraseDeriver: deriver,
        );
        await expectLater(
          engine.open(
            credential: withCredential
                ? PassphraseCredential(phrase: Uint8List.fromList([1, 2, 3]))
                : null,
          ),
          throwsA(
            isA<KeybayException>().having(
              (error) => error.code,
              'code',
              KeybayErrorCode.unsupportedStoreVersion,
            ),
          ),
        );
        expect(deriver.calls, 0);
        expect(fixture.files.liveGeneration, generation);
        expect(fixture.files.hasTransactionArtifacts, withStaging);
        final pin = (await fixture.files.openPinnedLive())!;
        try {
          expect(
            await pin.readExact(offset: 0, length: pin.length),
            retiredStore,
          );
        } finally {
          await pin.close();
        }
        expect(fixture.files.activeHandleCount, 0);
        // The original provider root must still authenticate the same package.
        final retained = (await fixture.host.protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ))!;
        try {
          expect(
            await retained.openPackage(sealedPackage: sealedPackage, aad: aad),
            _retiredPackage(),
          );
        } finally {
          await retained.close();
        }
      });
    }
  }
}

Uint8List _retiredPackage() => Uint8List.fromList([
  for (var i = 0; i < _retiredPackageHex.length; i += 2)
    int.parse(_retiredPackageHex.substring(i, i + 2), radix: 16),
]);

final class _UnexpectedDeriver implements V2PassphraseDeriver {
  int calls = 0;
  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) async {
    calls++;
    throw StateError('Retired format must fail before Argon derivation.');
  }
}

@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:test/test.dart';

void main() {
  group('V2 frozen limits', () {
    test('are finite and internally consistent', () {
      expect(V2StoreLimits.storeBytes, 16 * 1024 * 1024);
      expect(V2StoreLimits.providerStateBytes, 64);
      expect(V2StoreLimits.sealedPackageBytes, 4096);
      expect(V2StoreLimits.recordCount, 4096);
      expect(V2StoreLimits.recordKeyBytes, 120);
      expect(V2StoreLimits.recordValueBytes, 1024 * 1024);
      expect(V2StoreLimits.getManyInputs, 1024);
      expect(V2StoreLimits.manifestPlaintextBytes, 655364);
      expect(V2StoreLimits.sealedManifestBytes, 655404);
      expect(V2StoreLimits.sealedFrameOverhead, 40);
      expect(V2StoreLimits.argonMemoryKiB, 256 * 1024);
      expect(V2StoreLimits.argonIterations, 10);
      expect(V2StoreLimits.argonParallelism, 4);
    });
  });

  group('bootstrap', () {
    test('fixed-prefix probe returns the bounded full-core length', () {
      final encoded = encodeBootstrapCore(
        V2BootstrapCore(<int>[0xde, 0xad, 0xbe, 0xef]),
      );
      final fixedPrefix = Uint8List.sublistView(
        encoded,
        0,
        v2BootstrapCoreFixedBytes,
      );

      expect(decodeBootstrapCoreLength(fixedPrefix), encoded.length);
    });

    test(
      'fixed-prefix probe rejects size, magic, suite, and length bounds',
      () {
        final valid = Uint8List.sublistView(
          encodeBootstrapCore(V2BootstrapCore(const <int>[])),
          0,
          v2BootstrapCoreFixedBytes,
        );

        expect(
          () => decodeBootstrapCoreLength(
            Uint8List.sublistView(valid, 0, valid.length - 1),
          ),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
        expect(
          () =>
              decodeBootstrapCoreLength(Uint8List.fromList(<int>[...valid, 0])),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );

        final magic = Uint8List.fromList(valid)..[0] ^= 0xff;
        expect(
          () => decodeBootstrapCoreLength(magic),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );

        final suite = Uint8List.fromList(valid)..[5] = 2;
        expect(
          () => decodeBootstrapCoreLength(suite),
          throwsA(_formatFailure(V2FormatFailureCode.unsupportedSuite)),
        );

        final providerLength = Uint8List.fromList(valid);
        ByteData.sublistView(
          providerLength,
        ).setUint32(6, V2StoreLimits.providerStateBytes + 1);
        expect(
          () => decodeBootstrapCoreLength(providerLength),
          throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
        );
      },
    );

    test('has one canonical big-endian encoding', () {
      final core = V2BootstrapCore([0xde, 0xad, 0xbe, 0xef]);
      final bootstrap = V2Bootstrap(core: core, sealedPackageLength: 48);

      expect(_hex(encodeBootstrapCore(core)), '4b425632000100000004deadbeef');
      expect(
        _hex(encodeBootstrap(bootstrap)),
        '4b425632000100000004deadbeef00000030',
      );

      final decoded = decodeBootstrap(encodeBootstrap(bootstrap));
      expect(decoded.core.providerState, [0xde, 0xad, 0xbe, 0xef]);
      expect(decoded.sealedPackageLength, 48);
    });

    test('rejects oversized provider state before copying it', () {
      expect(
        () => V2BootstrapCore(
          List<int>.filled(V2StoreLimits.providerStateBytes + 1, 0),
        ),
        throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
      );
    });

    test('rejects non-byte provider elements instead of truncating them', () {
      for (final invalid in <int>[-1, 256]) {
        expect(
          () => V2BootstrapCore(<int>[invalid]),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
      }
    });

    test(
      'rejects suite changes, hostile lengths, truncation, and suffixes',
      () {
        final valid = encodeBootstrap(
          V2Bootstrap(
            core: V2BootstrapCore(const <int>[]),
            sealedPackageLength: 1,
          ),
        );

        final suite = Uint8List.fromList(valid)..[5] = 2;
        expect(
          () => decodeBootstrap(suite),
          throwsA(_formatFailure(V2FormatFailureCode.unsupportedSuite)),
        );

        final providerLength = Uint8List.fromList(valid);
        ByteData.sublistView(
          providerLength,
        ).setUint32(6, V2StoreLimits.providerStateBytes + 1);
        expect(
          () => decodeBootstrap(providerLength),
          throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
        );

        expect(
          () => decodeBootstrap(
            Uint8List.sublistView(valid, 0, valid.length - 1),
          ),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
        expect(
          () => decodeBootstrap(Uint8List.fromList(<int>[...valid, 0])),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
      },
    );
  });

  group('key packages', () {
    final storeId = _sequence(0x10, V2StoreLimits.storeIdBytes);
    final storeKey = _sequence(0x20, V2StoreLimits.storeKeyBytes);
    final methodId = _sequence(0x40, V2StoreLimits.methodIdBytes);
    final salt = _sequence(0x50, V2StoreLimits.argonSaltBytes);
    final envelope = _sequence(
      0x60,
      V2StoreLimits.nonceBytes +
          V2StoreLimits.storeKeyBytes +
          V2StoreLimits.tagBytes,
    );

    test('platform-only form is fixed width and round-trips', () {
      final package = V2PlatformOnlyPackage(
        storeId: storeId,
        epoch: 7,
        storeKey: storeKey,
      );
      final encoded = encodeKeyPackage(package);
      package.clear();
      expect(encoded, hasLength(v2PlatformOnlyPackageBytes));
      final decoded = decodeKeyPackage(encoded) as V2PlatformOnlyPackage;
      expect(decoded.storeId, storeId);
      expect(decoded.epoch, 7);

      final decodedStoreId = decoded.storeId..fillRange(0, storeId.length, 0);
      expect(decodedStoreId, everyElement(0));
      expect(decoded.storeId, storeId);

      final ownedStoreKey = decoded.takeStoreKey();
      expect(ownedStoreKey, storeKey);
      expect(decoded.takeStoreKey, throwsStateError);
      ownedStoreKey.fillRange(0, ownedStoreKey.length, 0);
      expect(ownedStoreKey, everyElement(0));
    });

    test('platform-only package clear is idempotent and consumes Kstore', () {
      final original = V2PlatformOnlyPackage(
        storeId: storeId,
        epoch: 7,
        storeKey: storeKey,
      );
      final encoded = encodeKeyPackage(original);
      original.clear();
      final package = decodeKeyPackage(encoded) as V2PlatformOnlyPackage;

      package.clear();
      package.clear();
      expect(package.takeStoreKey, throwsStateError);
      expect(() => encodeKeyPackage(package), throwsStateError);
    });

    test('passphrase form is fixed width and round-trips', () {
      final encoded = encodeKeyPackage(
        V2PassphrasePackage(
          storeId: storeId,
          epoch: 8,
          methodId: methodId,
          profileId: v2FirstPassphraseProfile,
          salt: salt,
          innerEnvelope: envelope,
        ),
      );
      expect(encoded, hasLength(v2PassphrasePackageBytes));
      final decoded = decodeKeyPackage(encoded) as V2PassphrasePackage;
      expect(decoded.storeId, storeId);
      expect(decoded.epoch, 8);
      expect(decoded.methodId, methodId);
      expect(decoded.profileId, v2FirstPassphraseProfile);
      expect(decoded.salt, salt);
      expect(decoded.innerEnvelope, envelope);

      decoded.methodId.fillRange(0, methodId.length, 0);
      decoded.salt.fillRange(0, salt.length, 0);
      decoded.innerEnvelope.fillRange(0, envelope.length, 0);
      expect(decoded.methodId, methodId);
      expect(decoded.salt, salt);
      expect(decoded.innerEnvelope, envelope);
    });

    test('unknown policies, profiles, lengths, and epoch zero fail closed', () {
      final platform = encodeKeyPackage(
        V2PlatformOnlyPackage(storeId: storeId, epoch: 1, storeKey: storeKey),
      );
      final policy = Uint8List.fromList(platform)..[24] = 0xff;
      expect(
        () => decodeKeyPackage(policy),
        throwsA(_formatFailure(V2FormatFailureCode.unsupportedPolicy)),
      );
      expect(
        () => decodeKeyPackage(
          Uint8List.sublistView(platform, 0, platform.length - 1),
        ),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
      expect(
        () => V2PlatformOnlyPackage(
          storeId: storeId,
          epoch: 0,
          storeKey: storeKey,
        ),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
      final excessiveEpoch = Uint8List.fromList(platform)..[16] = 0x80;
      expect(
        () => decodeKeyPackage(excessiveEpoch),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
      expect(
        () => V2PassphrasePackage(
          storeId: storeId,
          epoch: 1,
          methodId: methodId,
          profileId: 2,
          salt: salt,
          innerEnvelope: envelope,
        ),
        throwsA(_formatFailure(V2FormatFailureCode.unsupportedKdfProfile)),
      );
      final invalidStoreId = List<int>.of(storeId)..[0] = 256;
      expect(
        () => V2PlatformOnlyPackage(
          storeId: invalidStoreId,
          epoch: 1,
          storeKey: storeKey,
        ),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
    });

    test('method IDs use one lowercase 128-bit hex form', () {
      const encoded = '404142434445464748494a4b4c4d4e4f';
      expect(encodeMethodId(methodId), encoded);
      expect(decodeMethodId(encoded), methodId);
      for (final invalid in <String>[
        encoded.toUpperCase(),
        encoded.substring(2),
        '${encoded.substring(0, 31)}g',
      ]) {
        expect(
          () => decodeMethodId(invalid),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
      }
    });
  });

  group('record-key grammar', () {
    test('accepts only canonical ASCII segments', () {
      for (final valid in <String>[
        'A',
        'service/token',
        'a.b-c_d/0',
        _repeat('x', V2StoreLimits.recordKeyBytes),
      ]) {
        expect(isValidV2RecordKey(valid), isTrue, reason: valid);
      }
      for (final invalid in <String>[
        '',
        '/a',
        'a/',
        'a//b',
        '.a',
        'a/..',
        'a b',
        'café',
        _repeat('x', V2StoreLimits.recordKeyBytes + 1),
      ]) {
        expect(isValidV2RecordKey(invalid), isFalse, reason: invalid);
      }
    });
  });

  group('manifest', () {
    test('round-trips sorted entries without retaining decoded Strings', () {
      final manifest = V2Manifest(<V2ManifestEntry>[
        V2ManifestEntry(
          key: 'a',
          frameLength: 40,
          frameDigest: List<int>.filled(32, 1),
        ),
        V2ManifestEntry(
          key: 'service/token',
          frameLength: 53,
          frameDigest: List<int>.filled(32, 2),
        ),
      ]);
      final encoded = encodeManifest(manifest);
      final decoded = decodeManifest(encoded);

      expect(decoded.entries, hasLength(2));
      expect(decoded.entries[0].copyKeyBytes(), [0x61]);
      expect(decoded.entries[1].compareKeyBytes('service/token'.codeUnits), 0);
      expect(
        decoded.entries[1].hasFrameDigest(List<int>.filled(32, 2)),
        isTrue,
      );
      expect(encodeManifest(decoded), encoded);

      decoded.clear();
      expect(decoded.entries[1].copyKeyBytes(), everyElement(0));
      manifest.clear();
    });

    test('rejects duplicate and nonascending names', () {
      V2ManifestEntry entry(String key) => V2ManifestEntry(
        key: key,
        frameLength: 40,
        frameDigest: List<int>.filled(32, 0),
      );
      expect(
        () => V2Manifest(<V2ManifestEntry>[entry('a'), entry('a')]),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
      expect(
        () => V2Manifest(<V2ManifestEntry>[entry('b'), entry('a')]),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
    });

    test('rejects non-byte digest elements instead of truncating them', () {
      for (final invalid in <int>[-1, 256]) {
        final digest = List<int>.filled(V2StoreLimits.digestBytes, 0)
          ..[0] = invalid;
        expect(
          () => V2ManifestEntry(key: 'a', frameLength: 40, frameDigest: digest),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
      }
    });

    test(
      'rejects hostile counts, names, lengths, truncation, and suffixes',
      () {
        final excessiveCount = _u32(V2StoreLimits.recordCount + 1);
        expect(
          () => decodeManifest(excessiveCount),
          throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
        );

        final excessiveKey = Uint8List.fromList(<int>[
          ..._u32(1),
          ..._u32(V2StoreLimits.recordKeyBytes + 1),
        ]);
        expect(
          () => decodeManifest(excessiveKey),
          throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
        );

        final valid = encodeManifest(
          V2Manifest(<V2ManifestEntry>[
            V2ManifestEntry(
              key: 'a',
              frameLength: 40,
              frameDigest: List<int>.filled(32, 0),
            ),
          ]),
        );
        expect(
          () =>
              decodeManifest(Uint8List.sublistView(valid, 0, valid.length - 1)),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
        expect(
          () => decodeManifest(Uint8List.fromList(<int>[...valid, 0])),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );

        final invalidName = Uint8List.fromList(valid)..[8] = 0x2f;
        expect(
          () => decodeManifest(invalidName),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
        final shortFrame = Uint8List.fromList(valid);
        ByteData.sublistView(shortFrame).setUint32(9, 39);
        expect(
          () => decodeManifest(shortFrame),
          throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
        );
      },
    );

    test('checks list size before copying entries', () {
      final entry = V2ManifestEntry(
        key: 'a',
        frameLength: 40,
        frameDigest: List<int>.filled(32, 0),
      );
      expect(
        () => V2Manifest(
          List<V2ManifestEntry>.filled(V2StoreLimits.recordCount + 1, entry),
        ),
        throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
      );
      V2Manifest(<V2ManifestEntry>[entry]).clear();
    });
  });

  group('layout arithmetic', () {
    test('derives component and frame ranges without persisted offsets', () {
      final layout = deriveStoreLayout(
        fileLength: 18 + 48 + 40 + 53 + 100 + 4,
        bootstrap: V2Bootstrap(
          core: V2BootstrapCore(<int>[0, 1, 2, 3]),
          sealedPackageLength: 48,
        ),
        sealedManifestLength: 100,
      );
      expect(layout.packageOffset, 18);
      expect(layout.frameRegionOffset, 66);
      expect(layout.frameRegionLength, 93);
      expect(layout.manifestOffset, 159);
      expect(layout.trailerOffset, 259);

      final manifest = V2Manifest(<V2ManifestEntry>[
        V2ManifestEntry(
          key: 'a',
          frameLength: 40,
          frameDigest: List<int>.filled(32, 0),
        ),
        V2ManifestEntry(
          key: 'b',
          frameLength: 53,
          frameDigest: List<int>.filled(32, 0),
        ),
      ]);
      final ranges = deriveFrameRanges(
        manifest,
        frameRegionLength: layout.frameRegionLength,
      );
      expect(ranges.map((range) => range.offset), [0, 40]);
      expect(ranges.map((range) => range.length), [40, 53]);
      expect(ranges[1].entry.compareKeyBytes(<int>[0x62]), 0);
      manifest.clear();
    });

    test('rejects overlap, gaps, impossible regions, and oversized files', () {
      final one = V2Manifest(<V2ManifestEntry>[
        V2ManifestEntry(
          key: 'a',
          frameLength: 40,
          frameDigest: List<int>.filled(32, 0),
        ),
      ]);
      for (final length in <int>[39, 41]) {
        expect(
          () => deriveFrameRanges(one, frameRegionLength: length),
          throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
        );
      }
      expect(
        () => deriveStoreLayout(
          fileLength: 20,
          bootstrap: V2Bootstrap(
            core: V2BootstrapCore(const <int>[]),
            sealedPackageLength: 1,
          ),
          sealedManifestLength: 44,
        ),
        throwsA(_formatFailure(V2FormatFailureCode.invalidEncoding)),
      );
      expect(
        () => deriveStoreLayout(
          fileLength: V2StoreLimits.storeBytes + 1,
          bootstrap: V2Bootstrap(
            core: V2BootstrapCore(const <int>[]),
            sealedPackageLength: 1,
          ),
          sealedManifestLength: 44,
        ),
        throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
      );
      one.clear();
    });

    test('manifest trailer has a fixed bounded encoding', () {
      expect(_hex(encodeManifestLength(44)), '0000002c');
      expect(decodeManifestLength(_bytes('0000002c')), 44);
      for (final invalid in <int>[43, V2StoreLimits.sealedManifestBytes + 1]) {
        expect(
          () => encodeManifestLength(invalid),
          throwsA(_formatFailure(V2FormatFailureCode.limitExceeded)),
        );
      }
    });
  });
}

Matcher _formatFailure(V2FormatFailureCode code) => isA<V2FormatFailure>()
    .having((error) => error.code, 'code', code)
    .having(
      (error) => error.toString(),
      'redacted',
      'V2FormatFailure(${code.name})',
    );

Uint8List _sequence(int start, int length) => Uint8List.fromList(
  List<int>.generate(length, (index) => (start + index) & 0xff),
);

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

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

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();

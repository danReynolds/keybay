import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';

import 'v2_pinned_store_files.dart';
import 'v2_platform_fakes.dart';
import 'v2_software_root_lease.dart';

/// Test-only description of one serialized record frame.
final class V2StoreFixtureFrame {
  const V2StoreFixtureFrame({required this.offset, required this.length});

  /// Absolute offset within the complete store snapshot.
  final int offset;

  /// Exact serialized-frame length.
  final int length;
}

/// A valid V2 store plus its bound test host.
///
/// Logical inputs, record ordering, frame nonces, manifest nonce, and layout
/// are deterministic. The provider-opaque package bytes are intentionally not:
/// [SoftwareTestProtector] owns its nonce and uses secure randomness. This does
/// not change component lengths or frame offsets.
///
/// Values returned from [copyStoreKey] and [bytes] are caller-owned. [dispose]
/// clears fixture-owned key material, the encrypted generation, and the test
/// provider root; it cannot clear copies already returned to a test. Never use
/// real secrets in a test fixture.
final class V2StoreFixture {
  V2StoreFixture._({
    required this.host,
    required this.hostPlatform,
    required this.files,
    required SoftwareTestProtector protector,
    required Uint8List encryptedBytes,
    required Uint8List storeId,
    required Uint8List storeKey,
    required this.bootstrapLength,
    required this.packageOffset,
    required this.packageLength,
    required this.frameRegionOffset,
    required this.manifestOffset,
    required this.manifestLength,
    required this.trailerOffset,
    required Map<String, V2StoreFixtureFrame> frames,
  }) : _protector = protector,
       _encryptedBytes = encryptedBytes,
       _storeId = storeId,
       _storeKey = storeKey,
       frames = Map<String, V2StoreFixtureFrame>.unmodifiable(frames);

  final ResolvedHost host;
  final FakeHostPlatform hostPlatform;
  final MemoryPinnedStoreFiles files;
  final SoftwareTestProtector _protector;
  final Uint8List _encryptedBytes;
  final Uint8List _storeId;
  final Uint8List _storeKey;
  bool _disposed = false;

  final int bootstrapLength;
  final int packageOffset;
  final int packageLength;
  final int frameRegionOffset;
  final int manifestOffset;
  final int manifestLength;
  final int trailerOffset;
  final Map<String, V2StoreFixtureFrame> frames;

  /// A fresh copy of the encrypted store snapshot.
  Uint8List get bytes {
    _ensureLive();
    return Uint8List.fromList(_encryptedBytes);
  }

  /// A fresh copy of the non-secret store identifier.
  Uint8List get storeId {
    _ensureLive();
    return Uint8List.fromList(_storeId);
  }

  /// A fresh copy of the test-only store key for authenticated corruption.
  Uint8List copyStoreKey() {
    _ensureLive();
    return Uint8List.fromList(_storeKey);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _clear(_encryptedBytes);
    _clear(_storeId);
    _clear(_storeKey);
    final preparation = await _protector.prepareReset(
      interaction: PlatformInteraction.forbidden,
    );
    try {
      await files.withExclusiveTransaction(
        (transaction) => transaction.resetManagedArtifacts(),
      );
      await preparation.commit();
    } finally {
      await preparation.close();
    }
  }

  void _ensureLive() {
    if (_disposed) throw StateError('The V2 store fixture is disposed.');
  }
}

/// Builds a framed store for M4 reader tests.
///
/// Inputs are synchronously copied before the first asynchronous provider call.
/// Record keys are validated and serialized in canonical ascending byte order.
/// Tests that deliberately reuse [storeKey] across generations must give each
/// generation a distinct [nonceSequence].
Future<V2StoreFixture> buildV2StoreFixture({
  Map<String, List<int>> records = const <String, List<int>>{},
  int epoch = 1,
  List<int>? storeId,
  List<int>? storeKey,
  int nonceSequence = 0,
  bool passphraseProtected = false,
  String applicationId = 'dev.keybay.m4-fixture',
  String profileCode = 'm4-test',
  Uri? canonicalFileRoot,
}) async {
  final binding = ResolvedApplicationBinding.derive(
    identity: ApplicationIdentity(
      stableValue: applicationId,
      source: ApplicationIdentitySource.test,
      assurance: ApplicationIdentityAssurance.namespaceOnly,
    ),
    profile: HostProfile(profileCode),
    canonicalFileRoot:
        canonicalFileRoot ?? Uri.parse('file:///keybay-test/m4-fixture/'),
  );
  final expectedValues = _copyRecords(records);
  late final Uint8List ownedStoreId;
  late final Uint8List ownedStoreKey;
  Uint8List? pendingStoreId;
  try {
    pendingStoreId = _fixedBytes(
      storeId ?? _sequence(0x10, V2StoreLimits.storeIdBytes),
      V2StoreLimits.storeIdBytes,
      'storeId',
    );
    if (nonceSequence < 0 || nonceSequence > 0xffffffff) {
      throw ArgumentError.value(nonceSequence, 'nonceSequence');
    }
    final pendingStoreKey = _fixedBytes(
      storeKey ?? randomTestBytes(V2StoreLimits.storeKeyBytes),
      V2StoreLimits.storeKeyBytes,
      'storeKey',
    );
    ownedStoreId = pendingStoreId;
    ownedStoreKey = pendingStoreKey;
  } on Object {
    if (pendingStoreId != null) _clear(pendingStoreId);
    for (final value in expectedValues.values) {
      _clear(value);
    }
    expectedValues.clear();
    rethrow;
  }
  final registry = InMemoryRootRegistry();
  final protector = SoftwareTestProtector(binding: binding, registry: registry);

  PlatformRootLease? lease;
  V2KeyPackage? keyPackage;
  V2Manifest? manifest;
  Uint8List? packagePlaintext;
  Uint8List? packageAad;
  Uint8List? sealedPackage;
  Uint8List? sealedManifest;
  Uint8List? bootstrapBytes;
  Uint8List? storeBytes;
  final frames = <String, Uint8List>{};
  var committed = false;

  try {
    final creation = await protector.createOnly(
      interaction: PlatformInteraction.forbidden,
    );
    lease = creation.lease;
    final providerState = lease.providerState.copyBytes();
    final bootstrapCore = V2BootstrapCore(providerState);
    _clear(providerState);

    keyPackage = passphraseProtected
        ? V2PassphrasePackage(
            storeId: ownedStoreId,
            epoch: epoch,
            methodId: _sequence(0x20, V2StoreLimits.methodIdBytes),
            profileId: v2FirstPassphraseProfile,
            salt: _sequence(0x30, V2StoreLimits.argonSaltBytes),
            innerEnvelope: _sequence(
              0x70,
              V2StoreLimits.nonceBytes +
                  V2StoreLimits.storeKeyBytes +
                  V2StoreLimits.tagBytes,
            ),
          )
        : V2PlatformOnlyPackage(
            storeId: ownedStoreId,
            epoch: epoch,
            storeKey: ownedStoreKey,
          );
    packagePlaintext = encodeKeyPackage(keyPackage);
    final storageDomain = binding.domain.copyBytes();
    try {
      packageAad = encodePlatformPackageAad(
        storageDomain: storageDomain,
        bootstrapCore: bootstrapCore,
      );
      sealedPackage = await lease.sealPackage(
        plaintext: packagePlaintext,
        aad: packageAad,
      );

      final bootstrap = V2Bootstrap(
        core: bootstrapCore,
        sealedPackageLength: sealedPackage.length,
      );
      bootstrapBytes = encodeBootstrap(bootstrap);

      final manifestEntries = <V2ManifestEntry>[];
      var frameOrdinal = 0;
      for (final entry in expectedValues.entries) {
        final frame = await sealRecordFrame(
          storeKey: ownedStoreKey,
          storeId: ownedStoreId,
          epoch: epoch,
          key: entry.key,
          value: entry.value,
          nonce: _nonce(0x52, ++frameOrdinal, nonceSequence),
        );
        frames[entry.key] = frame;
        final digest = digestFrame(frame);
        try {
          manifestEntries.add(
            V2ManifestEntry(
              key: entry.key,
              frameLength: frame.length,
              frameDigest: digest,
            ),
          );
        } finally {
          _clear(digest);
        }
      }
      manifest = V2Manifest(manifestEntries);
      sealedManifest = await sealManifest(
        storeKey: ownedStoreKey,
        storeId: ownedStoreId,
        storageDomain: storageDomain,
        bootstrap: bootstrap,
        sealedPackage: sealedPackage,
        manifest: manifest,
        nonce: _nonce(0x4d, 1, nonceSequence),
      );

      final frameLocations = <String, V2StoreFixtureFrame>{};
      final packageOffset = bootstrapBytes.length;
      final frameRegionOffset = packageOffset + sealedPackage.length;
      var nextOffset = frameRegionOffset;
      for (final entry in frames.entries) {
        frameLocations[entry.key] = V2StoreFixtureFrame(
          offset: nextOffset,
          length: entry.value.length,
        );
        nextOffset += entry.value.length;
      }
      final manifestOffset = nextOffset;
      final trailerOffset = manifestOffset + sealedManifest.length;
      final trailer = encodeManifestLength(sealedManifest.length);
      try {
        final builder = BytesBuilder()
          ..add(bootstrapBytes)
          ..add(sealedPackage);
        for (final frame in frames.values) {
          builder.add(frame);
        }
        builder
          ..add(sealedManifest)
          ..add(trailer);
        storeBytes = builder.takeBytes();
      } finally {
        _clear(trailer);
      }
      if (storeBytes.length > V2StoreLimits.storeBytes) {
        throw ArgumentError.value(
          storeBytes.length,
          'records',
          'fixture exceeds the complete-store limit',
        );
      }
      final layout = deriveStoreLayout(
        fileLength: storeBytes.length,
        bootstrap: bootstrap,
        sealedManifestLength: sealedManifest.length,
      );
      if (layout.packageOffset != packageOffset ||
          layout.frameRegionOffset != frameRegionOffset ||
          layout.manifestOffset != manifestOffset ||
          layout.trailerOffset != trailerOffset) {
        throw StateError('The fixture layout is internally inconsistent.');
      }

      final files = MemoryPinnedStoreFiles(binding, liveBytes: storeBytes);
      final host = ResolvedHost(
        binding: binding,
        files: files,
        protector: protector,
      );
      final fixture = V2StoreFixture._(
        host: host,
        hostPlatform: FakeHostPlatform(host),
        files: files,
        protector: protector,
        encryptedBytes: Uint8List.fromList(storeBytes),
        storeId: Uint8List.fromList(ownedStoreId),
        storeKey: Uint8List.fromList(ownedStoreKey),
        bootstrapLength: bootstrapBytes.length,
        packageOffset: packageOffset,
        packageLength: sealedPackage.length,
        frameRegionOffset: frameRegionOffset,
        manifestOffset: manifestOffset,
        manifestLength: sealedManifest.length,
        trailerOffset: trailerOffset,
        frames: frameLocations,
      );
      committed = true;
      return fixture;
    } finally {
      _clear(storageDomain);
      _clear(bootstrapCore.providerState);
    }
  } finally {
    try {
      await lease?.close();
    } finally {
      if (keyPackage case final V2PlatformOnlyPackage platformPackage) {
        platformPackage.clear();
      }
      if (packagePlaintext != null) _clear(packagePlaintext);
      if (packageAad != null) _clear(packageAad);
      if (sealedPackage != null) _clear(sealedPackage);
      if (sealedManifest != null) _clear(sealedManifest);
      if (bootstrapBytes != null) _clear(bootstrapBytes);
      if (storeBytes != null) _clear(storeBytes);
      for (final frame in frames.values) {
        _clear(frame);
      }
      _clear(ownedStoreKey);
      _clear(ownedStoreId);
      manifest?.clear();
      for (final value in expectedValues.values) {
        _clear(value);
      }
      expectedValues.clear();
      if (!committed) {
        final preparation = await protector.prepareReset(
          interaction: PlatformInteraction.forbidden,
        );
        try {
          await preparation.commit();
        } finally {
          await preparation.close();
        }
      }
    }
  }
}

Map<String, Uint8List> _copyRecords(Map<String, List<int>> records) {
  if (records.length > V2StoreLimits.recordCount) {
    throw ArgumentError.value(
      records.length,
      'records',
      'fixture exceeds the record-count limit',
    );
  }
  final keys = records.keys.toList()..sort();
  final result = <String, Uint8List>{};
  try {
    for (final key in keys) {
      if (!isValidV2RecordKey(key)) {
        throw ArgumentError.value(key, 'records', 'invalid V2 record key');
      }
      final value = records[key]!;
      if (value.length > V2StoreLimits.recordValueBytes) {
        throw ArgumentError.value(
          value.length,
          'records',
          'fixture record exceeds the value limit',
        );
      }
      result[key] = _copyBytes(value, 'records');
    }
    return result;
  } on Object {
    for (final value in result.values) {
      _clear(value);
    }
    rethrow;
  }
}

Uint8List _fixedBytes(List<int> source, int length, String name) {
  if (source.length != length) {
    throw ArgumentError.value(source.length, name, 'invalid byte length');
  }
  return _copyBytes(source, name);
}

Uint8List _copyBytes(List<int> source, String name) {
  for (final byte in source) {
    if (byte < 0 || byte > 0xff) {
      throw ArgumentError.value('<redacted>', name, 'must contain bytes');
    }
  }
  return Uint8List.fromList(source);
}

Uint8List _sequence(int start, int length) => Uint8List.fromList(
  List<int>.generate(length, (index) => (start + index) & 0xff),
);

Uint8List _nonce(int domain, int ordinal, int sequence) {
  final nonce = Uint8List(V2StoreLimits.nonceBytes)..[0] = domain;
  ByteData.sublistView(nonce).setUint32(1, sequence);
  ByteData.sublistView(nonce).setUint64(V2StoreLimits.nonceBytes - 8, ordinal);
  return nonce;
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

/// Canonical, bounded Keybay V2 store components.
///
/// This library encodes individual components only. It deliberately has no
/// filesystem access and no whole-file decoder: M4 reads a pinned generation
/// selectively, while M5 owns persistence and atomic replacement.
library;

import 'dart:typed_data';

const List<int> v2StoreMagic = <int>[0x4b, 0x42, 0x56, 0x32]; // KBV2
const int v2PrimitiveSuite = 1;
const int v2PlatformOnlyPolicy = 0;
const int v2PassphrasePolicy = 1;
const int v2FirstPassphraseProfile = 1;
const int v2RecordFrameType = 1;
const int v2BootstrapCoreFixedBytes = 10;
const int v2BootstrapLengthBytes = 4;
const int v2ManifestLengthBytes = 4;
const int v2PlatformOnlyPackageBytes = 57;
const int v2PassphrasePackageBytes = 130;

/// Frozen resource bounds applied before allocation or cryptographic work.
abstract final class V2StoreLimits {
  static const int storeBytes = 16 * 1024 * 1024;
  static const int providerStateBytes = 64;
  static const int sealedPackageBytes = 4 * 1024;
  static const int recordCount = 4096;
  static const int recordKeyBytes = 120;
  static const int recordValueBytes = 1024 * 1024;
  static const int getManyInputs = 1024;
  static const int getManyResultBytes = storeBytes;
  static const int storeIdBytes = 16;
  static const int methodIdBytes = 16;
  static const int argonSaltBytes = 16;
  static const int storeKeyBytes = 32;
  static const int digestBytes = 32;
  static const int nonceBytes = 24;
  static const int tagBytes = 16;
  static const int sealedFrameOverhead = nonceBytes + tagBytes;
  static const int sealedFrameBytes = recordValueBytes + sealedFrameOverhead;
  static const int manifestPlaintextBytes =
      4 + recordCount * (4 + recordKeyBytes + 4 + digestBytes);
  static const int sealedManifestBytes =
      manifestPlaintextBytes + sealedFrameOverhead;

  // Absolute bounds for every future allowlisted profile. M6 assigns an
  // immutable measured tuple to profile 1; none of these values are accepted
  // from a store file directly.
  static const int argonMemoryKiB = 256 * 1024;
  static const int argonIterations = 10;
  static const int argonParallelism = 4;
}

enum V2FormatFailureCode {
  invalidEncoding,
  unsupportedSuite,
  unsupportedPolicy,
  unsupportedKdfProfile,
  limitExceeded,
}

/// Redacted structural failure used before the public M4 error mapping exists.
final class V2FormatFailure implements Exception {
  const V2FormatFailure(this.code);

  final V2FormatFailureCode code;

  @override
  String toString() => 'V2FormatFailure(${code.name})';
}

/// Public bytes needed before the platform-sealed package can be opened.
final class V2BootstrapCore {
  factory V2BootstrapCore(List<int> providerState) {
    if (providerState.length > V2StoreLimits.providerStateBytes) {
      throw const V2FormatFailure(V2FormatFailureCode.limitExceeded);
    }
    if (!_containsOnlyBytes(providerState)) _invalid();
    return V2BootstrapCore._(Uint8List.fromList(providerState));
  }

  V2BootstrapCore._(this.providerState);

  final Uint8List providerState;
}

/// The bootstrap core plus its bounded, unauthenticated package locator.
final class V2Bootstrap {
  factory V2Bootstrap({
    required V2BootstrapCore core,
    required int sealedPackageLength,
  }) {
    if (sealedPackageLength < 1 ||
        sealedPackageLength > V2StoreLimits.sealedPackageBytes) {
      throw const V2FormatFailure(V2FormatFailureCode.limitExceeded);
    }
    return V2Bootstrap._(
      core: V2BootstrapCore(core.providerState),
      sealedPackageLength: sealedPackageLength,
    );
  }

  V2Bootstrap._({required this.core, required this.sealedPackageLength});

  final V2BootstrapCore core;
  final int sealedPackageLength;
}

Uint8List encodeBootstrapCore(V2BootstrapCore core) {
  final fixed = ByteData(v2BootstrapCoreFixedBytes)
    ..setUint8(0, v2StoreMagic[0])
    ..setUint8(1, v2StoreMagic[1])
    ..setUint8(2, v2StoreMagic[2])
    ..setUint8(3, v2StoreMagic[3])
    ..setUint16(4, v2PrimitiveSuite)
    ..setUint32(6, core.providerState.length);
  return Uint8List.fromList(<int>[
    ...fixed.buffer.asUint8List(),
    ...core.providerState,
  ]);
}

V2BootstrapCore decodeBootstrapCore(Uint8List bytes) {
  if (bytes.length < v2BootstrapCoreFixedBytes) _invalid();
  final coreLength = decodeBootstrapCoreLength(
    Uint8List.sublistView(bytes, 0, v2BootstrapCoreFixedBytes),
  );
  if (bytes.length != coreLength) _invalid();
  return V2BootstrapCore(
    Uint8List.sublistView(bytes, v2BootstrapCoreFixedBytes),
  );
}

/// Validates the fixed bootstrap prefix and returns its bounded full-core size.
///
/// M4 uses this probe before requesting the variable provider-state bytes. The
/// complete decoder still revalidates the resulting component.
int decodeBootstrapCoreLength(Uint8List fixedPrefix) {
  if (fixedPrefix.length != v2BootstrapCoreFixedBytes) _invalid();
  _requireMagic(fixedPrefix);
  final view = ByteData.sublistView(fixedPrefix);
  if (view.getUint16(4) != v2PrimitiveSuite) {
    throw const V2FormatFailure(V2FormatFailureCode.unsupportedSuite);
  }
  final providerLength = view.getUint32(6);
  if (providerLength > V2StoreLimits.providerStateBytes) _limit();
  return v2BootstrapCoreFixedBytes + providerLength;
}

Uint8List encodeBootstrap(V2Bootstrap bootstrap) => Uint8List.fromList(<int>[
  ...encodeBootstrapCore(bootstrap.core),
  ..._u32(bootstrap.sealedPackageLength),
]);

V2Bootstrap decodeBootstrap(Uint8List bytes) {
  if (bytes.length < v2BootstrapCoreFixedBytes + v2BootstrapLengthBytes) {
    _invalid();
  }
  final coreLength = decodeBootstrapCoreLength(
    Uint8List.sublistView(bytes, 0, v2BootstrapCoreFixedBytes),
  );
  if (bytes.length != coreLength + v2BootstrapLengthBytes) _invalid();
  final packageLength = ByteData.sublistView(bytes).getUint32(coreLength);
  return V2Bootstrap(
    core: decodeBootstrapCore(Uint8List.sublistView(bytes, 0, coreLength)),
    sealedPackageLength: packageLength,
  );
}

sealed class V2KeyPackage {
  V2KeyPackage({required List<int> storeId, required int epoch})
    : epoch = _validatedEpoch(epoch),
      _storeId = _fixedCopy(storeId, V2StoreLimits.storeIdBytes);

  final Uint8List _storeId;
  bool _isCleared = false;

  /// Returns a caller-owned copy of the non-secret store identifier.
  Uint8List get storeId {
    _ensureAvailable();
    return Uint8List.fromList(_storeId);
  }

  final int epoch;

  /// Releases this decoded key package and clears any owned secret material.
  void clear();

  void _markCleared() {
    if (_isCleared) return;
    _isCleared = true;
  }

  void _ensureAvailable() {
    if (_isCleared) {
      throw StateError('The key package has been cleared.');
    }
  }
}

final class V2PlatformOnlyPackage extends V2KeyPackage {
  V2PlatformOnlyPackage({
    required super.storeId,
    required super.epoch,
    required List<int> storeKey,
  }) : _storeKey = _fixedCopy(storeKey, V2StoreLimits.storeKeyBytes);

  Uint8List? _storeKey;

  /// Transfers the mutable store-key buffer to the caller.
  ///
  /// The caller owns and must clear the returned buffer. The package no longer
  /// contains the key and cannot be encoded or consumed again.
  Uint8List takeStoreKey() {
    _ensureAvailable();
    final storeKey = _storeKey;
    if (storeKey == null) {
      throw StateError('The platform-only key package has been consumed.');
    }
    _storeKey = null;
    return storeKey;
  }

  /// Clears an unconsumed store key. This operation is idempotent.
  @override
  void clear() {
    final storeKey = _storeKey;
    if (storeKey != null) {
      storeKey.fillRange(0, storeKey.length, 0);
      _storeKey = null;
    }
    _markCleared();
  }

  Uint8List get _storeKeyForEncoding {
    _ensureAvailable();
    final storeKey = _storeKey;
    if (storeKey == null) {
      throw StateError('The platform-only key package has been consumed.');
    }
    return storeKey;
  }
}

final class V2PassphrasePackage extends V2KeyPackage {
  V2PassphrasePackage({
    required super.storeId,
    required super.epoch,
    required List<int> methodId,
    required int profileId,
    required List<int> salt,
    required List<int> innerEnvelope,
  }) : profileId = _validatedProfileId(profileId),
       _methodId = _fixedCopy(methodId, V2StoreLimits.methodIdBytes),
       _salt = _fixedCopy(salt, V2StoreLimits.argonSaltBytes),
       _innerEnvelope = _fixedCopy(
         innerEnvelope,
         V2StoreLimits.nonceBytes +
             V2StoreLimits.storeKeyBytes +
             V2StoreLimits.tagBytes,
       );

  final Uint8List _methodId;
  final int profileId;
  final Uint8List _salt;
  final Uint8List _innerEnvelope;

  Uint8List get methodId {
    _ensureAvailable();
    return Uint8List.fromList(_methodId);
  }

  Uint8List get salt {
    _ensureAvailable();
    return Uint8List.fromList(_salt);
  }

  Uint8List get innerEnvelope {
    _ensureAvailable();
    return Uint8List.fromList(_innerEnvelope);
  }

  @override
  void clear() {
    if (_isCleared) return;
    _markCleared();
  }
}

Uint8List encodeKeyPackage(V2KeyPackage package) {
  package._ensureAvailable();
  final out = BytesBuilder(copy: false)
    ..add(package._storeId)
    ..add(_u64(package.epoch));
  switch (package) {
    case V2PlatformOnlyPackage():
      out
        ..addByte(v2PlatformOnlyPolicy)
        ..add(package._storeKeyForEncoding);
    case V2PassphrasePackage():
      out
        ..addByte(v2PassphrasePolicy)
        ..add(package._methodId)
        ..addByte(package.profileId)
        ..add(package._salt)
        ..add(package._innerEnvelope);
  }
  return out.takeBytes();
}

V2KeyPackage decodeKeyPackage(Uint8List bytes) {
  const commonLength = V2StoreLimits.storeIdBytes + 8 + 1;
  if (bytes.length < commonLength) _invalid();
  final storeId = Uint8List.sublistView(bytes, 0, 16);
  final epoch = ByteData.sublistView(bytes).getUint64(16);
  final policy = bytes[24];
  switch (policy) {
    case v2PlatformOnlyPolicy:
      if (bytes.length != v2PlatformOnlyPackageBytes) {
        _invalid();
      }
      return V2PlatformOnlyPackage(
        storeId: storeId,
        epoch: epoch,
        storeKey: Uint8List.sublistView(bytes, commonLength),
      );
    case v2PassphrasePolicy:
      if (bytes.length != v2PassphrasePackageBytes) _invalid();
      final profileId = bytes[41];
      return V2PassphrasePackage(
        storeId: storeId,
        epoch: epoch,
        methodId: Uint8List.sublistView(bytes, 25, 41),
        profileId: profileId,
        salt: Uint8List.sublistView(bytes, 42, 58),
        innerEnvelope: Uint8List.sublistView(bytes, 58),
      );
    default:
      throw const V2FormatFailure(V2FormatFailureCode.unsupportedPolicy);
  }
}

String encodeMethodId(List<int> bytes) {
  final id = _fixedCopy(bytes, V2StoreLimits.methodIdBytes);
  final out = StringBuffer();
  for (final byte in id) {
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

Uint8List decodeMethodId(String id) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) _invalid();
  return Uint8List.fromList(<int>[
    for (var index = 0; index < id.length; index += 2)
      int.parse(id.substring(index, index + 2), radix: 16),
  ]);
}

bool isValidV2RecordKey(String key) => isValidV2RecordKeyBytes(key.codeUnits);

bool isValidV2RecordKeyBytes(List<int> key) {
  if (key.isEmpty || key.length > V2StoreLimits.recordKeyBytes) return false;
  var atSegmentStart = true;
  for (final byte in key) {
    if (byte == 0x2f) {
      if (atSegmentStart) return false;
      atSegmentStart = true;
      continue;
    }
    if (atSegmentStart) {
      if (!_isAsciiAlphaNumeric(byte)) return false;
      atSegmentStart = false;
    } else if (!_isRecordKeyByte(byte)) {
      return false;
    }
  }
  return !atSegmentStart;
}

bool _isAsciiAlphaNumeric(int byte) =>
    (byte >= 0x30 && byte <= 0x39) ||
    (byte >= 0x41 && byte <= 0x5a) ||
    (byte >= 0x61 && byte <= 0x7a);

bool _isRecordKeyByte(int byte) =>
    _isAsciiAlphaNumeric(byte) || byte == 0x2e || byte == 0x5f || byte == 0x2d;

final class V2ManifestEntry {
  factory V2ManifestEntry({
    required String key,
    required int frameLength,
    required List<int> frameDigest,
  }) {
    if (!isValidV2RecordKey(key)) _invalid();
    _validateFrameLength(frameLength);
    if (frameDigest.length != V2StoreLimits.digestBytes) _invalid();
    return V2ManifestEntry._owned(
      keyBytes: Uint8List.fromList(key.codeUnits),
      frameLength: frameLength,
      frameDigest: _fixedCopy(frameDigest, V2StoreLimits.digestBytes),
    );
  }

  /// Creates an entry without materializing an immutable record-key String.
  ///
  /// All inputs are copied. The returned entry owns its mutable key-name and
  /// digest buffers and releases the key-name buffer when its manifest clears.
  factory V2ManifestEntry.fromKeyBytes({
    required List<int> keyBytes,
    required int frameLength,
    required List<int> frameDigest,
  }) {
    if (!isValidV2RecordKeyBytes(keyBytes)) _invalid();
    _validateFrameLength(frameLength);
    if (frameDigest.length != V2StoreLimits.digestBytes) _invalid();

    final ownedKey = Uint8List.fromList(keyBytes);
    try {
      return V2ManifestEntry._owned(
        keyBytes: ownedKey,
        frameLength: frameLength,
        frameDigest: _fixedCopy(frameDigest, V2StoreLimits.digestBytes),
      );
    } on Object {
      ownedKey.fillRange(0, ownedKey.length, 0);
      rethrow;
    }
  }

  V2ManifestEntry._owned({
    required Uint8List keyBytes,
    required this.frameLength,
    required Uint8List frameDigest,
  }) : _keyBytes = keyBytes,
       _frameDigest = frameDigest {
    if (!isValidV2RecordKeyBytes(keyBytes) ||
        frameDigest.length != V2StoreLimits.digestBytes) {
      _invalid();
    }
    _validateFrameLength(frameLength);
  }

  final Uint8List _keyBytes;
  final int frameLength;
  final Uint8List _frameDigest;
  bool _isCleared = false;

  /// Returns a fresh mutable copy for key-oriented internal work.
  Uint8List copyKeyBytes() => Uint8List.fromList(_keyBytes);

  /// Orders an encoded requested key against this canonical stored key.
  int compareKeyBytes(List<int> candidate) =>
      _compareBytes(_keyBytes, candidate);

  /// Compares the exact serialized-frame digest without exposing owned bytes.
  bool hasFrameDigest(List<int> candidate) =>
      _sameBytes(_frameDigest, candidate);

  /// Clears the plaintext record-name buffer.
  ///
  /// This is idempotent. It lets streaming rotation code release an entry that
  /// has not yet transferred into a manifest.
  void clear() {
    if (_isCleared) return;
    _keyBytes.fillRange(0, _keyBytes.length, 0);
    _isCleared = true;
  }

  static void _validateFrameLength(int frameLength) {
    if (frameLength < V2StoreLimits.sealedFrameOverhead ||
        frameLength > V2StoreLimits.sealedFrameBytes) {
      _limit();
    }
  }
}

final class V2Manifest {
  V2Manifest(List<V2ManifestEntry> entries)
    : entries = _boundedManifestEntries(entries) {
    Uint8List? previous;
    for (final entry in this.entries) {
      if (!isValidV2RecordKeyBytes(entry._keyBytes) ||
          (previous != null && _compareBytes(previous, entry._keyBytes) >= 0)) {
        _invalid();
      }
      previous = entry._keyBytes;
    }
  }

  final List<V2ManifestEntry> entries;

  /// Clears SDK-owned plaintext record-name buffers after an operation.
  void clear() {
    for (final entry in entries) {
      entry.clear();
    }
  }
}

List<V2ManifestEntry> _boundedManifestEntries(List<V2ManifestEntry> source) {
  if (source.length > V2StoreLimits.recordCount) _limit();
  return List<V2ManifestEntry>.unmodifiable(source);
}

Uint8List encodeManifest(V2Manifest manifest) {
  final out = BytesBuilder(copy: false)..add(_u32(manifest.entries.length));
  for (final entry in manifest.entries) {
    if (!isValidV2RecordKeyBytes(entry._keyBytes)) _invalid();
    out
      ..add(_u32(entry._keyBytes.length))
      ..add(entry._keyBytes)
      ..add(_u32(entry.frameLength))
      ..add(entry._frameDigest);
  }
  final encoded = out.takeBytes();
  if (encoded.length > V2StoreLimits.manifestPlaintextBytes) _limit();
  return encoded;
}

V2Manifest decodeManifest(Uint8List bytes) {
  if (bytes.length > V2StoreLimits.manifestPlaintextBytes) _limit();
  final reader = _Reader(bytes);
  final count = reader.u32();
  if (count > V2StoreLimits.recordCount) _limit();
  final entries = <V2ManifestEntry>[];
  Uint8List? previous;
  try {
    for (var index = 0; index < count; index++) {
      final keyLength = reader.u32();
      if (keyLength < 1 || keyLength > V2StoreLimits.recordKeyBytes) _limit();
      final keyBytes = reader.takeBytes(keyLength);
      var transferred = false;
      try {
        if (!isValidV2RecordKeyBytes(keyBytes) ||
            (previous != null && _compareBytes(previous, keyBytes) >= 0)) {
          _invalid();
        }
        final frameLength = reader.u32();
        final frameDigest = reader.takeBytes(V2StoreLimits.digestBytes);
        entries.add(
          V2ManifestEntry._owned(
            keyBytes: keyBytes,
            frameLength: frameLength,
            frameDigest: frameDigest,
          ),
        );
        previous = keyBytes;
        transferred = true;
      } finally {
        if (!transferred) keyBytes.fillRange(0, keyBytes.length, 0);
      }
    }
    if (!reader.isAtEnd) _invalid();
    return V2Manifest(entries);
  } on Object {
    for (final entry in entries) {
      entry.clear();
    }
    rethrow;
  }
}

final class V2FrameRange {
  const V2FrameRange({
    required this.entry,
    required this.offset,
    required this.length,
  });

  final V2ManifestEntry entry;
  final int offset;
  final int length;
}

/// Bounded component offsets for one pinned store generation.
///
/// This is layout arithmetic only. The bootstrap, package, and manifest still
/// require their respective authentication steps before they are authoritative.
final class V2StoreLayout {
  const V2StoreLayout._({
    required this.packageOffset,
    required this.frameRegionOffset,
    required this.frameRegionLength,
    required this.manifestOffset,
    required this.manifestLength,
    required this.trailerOffset,
  });

  final int packageOffset;
  final int frameRegionOffset;
  final int frameRegionLength;
  final int manifestOffset;
  final int manifestLength;
  final int trailerOffset;
}

/// Derives safe component ranges from already bounded public lengths.
V2StoreLayout deriveStoreLayout({
  required int fileLength,
  required V2Bootstrap bootstrap,
  required int sealedManifestLength,
}) {
  final bootstrapLength = encodeBootstrap(bootstrap).length;
  final sealedPackageLength = bootstrap.sealedPackageLength;
  final maximumBootstrapLength =
      v2BootstrapCoreFixedBytes +
      V2StoreLimits.providerStateBytes +
      v2BootstrapLengthBytes;
  if (fileLength < 0 || fileLength > V2StoreLimits.storeBytes) _limit();
  if (bootstrapLength < v2BootstrapCoreFixedBytes + v2BootstrapLengthBytes ||
      bootstrapLength > maximumBootstrapLength) {
    _limit();
  }
  if (sealedPackageLength < 1 ||
      sealedPackageLength > V2StoreLimits.sealedPackageBytes) {
    _limit();
  }
  encodeManifestLength(sealedManifestLength);

  final packageOffset = bootstrapLength;
  final frameRegionOffset = packageOffset + sealedPackageLength;
  final trailerOffset = fileLength - v2ManifestLengthBytes;
  final manifestOffset = trailerOffset - sealedManifestLength;
  if (trailerOffset < 0 || manifestOffset < frameRegionOffset) _invalid();

  return V2StoreLayout._(
    packageOffset: packageOffset,
    frameRegionOffset: frameRegionOffset,
    frameRegionLength: manifestOffset - frameRegionOffset,
    manifestOffset: manifestOffset,
    manifestLength: sealedManifestLength,
    trailerOffset: trailerOffset,
  );
}

/// Derives frame offsets from authenticated manifest lengths.
List<V2FrameRange> deriveFrameRanges(
  V2Manifest manifest, {
  required int frameRegionLength,
}) {
  if (frameRegionLength < 0 || frameRegionLength > V2StoreLimits.storeBytes) {
    _limit();
  }
  var offset = 0;
  final ranges = <V2FrameRange>[];
  for (final entry in manifest.entries) {
    if (entry.frameLength > frameRegionLength - offset) _invalid();
    ranges.add(
      V2FrameRange(entry: entry, offset: offset, length: entry.frameLength),
    );
    offset += entry.frameLength;
  }
  if (offset != frameRegionLength) _invalid();
  return List<V2FrameRange>.unmodifiable(ranges);
}

Uint8List encodeManifestLength(int length) {
  if (length < V2StoreLimits.sealedFrameOverhead + 4 ||
      length > V2StoreLimits.sealedManifestBytes) {
    _limit();
  }
  return _u32(length);
}

int decodeManifestLength(Uint8List bytes) {
  if (bytes.length != v2ManifestLengthBytes) _invalid();
  final length = ByteData.sublistView(bytes).getUint32(0);
  encodeManifestLength(length);
  return length;
}

void _requireMagic(Uint8List bytes) {
  for (var index = 0; index < v2StoreMagic.length; index++) {
    if (bytes[index] != v2StoreMagic[index]) _invalid();
  }
}

Uint8List _fixedCopy(List<int> bytes, int length) {
  if (bytes.length != length || !_containsOnlyBytes(bytes)) _invalid();
  return Uint8List.fromList(bytes);
}

bool _containsOnlyBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 0xff) return false;
  }
  return true;
}

Uint8List _u32(int value) {
  if (value < 0 || value > 0xffffffff) _invalid();
  return (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
}

Uint8List _u64(int value) {
  if (value < 0 || value > 0x7fffffffffffffff) _invalid();
  return (ByteData(8)..setUint64(0, value)).buffer.asUint8List();
}

int _validatedEpoch(int epoch) {
  if (epoch < 1 || epoch > 0x7fffffffffffffff) _invalid();
  return epoch;
}

int _validatedProfileId(int profileId) {
  if (profileId != v2FirstPassphraseProfile) {
    throw const V2FormatFailure(V2FormatFailureCode.unsupportedKdfProfile);
  }
  return profileId;
}

Never _invalid() =>
    throw const V2FormatFailure(V2FormatFailureCode.invalidEncoding);

Never _limit() =>
    throw const V2FormatFailure(V2FormatFailureCode.limitExceeded);

int _compareBytes(List<int> first, List<int> second) {
  final sharedLength = first.length < second.length
      ? first.length
      : second.length;
  for (var index = 0; index < sharedLength; index++) {
    final difference = first[index] - second[index];
    if (difference != 0) return difference;
  }
  return first.length - second.length;
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

final class _Reader {
  _Reader(this._data) : _view = ByteData.sublistView(_data);

  final Uint8List _data;
  final ByteData _view;
  int offset = 0;

  bool get isAtEnd => offset == _data.length;

  int u32() {
    _need(4);
    final value = _view.getUint32(offset);
    offset += 4;
    return value;
  }

  Uint8List takeBytes(int length) {
    _need(length);
    final value = Uint8List.fromList(
      Uint8List.sublistView(_data, offset, offset + length),
    );
    offset += length;
    return value;
  }

  void _need(int length) {
    if (length < 0 || length > _data.length - offset) _invalid();
  }
}

part of 'store_format.dart';

const int v2MethodsPolicy = 2;
const int v2MethodsSuite = 2;
const int v2MaxMethods = 8;
const int v2MaxPasskeyRecordBytes = 12 * 1024;
const int v2MaxMethodLabelBytes = 256;
const int v2MethodsPackageMaxBytes =
    16 +
    8 +
    1 +
    4 +
    v2MaxMethods * (154 + v2MaxMethodLabelBytes + v2MaxPasskeyRecordBytes);

/// The route used to recover a method's wrapping key.
enum V2AuthMethodKind { passphrase, systemPasskey, hardwarePasskey }

/// One immutable, bounded method inside the platform-authenticated package.
///
/// This format owns encrypted material only. Passkey metadata remains opaque:
/// the engine validates its schema, route, and stable credential identity.
final class V2AuthMethodEnvelope {
  factory V2AuthMethodEnvelope({
    required List<int> methodId,
    required V2AuthMethodKind kind,
    required String label,
    required List<int> salt,
    required int profileId,
    required List<int> publicKey,
    required List<int> keyEnvelope,
    List<int> passkeyRecord = const <int>[],
  }) {
    if (label.length > v2MaxMethodLabelBytes) _limit();
    final labelBytes = utf8.encode(label);
    if (labelBytes.length > v2MaxMethodLabelBytes) _limit();
    // Encoding unpaired UTF-16 surrogates would silently replace the label.
    if (utf8.decode(labelBytes) != label) _invalid();
    if (passkeyRecord.length > v2MaxPasskeyRecordBytes) _limit();
    if (!_containsOnlyBytes(passkeyRecord)) _invalid();
    if (kind == V2AuthMethodKind.passphrase) {
      _validatedProfileId(profileId);
      if (passkeyRecord.isNotEmpty) _invalid();
    } else {
      if (profileId != 0 || passkeyRecord.isEmpty) _invalid();
      _decodeMethodUtf8(passkeyRecord);
    }
    return V2AuthMethodEnvelope._(
      methodId: _fixedCopy(methodId, V2StoreLimits.methodIdBytes),
      kind: kind,
      label: label,
      salt: _fixedCopy(salt, V2StoreLimits.argonSaltBytes),
      profileId: profileId,
      publicKey: _fixedCopy(publicKey, 32),
      keyEnvelope: _fixedCopy(keyEnvelope, 80),
      passkeyRecord: Uint8List.fromList(passkeyRecord),
    );
  }

  V2AuthMethodEnvelope._({
    required Uint8List methodId,
    required this.kind,
    required this.label,
    required Uint8List salt,
    required this.profileId,
    required Uint8List publicKey,
    required Uint8List keyEnvelope,
    required Uint8List passkeyRecord,
  }) : _methodId = methodId,
       _salt = salt,
       _publicKey = publicKey,
       _keyEnvelope = keyEnvelope,
       _passkeyRecord = passkeyRecord;

  final Uint8List _methodId;
  final V2AuthMethodKind kind;
  final String label;
  final Uint8List _salt;
  final int profileId;
  final Uint8List _publicKey;
  final Uint8List _keyEnvelope;
  final Uint8List _passkeyRecord;
  bool _isCleared = false;

  Uint8List get methodId => _copyBytes(_methodId);
  Uint8List get salt => _copyBytes(_salt);
  Uint8List get publicKey => _copyBytes(_publicKey);
  Uint8List get keyEnvelope => _copyBytes(_keyEnvelope);
  Uint8List get passkeyRecord => _copyBytes(_passkeyRecord);

  /// Replaces the store-key envelope without changing the method identity.
  V2AuthMethodEnvelope withKeyEnvelope(List<int> bytes) =>
      _copy(keyEnvelope: bytes);

  /// Replaces mutable provider metadata after successful authentication.
  V2AuthMethodEnvelope withPasskeyRecord(List<int> bytes) =>
      _copy(passkeyRecord: bytes);

  V2AuthMethodEnvelope _copy({
    List<int>? keyEnvelope,
    List<int>? passkeyRecord,
  }) {
    _ensureAvailable();
    return V2AuthMethodEnvelope(
      methodId: _methodId,
      kind: kind,
      label: label,
      salt: _salt,
      profileId: profileId,
      publicKey: _publicKey,
      keyEnvelope: keyEnvelope ?? _keyEnvelope,
      passkeyRecord: passkeyRecord ?? _passkeyRecord,
    );
  }

  Uint8List _copyBytes(Uint8List bytes) {
    _ensureAvailable();
    return Uint8List.fromList(bytes);
  }

  void _ensureAvailable() {
    if (_isCleared) {
      throw StateError('The authentication method has been cleared.');
    }
  }

  void _clear() {
    if (_isCleared) return;
    for (final bytes in <Uint8List>[
      _methodId,
      _salt,
      _publicKey,
      _keyEnvelope,
      _passkeyRecord,
    ]) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _isCleared = true;
  }
}

/// A canonical directory of independent methods, each wrapping the store key.
///
/// Input envelopes are cloned so clearing this package cannot invalidate the
/// caller's envelopes or another package. Returned envelopes cannot be mutated.
final class V2MethodsPackage extends V2KeyPackage {
  factory V2MethodsPackage({
    required List<int> storeId,
    required int epoch,
    required List<V2AuthMethodEnvelope> methods,
  }) {
    if (methods.isEmpty || methods.length > v2MaxMethods) _limit();
    final owned = <V2AuthMethodEnvelope>[];
    try {
      for (final method in methods) {
        owned.add(method._copy());
      }
      owned.sort(
        (first, second) => _compareBytes(first._methodId, second._methodId),
      );
      var passphrases = 0;
      Uint8List? previous;
      for (final method in owned) {
        if (previous != null &&
            _compareBytes(previous, method._methodId) >= 0) {
          _invalid();
        }
        if (method.kind == V2AuthMethodKind.passphrase && ++passphrases > 1) {
          _invalid();
        }
        previous = method._methodId;
      }
      return V2MethodsPackage._(
        storeId: storeId,
        epoch: epoch,
        methods: List<V2AuthMethodEnvelope>.unmodifiable(owned),
      );
    } on Object {
      for (final method in owned) {
        method._clear();
      }
      rethrow;
    }
  }

  V2MethodsPackage._({
    required super.storeId,
    required super.epoch,
    required List<V2AuthMethodEnvelope> methods,
  }) : _methods = methods;

  final List<V2AuthMethodEnvelope> _methods;

  List<V2AuthMethodEnvelope> get methods {
    _ensureAvailable();
    return _methods;
  }

  @override
  void clear() {
    if (_isCleared) return;
    for (final method in _methods) {
      method._clear();
    }
    _markCleared();
  }
}

Uint8List _encodeMethodsPackage(V2MethodsPackage package) {
  package._ensureAvailable();
  final out = BytesBuilder(copy: false)
    ..add(package._storeId)
    ..add(_u64(package.epoch))
    ..addByte(v2MethodsPolicy)
    ..add(_u32(package._methods.length));
  for (final method in package._methods) {
    final label = utf8.encode(method.label);
    out
      ..add(method._methodId)
      ..addByte(switch (method.kind) {
        V2AuthMethodKind.passphrase => 1,
        V2AuthMethodKind.systemPasskey => 2,
        V2AuthMethodKind.hardwarePasskey => 3,
      })
      ..add(_u32(label.length))
      ..add(label)
      ..add(method._salt)
      ..addByte(method.profileId)
      ..add(method._publicKey)
      ..add(method._keyEnvelope)
      ..add(_u32(method._passkeyRecord.length))
      ..add(method._passkeyRecord);
  }
  return out.takeBytes();
}

V2MethodsPackage _decodeMethodsPackage(Uint8List bytes) {
  if (bytes.length > v2MethodsPackageMaxBytes) _limit();
  final reader = _Reader(bytes);
  final storeId = reader.takeBytes(16);
  final epochBytes = reader.takeBytes(8);
  final epoch = ByteData.sublistView(epochBytes).getUint64(0);
  if (reader.takeBytes(1).single != v2MethodsPolicy) _invalid();
  final count = reader.u32();
  if (count < 1 || count > v2MaxMethods) _limit();
  final methods = <V2AuthMethodEnvelope>[];
  Uint8List? previous;
  try {
    for (var index = 0; index < count; index++) {
      final methodId = reader.takeBytes(16);
      if (previous != null && _compareBytes(previous, methodId) >= 0) {
        _invalid();
      }
      final kindTag = reader.takeBytes(1).single;
      final kind = switch (kindTag) {
        1 => V2AuthMethodKind.passphrase,
        2 => V2AuthMethodKind.systemPasskey,
        3 => V2AuthMethodKind.hardwarePasskey,
        _ => _invalid(),
      };
      final labelLength = reader.u32();
      if (labelLength > v2MaxMethodLabelBytes) _limit();
      final label = _decodeMethodUtf8(reader.takeBytes(labelLength));
      final salt = reader.takeBytes(16);
      final profileId = reader.takeBytes(1).single;
      final publicKey = reader.takeBytes(32);
      final keyEnvelope = reader.takeBytes(80);
      final recordLength = reader.u32();
      if (recordLength > v2MaxPasskeyRecordBytes) _limit();
      final passkeyRecord = reader.takeBytes(recordLength);
      methods.add(
        V2AuthMethodEnvelope(
          methodId: methodId,
          kind: kind,
          label: label,
          salt: salt,
          profileId: profileId,
          publicKey: publicKey,
          keyEnvelope: keyEnvelope,
          passkeyRecord: passkeyRecord,
        ),
      );
      previous = methodId;
    }
    if (!reader.isAtEnd) _invalid();
    return V2MethodsPackage(storeId: storeId, epoch: epoch, methods: methods);
  } finally {
    for (final method in methods) {
      method._clear();
    }
  }
}

String _decodeMethodUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    _invalid();
  }
}

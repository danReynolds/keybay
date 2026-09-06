/// Frozen cryptographic transcript for the Keybay V2 store format.
///
/// This library has no entropy source, filesystem access, or platform-provider
/// selection. Callers supply every nonce, and platform package sealing remains
/// behind `PlatformRootLease` because its serialized output is provider-opaque.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'store_format.dart';

const String v2ManifestKeyInfo = 'keybay:v2:s1:key:manifest';
const String v2RecordFrameKeyInfo = 'keybay:v2:s1:key:record-frame';
const String v2PlatformPackageAadLabel = 'keybay:v2:s1:aad:platform-package';
const String v2ManifestAadLabel = 'keybay:v2:s1:aad:manifest';
const String v2PassphraseEnvelopeAadLabel =
    'keybay:v2:s1:aad:passphrase-envelope';
const String v2RecordFrameAadLabel = 'keybay:v2:s1:aad:record-frame';

enum V2CryptoFailureCode { invalidInput, authenticationFailed }

/// Redacted primitive-boundary failure used before M4 public error mapping.
final class V2CryptoFailure implements Exception {
  const V2CryptoFailure(this.code);

  final V2CryptoFailureCode code;

  @override
  String toString() => 'V2CryptoFailure(${code.name})';
}

final DartXchacha20 _v2Aead = DartXchacha20.poly1305Aead();
const DartHkdf _v2Hkdf = DartHkdf(
  hmac: DartHmac(DartSha256()),
  outputLength: V2StoreLimits.storeKeyBytes,
);
const DartSha256 _v2Sha256 = DartSha256();

/// Package AAD binds the resolved storage domain and exact bootstrap core.
///
/// The package length is deliberately absent: a provider produces the opaque
/// package before that length exists. Provider open must authenticate and
/// consume the exact bounded blob passed to it.
Uint8List encodePlatformPackageAad({
  required Uint8List storageDomain,
  required V2BootstrapCore bootstrapCore,
}) {
  _requireLength(storageDomain, V2StoreLimits.digestBytes);
  return _encodeAad(v2PlatformPackageAadLabel, <List<int>>[
    storageDomain,
    encodeBootstrapCore(bootstrapCore),
  ]);
}

/// Manifest AAD binds all public prefix bytes through the sealed package.
Uint8List encodeManifestAad({
  required Uint8List storageDomain,
  required V2Bootstrap bootstrap,
  required Uint8List sealedPackage,
}) {
  _requireLength(storageDomain, V2StoreLimits.digestBytes);
  if (sealedPackage.length != bootstrap.sealedPackageLength ||
      sealedPackage.isEmpty ||
      sealedPackage.length > V2StoreLimits.sealedPackageBytes) {
    _invalidInput();
  }
  return _encodeAad(v2ManifestAadLabel, <List<int>>[
    storageDomain,
    encodeBootstrap(bootstrap),
    sealedPackage,
  ]);
}

/// Inner-envelope AAD binds a passphrase route to one store-key epoch.
Uint8List encodePassphraseEnvelopeAad({
  required Uint8List storeId,
  required int epoch,
  required Uint8List methodId,
  required int profileId,
  required Uint8List salt,
}) {
  _requireLength(storeId, V2StoreLimits.storeIdBytes);
  _requireEpoch(epoch);
  _requireLength(methodId, V2StoreLimits.methodIdBytes);
  if (profileId != v2FirstPassphraseProfile) _invalidInput();
  _requireLength(salt, V2StoreLimits.argonSaltBytes);
  return _encodeAad(v2PassphraseEnvelopeAadLabel, <List<int>>[
    storeId,
    _u64(epoch),
    methodId,
    <int>[profileId],
    salt,
  ]);
}

/// Record-frame AAD excludes physical layout so exact frames can be copied.
Uint8List encodeRecordFrameAad({
  required Uint8List storeId,
  required int epoch,
  required String key,
}) => encodeRecordFrameAadBytes(
  storeId: storeId,
  epoch: epoch,
  keyBytes: key.codeUnits,
);

/// Byte-oriented form used when a manifest already owns the canonical name.
Uint8List encodeRecordFrameAadBytes({
  required Uint8List storeId,
  required int epoch,
  required List<int> keyBytes,
}) {
  _requireLength(storeId, V2StoreLimits.storeIdBytes);
  _requireEpoch(epoch);
  if (!isValidV2RecordKeyBytes(keyBytes)) _invalidInput();
  return _encodeAad(v2RecordFrameAadLabel, <List<int>>[
    storeId,
    _u64(epoch),
    <int>[v2RecordFrameType],
    keyBytes,
  ]);
}

/// Derives the suite-1 manifest key. The returned buffer is caller-owned.
Future<Uint8List> deriveManifestKey({
  required Uint8List storeKey,
  required Uint8List storeId,
}) {
  final context = _StoreContext(storeKey, storeId);
  return _withCleanup(
    () => _deriveStoreSubkey(context, v2ManifestKeyInfo),
    context.clear,
  );
}

/// Derives the suite-1 record-frame key. The returned buffer is caller-owned.
Future<Uint8List> deriveRecordFrameKey({
  required Uint8List storeKey,
  required Uint8List storeId,
}) {
  final context = _StoreContext(storeKey, storeId);
  return _withCleanup(
    () => _deriveStoreSubkey(context, v2RecordFrameKeyInfo),
    context.clear,
  );
}

/// Seals one encoded manifest under a caller-supplied fresh nonce.
Future<Uint8List> sealManifest({
  required Uint8List storeKey,
  required Uint8List storeId,
  required Uint8List storageDomain,
  required V2Bootstrap bootstrap,
  required Uint8List sealedPackage,
  required V2Manifest manifest,
  required Uint8List nonce,
}) {
  _requireLength(storeKey, V2StoreLimits.storeKeyBytes);
  _requireLength(storeId, V2StoreLimits.storeIdBytes);
  _requireLength(nonce, V2StoreLimits.nonceBytes);
  final aad = encodeManifestAad(
    storageDomain: storageDomain,
    bootstrap: bootstrap,
    sealedPackage: sealedPackage,
  );
  final plaintext = encodeManifest(manifest);
  final context = _StoreContext(storeKey, storeId);
  final nonceSnapshot = Uint8List.fromList(nonce);
  return _withCleanup(
    () => _sealManifestOwned(
      context: context,
      plaintext: plaintext,
      aad: aad,
      nonce: nonceSnapshot,
    ),
    () {
      _clear(plaintext);
      context.clear();
    },
  );
}

Future<Uint8List> _sealManifestOwned({
  required _StoreContext context,
  required Uint8List plaintext,
  required Uint8List aad,
  required Uint8List nonce,
}) async {
  final key = await _deriveOwnedStoreSubkey(context, v2ManifestKeyInfo);
  try {
    return await _sealOwned(
      plaintext: plaintext,
      key: key,
      nonce: nonce,
      aad: aad,
    );
  } finally {
    key.destroy();
  }
}

/// Authenticates, opens, and canonically decodes one sealed manifest.
Future<V2Manifest> openManifest({
  required Uint8List storeKey,
  required Uint8List storeId,
  required Uint8List storageDomain,
  required V2Bootstrap bootstrap,
  required Uint8List sealedPackage,
  required Uint8List sealedManifest,
}) {
  _requireLength(storeKey, V2StoreLimits.storeKeyBytes);
  _requireLength(storeId, V2StoreLimits.storeIdBytes);
  if (sealedManifest.length < V2StoreLimits.sealedFrameOverhead + 4 ||
      sealedManifest.length > V2StoreLimits.sealedManifestBytes) {
    _invalidInput();
  }
  final aad = encodeManifestAad(
    storageDomain: storageDomain,
    bootstrap: bootstrap,
    sealedPackage: sealedPackage,
  );
  final context = _StoreContext(storeKey, storeId);
  final sealedSnapshot = Uint8List.fromList(sealedManifest);
  return _withCleanup(
    () => _openManifestOwned(
      context: context,
      aad: aad,
      sealedManifest: sealedSnapshot,
    ),
    context.clear,
  );
}

Future<V2Manifest> _openManifestOwned({
  required _StoreContext context,
  required Uint8List aad,
  required Uint8List sealedManifest,
}) async {
  final key = await _deriveOwnedStoreSubkey(context, v2ManifestKeyInfo);
  Uint8List? plaintext;
  try {
    plaintext = await _openOwned(sealed: sealedManifest, key: key, aad: aad);
    return decodeManifest(plaintext);
  } finally {
    if (plaintext != null) _clear(plaintext);
    key.destroy();
  }
}

/// Seals one record value under a caller-supplied fresh nonce.
Future<Uint8List> sealRecordFrame({
  required Uint8List storeKey,
  required Uint8List storeId,
  required int epoch,
  required String key,
  required Uint8List value,
  required Uint8List nonce,
}) => sealRecordFrameBytes(
  storeKey: storeKey,
  storeId: storeId,
  epoch: epoch,
  keyBytes: key.codeUnits,
  value: value,
  nonce: nonce,
);

/// Byte-oriented form used by rotation without making Strings.
Future<Uint8List> sealRecordFrameBytes({
  required Uint8List storeKey,
  required Uint8List storeId,
  required int epoch,
  required List<int> keyBytes,
  required Uint8List value,
  required Uint8List nonce,
}) {
  _requireLength(storeKey, V2StoreLimits.storeKeyBytes);
  _requireLength(storeId, V2StoreLimits.storeIdBytes);
  if (value.length > V2StoreLimits.recordValueBytes) _invalidInput();
  _requireLength(nonce, V2StoreLimits.nonceBytes);
  final aad = encodeRecordFrameAadBytes(
    storeId: storeId,
    epoch: epoch,
    keyBytes: keyBytes,
  );
  final context = _StoreContext(storeKey, storeId);
  final valueSnapshot = Uint8List.fromList(value);
  final nonceSnapshot = Uint8List.fromList(nonce);
  return _withCleanup(
    () => _sealRecordFrameOwned(
      context: context,
      aad: aad,
      value: valueSnapshot,
      nonce: nonceSnapshot,
    ),
    () {
      _clear(valueSnapshot);
      context.clear();
    },
  );
}

Future<Uint8List> _sealRecordFrameOwned({
  required _StoreContext context,
  required Uint8List aad,
  required Uint8List value,
  required Uint8List nonce,
}) async {
  final frameKey = await _deriveOwnedStoreSubkey(context, v2RecordFrameKeyInfo);
  try {
    return await _sealOwned(
      plaintext: value,
      key: frameKey,
      nonce: nonce,
      aad: aad,
    );
  } finally {
    frameKey.destroy();
  }
}

/// Authenticates and opens one record frame.
Future<Uint8List> openRecordFrame({
  required Uint8List storeKey,
  required Uint8List storeId,
  required int epoch,
  required String key,
  required Uint8List sealedFrame,
}) => openRecordFrameBytes(
  storeKey: storeKey,
  storeId: storeId,
  epoch: epoch,
  keyBytes: key.codeUnits,
  sealedFrame: sealedFrame,
);

/// Byte-oriented form used by rotation without making Strings.
Future<Uint8List> openRecordFrameBytes({
  required Uint8List storeKey,
  required Uint8List storeId,
  required int epoch,
  required List<int> keyBytes,
  required Uint8List sealedFrame,
}) {
  _requireLength(storeKey, V2StoreLimits.storeKeyBytes);
  _requireLength(storeId, V2StoreLimits.storeIdBytes);
  if (sealedFrame.length < V2StoreLimits.sealedFrameOverhead ||
      sealedFrame.length > V2StoreLimits.sealedFrameBytes) {
    _invalidInput();
  }
  final aad = encodeRecordFrameAadBytes(
    storeId: storeId,
    epoch: epoch,
    keyBytes: keyBytes,
  );
  final context = _StoreContext(storeKey, storeId);
  final sealedSnapshot = Uint8List.fromList(sealedFrame);
  return _withCleanup(
    () => _openRecordFrameOwned(
      context: context,
      aad: aad,
      sealedFrame: sealedSnapshot,
    ),
    context.clear,
  );
}

Future<Uint8List> _openRecordFrameOwned({
  required _StoreContext context,
  required Uint8List aad,
  required Uint8List sealedFrame,
}) async {
  final frameKey = await _deriveOwnedStoreSubkey(context, v2RecordFrameKeyInfo);
  try {
    return await _openOwned(sealed: sealedFrame, key: frameKey, aad: aad);
  } finally {
    frameKey.destroy();
  }
}

/// Seals `Kstore` inside the passphrase envelope.
Future<Uint8List> sealPassphraseEnvelope({
  required Uint8List passphraseKey,
  required Uint8List storeKey,
  required Uint8List storeId,
  required int epoch,
  required Uint8List methodId,
  required int profileId,
  required Uint8List salt,
  required Uint8List nonce,
}) {
  _requireLength(passphraseKey, V2StoreLimits.storeKeyBytes);
  _requireLength(storeKey, V2StoreLimits.storeKeyBytes);
  _requireLength(nonce, V2StoreLimits.nonceBytes);
  final aad = encodePassphraseEnvelopeAad(
    storeId: storeId,
    epoch: epoch,
    methodId: methodId,
    profileId: profileId,
    salt: salt,
  );
  final keySnapshot = Uint8List.fromList(passphraseKey);
  final storeKeySnapshot = Uint8List.fromList(storeKey);
  final nonceSnapshot = Uint8List.fromList(nonce);
  final ownedKey = SecretKeyData(keySnapshot, overwriteWhenDestroyed: true);
  return _withCleanup(
    () => _sealOwned(
      plaintext: storeKeySnapshot,
      key: ownedKey,
      nonce: nonceSnapshot,
      aad: aad,
    ),
    () {
      ownedKey.destroy();
      _clear(storeKeySnapshot);
    },
  );
}

/// Authenticates the passphrase envelope and returns caller-owned `Kstore`.
Future<Uint8List> openPassphraseEnvelope({
  required Uint8List passphraseKey,
  required Uint8List storeId,
  required int epoch,
  required Uint8List methodId,
  required int profileId,
  required Uint8List salt,
  required Uint8List innerEnvelope,
}) {
  _requireLength(passphraseKey, V2StoreLimits.storeKeyBytes);
  final expectedLength =
      V2StoreLimits.nonceBytes +
      V2StoreLimits.storeKeyBytes +
      V2StoreLimits.tagBytes;
  _requireLength(innerEnvelope, expectedLength);
  final aad = encodePassphraseEnvelopeAad(
    storeId: storeId,
    epoch: epoch,
    methodId: methodId,
    profileId: profileId,
    salt: salt,
  );
  final keySnapshot = Uint8List.fromList(passphraseKey);
  final envelopeSnapshot = Uint8List.fromList(innerEnvelope);
  final ownedKey = SecretKeyData(keySnapshot, overwriteWhenDestroyed: true);
  return _withCleanup(
    () => _openOwned(sealed: envelopeSnapshot, key: ownedKey, aad: aad),
    ownedKey.destroy,
  );
}

/// SHA-256 commitment to the exact serialized frame bytes.
Uint8List digestFrame(Uint8List sealedFrame) {
  if (sealedFrame.length < V2StoreLimits.sealedFrameOverhead ||
      sealedFrame.length > V2StoreLimits.sealedFrameBytes) {
    _invalidInput();
  }
  return Uint8List.fromList(_v2Sha256.hashSync(sealedFrame).bytes);
}

Future<Uint8List> _deriveStoreSubkey(_StoreContext context, String info) async {
  final key = await _deriveOwnedStoreSubkey(context, info);
  try {
    return Uint8List.fromList(key.bytes);
  } finally {
    key.destroy();
  }
}

Future<SecretKeyData> _deriveOwnedStoreSubkey(
  _StoreContext context,
  String info,
) async {
  final source = SecretKeyData(
    Uint8List.fromList(context.storeKey),
    overwriteWhenDestroyed: true,
  );
  SecretKeyData? derived;
  try {
    final dependencyResult = await _v2Hkdf.deriveKey(
      secretKey: source,
      nonce: context.storeId,
      info: ascii.encode(info),
    );
    try {
      derived = SecretKeyData(
        Uint8List.fromList(dependencyResult.bytes),
        overwriteWhenDestroyed: true,
      );
    } finally {
      dependencyResult.destroy();
    }
    return derived;
  } finally {
    source.destroy();
  }
}

Future<Uint8List> _sealOwned({
  required Uint8List plaintext,
  required SecretKeyData key,
  required Uint8List nonce,
  required Uint8List aad,
}) async {
  final box = await _v2Aead.encrypt(
    plaintext,
    secretKey: key,
    nonce: nonce,
    aad: aad,
  );
  return Uint8List.fromList(<int>[
    ...nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

Future<Uint8List> _openOwned({
  required Uint8List sealed,
  required SecretKeyData key,
  required Uint8List aad,
}) async {
  if (sealed.length < V2StoreLimits.sealedFrameOverhead) _invalidInput();
  final tagOffset = sealed.length - V2StoreLimits.tagBytes;
  final nonce = Uint8List.sublistView(sealed, 0, V2StoreLimits.nonceBytes);
  final ciphertext = Uint8List.sublistView(
    sealed,
    V2StoreLimits.nonceBytes,
    tagOffset,
  );
  final tag = Uint8List.sublistView(sealed, tagOffset);
  final workspace = Uint8List.fromList(ciphertext);
  try {
    final dependencyResult = await _v2Aead.decrypt(
      SecretBox(workspace, nonce: nonce, mac: Mac(tag)),
      secretKey: key,
      aad: aad,
      possibleBuffer: workspace,
      chunkSize: -1,
    );
    return Uint8List.fromList(dependencyResult);
  } on SecretBoxAuthenticationError {
    throw const V2CryptoFailure(V2CryptoFailureCode.authenticationFailed);
  } finally {
    _clear(workspace);
  }
}

final class _StoreContext {
  factory _StoreContext(Uint8List storeKey, Uint8List storeId) {
    _requireLength(storeKey, V2StoreLimits.storeKeyBytes);
    _requireLength(storeId, V2StoreLimits.storeIdBytes);
    return _StoreContext._(
      Uint8List.fromList(storeKey),
      Uint8List.fromList(storeId),
    );
  }

  _StoreContext._(this.storeKey, this.storeId);

  final Uint8List storeKey;
  final Uint8List storeId;

  void clear() {
    _clear(storeKey);
  }
}

Future<T> _withCleanup<T>(
  Future<T> Function() operation,
  void Function() cleanup,
) {
  try {
    return operation().whenComplete(cleanup);
  } on Object {
    cleanup();
    rethrow;
  }
}

Uint8List _encodeAad(String label, List<List<int>> fields) {
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode(label))
    ..addByte(0);
  for (final field in fields) {
    out
      ..add(_u32(field.length))
      ..add(field);
  }
  return out.takeBytes();
}

Uint8List _u32(int value) {
  if (value < 0 || value > 0xffffffff) _invalidInput();
  return (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
}

Uint8List _u64(int value) {
  _requireEpoch(value);
  return (ByteData(8)..setUint64(0, value)).buffer.asUint8List();
}

void _requireEpoch(int epoch) {
  if (epoch < 1 || epoch > 0x7fffffffffffffff) _invalidInput();
}

void _requireLength(List<int> bytes, int expected) {
  if (bytes.length != expected) _invalidInput();
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

Never _invalidInput() =>
    throw const V2CryptoFailure(V2CryptoFailureCode.invalidInput);

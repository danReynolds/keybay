/// Credential-derived method keys and fixed-suite, single-shot RFC 9180 HPKE.
///
/// The store authenticates the complete method directory before trusting any
/// recipient public key. HPKE base mode alone does not authenticate a sender.
/// Every call snapshots borrowed inputs before returning its Future. Returned
/// secrets are caller-owned; temporary buffers owned here are cleared. The
/// pinned X25519 implementation and Dart VM can retain internal temporaries.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'store_crypto.dart';

const int methodStoreKeyEnvelopeBytes = 80;
const int _maximumContextBytes = 64 * 1024;
const int _maximumPlaintextBytes = 64 * 1024;
const String _methodPrivateKeyLabel = 'keybay:v2:methods1:key:private';
const String _methodHpkeLabel = 'keybay:v2:methods1:hpke:store-key';
const DartX25519 _x25519 = DartX25519();
const DartHmac _hmac = DartHmac(DartSha256());
final DartChacha20 _aead = DartChacha20.poly1305Aead();
final Uint8List _kemSuite = Uint8List.fromList([75, 69, 77, 0, 32]);
final Uint8List _hpkeSuite = Uint8List.fromList([
  72,
  80,
  75,
  69,
  0,
  32,
  0,
  1,
  0,
  3,
]);
final Uint8List _version = Uint8List.fromList(ascii.encode('HPKE-v1'));
final Uint8List _empty = Uint8List(0);

/// Derives an X25519 private key from an Argon2 output or verified PRF output.
///
/// [context] is the canonical stable method transcript: store ID, method ID,
/// kind, salt and stable passkey record ID where applicable. It excludes the
/// epoch and mutable credential verification state. [salt] is 16 random bytes.
/// No private-key envelope or private key is persisted in the store.
Future<Uint8List> deriveMethodPrivateKey({
  required Uint8List material,
  required Uint8List salt,
  required Uint8List context,
}) {
  _requireLength(material, 32);
  _requireLength(salt, 16);
  _requireContext(context);
  final owned = _OwnedBytes();
  final materialCopy = owned.copy(material);
  final saltCopy = owned.copy(salt);
  final info = owned.join([
    ascii.encode(_methodPrivateKeyLabel),
    [0],
    context,
  ]);
  return _withOwned(owned, () async {
    final prk = _extract(owned, saltCopy, materialCopy);
    return Uint8List.fromList(_expand(owned, prk, info, 32));
  });
}

/// Returns the X25519 public key corresponding to a 32-byte private key.
Future<Uint8List> methodPublicKey({required Uint8List privateKey}) {
  _requireLength(privateKey, 32);
  final owned = _OwnedBytes();
  final privateCopy = owned.copy(privateKey);
  return _withOwned(owned, () async {
    final pair = await _x25519.newKeyPairFromSeed(privateCopy);
    try {
      return Uint8List.fromList((await pair.extractPublicKey()).bytes);
    } finally {
      pair.destroy();
    }
  });
}

/// Encrypts a store key to an authenticated method public key.
///
/// [context] binds store ID, epoch, method ID and immutable method identity.
/// Supply an independently fresh random [ephemeralSeed] for EVERY envelope.
/// The result is `enc[32] || ciphertext[32] || tag[16]` (no serialized nonce).
Future<Uint8List> sealMethodStoreKey({
  required Uint8List publicKey,
  required Uint8List storeKey,
  required Uint8List context,
  required Uint8List ephemeralSeed,
}) {
  _requireLength(storeKey, 32);
  _requireContext(context);
  final info = _methodInfo(context);
  return sealHpkeBase(
    publicKey: publicKey,
    plaintext: storeKey,
    info: info,
    aad: context,
    ephemeralSeed: ephemeralSeed,
  );
}

/// Recovers a provisional store key; authenticate the manifest before use.
Future<Uint8List> openMethodStoreKey({
  required Uint8List privateKey,
  required Uint8List sealedStoreKey,
  required Uint8List context,
}) {
  _requireLength(sealedStoreKey, methodStoreKeyEnvelopeBytes);
  _requireContext(context);
  final info = _methodInfo(context);
  return openHpkeBase(
    privateKey: privateKey,
    sealed: sealedStoreKey,
    info: info,
    aad: context,
  );
}

/// Internal RFC 9180 single-shot primitive, also exercised by published vectors.
///
/// Fixed mode 0 / KEM 0x0020 / KDF 0x0001 / AEAD 0x0003. This is not exported
/// by Keybay's public API. Store code must use [sealMethodStoreKey].
Future<Uint8List> sealHpkeBase({
  required Uint8List publicKey,
  required Uint8List plaintext,
  required Uint8List info,
  required Uint8List aad,
  required Uint8List ephemeralSeed,
}) {
  _requireLength(publicKey, 32);
  _requireLength(ephemeralSeed, 32);
  _requireBound(plaintext.length, _maximumPlaintextBytes);
  _requireBound(info.length, _maximumContextBytes + 128);
  _requireBound(aad.length, _maximumContextBytes);
  final owned = _OwnedBytes();
  final recipient = owned.copy(publicKey);
  final message = owned.copy(plaintext);
  final infoCopy = owned.copy(info);
  final aadCopy = owned.copy(aad);
  final seed = owned.copy(ephemeralSeed);
  return _withOwned(owned, () async {
    // RFC 9180 section 7.1.3: GenerateKeyPair = DeriveKeyPair(random(32)).
    final dkpPrk = _labeledExtract(owned, _kemSuite, _empty, 'dkp_prk', seed);
    final sk = _labeledExpand(owned, _kemSuite, dkpPrk, 'sk', _empty, 32);
    final enc = owned.add(await methodPublicKey(privateKey: sk));
    final dh = await _dh(owned, sk, recipient);
    final shared = _extractAndExpand(owned, dh, enc, recipient);
    final schedule = _keySchedule(owned, shared, infoCopy);
    final key = SecretKeyData(schedule.key, overwriteWhenDestroyed: true);
    try {
      final box = await _aead.encrypt(
        message,
        secretKey: key,
        nonce: schedule.nonce,
        aad: aadCopy,
      );
      return _join([enc, box.cipherText, box.mac.bytes]);
    } finally {
      key.destroy();
    }
  });
}

/// Internal inverse of [sealHpkeBase]; returns caller-owned plaintext.
Future<Uint8List> openHpkeBase({
  required Uint8List privateKey,
  required Uint8List sealed,
  required Uint8List info,
  required Uint8List aad,
}) {
  _requireLength(privateKey, 32);
  if (sealed.length < 48 || sealed.length > _maximumPlaintextBytes + 48) {
    _invalidInput();
  }
  _requireBound(info.length, _maximumContextBytes + 128);
  _requireBound(aad.length, _maximumContextBytes);
  final owned = _OwnedBytes();
  final sk = owned.copy(privateKey);
  final envelope = owned.copy(sealed);
  final infoCopy = owned.copy(info);
  final aadCopy = owned.copy(aad);
  return _withOwned(owned, () async {
    final enc = Uint8List.sublistView(envelope, 0, 32);
    final recipient = owned.add(await methodPublicKey(privateKey: sk));
    final dh = await _dh(owned, sk, enc);
    final shared = _extractAndExpand(owned, dh, enc, recipient);
    final schedule = _keySchedule(owned, shared, infoCopy);
    final key = SecretKeyData(schedule.key, overwriteWhenDestroyed: true);
    final tagOffset = envelope.length - 16;
    final workspace = owned.copy(
      Uint8List.sublistView(envelope, 32, tagOffset),
    );
    try {
      final plaintext = await _aead.decrypt(
        SecretBox(
          workspace,
          nonce: schedule.nonce,
          mac: Mac(Uint8List.sublistView(envelope, tagOffset)),
        ),
        secretKey: key,
        aad: aadCopy,
        possibleBuffer: workspace,
        chunkSize: -1,
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      _authenticationFailed();
    } finally {
      // The dependency decrypts into workspace before verifying the tag.
      // _withOwned clears that workspace on failure as well as success.
      key.destroy();
    }
  });
}

Future<Uint8List> _dh(
  _OwnedBytes owned,
  Uint8List privateKey,
  Uint8List publicKey,
) async {
  final pair = await _x25519.newKeyPairFromSeed(privateKey);
  SecretKey? secret;
  try {
    secret = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    final bytes = owned.copy(await secret.extractBytes());
    var any = 0;
    for (final byte in bytes) {
      any |= byte;
    }
    // Mandatory RFC 9180 section 7.1.4 contributory-behavior check.
    if (any == 0) _authenticationFailed();
    return bytes;
  } finally {
    secret?.destroy();
    pair.destroy();
  }
}

Uint8List _extractAndExpand(
  _OwnedBytes owned,
  Uint8List dh,
  Uint8List enc,
  Uint8List recipient,
) {
  final eaePrk = _labeledExtract(owned, _kemSuite, _empty, 'eae_prk', dh);
  return _labeledExpand(
    owned,
    _kemSuite,
    eaePrk,
    'shared_secret',
    owned.join([enc, recipient]),
    32,
  );
}

({Uint8List key, Uint8List nonce}) _keySchedule(
  _OwnedBytes owned,
  Uint8List shared,
  Uint8List info,
) {
  final pskIdHash = _labeledExtract(
    owned,
    _hpkeSuite,
    _empty,
    'psk_id_hash',
    _empty,
  );
  final infoHash = _labeledExtract(
    owned,
    _hpkeSuite,
    _empty,
    'info_hash',
    info,
  );
  final context = owned.join([
    [0],
    pskIdHash,
    infoHash,
  ]);
  final secret = _labeledExtract(owned, _hpkeSuite, shared, 'secret', _empty);
  return (
    key: _labeledExpand(owned, _hpkeSuite, secret, 'key', context, 32),
    nonce: _labeledExpand(owned, _hpkeSuite, secret, 'base_nonce', context, 12),
  );
}

Uint8List _labeledExtract(
  _OwnedBytes owned,
  Uint8List suite,
  Uint8List salt,
  String label,
  Uint8List ikm,
) => _extract(
  owned,
  salt,
  owned.join([_version, suite, ascii.encode(label), ikm]),
);

Uint8List _labeledExpand(
  _OwnedBytes owned,
  Uint8List suite,
  Uint8List prk,
  String label,
  Uint8List info,
  int length,
) => _expand(
  owned,
  prk,
  owned.join([
    [length >> 8, length & 255],
    _version,
    suite,
    ascii.encode(label),
    info,
  ]),
  length,
);

Uint8List _extract(_OwnedBytes owned, Uint8List salt, Uint8List ikm) =>
    _mac(owned, salt, ikm);

Uint8List _expand(
  _OwnedBytes owned,
  Uint8List prk,
  Uint8List info,
  int length,
) {
  // Every profile output is <= SHA256's output length: exactly one HKDF block.
  if (length < 1 || length > 32) _invalidInput();
  final block = _mac(
    owned,
    prk,
    owned.join([
      info,
      [1],
    ]),
  );
  return owned.copy(Uint8List.sublistView(block, 0, length));
}

Uint8List _mac(_OwnedBytes owned, Uint8List keyBytes, Uint8List input) {
  final key = SecretKeyData(owned.copy(keyBytes), overwriteWhenDestroyed: true);
  try {
    final mac = _hmac.calculateMacSync(
      input,
      secretKeyData: key,
      nonce: _empty,
    );
    // DartHmac's sink returns a writable Uint8List; retain it for cleanup.
    return owned.add(mac.bytes as Uint8List);
  } finally {
    key.destroy();
  }
}

Uint8List _methodInfo(Uint8List context) => _join([
  ascii.encode(_methodHpkeLabel),
  [0],
  context,
]);

Uint8List _join(List<List<int>> fields) {
  final length = fields.fold<int>(0, (sum, field) => sum + field.length);
  final bytes = Uint8List(length);
  var offset = 0;
  for (final field in fields) {
    bytes.setRange(offset, offset + field.length, field);
    offset += field.length;
  }
  return bytes;
}

final class _OwnedBytes {
  final List<Uint8List> _buffers = [];

  Uint8List add(Uint8List bytes) {
    _buffers.add(bytes);
    return bytes;
  }

  Uint8List copy(List<int> bytes) => add(Uint8List.fromList(bytes));

  Uint8List join(List<List<int>> fields) => add(_join(fields));

  void clear() {
    for (final bytes in _buffers) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _buffers.clear();
  }
}

Future<T> _withOwned<T>(_OwnedBytes owned, Future<T> Function() operation) {
  try {
    return operation().whenComplete(owned.clear);
  } on Object {
    owned.clear();
    rethrow;
  }
}

void _requireContext(Uint8List context) {
  if (context.isEmpty) _invalidInput();
  _requireBound(context.length, _maximumContextBytes);
}

void _requireBound(int length, int maximum) {
  if (length > maximum) _invalidInput();
}

void _requireLength(Uint8List bytes, int length) {
  if (bytes.length != length) _invalidInput();
}

Never _invalidInput() =>
    throw const V2CryptoFailure(V2CryptoFailureCode.invalidInput);

Never _authenticationFailed() =>
    throw const V2CryptoFailure(V2CryptoFailureCode.authenticationFailed);

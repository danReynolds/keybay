/// Software package sealing for platform providers with exportable root bytes.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'entropy_source.dart';
import 'format/store_format.dart';
import 'platform_protector.dart';

/// An operation-scoped platform lease backed by an exportable 256-bit root.
///
/// The platform provider remains responsible for durable root custody. This
/// helper owns only the short-lived root copy handed to it and implements the
/// common XChaCha20-Poly1305 package format. The exact caller-provided AAD is
/// authenticated without interpretation.
final class ExportableRootLease implements PlatformRootLease {
  ExportableRootLease({
    required Uint8List root,
    required ProviderState providerState,
    V2EntropySource? entropy,
  }) : _root = _copyRoot(root),
       _providerState = ProviderState(providerState.copyBytes()),
       _entropy = entropy ?? SecureV2EntropySource();

  static final DartXchacha20 _aead = DartXchacha20.poly1305Aead();

  final ProviderState _providerState;
  final V2EntropySource _entropy;
  Uint8List _root;
  bool _closed = false;

  @override
  ProviderState get providerState => _providerState;

  @override
  Future<Uint8List> sealPackage({
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    _ensureOpen();
    if (plaintext.length >
        V2StoreLimits.sealedPackageBytes - V2StoreLimits.sealedFrameOverhead) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }

    // These copies happen before the first await, so later caller mutation
    // cannot alter the cryptographic operation.
    final plaintextCopy = Uint8List.fromList(plaintext);
    final aadCopy = Uint8List.fromList(aad);
    Uint8List? nonce;
    SecretKeyData? operationKey;
    try {
      nonce = _entropy.randomBytes(V2StoreLimits.nonceBytes);
      operationKey = SecretKeyData(
        Uint8List.fromList(_root),
        overwriteWhenDestroyed: true,
      );
      final box = await _aead.encrypt(
        plaintextCopy,
        secretKey: operationKey,
        nonce: nonce,
        aad: aadCopy,
        possibleBuffer: plaintextCopy,
      );
      final sealed =
          Uint8List(nonce.length + box.cipherText.length + box.mac.bytes.length)
            ..setRange(0, nonce.length, nonce)
            ..setRange(
              nonce.length,
              nonce.length + box.cipherText.length,
              box.cipherText,
            )
            ..setRange(
              nonce.length + box.cipherText.length,
              nonce.length + box.cipherText.length + box.mac.bytes.length,
              box.mac.bytes,
            );
      if (sealed.isEmpty || sealed.length > V2StoreLimits.sealedPackageBytes) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.operationFailed,
        );
      }
      return sealed;
    } on PlatformProtectorFailure {
      rethrow;
    } on V2EntropyFailure {
      rethrow;
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    } finally {
      _clear(plaintextCopy);
      operationKey?.destroy();
    }
  }

  @override
  Future<Uint8List> openPackage({
    required Uint8List sealedPackage,
    required Uint8List aad,
  }) async {
    _ensureOpen();
    if (sealedPackage.length < V2StoreLimits.sealedFrameOverhead ||
        sealedPackage.length > V2StoreLimits.sealedPackageBytes) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    }

    // Keep one owned ciphertext workspace. Successful plaintext is copied out
    // before the workspace is cleared; failed authentication releases none.
    final sealedCopy = Uint8List.fromList(sealedPackage);
    final aadCopy = Uint8List.fromList(aad);
    SecretKeyData? operationKey;
    Uint8List? workspace;
    try {
      final tagStart = sealedCopy.length - V2StoreLimits.tagBytes;
      final nonce = Uint8List.sublistView(
        sealedCopy,
        0,
        V2StoreLimits.nonceBytes,
      );
      final tag = Uint8List.sublistView(sealedCopy, tagStart);
      workspace = Uint8List.fromList(
        Uint8List.sublistView(sealedCopy, V2StoreLimits.nonceBytes, tagStart),
      );
      operationKey = SecretKeyData(
        Uint8List.fromList(_root),
        overwriteWhenDestroyed: true,
      );
      final plaintext = await _aead.decrypt(
        SecretBox(workspace, nonce: nonce, mac: Mac(tag)),
        secretKey: operationKey,
        aad: aadCopy,
        possibleBuffer: workspace,
        chunkSize: -1,
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    } on PlatformProtectorFailure {
      rethrow;
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    } finally {
      if (workspace != null) _clear(workspace);
      operationKey?.destroy();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _clear(_root);
    _root = Uint8List(0);
  }

  void _ensureOpen() {
    if (_closed) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.leaseClosed,
      );
    }
  }
}

Uint8List _copyRoot(Uint8List root) {
  if (root.length != V2StoreLimits.storeKeyBytes) {
    throw ArgumentError.value('<redacted>', 'root', 'invalid root length');
  }
  return Uint8List.fromList(root);
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

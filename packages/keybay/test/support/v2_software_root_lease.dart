import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/platform_protector.dart';

/// Shared software sealer for disposable V2 platform-boundary tests.
final class SoftwareRootLease implements PlatformRootLease {
  SoftwareRootLease({
    required Uint8List root,
    required ProviderState providerState,
  }) : _root = Uint8List.fromList(root),
       _providerState = ProviderState(providerState.copyBytes());

  static final DartXchacha20 _aead = DartXchacha20.poly1305Aead();

  final ProviderState _providerState;
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
    final plaintextCopy = Uint8List.fromList(plaintext);
    final aadCopy = Uint8List.fromList(aad);
    try {
      final nonce = randomTestBytes(24);
      final box = await _aead.encrypt(
        plaintextCopy,
        secretKey: SecretKey(_root),
        nonce: nonce,
        aad: aadCopy,
      );
      return Uint8List.fromList(<int>[
        ...nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } finally {
      clearTestBytes(plaintextCopy);
      clearTestBytes(aadCopy);
    }
  }

  @override
  Future<Uint8List> openPackage({
    required Uint8List sealedPackage,
    required Uint8List aad,
  }) async {
    _ensureOpen();
    const nonceLength = 24;
    const tagLength = 16;
    if (sealedPackage.length < nonceLength + tagLength) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    }
    final sealedCopy = Uint8List.fromList(sealedPackage);
    final aadCopy = Uint8List.fromList(aad);
    try {
      final nonce = Uint8List.sublistView(sealedCopy, 0, nonceLength);
      final tagStart = sealedCopy.length - tagLength;
      final ciphertext = Uint8List.sublistView(
        sealedCopy,
        nonceLength,
        tagStart,
      );
      final mac = Uint8List.sublistView(sealedCopy, tagStart);
      final workspace = Uint8List.fromList(ciphertext);
      try {
        final plaintext = await _aead.decrypt(
          SecretBox(workspace, nonce: nonce, mac: Mac(mac)),
          secretKey: SecretKey(_root),
          aad: aadCopy,
          possibleBuffer: workspace,
          chunkSize: -1,
        );
        return Uint8List.fromList(plaintext);
      } on SecretBoxAuthenticationError {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.authenticationFailed,
        );
      } finally {
        clearTestBytes(workspace);
      }
    } finally {
      clearTestBytes(sealedCopy);
      clearTestBytes(aadCopy);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    clearTestBytes(_root);
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

Uint8List randomTestBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = random.nextInt(256);
  }
  return bytes;
}

bool sameTestBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

void clearTestBytes(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

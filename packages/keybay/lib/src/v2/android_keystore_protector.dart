/// Android V2 protection backed by one non-exportable Android Keystore key.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import '../errors.dart';
import '../ffi/jni.dart';
import 'format/store_format.dart';
import 'host_binding.dart';
import 'platform_protector.dart';

const int _purposeEncryptDecrypt = 1 | 2;
const int _encryptMode = 1;
const int _decryptMode = 2;
const int _gcmTagBits = 128;
const int _gcmNonceBytes = 12;
const int _gcmTagBytes = 16;
const int _continuityStateBytes =
    _gcmNonceBytes + V2StoreLimits.digestBytes + _gcmTagBytes;
const String _aliasPrefix = 'keybay.v2.';
const String _strongBoxUnavailable =
    'android/security/keystore/StrongBoxUnavailableException';

/// One Android Keystore ciphertext returned by [AndroidKeystoreAead].
///
/// The object owns snapshots of both buffers and can be cleared after the
/// caller has encoded them.
final class AndroidKeystoreBox {
  AndroidKeystoreBox({required Uint8List nonce, required Uint8List ciphertext})
    : nonce = Uint8List.fromList(nonce),
      ciphertext = Uint8List.fromList(ciphertext);

  final Uint8List nonce;
  final Uint8List ciphertext;

  void clear() {
    _clear(nonce);
    _clear(ciphertext);
  }
}

/// The deliberately narrow Android Keystore seam used by V2.
///
/// Implementations never export key bytes. The alias is supplied by the V2
/// protector, and [seal]/[open] authenticate the exact AAD byte string they
/// receive.
abstract interface class AndroidKeystoreAead {
  Future<bool> contains(String alias);

  /// Creates an AES-256-GCM key when [alias] is not already present.
  ///
  /// Android Keystore has no compare-and-create primitive: the caller must
  /// hold the one profile-level cross-process store lock across this
  /// check-and-generate operation. Returns `true` for generation and `false`
  /// when the already-present key was adopted. The caller then performs a
  /// cryptographic read-back before trusting either result.
  Future<bool> createUnderExclusiveLock(String alias);

  Future<AndroidKeystoreBox> seal({
    required String alias,
    required Uint8List plaintext,
    required Uint8List aad,
  });

  Future<Uint8List> open({
    required String alias,
    required AndroidKeystoreBox box,
    required Uint8List aad,
  });

  Future<void> delete(String alias);
}

/// Android's V2 platform protector.
///
/// The application root remains non-exportable in Android Keystore. Provider
/// state is a GCM-sealed copy of the resolved storage-domain commitment. It
/// proves both key continuity and file-domain binding before the key may seal
/// or open the independent V2 key package.
final class AndroidKeystoreProtector implements PlatformProtector {
  AndroidKeystoreProtector({
    required this.binding,
    AndroidKeystoreAead? keystore,
  }) : _keystore = keystore ?? JniAndroidKeystoreAead();

  @override
  final ResolvedApplicationBinding binding;

  final AndroidKeystoreAead _keystore;

  String get _alias => '$_aliasPrefix${binding.providerAddress}';

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) => _atAndroidBoundary(() async {
    if (state.length != _continuityStateBytes) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    if (!await _keystore.contains(_alias)) return null;
    await _verifyContinuity(state);
    return _AndroidKeystoreLease(
      alias: _alias,
      state: state,
      keystore: _keystore,
    );
  });

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) => _atAndroidBoundary(() async {
    // The common engine holds this application's fixed StoreFiles lock
    // while calling createOnly. Android Keystore itself does not provide
    // atomic compare-and-create for symmetric-key aliases.
    final created = await _keystore.createUnderExclusiveLock(_alias);
    ProviderState? state;
    try {
      state = await _newContinuityState();
      await _verifyContinuity(state);
      return PlatformRootCreation(
        lease: _AndroidKeystoreLease(
          alias: _alias,
          state: state,
          keystore: _keystore,
        ),
        disposition: created
            ? RootCreationDisposition.created
            : RootCreationDisposition.adopted,
      );
    } on PlatformProtectorFailure catch (failure) {
      if (!created &&
          (failure.code == PlatformProtectorFailureCode.authenticationFailed ||
              failure.code == PlatformProtectorFailureCode.invalidated)) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.stateConflict,
        );
      }
      if (created &&
          (failure.code == PlatformProtectorFailureCode.authenticationFailed ||
              failure.code == PlatformProtectorFailureCode.invalidated)) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.operationFailed,
        );
      }
      rethrow;
    }
  });

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) => _atAndroidBoundary(() async {
    // Android Keystore cannot compare-and-delete a non-exportable key.
    // Cryptographically challenging the alias would only make an
    // invalidated key impossible to reset, without preventing a same-UID
    // process from replacing it after the challenge. Preparation therefore
    // establishes only whether this fixed app-private alias existed.
    return _AndroidPreparedReset(
      owner: this,
      wasPresent: await _keystore.contains(_alias),
    );
  });

  Future<ProviderState> _newContinuityState() async {
    final domain = binding.domain.copyBytes();
    final aad = _continuityAad(binding.providerAddress);
    AndroidKeystoreBox? box;
    Uint8List? encoded;
    try {
      box = await _keystore.seal(alias: _alias, plaintext: domain, aad: aad);
      encoded = _encodeBox(box, maximumBytes: _continuityStateBytes);
      if (encoded.length != _continuityStateBytes) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.operationFailed,
        );
      }
      return ProviderState(encoded);
    } finally {
      _clear(domain);
      _clear(aad);
      box?.clear();
      if (encoded != null) _clear(encoded);
    }
  }

  Future<void> _verifyContinuity(ProviderState state) async {
    final encoded = state.copyBytes();
    final aad = _continuityAad(binding.providerAddress);
    final expected = binding.domain.copyBytes();
    AndroidKeystoreBox? box;
    Uint8List? actual;
    try {
      box = _decodeBox(encoded, maximumBytes: _continuityStateBytes);
      try {
        actual = await _keystore.open(alias: _alias, box: box, aad: aad);
      } on PlatformProtectorFailure catch (failure) {
        if (failure.code == PlatformProtectorFailureCode.authenticationFailed) {
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.invalidated,
          );
        }
        rethrow;
      }
      if (!_sameBytes(actual, expected)) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.stateConflict,
        );
      }
    } finally {
      _clear(encoded);
      _clear(aad);
      _clear(expected);
      box?.clear();
      if (actual != null) _clear(actual);
    }
  }

  Future<void> _commitReset(bool wasPresent) async {
    try {
      final exists = await _keystore.contains(_alias);
      if (!exists) return;
      if (!wasPresent) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.resetIncomplete,
        );
      }
      await _keystore.delete(_alias);
      if (await _keystore.contains(_alias)) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.resetIncomplete,
        );
      }
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }
}

final class _AndroidKeystoreLease implements PlatformRootLease {
  _AndroidKeystoreLease({
    required this.alias,
    required ProviderState state,
    required AndroidKeystoreAead keystore,
  }) : _state = ProviderState(state.copyBytes()),
       _keystore = keystore;

  final String alias;
  final ProviderState _state;
  final AndroidKeystoreAead _keystore;
  bool _closed = false;

  @override
  ProviderState get providerState => _state;

  @override
  Future<Uint8List> sealPackage({
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    _ensureOpen();
    if (plaintext.length >
        V2StoreLimits.sealedPackageBytes - _gcmNonceBytes - _gcmTagBytes) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    final plaintextCopy = Uint8List.fromList(plaintext);
    final aadCopy = Uint8List.fromList(aad);
    AndroidKeystoreBox? box;
    try {
      box = await _keystore.seal(
        alias: alias,
        plaintext: plaintextCopy,
        aad: aadCopy,
      );
      return _encodeBox(box, maximumBytes: V2StoreLimits.sealedPackageBytes);
    } finally {
      _clear(plaintextCopy);
      _clear(aadCopy);
      box?.clear();
    }
  }

  @override
  Future<Uint8List> openPackage({
    required Uint8List sealedPackage,
    required Uint8List aad,
  }) async {
    _ensureOpen();
    if (sealedPackage.length < _gcmNonceBytes + _gcmTagBytes ||
        sealedPackage.length > V2StoreLimits.sealedPackageBytes) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    }
    final sealedCopy = Uint8List.fromList(sealedPackage);
    final aadCopy = Uint8List.fromList(aad);
    AndroidKeystoreBox? box;
    Uint8List? providerPlaintext;
    try {
      box = _decodeBox(
        sealedCopy,
        maximumBytes: V2StoreLimits.sealedPackageBytes,
      );
      providerPlaintext = await _keystore.open(
        alias: alias,
        box: box,
        aad: aadCopy,
      );
      if (providerPlaintext.length > V2StoreLimits.sealedPackageBytes) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.operationFailed,
        );
      }
      return Uint8List.fromList(providerPlaintext);
    } finally {
      _clear(sealedCopy);
      _clear(aadCopy);
      box?.clear();
      if (providerPlaintext != null) _clear(providerPlaintext);
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.leaseClosed,
      );
    }
  }
}

final class _AndroidPreparedReset implements PreparedPlatformReset {
  _AndroidPreparedReset({
    required AndroidKeystoreProtector owner,
    required bool wasPresent,
  }) : _owner = owner,
       _wasPresent = wasPresent;

  final AndroidKeystoreProtector _owner;
  final bool _wasPresent;
  bool _commitAttempted = false;
  bool _closed = false;

  @override
  Future<void> commit() async {
    if (_closed || _commitAttempted) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
    _commitAttempted = true;
    return _owner._commitReset(_wasPresent);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
  }
}

/// Direct JNI implementation of [AndroidKeystoreAead].
///
/// Key generation requests StrongBox once and retries through Android's normal
/// provider only for the documented `StrongBoxUnavailableException`. This is
/// one fixed profile policy, not a runtime provider selector. There is no
/// wrapped-key sidecar or V1 alias probe.
final class JniAndroidKeystoreAead implements AndroidKeystoreAead {
  @override
  Future<bool> contains(String alias) async => Jni.instance().withFrame((f) {
    final keystore = _loadKeystore(f);
    return _contains(f, keystore, alias);
  });

  @override
  Future<bool> createUnderExclusiveLock(String alias) async =>
      Jni.instance().withFrame((f) {
        final keystore = _loadKeystore(f);
        if (_contains(f, keystore, alias)) return false;
        _generate(f, alias);
        final reloaded = _loadKeystore(f);
        if (!_contains(f, reloaded, alias) ||
            _key(f, reloaded, alias) == nullptr) {
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.operationFailed,
          );
        }
        return true;
      }, capacity: 256);

  @override
  Future<AndroidKeystoreBox> seal({
    required String alias,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async => Jni.instance().withFrame((f) {
    return _mapJavaFailures(f, () {
      final keystore = _loadKeystore(f);
      final key = _requiredKey(f, keystore, alias);
      final (cipherClass, cipher) = _newCipher(f);
      final init = f.methodId(cipherClass, 'init', '(ILjava/security/Key;)V');
      f.callVoidA(cipher, init, <Object?>[_encryptMode, key], 'Cipher.init');
      _updateAad(f, cipherClass, cipher, aad);
      final doFinal = f.methodId(cipherClass, 'doFinal', '([B)[B');
      final plaintextArray = f.byteArray(plaintext);
      Pointer<Void> ciphertextArray = nullptr;
      try {
        ciphertextArray = f.callObjectA(cipher, doFinal, <Object?>[
          plaintextArray,
        ], 'Cipher.doFinal');
        final ciphertext = f.dartBytes(
          ciphertextArray,
          maxBytes: V2StoreLimits.sealedPackageBytes,
        );
        final getIv = f.methodId(cipherClass, 'getIV', '()[B');
        final nonce = f.dartBytes(
          f.callObjectA(cipher, getIv, const [], 'Cipher.getIV'),
          maxBytes: _gcmNonceBytes,
        );
        try {
          return AndroidKeystoreBox(nonce: nonce, ciphertext: ciphertext);
        } finally {
          _clear(nonce);
          _clear(ciphertext);
        }
      } finally {
        _clearJavaArray(
          f,
          plaintextArray,
          maximum: V2StoreLimits.sealedPackageBytes,
        );
        _clearJavaArray(
          f,
          ciphertextArray,
          maximum: V2StoreLimits.sealedPackageBytes,
        );
      }
    });
  });

  @override
  Future<Uint8List> open({
    required String alias,
    required AndroidKeystoreBox box,
    required Uint8List aad,
  }) async => Jni.instance().withFrame((f) {
    return _mapJavaFailures(f, () {
      final keystore = _loadKeystore(f);
      final key = _requiredKey(f, keystore, alias);
      final (cipherClass, cipher) = _newCipher(f);
      final gcmClass = f.findClass('javax/crypto/spec/GCMParameterSpec');
      final parameters = f.newObject(gcmClass, '(I[B)V', <Object?>[
        _gcmTagBits,
        f.byteArray(box.nonce),
      ], 'GCMParameterSpec');
      final init = f.methodId(
        cipherClass,
        'init',
        '(ILjava/security/Key;Ljava/security/spec/AlgorithmParameterSpec;)V',
      );
      f.callVoidA(cipher, init, <Object?>[
        _decryptMode,
        key,
        parameters,
      ], 'Cipher.init');
      _updateAad(f, cipherClass, cipher, aad);
      final doFinal = f.methodId(cipherClass, 'doFinal', '([B)[B');
      final ciphertextArray = f.byteArray(box.ciphertext);
      Pointer<Void> plaintextArray = nullptr;
      try {
        plaintextArray = f.callObjectA(cipher, doFinal, <Object?>[
          ciphertextArray,
        ], 'Cipher.doFinal');
        return f.dartBytes(
          plaintextArray,
          maxBytes: V2StoreLimits.sealedPackageBytes,
        );
      } finally {
        _clearJavaArray(
          f,
          ciphertextArray,
          maximum: V2StoreLimits.sealedPackageBytes,
        );
        _clearJavaArray(
          f,
          plaintextArray,
          maximum: V2StoreLimits.sealedPackageBytes,
        );
      }
    });
  });

  @override
  Future<void> delete(String alias) async => Jni.instance().withFrame((f) {
    _mapJavaFailures(f, () {
      final keystore = _loadKeystore(f);
      if (!_contains(f, keystore, alias)) return;
      final keystoreClass = f.findClass('java/security/KeyStore');
      final deleteEntry = f.methodId(
        keystoreClass,
        'deleteEntry',
        '(Ljava/lang/String;)V',
      );
      f.callVoidA(keystore, deleteEntry, <Object?>[
        f.str(alias),
      ], 'KeyStore.deleteEntry');
    });
  });
}

Pointer<Void> _loadKeystore(JniFrame f) => _mapJavaFailures(f, () {
  final keystoreClass = f.findClass('java/security/KeyStore');
  final getInstance = f.staticMethodId(
    keystoreClass,
    'getInstance',
    '(Ljava/lang/String;)Ljava/security/KeyStore;',
  );
  final keystore = f.callStaticObjectA(keystoreClass, getInstance, <Object?>[
    f.str('AndroidKeyStore'),
  ], 'KeyStore.getInstance');
  final load = f.methodId(keystoreClass, 'load', '(Ljava/io/InputStream;[C)V');
  f.callVoidA(keystore, load, const [null, null], 'KeyStore.load');
  return keystore;
});

bool _contains(JniFrame f, Pointer<Void> keystore, String alias) =>
    _mapJavaFailures(f, () {
      final keystoreClass = f.findClass('java/security/KeyStore');
      final containsAlias = f.methodId(
        keystoreClass,
        'containsAlias',
        '(Ljava/lang/String;)Z',
      );
      return f.callBooleanA(keystore, containsAlias, <Object?>[
        f.str(alias),
      ], 'KeyStore.containsAlias');
    });

Pointer<Void> _key(JniFrame f, Pointer<Void> keystore, String alias) =>
    _mapJavaFailures(f, () {
      final keystoreClass = f.findClass('java/security/KeyStore');
      final getKey = f.methodId(
        keystoreClass,
        'getKey',
        '(Ljava/lang/String;[C)Ljava/security/Key;',
      );
      return f.callObjectA(keystore, getKey, <Object?>[
        f.str(alias),
        null,
      ], 'KeyStore.getKey');
    });

Pointer<Void> _requiredKey(JniFrame f, Pointer<Void> keystore, String alias) {
  final key = _key(f, keystore, alias);
  if (key == nullptr) {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.invalidated,
    );
  }
  return key;
}

void _generate(JniFrame f, String alias) {
  try {
    _generateOnce(f, alias, strongBox: true);
  } on JavaThrown catch (failure) {
    if (!f.isThrowableA(failure, _strongBoxUnavailable)) {
      _mapJavaFailures<void>(f, () => throw failure);
    }
    _mapJavaFailures<void>(f, () => _generateOnce(f, alias, strongBox: false));
  }
}

void _generateOnce(JniFrame f, String alias, {required bool strongBox}) {
  final builderClass = f.findClass(
    r'android/security/keystore/KeyGenParameterSpec$Builder',
  );
  const builderSignature =
      r'Landroid/security/keystore/KeyGenParameterSpec$Builder;';
  var builder = f.newObject(builderClass, '(Ljava/lang/String;I)V', <Object?>[
    f.str(alias),
    _purposeEncryptDecrypt,
  ], 'KeyGenParameterSpec.Builder');

  Pointer<Void> chain(
    String method,
    String argumentSignature,
    List<Object?> arguments,
  ) {
    final id = f.methodId(
      builderClass,
      method,
      '($argumentSignature)$builderSignature',
    );
    return f.callObjectA(builder, id, arguments, 'Builder.$method');
  }

  builder = chain('setBlockModes', '[Ljava/lang/String;', <Object?>[
    f.stringArray(const ['GCM']),
  ]);
  builder = chain('setEncryptionPaddings', '[Ljava/lang/String;', <Object?>[
    f.stringArray(const ['NoPadding']),
  ]);
  builder = chain('setKeySize', 'I', const <Object?>[256]);
  builder = chain('setUserAuthenticationRequired', 'Z', const <Object?>[false]);
  if (strongBox) {
    builder = chain('setIsStrongBoxBacked', 'Z', const <Object?>[true]);
  }
  final build = f.methodId(
    builderClass,
    'build',
    '()Landroid/security/keystore/KeyGenParameterSpec;',
  );
  final parameters = f.callObjectA(builder, build, const [], 'Builder.build');

  final generatorClass = f.findClass('javax/crypto/KeyGenerator');
  final getInstance = f.staticMethodId(
    generatorClass,
    'getInstance',
    '(Ljava/lang/String;Ljava/lang/String;)Ljavax/crypto/KeyGenerator;',
  );
  final generator = f.callStaticObjectA(generatorClass, getInstance, <Object?>[
    f.str('AES'),
    f.str('AndroidKeyStore'),
  ], 'KeyGenerator.getInstance');
  final initialize = f.methodId(
    generatorClass,
    'init',
    '(Ljava/security/spec/AlgorithmParameterSpec;)V',
  );
  f.callVoidA(generator, initialize, <Object?>[
    parameters,
  ], 'KeyGenerator.init');
  final generateKey = f.methodId(
    generatorClass,
    'generateKey',
    '()Ljavax/crypto/SecretKey;',
  );
  f.callObjectA(generator, generateKey, const [], 'KeyGenerator.generateKey');
}

(Pointer<Void>, Pointer<Void>) _newCipher(JniFrame f) {
  final cipherClass = f.findClass('javax/crypto/Cipher');
  final getInstance = f.staticMethodId(
    cipherClass,
    'getInstance',
    '(Ljava/lang/String;)Ljavax/crypto/Cipher;',
  );
  final cipher = f.callStaticObjectA(cipherClass, getInstance, <Object?>[
    f.str('AES/GCM/NoPadding'),
  ], 'Cipher.getInstance');
  return (cipherClass, cipher);
}

void _updateAad(
  JniFrame f,
  Pointer<Void> cipherClass,
  Pointer<Void> cipher,
  Uint8List aad,
) {
  final updateAad = f.methodId(cipherClass, 'updateAAD', '([B)V');
  final aadArray = f.byteArray(aad);
  try {
    f.callVoidA(cipher, updateAad, <Object?>[aadArray], 'Cipher.updateAAD');
  } finally {
    _clearJavaArray(f, aadArray, maximum: V2StoreLimits.sealedPackageBytes);
  }
}

void _clearJavaArray(
  JniFrame frame,
  Pointer<Void> array, {
  required int maximum,
}) {
  try {
    frame.clearByteArray(array, maxBytes: maximum);
  } on Object {
    // Heap zeroing is best-effort and must not replace an authentication or
    // provider failure already in flight.
  }
}

T _mapJavaFailures<T>(JniFrame f, T Function() operation) {
  try {
    return operation();
  } on PlatformProtectorFailure {
    rethrow;
  } on JavaThrown catch (failure) {
    if (f.isThrowableA(failure, 'javax/crypto/AEADBadTagException')) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    }
    if (f.isThrowableA(
          failure,
          'android/security/keystore/KeyPermanentlyInvalidatedException',
        ) ||
        f.isThrowableA(failure, 'java/security/UnrecoverableKeyException')) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    if (f.isThrowableA(
      failure,
      'android/security/keystore/UserNotAuthenticatedException',
    )) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.interactionRequired,
      );
    }
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  }
}

Future<T> _atAndroidBoundary<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on PlatformProtectorFailure {
    rethrow;
  } on KeystoreLocked {
    throw const PlatformProtectorFailure(PlatformProtectorFailureCode.locked);
  } on KeystoreUnreachable {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.unavailable,
    );
  } on SecretStoreException {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  } on Object {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  }
}

Uint8List _continuityAad(String providerAddress) => Uint8List.fromList(
  utf8.encode('keybay:v2:android-keystore:continuity\u0000$providerAddress'),
);

Uint8List _encodeBox(AndroidKeystoreBox box, {required int maximumBytes}) {
  final length = box.nonce.length + box.ciphertext.length;
  if (box.nonce.length != _gcmNonceBytes ||
      box.ciphertext.length < _gcmTagBytes ||
      length > maximumBytes) {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  }
  return Uint8List(length)
    ..setRange(0, box.nonce.length, box.nonce)
    ..setRange(box.nonce.length, length, box.ciphertext);
}

AndroidKeystoreBox _decodeBox(Uint8List encoded, {required int maximumBytes}) {
  if (encoded.length < _gcmNonceBytes + _gcmTagBytes ||
      encoded.length > maximumBytes) {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.authenticationFailed,
    );
  }
  return AndroidKeystoreBox(
    nonce: Uint8List.sublistView(encoded, 0, _gcmNonceBytes),
    ciphertext: Uint8List.sublistView(encoded, _gcmNonceBytes),
  );
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

/// Android V2 protection backed by one non-exportable Android Keystore key.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import '../errors.dart';
import '../ffi/jni.dart';
import 'device_access.dart';
import 'format/store_format.dart';
import 'host_binding.dart';
import 'platform_protector.dart';

const int _purposeEncryptDecrypt = 1 | 2;
const int _encryptMode = 1;
const int _decryptMode = 2;
const int _gcmTagBits = 128;
const int _gcmNonceBytes = 12;
const int _gcmTagBytes = 16;
const int _legacyContinuityStateBytes =
    _gcmNonceBytes + V2StoreLimits.digestBytes + _gcmTagBytes;
const int _continuityTagBytes = 2;
const int _taggedContinuityStateBytes =
    _continuityTagBytes + _legacyContinuityStateBytes;
const int _continuityVersion2 = 0x02;
const int _continuitySlotMask = 0x01;
const int _continuityAfterFirstUnlockBit = 0x02;
const int _continuityValidFlagsMask =
    _continuitySlotMask | _continuityAfterFirstUnlockBit;
const String _aliasPrefix = 'keybay.v2.';
const String _alternateAliasSuffix = '.alt';
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
  ///
  /// When [conflictAlias] is supplied, generation is refused with
  /// [PlatformProtectorFailureCode.stateConflict] if [conflictAlias] already
  /// exists in Keystore.
  Future<bool> createUnderExclusiveLock(
    String alias, {
    bool unlockedDeviceRequired = true,
    String? conflictAlias,
  });

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

/// The synchronous create-only guard shared by JNI and provider contract tests.
///
/// [hasKey] must use `KeyStore.getKey`, not `containsAlias`: Android 12+
/// propagates metadata lookup failures from getKey for the AES root, whereas
/// containsAlias can hide them as false. A null key can also mean a certificate
/// entry, so a positive [containsAlias] result rejects that observable conflict.
/// Neither the public API nor this guard proves universal alias absence when a
/// certificate lookup is itself unavailable. Callers hold the profile store
/// lock; this is not an atomic Keystore compare-and-create operation.
bool createAndroidKeystoreKeyUnderExclusiveLock({
  required bool Function() hasKey,
  required bool Function() containsAlias,
  bool Function()? hasConflictAlias,
  required void Function() generateAndVerify,
}) {
  if (hasKey()) return false;
  if (containsAlias()) {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.stateConflict,
    );
  }
  if (hasConflictAlias != null && hasConflictAlias()) {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.stateConflict,
    );
  }
  generateAndVerify();
  return true;
}

final class _ParsedAndroidContinuity {
  const _ParsedAndroidContinuity({
    required this.slot,
    required this.deviceAccess,
    required this.boxBytes,
    required this.isLegacy,
  });

  final int slot;
  final KeybayDeviceAccess? deviceAccess;
  final Uint8List boxBytes;
  final bool isLegacy;
}

/// Android's V2 platform protector.
///
/// The application root remains non-exportable in Android Keystore. Provider
/// state is a GCM-sealed copy of the resolved storage-domain commitment. It
/// proves both key continuity and file-domain binding before the key may seal
/// or open the independent V2 key package.
///
/// Two fixed, identity-derived aliases (`slot 0` and `slot 1`) allow atomic,
/// crash-safe [KeybayDeviceAccess] rotation without untrusted persisted alias
/// names: `reset` always owns both fixed aliases. Legacy 60-byte 0.3.2
/// continuity states continue opening on `slot 0`.
final class AndroidKeystoreProtector implements PlatformProtector {
  AndroidKeystoreProtector({
    required this.binding,
    AndroidKeystoreAead? keystore,
  }) : _keystore = keystore ?? JniAndroidKeystoreAead();

  @override
  final ResolvedApplicationBinding binding;

  final AndroidKeystoreAead _keystore;

  String get _primaryAlias => '$_aliasPrefix${binding.providerAddress}';

  String get _alternateAlias => '$_primaryAlias$_alternateAliasSuffix';

  String _aliasForSlot(int slot) => slot == 0 ? _primaryAlias : _alternateAlias;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) => _atAndroidBoundary(() async {
    final parsed = _parseContinuityState(state);
    try {
      final alias = _aliasForSlot(parsed.slot);
      if (!await _keystore.contains(alias)) return null;
      await _verifyContinuity(parsed, alias: alias);
      return _AndroidKeystoreLease(
        alias: alias,
        state: state,
        keystore: _keystore,
      );
    } finally {
      _clear(parsed.boxBytes);
    }
  });

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
    KeybayDeviceAccess deviceAccess = KeybayDeviceAccess.whenUnlocked,
  }) => _atAndroidBoundary(() async {
    // The common engine holds this application's fixed StoreFiles lock
    // while calling createOnly. Android Keystore itself does not provide
    // atomic compare-and-create for symmetric-key aliases.
    final created = await _keystore.createUnderExclusiveLock(
      _primaryAlias,
      unlockedDeviceRequired: deviceAccess == KeybayDeviceAccess.whenUnlocked,
      conflictAlias: _alternateAlias,
    );
    ProviderState? state;
    try {
      state = await _newTaggedContinuityState(
        slot: 0,
        deviceAccess: deviceAccess,
      );
      await _verifyContinuity(
        _parseContinuityState(state),
        alias: _primaryAlias,
      );
      return PlatformRootCreation(
        lease: _AndroidKeystoreLease(
          alias: _primaryAlias,
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
  Future<PreparedPlatformDeviceAccessChange?> prepareDeviceAccessChange(
    ProviderState state, {
    required KeybayDeviceAccess deviceAccess,
    required PlatformInteraction interaction,
  }) => _atAndroidBoundary(() async {
    final parsed = _parseContinuityState(state);
    try {
      final currentAlias = _aliasForSlot(parsed.slot);
      if (!await _keystore.contains(currentAlias)) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.invalidated,
        );
      }
      await _verifyContinuity(parsed, alias: currentAlias);
      final nextSlot = parsed.slot == 0 ? 1 : 0;
      final nextAlias = _aliasForSlot(nextSlot);
      if (!parsed.isLegacy && parsed.deviceAccess == deviceAccess) {
        // If a prior rotation installed the live store on `currentAlias` but
        // failed before removing the retired key on `nextAlias`, finish
        // cleaning up that leftover weaker/old alias now.
        if (await _keystore.contains(nextAlias)) {
          return _AndroidRetiredAliasCleanupChange(
            owner: this,
            retiredAlias: nextAlias,
          );
        }
        return null;
      }

      // The common engine holds the exclusive store lock and has just
      // authenticated the live store on `currentAlias`. Any leftover key on
      // the inactive slot came from an interrupted prior rotation and may be
      // cleared.
      if (await _keystore.contains(nextAlias)) {
        await _keystore.delete(nextAlias);
        if (await _keystore.contains(nextAlias)) {
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.operationFailed,
          );
        }
      }

      final created = await _keystore.createUnderExclusiveLock(
        nextAlias,
        unlockedDeviceRequired: deviceAccess == KeybayDeviceAccess.whenUnlocked,
      );
      if (!created) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.stateConflict,
        );
      }

      try {
        final nextState = await _newTaggedContinuityState(
          slot: nextSlot,
          deviceAccess: deviceAccess,
        );
        final nextParsed = _parseContinuityState(nextState);
        try {
          await _verifyContinuity(nextParsed, alias: nextAlias);
        } finally {
          _clear(nextParsed.boxBytes);
        }
        final replacementLease = _AndroidKeystoreLease(
          alias: nextAlias,
          state: nextState,
          keystore: _keystore,
        );
        return _AndroidPreparedDeviceAccessChange(
          owner: this,
          replacementLease: replacementLease,
          oldAlias: currentAlias,
          newAlias: nextAlias,
        );
      } on Object {
        try {
          await _keystore.delete(nextAlias);
        } on Object {
          // Best-effort cleanup of the unused replacement alias.
        }
        rethrow;
      }
    } finally {
      _clear(parsed.boxBytes);
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
    // establishes only which fixed app-private aliases existed.
    final primaryWasPresent = await _keystore.contains(_primaryAlias);
    final alternateWasPresent = await _keystore.contains(_alternateAlias);
    return _AndroidPreparedReset(
      owner: this,
      primaryWasPresent: primaryWasPresent,
      alternateWasPresent: alternateWasPresent,
    );
  });

  Future<ProviderState> _newTaggedContinuityState({
    required int slot,
    required KeybayDeviceAccess deviceAccess,
  }) async {
    final alias = _aliasForSlot(slot);
    final domain = binding.domain.copyBytes();
    final aad = _taggedContinuityAad(
      binding.providerAddress,
      slot: slot,
      deviceAccess: deviceAccess,
    );
    AndroidKeystoreBox? box;
    Uint8List? encodedBox;
    Uint8List? tagged;
    try {
      box = await _keystore.seal(alias: alias, plaintext: domain, aad: aad);
      encodedBox = _encodeBox(box, maximumBytes: _legacyContinuityStateBytes);
      if (encodedBox.length != _legacyContinuityStateBytes) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.operationFailed,
        );
      }
      final flags =
          (slot & _continuitySlotMask) |
          (deviceAccess == KeybayDeviceAccess.afterFirstUnlock
              ? _continuityAfterFirstUnlockBit
              : 0);
      tagged = Uint8List(_taggedContinuityStateBytes)
        ..[0] = _continuityVersion2
        ..[1] = flags
        ..setRange(
          _continuityTagBytes,
          _taggedContinuityStateBytes,
          encodedBox,
        );
      return ProviderState(tagged);
    } finally {
      _clear(domain);
      _clear(aad);
      box?.clear();
      if (encodedBox != null) _clear(encodedBox);
      if (tagged != null) _clear(tagged);
    }
  }

  _ParsedAndroidContinuity _parseContinuityState(ProviderState state) {
    final raw = state.copyBytes();
    if (raw.length == _legacyContinuityStateBytes) {
      return _ParsedAndroidContinuity(
        slot: 0,
        deviceAccess: null,
        boxBytes: raw,
        isLegacy: true,
      );
    }
    if (raw.length == _taggedContinuityStateBytes) {
      final version = raw[0];
      final flags = raw[1];
      if (version == _continuityVersion2 &&
          (flags & ~_continuityValidFlagsMask) == 0) {
        final slot = flags & _continuitySlotMask;
        final access = (flags & _continuityAfterFirstUnlockBit) != 0
            ? KeybayDeviceAccess.afterFirstUnlock
            : KeybayDeviceAccess.whenUnlocked;
        final boxBytes = Uint8List.fromList(
          Uint8List.sublistView(raw, _continuityTagBytes),
        );
        _clear(raw);
        return _ParsedAndroidContinuity(
          slot: slot,
          deviceAccess: access,
          boxBytes: boxBytes,
          isLegacy: false,
        );
      }
    }
    _clear(raw);
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.invalidated,
    );
  }

  Future<void> _verifyContinuity(
    _ParsedAndroidContinuity parsed, {
    required String alias,
  }) async {
    final aad = parsed.isLegacy
        ? _legacyContinuityAad(binding.providerAddress)
        : _taggedContinuityAad(
            binding.providerAddress,
            slot: parsed.slot,
            deviceAccess: parsed.deviceAccess!,
          );
    final expected = binding.domain.copyBytes();
    AndroidKeystoreBox? box;
    Uint8List? actual;
    try {
      box = _decodeBox(
        parsed.boxBytes,
        maximumBytes: _legacyContinuityStateBytes,
      );
      try {
        actual = await _keystore.open(alias: alias, box: box, aad: aad);
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
      _clear(parsed.boxBytes);
      _clear(aad);
      _clear(expected);
      box?.clear();
      if (actual != null) _clear(actual);
    }
  }

  Future<void> _commitReset({
    required bool primaryWasPresent,
    required bool alternateWasPresent,
  }) async {
    try {
      await _deleteSlotOnReset(_primaryAlias, wasPresent: primaryWasPresent);
      await _deleteSlotOnReset(
        _alternateAlias,
        wasPresent: alternateWasPresent,
      );
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }

  Future<void> _deleteSlotOnReset(
    String alias, {
    required bool wasPresent,
  }) async {
    final exists = await _keystore.contains(alias);
    if (!exists) return;
    if (!wasPresent) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
    await _keystore.delete(alias);
    if (await _keystore.contains(alias)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }

  Future<void> _deleteRetiredAlias(String alias) =>
      _atAndroidBoundary(() async {
        if (!await _keystore.contains(alias)) return;
        await _keystore.delete(alias);
        if (await _keystore.contains(alias)) {
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.operationFailed,
          );
        }
      });
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
    required bool primaryWasPresent,
    required bool alternateWasPresent,
  }) : _owner = owner,
       _primaryWasPresent = primaryWasPresent,
       _alternateWasPresent = alternateWasPresent;

  final AndroidKeystoreProtector _owner;
  final bool _primaryWasPresent;
  final bool _alternateWasPresent;
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
    return _owner._commitReset(
      primaryWasPresent: _primaryWasPresent,
      alternateWasPresent: _alternateWasPresent,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
  }
}

final class _AndroidPreparedDeviceAccessChange
    implements PreparedPlatformDeviceAccessChange {
  _AndroidPreparedDeviceAccessChange({
    required AndroidKeystoreProtector owner,
    required PlatformRootLease replacementLease,
    required String oldAlias,
    required String newAlias,
  }) : _owner = owner,
       _replacementLease = replacementLease,
       _oldAlias = oldAlias,
       _newAlias = newAlias;

  final AndroidKeystoreProtector _owner;
  final PlatformRootLease _replacementLease;
  final String _oldAlias;
  final String _newAlias;
  bool _committed = false;
  bool _aborted = false;
  bool _closed = false;

  @override
  PlatformRootLease get replacementLease => _replacementLease;

  @override
  Future<void> commit() async {
    if (_closed || _committed || _aborted) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    _committed = true;
    await _owner._deleteRetiredAlias(_oldAlias);
  }

  @override
  Future<void> abort() async {
    if (_committed || _aborted) return;
    _aborted = true;
    await _owner._deleteRetiredAlias(_newAlias);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _replacementLease.close();
  }
}

final class _AndroidRetiredAliasCleanupChange
    implements PreparedPlatformDeviceAccessChange {
  _AndroidRetiredAliasCleanupChange({
    required AndroidKeystoreProtector owner,
    required String retiredAlias,
  }) : _owner = owner,
       _retiredAlias = retiredAlias;

  final AndroidKeystoreProtector _owner;
  final String _retiredAlias;
  bool _committed = false;
  bool _closed = false;

  @override
  PlatformRootLease? get replacementLease => null;

  @override
  Future<void> commit() async {
    if (_closed || _committed) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    _committed = true;
    await _owner._deleteRetiredAlias(_retiredAlias);
  }

  @override
  Future<void> abort() async {}

  @override
  Future<void> close() async {
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
  Future<bool> createUnderExclusiveLock(
    String alias, {
    bool unlockedDeviceRequired = true,
    String? conflictAlias,
  }) async => Jni.instance().withFrame((f) {
    final keystore = _loadKeystore(f);
    return createAndroidKeystoreKeyUnderExclusiveLock(
      // AOSP AndroidKeyStoreProvider maps KEY_NOT_FOUND to null and
      // propagates other key metadata failures through getKey. It also
      // returns null for pure certificate entries; this is intentionally
      // an AES-root-specific check, not a raw KEY_NOT_FOUND result.
      hasKey: () => _key(f, keystore, alias) != nullptr,
      containsAlias: () => _contains(f, keystore, alias),
      hasConflictAlias: conflictAlias == null
          ? null
          : () =>
                _key(f, keystore, conflictAlias) != nullptr ||
                _contains(f, keystore, conflictAlias),
      generateAndVerify: () {
        _generate(f, alias, unlockedDeviceRequired: unlockedDeviceRequired);
        final reloaded = _loadKeystore(f);
        if (_key(f, reloaded, alias) == nullptr) {
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.operationFailed,
          );
        }
      },
    );
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

void _generate(
  JniFrame f,
  String alias, {
  required bool unlockedDeviceRequired,
}) {
  try {
    _generateOnce(
      f,
      alias,
      strongBox: true,
      unlockedDeviceRequired: unlockedDeviceRequired,
    );
  } on JavaThrown catch (failure) {
    if (!f.isThrowableA(failure, _strongBoxUnavailable)) {
      _mapJavaFailures<void>(f, () => throw failure);
    }
    _mapJavaFailures<void>(
      f,
      () => _generateOnce(
        f,
        alias,
        strongBox: false,
        unlockedDeviceRequired: unlockedDeviceRequired,
      ),
    );
  }
}

void _generateOnce(
  JniFrame f,
  String alias, {
  required bool strongBox,
  required bool unlockedDeviceRequired,
}) {
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
  builder = chain('setUnlockedDeviceRequired', 'Z', <Object?>[
    unlockedDeviceRequired,
  ]);
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
      throw const PlatformProtectorFailure(PlatformProtectorFailureCode.locked);
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

Uint8List _legacyContinuityAad(String providerAddress) => Uint8List.fromList(
  utf8.encode('keybay:v2:android-keystore:continuity\u0000$providerAddress'),
);

String _deviceAccessWireToken(KeybayDeviceAccess deviceAccess) =>
    switch (deviceAccess) {
      KeybayDeviceAccess.whenUnlocked => 'whenUnlocked',
      KeybayDeviceAccess.afterFirstUnlock => 'afterFirstUnlock',
    };

Uint8List _taggedContinuityAad(
  String providerAddress, {
  required int slot,
  required KeybayDeviceAccess deviceAccess,
}) => Uint8List.fromList(
  utf8.encode(
    'keybay:v2:android-keystore:continuity:v2\u0000'
    '$providerAddress\u0000$slot\u0000${_deviceAccessWireToken(deviceAccess)}',
  ),
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

part of 'keybay_v2.dart';

/// Canonical method contexts exclude mutable provider verification state.
Uint8List _methodContext(
  Uint8List storeId,
  Uint8List methodId,
  V2AuthMethodKind kind,
  Uint8List salt,
  String recordId, {
  int? epoch,
  Uint8List? publicKey,
}) {
  final fields = <List<int>>[
    ascii.encode('keybay:v2:methods:1'),
    storeId,
    methodId,
    [kind.index + 1],
    salt,
    ascii.encode(recordId),
    if (epoch != null) (ByteData(8)..setUint64(0, epoch)).buffer.asUint8List(),
    if (publicKey != null) publicKey,
  ];
  final out = BytesBuilder(copy: false);
  for (final field in fields) {
    out
      ..add((ByteData(4)..setUint32(0, field.length)).buffer.asUint8List())
      ..add(field);
  }
  return out.takeBytes();
}

PasskeyRecord _methodRecord(V2AuthMethodEnvelope method) {
  try {
    final json = jsonDecode(utf8.decode(method.passkeyRecord));
    if (json is! Map<String, dynamic>) throw const FormatException();
    final record = PasskeyRecord.fromJson(json);
    final expected = method.kind == V2AuthMethodKind.systemPasskey
        ? PasskeyRoute.system
        : PasskeyRoute.hardware;
    if (method.kind == V2AuthMethodKind.passphrase ||
        record.route != expected) {
      throw const FormatException();
    }
    return record;
  } on Object {
    throw _error(
      KeybayErrorCode.storeAuthenticationFailed,
      'The stored authentication method is invalid.',
    );
  }
}

AuthMethod _describeMethod(V2AuthMethodEnvelope method, Uint8List storeId) {
  final id = encodeMethodId(method.methodId);
  final store = base64UrlEncode(storeId);
  if (method.kind == V2AuthMethodKind.passphrase) {
    return PassphraseMethod._(id, store, label: method.label);
  }
  final record = _methodRecord(method);
  return PasskeyMethod._(
    id,
    storeId: store,
    rpId: record.rpId,
    route: record.route,
    label: method.label,
  );
}

List<AuthMethod> _describePackage(V2KeyPackage package) => switch (package) {
  V2PlatformOnlyPackage() => const [],
  V2PassphrasePackage() => [
    PassphraseMethod._(
      encodeMethodId(package.methodId),
      base64UrlEncode(package.storeId),
    ),
  ],
  V2MethodsPackage() => _describeMethods(package),
};

List<AuthMethod> _describeMethods(V2MethodsPackage package) {
  final identities = <String>{};
  final result = <AuthMethod>[];
  for (final method in package.methods) {
    if (method.kind != V2AuthMethodKind.passphrase &&
        !identities.add(_methodRecord(method).id)) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'The stored authentication methods contain duplicate credentials.',
      );
    }
    result.add(_describeMethod(method, package.storeId));
  }
  return List.unmodifiable(result);
}

final Object _authCallbackZone = Object();

final class _AuthCallbackScope {
  bool active = true;
}

void _checkAuthCallback() {
  final scope = Zone.current[_authCallbackZone];
  if (scope is _AuthCallbackScope && scope.active) {
    throw _error(
      KeybayErrorCode.storeBusy,
      'Keybay operations cannot run from an authentication callback.',
    );
  }
}

Future<PasskeyResult> _runPasskey(Future<PasskeyResult> Function() operation) {
  final scope = _AuthCallbackScope();
  // A callback may schedule UI work for later. Only a live ceremony can
  // deadlock that work; its inherited zone must not forbid Keybay forever.
  return runZoned(
    () => Future<PasskeyResult>.sync(operation),
    zoneValues: {_authCallbackZone: scope},
  ).whenComplete(() => scope.active = false);
}

V2AuthMethodEnvelope _selectMethod(
  V2MethodsPackage package,
  _CredentialSnapshot credential,
) {
  final passkey = credential.passkey;
  final hints = _describePackage(package);
  bool matches(V2AuthMethodEnvelope method) {
    if (passkey == null) return method.kind == V2AuthMethodKind.passphrase;
    if (method.kind == V2AuthMethodKind.passphrase) return false;
    final record = _methodRecord(method);
    return record.rpId == passkey.rpId.toLowerCase() &&
        record.route == passkey.route;
  }

  final id = credential.methodId;
  if (id != null) {
    for (final method in package.methods) {
      if (encodeMethodId(method.methodId) != id) continue;
      if (matches(method)) return method;
      throw _error(
        KeybayErrorCode.protectionMismatch,
        'The method does not match the requested route.',
      );
    }
    throw _error(
      KeybayErrorCode.authMethodNotConfigured,
      'The requested method is not configured.',
    );
  }
  final compatible = package.methods.where(matches).toList();
  if (compatible.isEmpty) {
    throw _error(
      KeybayErrorCode.protectionMismatch,
      'No matching authentication method is configured.',
    );
  }
  if (compatible.length != 1) {
    throw _error(
      KeybayErrorCode.authMethodSelectionRequired,
      'Select one configured passkey method.',
      authMethods: hints
          .whereType<PasskeyMethod>()
          .where(
            (method) =>
                method.rpId == passkey!.rpId.toLowerCase() &&
                method.route == passkey.route,
          )
          .toList(),
    );
  }
  return compatible.single;
}

void _checkPasskeyCancelled(_CredentialSnapshot? credential) {
  if (credential?.cancellation?.isCancelled ?? false) {
    throw _error(
      KeybayErrorCode.passkeyOperationFailed,
      'Passkey authentication was cancelled.',
      passkeyCode: PasskeyErrorCode.cancelled,
    );
  }
}

Future<V2AuthMethodEnvelope> _enrollMethod({
  required V2StoreEngine engine,
  required _CredentialSnapshot credential,
  required Uint8List storeId,
  required int epoch,
  required Uint8List storeKey,
  required Uint8List methodId,
  Uint8List? legacySalt,
  Uint8List? legacyMaterial,
}) async {
  final request = credential.passkey;
  _checkPasskeyCancelled(credential);
  final kind = request == null
      ? V2AuthMethodKind.passphrase
      : request.route == PasskeyRoute.system
      ? V2AuthMethodKind.systemPasskey
      : V2AuthMethodKind.hardwarePasskey;
  final salt =
      legacySalt ?? engine._entropy.randomBytes(V2StoreLimits.argonSaltBytes);
  Uint8List? material;
  Uint8List? privateKey;
  PasskeyResult? result;
  var recordBytes = Uint8List(0);
  var recordId = '';
  try {
    if (request == null) {
      material = legacyMaterial != null
          ? Uint8List.fromList(legacyMaterial)
          : await _derivePassphraseAndReleaseCredential(
              deriver: engine._passphraseDeriver,
              credential: credential,
              profileId: v2FirstPassphraseProfile,
              salt: salt,
            );
    } else {
      result = await _runPasskey(
        () => engine
            ._keypassClient(request)
            .create(
              label: credential.label,
              cancellation: credential.cancellation,
            ),
      );
      credential.clear();
      if (result.record.rpId != request.rpId.toLowerCase() ||
          result.record.route != request.route) {
        throw const PasskeyException(PasskeyErrorCode.verificationFailed);
      }
      recordBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(result.record.toJson())),
      );
      recordId = result.record.id;
      material = Uint8List.fromList(result.secret);
    }
    privateKey = await deriveMethodPrivateKey(
      material: material,
      salt: salt,
      context: _methodContext(storeId, methodId, kind, salt, recordId),
    );
    _clear(material);
    material = null;
    result?.dispose();
    result = null;
    final publicKey = await methodPublicKey(privateKey: privateKey);
    final context = _methodContext(
      storeId,
      methodId,
      kind,
      salt,
      recordId,
      epoch: epoch,
      publicKey: publicKey,
    );
    final seed = engine._entropy.randomBytes(32);
    late final Uint8List envelope;
    try {
      envelope = await sealMethodStoreKey(
        publicKey: publicKey,
        storeKey: storeKey,
        context: context,
        ephemeralSeed: seed,
      );
    } finally {
      _clear(seed);
    }
    final checked = await openMethodStoreKey(
      privateKey: privateKey,
      sealedStoreKey: envelope,
      context: context,
    );
    try {
      if (!_constantTimeEquals(checked, storeKey)) {
        throw const V2CryptoFailure(V2CryptoFailureCode.authenticationFailed);
      }
    } finally {
      _clear(checked);
    }
    _checkPasskeyCancelled(credential);
    return V2AuthMethodEnvelope(
      methodId: methodId,
      kind: kind,
      label: credential.label,
      salt: salt,
      profileId: request == null ? v2FirstPassphraseProfile : 0,
      publicKey: publicKey,
      keyEnvelope: envelope,
      passkeyRecord: recordBytes,
    );
  } finally {
    credential.clear();
    if (material != null) _clear(material);
    if (privateKey != null) _clear(privateKey);
    result?.dispose();
  }
}

final class _UnlockedMethod {
  const _UnlockedMethod(this.storeKey, this.method);
  final Uint8List storeKey;
  final V2AuthMethodEnvelope method;
}

Future<_UnlockedMethod> _unlockMethod({
  required V2StoreEngine engine,
  required V2MethodsPackage package,
  required V2AuthMethodEnvelope method,
  required _CredentialSnapshot credential,
}) async {
  Uint8List? material;
  Uint8List? privateKey;
  Uint8List? storeKey;
  PasskeyResult? result;
  var updated = method;
  var recordId = '';
  try {
    if (method.kind == V2AuthMethodKind.passphrase) {
      material = await _derivePassphraseAndReleaseCredential(
        deriver: engine._passphraseDeriver,
        credential: credential,
        profileId: method.profileId,
        salt: method.salt,
      );
    } else {
      final request = credential.passkey!;
      final record = _methodRecord(method);
      recordId = record.id;
      result = await _runPasskey(
        () => engine
            ._keypassClient(request)
            .unlock(record, cancellation: credential.cancellation),
      );
      credential.clear();
      if (result.record.id != recordId) {
        throw const PasskeyException(PasskeyErrorCode.verificationFailed);
      }
      material = Uint8List.fromList(result.secret);
      updated = method.withPasskeyRecord(
        Uint8List.fromList(utf8.encode(jsonEncode(result.record.toJson()))),
      );
    }
    privateKey = await deriveMethodPrivateKey(
      material: material,
      salt: method.salt,
      context: _methodContext(
        package.storeId,
        method.methodId,
        method.kind,
        method.salt,
        recordId,
      ),
    );
    _clear(material);
    material = null;
    result?.dispose();
    result = null;
    final publicKey = await methodPublicKey(privateKey: privateKey);
    if (!_constantTimeEquals(publicKey, method.publicKey)) {
      throw const V2CryptoFailure(V2CryptoFailureCode.authenticationFailed);
    }
    storeKey = await openMethodStoreKey(
      privateKey: privateKey,
      sealedStoreKey: method.keyEnvelope,
      context: _methodContext(
        package.storeId,
        method.methodId,
        method.kind,
        method.salt,
        recordId,
        epoch: package.epoch,
        publicKey: publicKey,
      ),
    );
    _checkPasskeyCancelled(credential);
    final opened = _UnlockedMethod(storeKey, updated);
    storeKey = null;
    return opened;
  } on V2CryptoFailure {
    throw _error(
      KeybayErrorCode.unlockFailed,
      'The supplied credential did not unlock the store.',
    );
  } finally {
    credential.clear();
    if (material != null) _clear(material);
    if (privateKey != null) _clear(privateKey);
    if (storeKey != null) _clear(storeKey);
    result?.dispose();
  }
}

Future<V2AuthMethodEnvelope> _rewrapMethod({
  required V2StoreEngine engine,
  required V2AuthMethodEnvelope method,
  required Uint8List storeId,
  required int epoch,
  required Uint8List storeKey,
}) async {
  final recordId = method.kind == V2AuthMethodKind.passphrase
      ? ''
      : _methodRecord(method).id;
  final seed = engine._entropy.randomBytes(32);
  try {
    final envelope = await sealMethodStoreKey(
      publicKey: method.publicKey,
      storeKey: storeKey,
      ephemeralSeed: seed,
      context: _methodContext(
        storeId,
        method.methodId,
        method.kind,
        method.salt,
        recordId,
        epoch: epoch,
        publicKey: method.publicKey,
      ),
    );
    return method.withKeyEnvelope(envelope);
  } finally {
    _clear(seed);
  }
}

final class _PolicyReplacement {
  const _PolicyReplacement(this.package, this.method);
  final V2KeyPackage package;
  final AuthMethod? method;
}

Future<_PolicyReplacement> _buildAuthReplacement({
  required V2StoreSession session,
  required V2KeyPackage current,
  required _AuthChange change,
  required _CredentialSnapshot? credential,
  required String? methodId,
  required int epoch,
  required Uint8List storeKey,
}) async {
  if (current is V2PassphrasePackage) {
    throw _error(
      KeybayErrorCode.staleSession,
      'Reopen the legacy store before changing its authentication.',
    );
  }
  final methods = current is V2MethodsPackage
      ? current.methods
      : <V2AuthMethodEnvelope>[];
  _describePackage(current);
  final request = credential?.passkey;
  V2AuthMethodEnvelope? target;
  switch (change) {
    case _AuthChange.add:
      if (credential == null) throw StateError('Missing enrollment credential');
      if (request == null &&
          methods.any((method) => method.kind == V2AuthMethodKind.passphrase)) {
        throw _error(
          KeybayErrorCode.authMethodAlreadyConfigured,
          'A passphrase is already configured.',
        );
      }
      if (methods.length == v2MaxMethods) {
        throw _error(
          KeybayErrorCode.limitExceeded,
          'The authentication method limit was reached.',
        );
      }
    case _AuthChange.remove:
      for (final method in methods) {
        if (encodeMethodId(method.methodId) == methodId) target = method;
      }
      if (target == null) {
        throw _error(
          KeybayErrorCode.authMethodNotConfigured,
          'The method to remove is not configured.',
        );
      }
  }
  final replacements = <V2AuthMethodEnvelope>[];
  AuthMethod? result;
  if (change != _AuthChange.remove) {
    final added = await _enrollMethod(
      engine: session._engine,
      credential: credential!,
      storeId: session._storeId,
      epoch: epoch,
      storeKey: storeKey,
      methodId: session._entropy.randomBytes(V2StoreLimits.methodIdBytes),
    );
    if (added.kind != V2AuthMethodKind.passphrase) {
      final id = _methodRecord(added).id;
      if (methods.any(
        (method) =>
            !identical(method, target) &&
            method.kind != V2AuthMethodKind.passphrase &&
            _methodRecord(method).id == id,
      )) {
        throw _error(
          KeybayErrorCode.authMethodAlreadyConfigured,
          'That credential is already configured.',
        );
      }
    }
    replacements.add(added);
    result = _describeMethod(added, session._storeId);
  }
  for (final method in methods) {
    if (identical(method, target)) continue;
    replacements.add(
      await _rewrapMethod(
        engine: session._engine,
        method: method,
        storeId: session._storeId,
        epoch: epoch,
        storeKey: storeKey,
      ),
    );
  }
  final V2KeyPackage package = replacements.isEmpty
      ? V2PlatformOnlyPackage(
          storeId: session._storeId,
          epoch: epoch,
          storeKey: storeKey,
        )
      : V2MethodsPackage(
          storeId: session._storeId,
          epoch: epoch,
          methods: replacements,
        );
  return _PolicyReplacement(package, result);
}

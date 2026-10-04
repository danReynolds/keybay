part of 'keybay_v2.dart';

enum _AuthChange { add, remove }

enum _RotationGeneration { old, replacement, unknown }

/// Prepares authentication outside the file lock, then atomically rotates.
///
/// An authenticated session authorizes changes; credential material is used
/// only for the newly enrolled method. Every surviving method is
/// rewrapped to its authenticated public key without requesting its secret.
Future<AuthMethod?> _commitAuthChange(
  V2StoreSession session,
  _AuthChange change, {
  _CredentialSnapshot? credential,
  String? methodId,
}) async {
  Future<void>? peerDrain;
  AuthMethod? result;
  Object? primaryFailure;
  StackTrace? primaryStack;
  _PreparedAuthRotation? prepared;
  try {
    _checkPasskeyCancelled(credential);
    session._ensureCurrent();
    final plan = await _prepareAuthRotation(
      session,
      change,
      credential: credential,
      methodId: methodId,
    );
    prepared = plan;
    result = await session._host.files.withExclusiveTransaction((
      transaction,
    ) async {
      session._ensureCurrent();
      _checkPasskeyCancelled(credential);
      await _requireCompleteStore(transaction);
      final sourcePin = await _openPin(transaction.openPinnedLive);

      _OpenedGeneration? source;
      V2Manifest? replacementManifest;
      final pendingEntries = <V2ManifestEntry>[];
      StagedStoreFile? stage;
      var sourcePinClosed = false;
      var replacementAdopted = false;
      final nextEpoch = plan.epoch;
      final nextStoreKey = plan.storeKey;

      try {
        final actualPrefix = await _readPrefix(sourcePin);
        if (!_constantTimeEquals(
              actualPrefix.sealedPackage,
              plan.originalPrefix.sealedPackage,
            ) ||
            !_constantTimeEquals(
              encodeBootstrap(actualPrefix.bootstrap),
              encodeBootstrap(plan.originalPrefix.bootstrap),
            )) {
          throw _error(
            KeybayErrorCode.storeStateConflict,
            'Authentication state changed while preparing the update.',
          );
        }
        // A record writer preserves the prefix. Authenticate and rotate its
        // latest generation rather than replacing it with preparation's pin.
        source = await _openAuthenticatedGeneration(
          host: session._host,
          pin: sourcePin,
          storeKey: session._storeKey,
          storeId: session._storeId,
        );

        final replacementBootstrap = plan.bootstrap;
        final sealedPackage = plan.sealedPackage;
        final bootstrapBytes = encodeBootstrap(replacementBootstrap);
        final expectedLength =
            bootstrapBytes.length +
            sealedPackage.length +
            source.layout.frameRegionLength +
            source.layout.manifestLength +
            v2ManifestLengthBytes;
        stage = await transaction.createStaging(expectedLength: expectedLength);
        await stage.append(bootstrapBytes);
        await stage.append(sealedPackage);

        for (final range in source.ranges) {
          final frame = await _readExact(
            sourcePin,
            offset: source.layout.frameRegionOffset + range.offset,
            length: range.length,
          );
          Uint8List? keyBytes;
          Uint8List? value;
          V2ManifestEntry? replacementEntry;
          try {
            final sourceDigest = digestFrame(frame);
            if (!range.entry.hasFrameDigest(sourceDigest)) {
              throw _error(
                KeybayErrorCode.storeAuthenticationFailed,
                'A source record frame failed authentication.',
              );
            }
            keyBytes = range.entry.copyKeyBytes();
            value = await openRecordFrameBytes(
              storeKey: session._storeKey,
              storeId: session._storeId,
              epoch: session._epoch,
              keyBytes: keyBytes,
              sealedFrame: frame,
            );
            final frameNonce = session._entropy.randomBytes(
              V2StoreLimits.nonceBytes,
            );
            final replacementFrame = await sealRecordFrameBytes(
              storeKey: nextStoreKey,
              storeId: session._storeId,
              epoch: nextEpoch,
              keyBytes: keyBytes,
              value: value,
              nonce: frameNonce,
            );
            final replacementDigest = digestFrame(replacementFrame);
            replacementEntry = V2ManifestEntry.fromKeyBytes(
              keyBytes: keyBytes,
              frameLength: replacementFrame.length,
              frameDigest: replacementDigest,
            );
            pendingEntries.add(replacementEntry);
            replacementEntry = null;
            await stage.append(replacementFrame);
          } finally {
            replacementEntry?.clear();
            if (keyBytes != null) _clear(keyBytes);
            if (value != null) _clear(value);
          }
        }

        replacementManifest = V2Manifest(pendingEntries);
        final manifestNonce = session._entropy.randomBytes(
          V2StoreLimits.nonceBytes,
        );
        final manifestDomain = session._host.binding.domain.copyBytes();
        final sealedManifest = await sealManifest(
          storeKey: nextStoreKey,
          storeId: session._storeId,
          storageDomain: manifestDomain,
          bootstrap: replacementBootstrap,
          sealedPackage: sealedPackage,
          manifest: replacementManifest,
          nonce: manifestNonce,
        );
        if (sealedManifest.length != source.layout.manifestLength) {
          throw _error(
            KeybayErrorCode.storeAuthenticationFailed,
            'The rotated manifest changed its canonical size.',
          );
        }
        final trailer = encodeManifestLength(sealedManifest.length);
        await stage.append(sealedManifest);
        await stage.append(trailer);

        final sourceCloseFailure = await _closePin(sourcePin);
        sourcePinClosed = true;
        if (sourceCloseFailure != null) throw sourceCloseFailure;

        final stagedPin = await stage.finish();
        await _usePin(stagedPin, (pin) async {
          await _verifyCompleteSnapshot(
            host: session._host,
            pin: pin,
            storeKey: nextStoreKey,
            storeId: session._storeId,
            expectedRecordCount: replacementManifest!.entries.length,
          );
        });
        session._ensureCurrent();
        _checkPasskeyCancelled(credential);
        try {
          await stage.replaceLive();
          final committedPin = await _openPin(transaction.openPinnedLive);
          await _usePin(committedPin, (pin) async {
            await _verifyCompleteSnapshot(
              host: session._host,
              pin: pin,
              storeKey: nextStoreKey,
              storeId: session._storeId,
              expectedRecordCount: replacementManifest!.entries.length,
            );
          });
          replacementAdopted = true;
        } on Object {
          final live = await _classifyRotationGeneration(
            transaction: transaction,
            session: session,
            replacementStoreKey: nextStoreKey,
            expectedRecordCount: replacementManifest.entries.length,
          );
          if (live == _RotationGeneration.replacement) {
            replacementAdopted = true;
          } else if (live == _RotationGeneration.unknown) {
            session._invalidateImmediately();
            peerDrain = session._engine._abandonRotationGeneration(session);
          }
          rethrow;
        } finally {
          if (replacementAdopted) {
            session._adoptRotation(
              storeKey: plan.takeStoreKey(),
              epoch: nextEpoch,
              authMethods: plan.authMethods,
            );
            peerDrain = session._engine._advanceRotationGeneration(session);
          }
        }

        return plan.changedMethod;
      } finally {
        if (!sourcePinClosed) {
          await _closePin(sourcePin);
        }
        source?.clear();
        replacementManifest?.clear();
        if (replacementManifest == null) {
          for (final entry in pendingEntries) {
            entry.clear();
          }
        }
      }
    });
  } on Object catch (error, stackTrace) {
    primaryFailure = _mapReaderFailure(error);
    primaryStack = stackTrace;
  } finally {
    prepared?.clear();
  }

  try {
    await peerDrain;
  } on Object {
    // Session invalidation cleanup cannot replace the transaction's result.
  }
  if (primaryFailure != null) {
    Error.throwWithStackTrace(primaryFailure, primaryStack!);
  }
  return result;
}

/// Owns only the prepared next key after provider resources have been closed.
/// The original authenticated prefix is a CAS token, not a record snapshot.
final class _PreparedAuthRotation {
  _PreparedAuthRotation({
    required this.originalPrefix,
    required this.bootstrap,
    required this.sealedPackage,
    required this.epoch,
    required Uint8List storeKey,
    required this.authMethods,
    required this.changedMethod,
  }) : _storeKey = storeKey;

  final _StorePrefix originalPrefix;
  final V2Bootstrap bootstrap;
  final Uint8List sealedPackage;
  final int epoch;
  final List<AuthMethod> authMethods;
  final AuthMethod? changedMethod;
  Uint8List? _storeKey;

  Uint8List get storeKey => _storeKey!;

  Uint8List takeStoreKey() {
    final key = _storeKey!;
    _storeKey = null;
    return key;
  }

  void clear() {
    final key = _storeKey;
    _storeKey = null;
    if (key != null) _clear(key);
  }
}

Future<_PreparedAuthRotation> _prepareAuthRotation(
  V2StoreSession session,
  _AuthChange change, {
  required _CredentialSnapshot? credential,
  required String? methodId,
}) async {
  // This short transaction checks incomplete state before presenting UI. The
  // lock is released with the original inode pinned, before any provider call.
  final pin = await session._host.files.withExclusiveTransaction((
    transaction,
  ) async {
    session._ensureCurrent();
    _checkPasskeyCancelled(credential);
    await _requireCompleteStore(transaction);
    return _openPin(transaction.openPinnedLive);
  });
  _OpenedGeneration? source;
  PlatformRootLease? lease;
  V2KeyPackage? currentPackage;
  V2KeyPackage? replacementPackage;
  Uint8List? currentPlaintext;
  Uint8List? currentStoreKey;
  Uint8List? nextStoreKey;
  Uint8List? replacementPlaintext;
  _PreparedAuthRotation? result;
  Object? primaryFailure;
  StackTrace? primaryStack;
  try {
    source = await _openAuthenticatedGeneration(
      host: session._host,
      pin: pin,
      storeKey: session._storeKey,
      storeId: session._storeId,
    );
    session._ensureCurrent();
    _checkPasskeyCancelled(credential);
    final state = ProviderState(source.prefix.bootstrap.core.providerState);
    lease = await session._host.protector.openExisting(
      state,
      interaction: PlatformInteraction.allowed,
    );
    if (lease == null || !lease.providerState.hasSameBytes(state)) {
      throw _error(
        KeybayErrorCode.platformKeyInvalidated,
        'The platform protection key is unavailable.',
      );
    }
    currentPlaintext = await lease.openPackage(
      sealedPackage: source.prefix.sealedPackage,
      aad: encodePlatformPackageAad(
        storageDomain: session._host.binding.domain.copyBytes(),
        bootstrapCore: source.prefix.bootstrap.core,
      ),
    );
    currentPackage = decodeKeyPackage(currentPlaintext);
    if (currentPackage.epoch != session._epoch ||
        !_constantTimeEquals(currentPackage.storeId, session._storeId)) {
      throw _error(
        KeybayErrorCode.staleSession,
        'The Keybay session is stale.',
      );
    }
    if (currentPackage is V2PlatformOnlyPackage) {
      currentStoreKey = currentPackage.takeStoreKey();
      if (!_constantTimeEquals(currentStoreKey, session._storeKey)) {
        throw _error(
          KeybayErrorCode.storeAuthenticationFailed,
          'The platform package does not match this session.',
        );
      }
    }
    final nextEpoch = session._epoch + 1;
    nextStoreKey = session._entropy.randomBytes(V2StoreLimits.storeKeyBytes);
    final next = await _buildAuthReplacement(
      session: session,
      current: currentPackage,
      change: change,
      credential: credential,
      methodId: methodId,
      epoch: nextEpoch,
      storeKey: nextStoreKey,
    );
    replacementPackage = next.package;
    session._ensureCurrent();
    _checkPasskeyCancelled(credential);
    replacementPlaintext = encodeKeyPackage(replacementPackage);
    final core = V2BootstrapCore(
      source.prefix.bootstrap.core.providerState,
      suite: v2MethodsSuite,
    );
    final aad = encodePlatformPackageAad(
      storageDomain: session._host.binding.domain.copyBytes(),
      bootstrapCore: core,
    );
    final sealed = await lease.sealPackage(
      plaintext: replacementPlaintext,
      aad: aad,
    );
    _validateSealedPackage(sealed);
    await _verifyKeyPackage(
      lease: lease,
      sealedPackage: sealed,
      aad: aad,
      expectedPlaintext: replacementPlaintext,
    );
    result = _PreparedAuthRotation(
      originalPrefix: source.prefix,
      bootstrap: V2Bootstrap(core: core, sealedPackageLength: sealed.length),
      sealedPackage: sealed,
      epoch: nextEpoch,
      storeKey: nextStoreKey,
      authMethods: _describePackage(replacementPackage),
      changedMethod: next.method,
    );
    nextStoreKey = null;
  } on Object catch (error, stackTrace) {
    primaryFailure = error;
    primaryStack = stackTrace;
  } finally {
    source?.clear();
    currentPackage?.clear();
    replacementPackage?.clear();
    if (currentPlaintext != null) _clear(currentPlaintext);
    if (currentStoreKey != null) _clear(currentStoreKey);
    if (nextStoreKey != null) _clear(nextStoreKey);
    if (replacementPlaintext != null) _clear(replacementPlaintext);
  }
  final cleanupFailure = await _closeOpenResources(lease, pin);
  final failure = primaryFailure ?? cleanupFailure;
  if (failure != null) {
    result?.clear();
    Error.throwWithStackTrace(failure, primaryStack ?? StackTrace.current);
  }
  return result!;
}

Future<_RotationGeneration> _classifyRotationGeneration({
  required StoreTransaction transaction,
  required V2StoreSession session,
  required Uint8List replacementStoreKey,
  required int expectedRecordCount,
}) async {
  try {
    final pin = await transaction.openPinnedLive();
    if (pin == null) return _RotationGeneration.unknown;
    try {
      try {
        await _verifyCompleteSnapshot(
          host: session._host,
          pin: pin,
          storeKey: replacementStoreKey,
          storeId: session._storeId,
          expectedRecordCount: expectedRecordCount,
        );
        return _RotationGeneration.replacement;
      } on Object {
        try {
          await _verifyCompleteSnapshot(
            host: session._host,
            pin: pin,
            storeKey: session._storeKey,
            storeId: session._storeId,
            expectedRecordCount: expectedRecordCount,
          );
          return _RotationGeneration.old;
        } on Object {
          return _RotationGeneration.unknown;
        }
      }
    } finally {
      await _closePin(pin);
    }
  } on Object {
    return _RotationGeneration.unknown;
  }
}

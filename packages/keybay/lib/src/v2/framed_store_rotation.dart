part of 'keybay_v2.dart';

enum _AuthChange { add, update, remove }

enum _RotationGeneration { old, replacement, unknown }

/// Rotates the store key and unlock policy in one complete-file transaction.
///
/// The returned value is the configured passphrase method ID, or `null` after
/// removal. Credentials authorize only construction of the replacement route;
/// the already-open session authorizes the policy change itself.
Future<String?> _commitAuthChange(
  V2StoreSession session,
  _AuthChange change, {
  _CredentialSnapshot? credential,
  String? methodId,
}) async {
  final currentMethodId = session._passphraseMethodId;
  switch (change) {
    case _AuthChange.add:
      if (credential == null || methodId != null) {
        throw StateError('Invalid passphrase-add operation.');
      }
    case _AuthChange.update:
      if (credential == null || methodId != null) {
        throw StateError('Invalid passphrase-update operation.');
      }
    case _AuthChange.remove:
      if (credential != null) {
        throw StateError('Invalid passphrase-remove operation.');
      }
  }

  Future<void>? peerDrain;
  String? result;
  Object? primaryFailure;
  StackTrace? primaryStack;
  try {
    result = await session._host.files.withExclusiveTransaction((
      transaction,
    ) async {
      session._ensureCurrent();
      await _requireCompleteStore(transaction);
      final sourcePin = await _openPin(transaction.openPinnedLive);

      _OpenedGeneration? source;
      PlatformRootLease? lease;
      V2KeyPackage? currentPackage;
      V2KeyPackage? replacementPackage;
      V2Manifest? replacementManifest;
      final pendingEntries = <V2ManifestEntry>[];
      Uint8List? currentPlaintext;
      Uint8List? currentStoreKey;
      Uint8List? nextStoreKey;
      Uint8List? nextMethodBytes;
      Uint8List? nextSalt;
      Uint8List? nextPassphraseKey;
      Uint8List? replacementPlaintext;
      StagedStoreFile? stage;
      var sourcePinClosed = false;
      var replacementAdopted = false;
      final nextEpoch = session._epoch + 1;
      String? nextMethodId;

      try {
        source = await _openAuthenticatedGeneration(
          host: session._host,
          pin: sourcePin,
          storeKey: session._storeKey,
          storeId: session._storeId,
        );

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
        final domain = session._host.binding.domain.copyBytes();
        final currentAad = encodePlatformPackageAad(
          storageDomain: domain,
          bootstrapCore: source.prefix.bootstrap.core,
        );
        currentPlaintext = await lease.openPackage(
          sealedPackage: source.prefix.sealedPackage,
          aad: currentAad,
        );
        currentPackage = decodeKeyPackage(currentPlaintext);

        final currentStoreId = currentPackage.storeId;
        if (currentPackage.epoch != session._epoch ||
            !_constantTimeEquals(currentStoreId, session._storeId)) {
          throw _error(
            KeybayErrorCode.staleSession,
            'The Keybay session is stale.',
          );
        }
        if (currentMethodId == null) {
          if (currentPackage is! V2PlatformOnlyPackage) {
            throw _error(
              KeybayErrorCode.staleSession,
              'The Keybay session is stale.',
            );
          }
          currentStoreKey = currentPackage.takeStoreKey();
          if (!_constantTimeEquals(currentStoreKey, session._storeKey)) {
            throw _error(
              KeybayErrorCode.storeAuthenticationFailed,
              'The platform package does not match the active session.',
            );
          }
        } else {
          if (currentPackage is! V2PassphrasePackage) {
            throw _error(
              KeybayErrorCode.staleSession,
              'The Keybay session is stale.',
            );
          }
          final currentMethodBytes = currentPackage.methodId;
          if (encodeMethodId(currentMethodBytes) != currentMethodId) {
            throw _error(
              KeybayErrorCode.staleSession,
              'The Keybay session is stale.',
            );
          }
        }

        switch (change) {
          case _AuthChange.add:
            if (currentMethodId != null) {
              throw _error(
                KeybayErrorCode.authMethodAlreadyConfigured,
                'A passphrase method is already configured.',
              );
            }
          case _AuthChange.update:
            if (currentMethodId == null) {
              throw _error(
                KeybayErrorCode.authMethodNotConfigured,
                'No passphrase method is configured.',
              );
            }
          case _AuthChange.remove:
            if (currentMethodId == null || currentMethodId != methodId) {
              throw _error(
                KeybayErrorCode.authMethodNotConfigured,
                'The requested unlock method is not configured.',
              );
            }
        }

        nextStoreKey = session._entropy.randomBytes(
          V2StoreLimits.storeKeyBytes,
        );
        if (change == _AuthChange.remove) {
          replacementPackage = V2PlatformOnlyPackage(
            storeId: session._storeId,
            epoch: nextEpoch,
            storeKey: nextStoreKey,
          );
        } else {
          nextMethodBytes = change == _AuthChange.add
              ? session._entropy.randomBytes(V2StoreLimits.methodIdBytes)
              : decodeMethodId(currentMethodId!);
          nextMethodId = encodeMethodId(nextMethodBytes);
          nextSalt = session._entropy.randomBytes(V2StoreLimits.argonSaltBytes);
          final nextEnvelopeNonce = session._entropy.randomBytes(
            V2StoreLimits.nonceBytes,
          );
          nextPassphraseKey = await _derivePassphraseAndReleaseCredential(
            deriver: session._engine._passphraseDeriver,
            credential: credential!,
            profileId: v2FirstPassphraseProfile,
            salt: nextSalt,
          );
          final nextInnerEnvelope = await sealPassphraseEnvelope(
            passphraseKey: nextPassphraseKey,
            storeKey: nextStoreKey,
            storeId: session._storeId,
            epoch: nextEpoch,
            methodId: nextMethodBytes,
            profileId: v2FirstPassphraseProfile,
            salt: nextSalt,
            nonce: nextEnvelopeNonce,
          );
          replacementPackage = V2PassphrasePackage(
            storeId: session._storeId,
            epoch: nextEpoch,
            methodId: nextMethodBytes,
            profileId: v2FirstPassphraseProfile,
            salt: nextSalt,
            innerEnvelope: nextInnerEnvelope,
          );
        }

        replacementPlaintext = encodeKeyPackage(replacementPackage);
        final replacementDomain = session._host.binding.domain.copyBytes();
        final replacementAad = encodePlatformPackageAad(
          storageDomain: replacementDomain,
          bootstrapCore: source.prefix.bootstrap.core,
        );
        final sealedPackage = await lease.sealPackage(
          plaintext: replacementPlaintext,
          aad: replacementAad,
        );
        _validateSealedPackage(sealedPackage);
        await _verifyKeyPackage(
          lease: lease,
          sealedPackage: sealedPackage,
          aad: replacementAad,
          expectedStoreId: session._storeId,
          expectedStoreKey: nextStoreKey,
          expectedEpoch: nextEpoch,
          expectedMethodId: nextMethodBytes,
          expectedSalt: nextSalt,
          passphraseKey: nextPassphraseKey,
        );

        await lease.close();
        lease = null;
        if (nextPassphraseKey != null) {
          _clear(nextPassphraseKey);
          nextPassphraseKey = null;
        }

        final replacementBootstrap = V2Bootstrap(
          core: source.prefix.bootstrap.core,
          sealedPackageLength: sealedPackage.length,
        );
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
            storeKey: nextStoreKey!,
            storeId: session._storeId,
            expectedRecordCount: replacementManifest!.entries.length,
          );
        });
        session._ensureCurrent();
        try {
          await stage.replaceLive();
          final committedPin = await _openPin(transaction.openPinnedLive);
          await _usePin(committedPin, (pin) async {
            await _verifyCompleteSnapshot(
              host: session._host,
              pin: pin,
              storeKey: nextStoreKey!,
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
            final adoptedKey = nextStoreKey;
            nextStoreKey = null;
            session._adoptRotation(
              storeKey: adoptedKey,
              epoch: nextEpoch,
              passphraseMethodId: nextMethodId,
            );
            peerDrain = session._engine._advanceRotationGeneration(session);
          }
        }

        return nextMethodId;
      } finally {
        if (!sourcePinClosed) {
          await _closePin(sourcePin);
        }
        if (lease != null) {
          try {
            await lease.close();
          } on Object {
            // A prior failure retains precedence; the outer transaction maps it.
          }
        }
        source?.clear();
        replacementManifest?.clear();
        if (replacementManifest == null) {
          for (final entry in pendingEntries) {
            entry.clear();
          }
        }
        currentPackage?.clear();
        replacementPackage?.clear();
        if (currentPlaintext != null) _clear(currentPlaintext);
        if (currentStoreKey != null) _clear(currentStoreKey);
        if (nextStoreKey != null) _clear(nextStoreKey);
        if (nextPassphraseKey != null) _clear(nextPassphraseKey);
        if (replacementPlaintext != null) _clear(replacementPlaintext);
      }
    });
  } on Object catch (error, stackTrace) {
    primaryFailure = _mapReaderFailure(error);
    primaryStack = stackTrace;
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

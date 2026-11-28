part of 'keybay_v2.dart';

/// Updates the platform protector's [KeybayDeviceAccess] policy for an open,
/// authenticated session.
///
/// On Apple Data Protection Keychain, this updates `kSecAttrAccessible` in
/// place without rewriting the vault file. On Android 12+ Keystore, where key
/// parameters are immutable, this rotates to the inactive fixed alias,
/// atomically commits the re-sealed key package + manifest while copying
/// authenticated record frames byte-for-byte, verifies the live snapshot, and
/// only then removes the retired alias. Desktop login keyrings return `null`
/// from preparation and complete as a verified no-op.
Future<void> _commitDeviceAccessChange(
  V2StoreSession session,
  KeybayDeviceAccess deviceAccess,
) async {
  try {
    session._ensureCurrent();
    await session._host.files.withExclusiveTransaction((transaction) async {
      session._ensureCurrent();
      await _requireCompleteStore(transaction);
      final sourcePin = await _openPin(transaction.openPinnedLive);
      var sourcePinClosed = false;
      _OpenedGeneration? source;
      PreparedPlatformDeviceAccessChange? prepared;
      PlatformRootLease? currentLease;
      ProviderState? originalState;
      Uint8List? packagePlaintext;
      var replaceAttempted = false;
      var committed = false;
      Object? primaryFailure;
      StackTrace? primaryStack;
      try {
        source = await _openAuthenticatedGeneration(
          host: session._host,
          pin: sourcePin,
          storeKey: session._storeKey,
          storeId: session._storeId,
        );
        final prefix = source.prefix;
        final state = ProviderState(prefix.bootstrap.core.providerState);
        originalState = state;
        prepared = await session._host.protector.prepareDeviceAccessChange(
          state,
          deviceAccess: deviceAccess,
          interaction: PlatformInteraction.allowed,
        );
        if (prepared != null) {
          final nextLease = prepared.replacementLease;
          if (nextLease == null) {
            // In-place platform attribute update (Apple Data Protection
            // Keychain) or leftover retired-alias cleanup (Android): no file
            // rewrite needed.
            session._ensureCurrent();
            await prepared.commit();
            committed = true;
          } else {
            // Platform key rotation (Android 12+ Keystore): re-seal the exact
            // key package under the replacement lease and atomically replace
            // the live store before deleting the retired key.
            currentLease = await session._host.protector.openExisting(
              state,
              interaction: PlatformInteraction.allowed,
            );
            if (currentLease == null ||
                !currentLease.providerState.hasSameBytes(state)) {
              throw _error(
                KeybayErrorCode.platformKeyInvalidated,
                'The platform protection key is unavailable.',
              );
            }
            final domain = session._host.binding.domain.copyBytes();
            packagePlaintext = await currentLease.openPackage(
              sealedPackage: prefix.sealedPackage,
              aad: encodePlatformPackageAad(
                storageDomain: domain,
                bootstrapCore: prefix.bootstrap.core,
              ),
            );
            await currentLease.close();
            currentLease = null;

            final replacementCore = V2BootstrapCore(
              nextLease.providerState.copyBytes(),
              suite: prefix.bootstrap.core.suite,
            );
            final nextAad = encodePlatformPackageAad(
              storageDomain: domain,
              bootstrapCore: replacementCore,
            );
            final nextSealedPackage = await nextLease.sealPackage(
              plaintext: packagePlaintext,
              aad: nextAad,
            );
            _validateSealedPackage(nextSealedPackage);
            await _verifyKeyPackage(
              lease: nextLease,
              sealedPackage: nextSealedPackage,
              aad: nextAad,
              expectedPlaintext: packagePlaintext,
            );
            _clear(packagePlaintext);
            packagePlaintext = null;

            final nextBootstrap = V2Bootstrap(
              core: replacementCore,
              sealedPackageLength: nextSealedPackage.length,
            );
            final bootstrapBytes = encodeBootstrap(nextBootstrap);
            final sealedManifest = await sealManifest(
              storeKey: session._storeKey,
              storeId: session._storeId,
              storageDomain: domain,
              bootstrap: nextBootstrap,
              sealedPackage: nextSealedPackage,
              manifest: source.manifest,
              nonce: session._entropy.randomBytes(V2StoreLimits.nonceBytes),
            );
            final expectedLength =
                bootstrapBytes.length +
                nextSealedPackage.length +
                source.layout.frameRegionLength +
                sealedManifest.length +
                v2ManifestLengthBytes;
            final nextLayout = deriveStoreLayout(
              fileLength: expectedLength,
              bootstrap: nextBootstrap,
              sealedManifestLength: sealedManifest.length,
            );
            deriveFrameRanges(
              source.manifest,
              frameRegionLength: nextLayout.frameRegionLength,
            );
            final stage = await transaction.createStaging(
              expectedLength: expectedLength,
            );
            await stage.append(bootstrapBytes);
            await stage.append(nextSealedPackage);
            for (final range in source.ranges) {
              final bytes = await _readExact(
                sourcePin,
                offset: source.layout.frameRegionOffset + range.offset,
                length: range.length,
              );
              if (!range.entry.hasFrameDigest(digestFrame(bytes))) {
                throw _error(
                  KeybayErrorCode.storeAuthenticationFailed,
                  'A source frame failed authentication.',
                );
              }
              await stage.append(bytes);
            }
            await stage.append(sealedManifest);
            await stage.append(encodeManifestLength(sealedManifest.length));

            final sourceCloseFailure = await _closePin(sourcePin);
            sourcePinClosed = true;
            if (sourceCloseFailure != null) throw sourceCloseFailure;

            final stagedPin = await stage.finish();
            await _usePin(
              stagedPin,
              (staged) => _verifyCompleteSnapshot(
                host: session._host,
                pin: staged,
                storeKey: session._storeKey,
                storeId: session._storeId,
                expectedRecordCount: source!.manifest.entries.length,
              ),
            );
            session._ensureCurrent();
            replaceAttempted = true;
            await stage.replaceLive();
            await _usePin(
              await _openPin(transaction.openPinnedLive),
              (committedPin) => _verifyCompleteSnapshot(
                host: session._host,
                pin: committedPin,
                storeKey: session._storeKey,
                storeId: session._storeId,
                expectedRecordCount: source!.manifest.entries.length,
              ),
            );
            await prepared.commit();
            committed = true;
          }
        }
      } on Object catch (error, stackTrace) {
        primaryFailure = error;
        primaryStack = stackTrace;
      }

      Object? cleanupFailure;
      StackTrace? cleanupStack;
      if (packagePlaintext != null) _clear(packagePlaintext);
      source?.clear();
      if (currentLease != null) {
        try {
          await currentLease.close();
        } on Object catch (error, stackTrace) {
          cleanupFailure ??= error;
          cleanupStack ??= stackTrace;
        }
      }
      if (!sourcePinClosed) {
        final closeFailure = await _closePin(sourcePin);
        sourcePinClosed = true;
        if (closeFailure != null) {
          cleanupFailure ??= closeFailure;
        }
      }
      if (prepared != null) {
        if (!committed && prepared.replacementLease != null) {
          final safeToAbort =
              !replaceAttempted ||
              (originalState != null &&
                  await _liveStillMatchesProviderState(
                    transaction: transaction,
                    expectedState: originalState,
                  ));
          if (safeToAbort) {
            try {
              await prepared.abort();
            } on Object {
              // Best-effort removal of an affirmatively unreferenced key.
            }
          }
        }
        try {
          await prepared.close();
        } on Object catch (error, stackTrace) {
          cleanupFailure ??= error;
          cleanupStack ??= stackTrace;
        }
      }
      final failure = primaryFailure ?? cleanupFailure;
      if (failure != null) {
        Error.throwWithStackTrace(
          failure,
          primaryStack ?? cleanupStack ?? StackTrace.current,
        );
      }
    });
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(_mapReaderFailure(error), stackTrace);
  }
}

/// Returns `true` only when the live store file can be opened and its
/// bootstrap `providerState` is affirmatively confirmed to still match
/// [expectedState]. Any unreadable, missing, or rotated state returns `false`
/// so cleanup never deletes a replacement key that the live store may depend on.
Future<bool> _liveStillMatchesProviderState({
  required StoreTransaction transaction,
  required ProviderState expectedState,
}) async {
  try {
    final pin = await _openPin(transaction.openPinnedLive);
    return await _usePin(pin, (live) async {
      final prefix = await _readPrefix(live);
      return expectedState.hasSameBytes(
        ProviderState(prefix.bootstrap.core.providerState),
      );
    });
  } on Object {
    return false;
  }
}

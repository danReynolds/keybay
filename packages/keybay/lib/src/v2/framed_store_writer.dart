part of 'keybay_v2.dart';

const int _initialStoreEpoch = 1;

enum _RecordChangeKind { set, delete, clear }

final class _RecordChange {
  const _RecordChange.set(this.requested, this.value)
    : kind = _RecordChangeKind.set;

  const _RecordChange.delete(this.requested)
    : kind = _RecordChangeKind.delete,
      value = null;

  const _RecordChange.clear()
    : kind = _RecordChangeKind.clear,
      requested = null,
      value = null;

  final _RecordChangeKind kind;
  final _RequestedRecord? requested;
  final Uint8List? value;
}

final class _InitializedStore {
  const _InitializedStore({
    required this.storeId,
    required this.storeKey,
    required this.epoch,
    required this.passphraseMethodId,
  });

  final Uint8List storeId;
  final Uint8List storeKey;
  final int epoch;
  final String? passphraseMethodId;
}

extension _V2PlatformInitialization on V2StoreEngine {
  Future<_InitializedStore> _initializeStore(
    ResolvedHost host,
    StoreTransaction transaction,
    _CredentialSnapshot? credential,
  ) async {
    Uint8List? storeId;
    Uint8List? storeKey;
    Uint8List? methodId;
    Uint8List? passphraseSalt;
    Uint8List? passphraseKey;
    Uint8List? packagePlaintext;
    V2KeyPackage? keyPackage;
    V2Manifest? manifest;
    PlatformRootLease? lease;
    _InitializedStore? result;
    String? passphraseMethodId;
    Object? primaryFailure;
    StackTrace? primaryStack;

    try {
      storeId = _entropy.randomBytes(V2StoreLimits.storeIdBytes);
      storeKey = _entropy.randomBytes(V2StoreLimits.storeKeyBytes);
      final manifestNonce = _entropy.randomBytes(V2StoreLimits.nonceBytes);

      if (credential == null) {
        keyPackage = V2PlatformOnlyPackage(
          storeId: storeId,
          epoch: _initialStoreEpoch,
          storeKey: storeKey,
        );
      } else {
        methodId = _entropy.randomBytes(V2StoreLimits.methodIdBytes);
        passphraseSalt = _entropy.randomBytes(V2StoreLimits.argonSaltBytes);
        final passphraseNonce = _entropy.randomBytes(V2StoreLimits.nonceBytes);
        passphraseKey = await _derivePassphraseAndReleaseCredential(
          deriver: _passphraseDeriver,
          credential: credential,
          profileId: v2FirstPassphraseProfile,
          salt: passphraseSalt,
        );
        final innerEnvelope = await sealPassphraseEnvelope(
          passphraseKey: passphraseKey,
          storeKey: storeKey,
          storeId: storeId,
          epoch: _initialStoreEpoch,
          methodId: methodId,
          profileId: v2FirstPassphraseProfile,
          salt: passphraseSalt,
          nonce: passphraseNonce,
        );
        keyPackage = V2PassphrasePackage(
          storeId: storeId,
          epoch: _initialStoreEpoch,
          methodId: methodId,
          profileId: v2FirstPassphraseProfile,
          salt: passphraseSalt,
          innerEnvelope: innerEnvelope,
        );
        passphraseMethodId = encodeMethodId(methodId);
      }
      packagePlaintext = encodeKeyPackage(keyPackage);

      // Finish every fallible entropy/KDF step before creating provider state.
      // A derivation failure therefore leaves no root-only partial store.
      final creation = await host.protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      lease = creation.lease;
      switch (creation.disposition) {
        case RootCreationDisposition.adopted:
          throw _error(
            KeybayErrorCode.storeStateConflict,
            'Platform protection exists without a complete V2 store.',
          );
        case RootCreationDisposition.created:
        case RootCreationDisposition.reused:
          break;
      }

      final providerState = lease.providerState.copyBytes();
      final bootstrapCore = V2BootstrapCore(providerState);
      final domain = host.binding.domain.copyBytes();
      final packageAad = encodePlatformPackageAad(
        storageDomain: domain,
        bootstrapCore: bootstrapCore,
      );
      late final Uint8List sealedPackage;
      try {
        sealedPackage = await lease.sealPackage(
          plaintext: packagePlaintext,
          aad: packageAad,
        );
        _validateSealedPackage(sealedPackage);
        await _verifyKeyPackage(
          lease: lease,
          sealedPackage: sealedPackage,
          aad: packageAad,
          expectedStoreId: storeId,
          expectedStoreKey: storeKey,
          expectedEpoch: _initialStoreEpoch,
          expectedMethodId: methodId,
          expectedSalt: passphraseSalt,
          passphraseKey: passphraseKey,
        );
      } finally {
        _clear(packagePlaintext);
        packagePlaintext = null;
        keyPackage.clear();
        keyPackage = null;
        if (passphraseKey != null) {
          _clear(passphraseKey);
          passphraseKey = null;
        }
      }
      await lease.close();
      lease = null;

      final bootstrap = V2Bootstrap(
        core: bootstrapCore,
        sealedPackageLength: sealedPackage.length,
      );
      final bootstrapBytes = encodeBootstrap(bootstrap);
      manifest = V2Manifest(const <V2ManifestEntry>[]);
      final sealedManifest = await sealManifest(
        storeKey: storeKey,
        storeId: storeId,
        storageDomain: domain,
        bootstrap: bootstrap,
        sealedPackage: sealedPackage,
        manifest: manifest,
        nonce: manifestNonce,
      );
      final trailer = encodeManifestLength(sealedManifest.length);

      final expectedLength =
          bootstrapBytes.length +
          sealedPackage.length +
          sealedManifest.length +
          trailer.length;
      final layout = deriveStoreLayout(
        fileLength: expectedLength,
        bootstrap: bootstrap,
        sealedManifestLength: sealedManifest.length,
      );
      deriveFrameRanges(manifest, frameRegionLength: layout.frameRegionLength);

      final stage = await transaction.createStaging(
        expectedLength: expectedLength,
      );
      await stage.append(bootstrapBytes);
      await stage.append(sealedPackage);
      await stage.append(sealedManifest);
      await stage.append(trailer);

      final stagedPin = await stage.finish();
      await _usePin(stagedPin, (pin) async {
        await _verifyCompleteSnapshot(
          host: host,
          pin: pin,
          storeKey: storeKey!,
          storeId: storeId!,
          expectedRecordCount: 0,
        );
      });
      await stage.replaceLive();

      final committedPin = await _openPin(transaction.openPinnedLive);
      await _usePin(committedPin, (pin) async {
        await _verifyCompleteSnapshot(
          host: host,
          pin: pin,
          storeKey: storeKey!,
          storeId: storeId!,
          expectedRecordCount: 0,
        );
      });

      result = _InitializedStore(
        storeId: storeId,
        storeKey: storeKey,
        epoch: _initialStoreEpoch,
        passphraseMethodId: passphraseMethodId,
      );
      storeId = null;
      storeKey = null;
    } on Object catch (error, stackTrace) {
      primaryFailure = error;
      primaryStack = stackTrace;
    }

    Object? cleanupFailure;
    StackTrace? cleanupStack;
    if (lease != null) {
      try {
        await lease.close();
      } on Object catch (error, stackTrace) {
        cleanupFailure = error;
        cleanupStack = stackTrace;
      }
    }
    if (storeKey != null) _clear(storeKey);
    if (passphraseKey != null) _clear(passphraseKey);
    if (packagePlaintext != null) _clear(packagePlaintext);
    keyPackage?.clear();
    manifest?.clear();

    final failure = primaryFailure ?? cleanupFailure;
    if (failure != null) {
      if (result != null) {
        _clear(result.storeKey);
      }
      Error.throwWithStackTrace(
        failure,
        primaryStack ?? cleanupStack ?? StackTrace.current,
      );
    }
    return result!;
  }

  Future<void> _resetPlatformState() async {
    Future<void>? invalidation;
    var resetCrossedRevocation = false;
    try {
      final host = await _resolveHost();
      await host.files.withExclusiveTransaction((transaction) async {
        PreparedPlatformReset? prepared;
        Object? primaryFailure;
        StackTrace? primaryStack;
        var liveWasRevoked = false;
        try {
          prepared = await host.protector.prepareReset(
            interaction: PlatformInteraction.allowed,
          );
          try {
            await transaction.resetManagedArtifacts();
            liveWasRevoked = true;
            resetCrossedRevocation = true;
          } on StoreFilesFailure catch (error, stackTrace) {
            if (error.code == StoreFilesFailureCode.resetNotStarted) {
              Error.throwWithStackTrace(error, stackTrace);
            }
            if (error.code != StoreFilesFailureCode.resetIncomplete) {
              rethrow;
            }
            liveWasRevoked = true;
            resetCrossedRevocation = true;
            primaryFailure = error;
            primaryStack = stackTrace;
          }

          invalidation = _invalidateSessions();
          try {
            await prepared.commit();
          } on Object catch (error, stackTrace) {
            primaryFailure ??= error;
            primaryStack ??= stackTrace;
          }
        } on Object catch (error, stackTrace) {
          primaryFailure ??= error;
          primaryStack ??= stackTrace;
        }

        Object? cleanupFailure;
        StackTrace? cleanupStack;
        if (prepared != null) {
          try {
            await prepared.close();
          } on Object catch (error, stackTrace) {
            cleanupFailure = error;
            cleanupStack = stackTrace;
          }
        }

        final failure = primaryFailure ?? cleanupFailure;
        if (failure != null) {
          if (liveWasRevoked) {
            throw _error(
              KeybayErrorCode.resetIncomplete,
              'Reset crossed the file-revocation point but did not complete.',
            );
          }
          Error.throwWithStackTrace(
            failure,
            primaryStack ?? cleanupStack ?? StackTrace.current,
          );
        }
      });
    } on Object catch (error, stackTrace) {
      if (resetCrossedRevocation) {
        throw _error(
          KeybayErrorCode.resetIncomplete,
          'Reset crossed the file-revocation point but did not complete.',
        );
      }
      Error.throwWithStackTrace(_mapReaderFailure(error), stackTrace);
    } finally {
      await invalidation;
    }
  }
}

Future<bool?> _commitRecordChange(
  V2StoreSession session,
  _RecordChange change,
) async {
  try {
    return await session._host.files.withExclusiveTransaction((
      transaction,
    ) async {
      session._ensureCurrent();
      await _requireCompleteStore(transaction);
      final sourcePin = await _openPin(transaction.openPinnedLive);

      _OpenedGeneration? source;
      StagedStoreFile? stage;
      Uint8List? newFrame;
      V2Manifest? replacementManifest;
      V2Manifest? changedEntryOwner;
      bool? operationResult;
      var commitRequired = true;
      Object? primaryFailure;
      StackTrace? primaryStack;

      try {
        source = await _openAuthenticatedGeneration(
          host: session._host,
          pin: sourcePin,
          storeKey: session._storeKey,
          storeId: session._storeId,
        );

        final targetRange = change.requested == null
            ? null
            : session._findRange(source.ranges, change.requested!.bytes);
        if (change.kind == _RecordChangeKind.delete && targetRange == null) {
          operationResult = false;
          commitRequired = false;
        } else if (change.kind == _RecordChangeKind.clear &&
            source.ranges.isEmpty) {
          operationResult = null;
          commitRequired = false;
        }

        if (!commitRequired) {
          if (change.kind == _RecordChangeKind.clear) {
            await _verifyAllFrameDigests(sourcePin, source);
          }
        } else {
          V2ManifestEntry? changedEntry;
          if (change.kind == _RecordChangeKind.set) {
            final frameNonce = session._entropy.randomBytes(
              V2StoreLimits.nonceBytes,
            );
            newFrame = await sealRecordFrameBytes(
              storeKey: session._storeKey,
              storeId: session._storeId,
              epoch: session._epoch,
              keyBytes: change.requested!.bytes,
              value: change.value!,
              nonce: frameNonce,
            );
            final newFrameDigest = digestFrame(newFrame);
            changedEntryOwner = V2Manifest(<V2ManifestEntry>[
              V2ManifestEntry(
                key: change.requested!.key,
                frameLength: newFrame.length,
                frameDigest: newFrameDigest,
              ),
            ]);
            changedEntry = changedEntryOwner.entries.single;
          }

          final entries = _replacementEntries(
            source.manifest.entries,
            change,
            changedEntry,
          );
          replacementManifest = V2Manifest(entries);
          final manifestNonce = session._entropy.randomBytes(
            V2StoreLimits.nonceBytes,
          );
          final domain = session._host.binding.domain.copyBytes();
          final sealedManifest = await sealManifest(
            storeKey: session._storeKey,
            storeId: session._storeId,
            storageDomain: domain,
            bootstrap: source.prefix.bootstrap,
            sealedPackage: source.prefix.sealedPackage,
            manifest: replacementManifest,
            nonce: manifestNonce,
          );
          final bootstrapBytes = encodeBootstrap(source.prefix.bootstrap);
          final trailer = encodeManifestLength(sealedManifest.length);
          final frameRegionLength = replacementManifest.entries.fold<int>(
            0,
            (length, entry) => length + entry.frameLength,
          );
          final expectedLength =
              bootstrapBytes.length +
              source.prefix.sealedPackage.length +
              frameRegionLength +
              sealedManifest.length +
              trailer.length;
          final layout = deriveStoreLayout(
            fileLength: expectedLength,
            bootstrap: source.prefix.bootstrap,
            sealedManifestLength: sealedManifest.length,
          );
          deriveFrameRanges(
            replacementManifest,
            frameRegionLength: layout.frameRegionLength,
          );

          stage = await transaction.createStaging(
            expectedLength: expectedLength,
          );
          await stage.append(bootstrapBytes);
          await stage.append(source.prefix.sealedPackage);
          await _copyForwardFrames(
            sourcePin: sourcePin,
            source: source,
            stage: stage,
            change: change,
            newFrame: newFrame,
          );
          await stage.append(sealedManifest);
          await stage.append(trailer);
          operationResult = change.kind == _RecordChangeKind.delete
              ? true
              : null;
        }
      } on Object catch (error, stackTrace) {
        primaryFailure = error;
        primaryStack = stackTrace;
      }

      final sourceCloseFailure = await _closePin(sourcePin);
      final sourceFailure = primaryFailure ?? sourceCloseFailure;
      if (sourceFailure != null) {
        source?.clear();
        replacementManifest?.clear();
        changedEntryOwner?.clear();
        Error.throwWithStackTrace(
          sourceFailure,
          primaryStack ?? StackTrace.current,
        );
      }

      try {
        if (!commitRequired) return operationResult;
        final stagedPin = await stage!.finish();
        await _usePin(stagedPin, (pin) async {
          await _verifyCompleteSnapshot(
            host: session._host,
            pin: pin,
            storeKey: session._storeKey,
            storeId: session._storeId,
            expectedRecordCount: replacementManifest!.entries.length,
          );
        });
        session._ensureCurrent();
        await stage.replaceLive();

        final committedPin = await _openPin(transaction.openPinnedLive);
        await _usePin(committedPin, (pin) async {
          await _verifyCompleteSnapshot(
            host: session._host,
            pin: pin,
            storeKey: session._storeKey,
            storeId: session._storeId,
            expectedRecordCount: replacementManifest!.entries.length,
          );
        });
        return operationResult;
      } finally {
        source?.clear();
        replacementManifest?.clear();
        changedEntryOwner?.clear();
      }
    });
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(_mapReaderFailure(error), stackTrace);
  }
}

List<V2ManifestEntry> _replacementEntries(
  List<V2ManifestEntry> source,
  _RecordChange change,
  V2ManifestEntry? changed,
) {
  if (change.kind == _RecordChangeKind.clear) {
    return <V2ManifestEntry>[];
  }

  final requested = change.requested!;
  final result = <V2ManifestEntry>[];
  var inserted = false;
  for (final entry in source) {
    final comparison = entry.compareKeyBytes(requested.bytes);
    if (change.kind == _RecordChangeKind.set && !inserted && comparison > 0) {
      result.add(changed!);
      inserted = true;
    }
    if (comparison == 0) {
      if (change.kind == _RecordChangeKind.set && !inserted) {
        result.add(changed!);
        inserted = true;
      }
      continue;
    }
    result.add(entry);
  }
  if (change.kind == _RecordChangeKind.set && !inserted) {
    result.add(changed!);
  }
  return result;
}

Future<void> _copyForwardFrames({
  required PinnedStoreFile sourcePin,
  required _OpenedGeneration source,
  required StagedStoreFile stage,
  required _RecordChange change,
  required Uint8List? newFrame,
}) async {
  final requested = change.requested;
  var inserted = false;
  for (final range in source.ranges) {
    final comparison = requested == null
        ? 0
        : range.entry.compareKeyBytes(requested.bytes);
    if (change.kind == _RecordChangeKind.set && !inserted && comparison > 0) {
      await stage.append(newFrame!);
      inserted = true;
    }

    final frame = await _readExact(
      sourcePin,
      offset: source.layout.frameRegionOffset + range.offset,
      length: range.length,
    );
    final digest = digestFrame(frame);
    if (!range.entry.hasFrameDigest(digest)) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'A source record frame failed authentication.',
      );
    }
    if (change.kind == _RecordChangeKind.clear || comparison == 0) {
      if (change.kind == _RecordChangeKind.set && comparison == 0) {
        await stage.append(newFrame!);
        inserted = true;
      }
    } else {
      await stage.append(frame);
    }
  }
  if (change.kind == _RecordChangeKind.set && !inserted) {
    await stage.append(newFrame!);
  }
}

Future<void> _verifyCompleteSnapshot({
  required ResolvedHost host,
  required PinnedStoreFile pin,
  required Uint8List storeKey,
  required Uint8List storeId,
  int? expectedRecordCount,
}) async {
  final generation = await _openAuthenticatedGeneration(
    host: host,
    pin: pin,
    storeKey: storeKey,
    storeId: storeId,
  );
  try {
    if (expectedRecordCount != null &&
        generation.manifest.entries.length != expectedRecordCount) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'The staged V2 store does not match the intended snapshot.',
      );
    }
    await _verifyAllFrameDigests(pin, generation);
  } finally {
    generation.clear();
  }
}

Future<void> _verifyAllFrameDigests(
  PinnedStoreFile pin,
  _OpenedGeneration generation,
) async {
  for (final range in generation.ranges) {
    final frame = await _readExact(
      pin,
      offset: generation.layout.frameRegionOffset + range.offset,
      length: range.length,
    );
    final digest = digestFrame(frame);
    if (!range.entry.hasFrameDigest(digest)) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'A V2 record frame failed authentication.',
      );
    }
  }
}

Future<T> _usePin<T>(
  PinnedStoreFile pin,
  Future<T> Function(PinnedStoreFile pin) operation,
) async {
  T? result;
  Object? primaryFailure;
  StackTrace? primaryStack;
  try {
    result = await operation(pin);
  } on Object catch (error, stackTrace) {
    primaryFailure = error;
    primaryStack = stackTrace;
  }
  final cleanupFailure = await _closePin(pin);
  final failure = primaryFailure ?? cleanupFailure;
  if (failure != null) {
    Error.throwWithStackTrace(failure, primaryStack ?? StackTrace.current);
  }
  return result as T;
}

Future<void> _verifyKeyPackage({
  required PlatformRootLease lease,
  required Uint8List sealedPackage,
  required Uint8List aad,
  required Uint8List expectedStoreId,
  required Uint8List expectedStoreKey,
  required int expectedEpoch,
  required Uint8List? expectedMethodId,
  required Uint8List? expectedSalt,
  required Uint8List? passphraseKey,
}) async {
  Uint8List? plaintext;
  Uint8List? openedStoreId;
  Uint8List? openedStoreKey;
  Uint8List? openedMethodId;
  Uint8List? openedSalt;
  Uint8List? openedEnvelope;
  V2KeyPackage? package;
  try {
    plaintext = await lease.openPackage(sealedPackage: sealedPackage, aad: aad);
    package = decodeKeyPackage(plaintext);
    if (package.epoch != expectedEpoch) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'The platform package failed verification.',
      );
    }
    openedStoreId = package.storeId;
    if (!_constantTimeEquals(openedStoreId, expectedStoreId)) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'The platform package failed verification.',
      );
    }

    if (expectedMethodId == null) {
      if (package is! V2PlatformOnlyPackage ||
          expectedSalt != null ||
          passphraseKey != null) {
        throw _error(
          KeybayErrorCode.storeAuthenticationFailed,
          'The platform package failed verification.',
        );
      }
      openedStoreKey = package.takeStoreKey();
    } else {
      if (package is! V2PassphrasePackage ||
          expectedSalt == null ||
          passphraseKey == null) {
        throw _error(
          KeybayErrorCode.storeAuthenticationFailed,
          'The platform package failed verification.',
        );
      }
      openedMethodId = package.methodId;
      openedSalt = package.salt;
      openedEnvelope = package.innerEnvelope;
      if (!_constantTimeEquals(openedMethodId, expectedMethodId) ||
          !_constantTimeEquals(openedSalt, expectedSalt) ||
          package.profileId != v2FirstPassphraseProfile) {
        throw _error(
          KeybayErrorCode.storeAuthenticationFailed,
          'The platform package failed verification.',
        );
      }
      openedStoreKey = await openPassphraseEnvelope(
        passphraseKey: passphraseKey,
        storeId: openedStoreId,
        epoch: package.epoch,
        methodId: openedMethodId,
        profileId: package.profileId,
        salt: openedSalt,
        innerEnvelope: openedEnvelope,
      );
    }
    if (!_constantTimeEquals(openedStoreKey, expectedStoreKey)) {
      throw _error(
        KeybayErrorCode.storeAuthenticationFailed,
        'The platform package failed verification.',
      );
    }
  } finally {
    package?.clear();
    if (plaintext != null) _clear(plaintext);
    if (openedStoreKey != null) _clear(openedStoreKey);
  }
}

void _validateSealedPackage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > V2StoreLimits.sealedPackageBytes) {
    throw _error(
      KeybayErrorCode.platformOperationFailed,
      'The platform protector returned an invalid package.',
    );
  }
}

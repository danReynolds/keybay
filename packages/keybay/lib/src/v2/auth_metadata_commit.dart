part of 'keybay_v2.dart';

/// Commit migration/provider verification state before publishing a session.
/// The original package is a compare-and-swap token. Ordinary record writes
/// preserve it and are merged by copying the latest authenticated generation.
Future<void> _commitOpenedMetadata({
  required V2StoreEngine engine,
  required ResolvedHost host,
  required PlatformRootLease lease,
  required Uint8List storeKey,
  required Uint8List storeId,
  required _StorePrefix expectedPrefix,
  required V2MethodsPackage? replacement,
  required int openingGeneration,
  required _CredentialSnapshot? credential,
}) => host.files.withExclusiveTransaction((transaction) async {
  _checkPasskeyCancelled(credential);
  if (engine._runtimeGeneration != openingGeneration) {
    throw _error(
      KeybayErrorCode.staleSession,
      'The store changed while opening.',
    );
  }
  final pin = await _openPin(transaction.openPinnedLive);
  _OpenedGeneration? source;
  Uint8List? plaintext;
  try {
    final actual = await _readPrefix(pin);
    if (!_constantTimeEquals(
          actual.sealedPackage,
          expectedPrefix.sealedPackage,
        ) ||
        !_constantTimeEquals(
          encodeBootstrap(actual.bootstrap),
          encodeBootstrap(expectedPrefix.bootstrap),
        )) {
      throw _error(
        KeybayErrorCode.storeStateConflict,
        'Authentication state changed while opening. Retry the open.',
      );
    }
    source = await _openAuthenticatedGeneration(
      host: host,
      pin: pin,
      storeKey: storeKey,
      storeId: storeId,
    );
    // Only an authenticated live generation authorizes removal of abandoned
    // staging. Failed credentials never change existing transaction artifacts.
    _checkPasskeyCancelled(credential);
    if ((await transaction.observeArtifacts()).hasTransactionArtifacts) {
      await transaction.discardAbandonedStaging();
    }
    if (replacement == null) return;
    _checkPasskeyCancelled(credential);
    final core = V2BootstrapCore(
      actual.bootstrap.core.providerState,
      suite: v2MethodsSuite,
    );
    final domain = host.binding.domain.copyBytes();
    final aad = encodePlatformPackageAad(
      storageDomain: domain,
      bootstrapCore: core,
    );
    plaintext = encodeKeyPackage(replacement);
    final sealed = await lease.sealPackage(plaintext: plaintext, aad: aad);
    _validateSealedPackage(sealed);
    await _verifyKeyPackage(
      lease: lease,
      sealedPackage: sealed,
      aad: aad,
      expectedPlaintext: plaintext,
    );
    _clear(plaintext);
    plaintext = null;
    final bootstrap = V2Bootstrap(
      core: core,
      sealedPackageLength: sealed.length,
    );
    final bootstrapBytes = encodeBootstrap(bootstrap);
    final manifest = await sealManifest(
      storeKey: storeKey,
      storeId: storeId,
      storageDomain: domain,
      bootstrap: bootstrap,
      sealedPackage: sealed,
      manifest: source.manifest,
      nonce: engine._entropy.randomBytes(V2StoreLimits.nonceBytes),
    );
    final stage = await transaction.createStaging(
      expectedLength:
          bootstrapBytes.length +
          sealed.length +
          source.layout.frameRegionLength +
          manifest.length +
          v2ManifestLengthBytes,
    );
    await stage.append(bootstrapBytes);
    await stage.append(sealed);
    for (final range in source.ranges) {
      final bytes = await _readExact(
        pin,
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
    await stage.append(manifest);
    await stage.append(encodeManifestLength(manifest.length));
    await _usePin(
      await stage.finish(),
      (staged) => _verifyCompleteSnapshot(
        host: host,
        pin: staged,
        storeKey: storeKey,
        storeId: storeId,
        expectedRecordCount: source!.manifest.entries.length,
      ),
    );
    _checkPasskeyCancelled(credential);
    if (engine._runtimeGeneration != openingGeneration) {
      throw _error(
        KeybayErrorCode.staleSession,
        'The store changed while opening.',
      );
    }
    await stage.replaceLive();
    await _usePin(
      await _openPin(transaction.openPinnedLive),
      (committed) => _verifyCompleteSnapshot(
        host: host,
        pin: committed,
        storeKey: storeKey,
        storeId: storeId,
        expectedRecordCount: source!.manifest.entries.length,
      ),
    );
  } finally {
    source?.clear();
    if (plaintext != null) _clear(plaintext);
    await pin.close();
  }
});

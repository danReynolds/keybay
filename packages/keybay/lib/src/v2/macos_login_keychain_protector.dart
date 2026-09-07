/// macOS unentitled/CLI protection using the fixed login Keychain.
library;

import 'dart:typed_data';

import 'apple_keychain_protector_boundary.dart';
import 'entropy_source.dart';
import 'exportable_root_protector_core.dart';
import 'host_binding.dart';
import 'macos_login_keychain_root_store.dart';
import 'platform_protector.dart';

const List<int> _recordMagic = <int>[
  0x4b,
  0x42,
  0x56,
  0x32,
  0x4d,
  0x4b,
  0x30,
  0x31,
]; // KBV2MK01

/// The V2 protector for a normal macOS process without DP-keychain entitlement.
///
/// One exact item in the effective account's login Keychain is addressed by
/// the resolved application's provider address. Its value contains the
/// selected storage-domain commitment and one random exportable root. Provider
/// state is a domain-separated fingerprint of that root, so replacement is
/// classified before package open.
///
/// Classic file Keychains cannot enforce per-call UI suppression. Acquisitions
/// therefore require interaction permission before any native access; ordinary
/// record operations use the already-open session key and never need a root.
final class MacOSLoginKeychainProtector implements PlatformProtector {
  MacOSLoginKeychainProtector({
    required this.binding,
    required MacOSLoginKeychainRootStore roots,
    V2EntropySource? entropy,
  }) : _roots = roots,
       _core = ExportableRootProtectorCore(
         binding: binding,
         recordMagic: _recordMagic,
         providerStateLabel: 'keybay:v2:macos-login-keychain:provider-state',
         entropy: entropy,
       );

  @override
  final ResolvedApplicationBinding binding;

  final MacOSLoginKeychainRootStore _roots;
  final ExportableRootProtectorCore _core;

  String get _account => binding.providerAddress;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) => atAppleKeychainProtectorBoundary(() {
    _core.requireExpectedState(state);
    _requireInteractionAllowed(interaction);
    return _core.openExisting(state, () => _roots.read(_account));
  });

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) => atAppleKeychainProtectorBoundary(() async {
    _requireInteractionAllowed(interaction);
    Uint8List? candidateRoot;
    Uint8List? candidateRecord;
    Uint8List? winnerRecord;
    try {
      candidateRoot = _core.randomRoot();
      candidateRecord = _core.encodeRecord(candidateRoot);
      final inserted = await _roots.createIfAbsent(_account, candidateRecord);

      // Always read back from the same fixed Keychain target. Success from
      // add is not enough if it did not persist the exact candidate bytes.
      winnerRecord = await _roots.read(_account);
      if (winnerRecord == null ||
          (inserted && !_core.sameBytes(winnerRecord, candidateRecord))) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.stateConflict,
        );
      }
      return _core.creationFromRecord(
        winnerRecord,
        inserted
            ? RootCreationDisposition.created
            : RootCreationDisposition.adopted,
      );
    } finally {
      if (candidateRoot != null) _core.clear(candidateRoot);
      if (candidateRecord != null) _core.clear(candidateRecord);
      if (winnerRecord != null) _core.clear(winnerRecord);
    }
  });

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) => atAppleKeychainProtectorBoundary(() async {
    _requireInteractionAllowed(interaction);
    final record = await _roots.read(_account);
    try {
      // Preserve a structurally valid record owned by another file domain.
      // Malformed state at this exact address remains resettable by digest.
      if (record != null && _core.hasValidRecordShape(record)) {
        _core.verifyDomain(record);
      }
      return _core.prepareReset(record: record, commit: _commitReset);
    } finally {
      if (record != null) _core.clear(record);
    }
  });

  void _requireInteractionAllowed(PlatformInteraction interaction) {
    if (interaction != PlatformInteraction.allowed) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.interactionRequired,
      );
    }
  }

  Future<void> _commitReset(Uint8List? expectedDigest) async {
    try {
      final current = await _roots.read(_account);
      if (current == null) return;
      try {
        _core.requirePreparedResetMatch(current, expectedDigest);
      } finally {
        _core.clear(current);
      }

      await _roots.delete(_account);
      if (await _roots.exists(_account)) {
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

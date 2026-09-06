/// Shared iOS and entitled-macOS V2 Data Protection Keychain protector.
library;

import 'dart:typed_data';

import 'apple_data_protection_keychain_root_store.dart';
import 'apple_keychain_protector_boundary.dart';
import 'entropy_source.dart';
import 'exportable_root_protector_core.dart';
import 'host_binding.dart';
import 'platform_protector.dart';

const List<int> _recordMagic = <int>[
  0x4b,
  0x42,
  0x56,
  0x32,
  0x41,
  0x50,
  0x30,
  0x31,
]; // KBV2AP01

/// One V2 root in the signed app's exact application-identifier group.
///
/// The qualified host profile owns access-group selection before constructing
/// [roots]. That exact-group ownership also fixes reset policy: reset may
/// remove malformed or old-domain bytes at this one identity-derived V2
/// address. Open and create never repair such state; they fail closed.
final class AppleDataProtectionKeychainProtector implements PlatformProtector {
  AppleDataProtectionKeychainProtector({
    required this.binding,
    required DataProtectionKeychainRootStore roots,
    V2EntropySource? entropy,
  }) : _roots = roots,
       _core = ExportableRootProtectorCore(
         binding: binding,
         recordMagic: _recordMagic,
         providerStateLabel:
             'keybay:v2:apple-data-protection-keychain:provider-state',
         entropy: entropy,
       );

  @override
  final ResolvedApplicationBinding binding;

  final DataProtectionKeychainRootStore _roots;
  final ExportableRootProtectorCore _core;

  String get _account => binding.providerAddress;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) => atAppleKeychainProtectorBoundary(
    () => _core.openExisting(state, () => _roots.read(_account)),
  );

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) => atAppleKeychainProtectorBoundary(() async {
    Uint8List? candidateRoot;
    Uint8List? candidateRecord;
    Uint8List? winnerRecord;
    try {
      candidateRoot = _core.randomRoot();
      candidateRecord = _core.encodeRecord(candidateRoot);
      final inserted = await _roots.createIfAbsent(_account, candidateRecord);

      // Do not trust add alone. Read the exact item back and either verify
      // our bytes or adopt the already-present same-domain root.
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
    final record = await _roots.read(_account);
    try {
      // This exact address lives in the app's signed group. Its file-domain
      // path may legitimately change after reinstall, so reset owns even
      // malformed and old-domain state here. Open still validates it.
      return _core.prepareReset(record: record, commit: _commitReset);
    } finally {
      if (record != null) _core.clear(record);
    }
  });

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

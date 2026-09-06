/// Ordinary Linux V2 protection using one Secret Service application root.
library;

import 'dart:typed_data';

import '../errors.dart';
import 'entropy_source.dart';
import 'exportable_root_protector_core.dart';
import 'host_binding.dart';
import 'linux_secret_service_root_store.dart';
import 'platform_protector.dart';

const List<int> _recordMagic = <int>[
  0x4b,
  0x42,
  0x56,
  0x32,
  0x4c,
  0x53,
  0x30,
  0x31,
]; // KBV2LS01

/// One identity-derived Secret Service root for an ordinary Linux store.
final class LinuxSecretServiceProtector implements PlatformProtector {
  LinuxSecretServiceProtector({
    required this.binding,
    required LinuxSecretServiceRootStore roots,
    V2EntropySource? entropy,
  }) : _roots = roots,
       _core = ExportableRootProtectorCore(
         binding: binding,
         recordMagic: _recordMagic,
         providerStateLabel: 'keybay:v2:linux-secret-service:provider-state',
         entropy: entropy,
       );

  @override
  final ResolvedApplicationBinding binding;

  final LinuxSecretServiceRootStore _roots;
  final ExportableRootProtectorCore _core;

  String get _account => binding.providerAddress;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) => _atSecretServiceBoundary(
    () => _core.openExisting(state, () async {
      final item = await _roots.readUnique(_account);
      return item?.value;
    }),
  );

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) => _atSecretServiceBoundary(
    () => _roots.withCreationLock(_account, () async {
      Uint8List? existingRecord;
      Uint8List? candidateRoot;
      Uint8List? candidateRecord;
      Uint8List? winnerRecord;
      try {
        existingRecord = (await _roots.readUnique(_account))?.value;
        if (existingRecord != null) {
          return _core.creationFromRecord(
            existingRecord,
            RootCreationDisposition.adopted,
          );
        }

        candidateRoot = _core.randomRoot();
        candidateRecord = _core.encodeRecord(candidateRoot);
        await _roots.createNew(_account, candidateRecord);

        // CreateItem uses replace=false. This exact re-query then rejects
        // a raced duplicate or any changed winner before adopting state.
        winnerRecord = (await _roots.readUnique(_account))?.value;
        if (winnerRecord == null ||
            !_core.sameBytes(winnerRecord, candidateRecord)) {
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.stateConflict,
          );
        }
        return _core.creationFromRecord(
          winnerRecord,
          RootCreationDisposition.created,
        );
      } finally {
        if (existingRecord != null) _core.clear(existingRecord);
        if (candidateRoot != null) _core.clear(candidateRoot);
        if (candidateRecord != null) _core.clear(candidateRecord);
        if (winnerRecord != null) _core.clear(winnerRecord);
      }
    }),
  );

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) => _atSecretServiceBoundary(() async {
    final item = await _roots.readUnique(_account);
    final record = item?.value;
    try {
      // Preserve a valid record for another domain. Malformed state at
      // this exact fixed address remains resettable by digest.
      if (record != null && _core.hasValidRecordShape(record)) {
        _core.verifyDomain(record);
      }
      return _core.prepareReset(record: record, commit: _commitReset);
    } finally {
      if (record != null) _core.clear(record);
    }
  });

  Future<void> _commitReset(Uint8List? expectedDigest) async {
    try {
      await _roots.withCreationLock(_account, () async {
        final currentItem = await _roots.readUnique(_account);
        if (currentItem == null) return;
        final current = currentItem.value;
        try {
          _core.requirePreparedResetMatch(current, expectedDigest);
        } finally {
          _core.clear(current);
        }

        await _roots.delete(currentItem);
        final remaining = (await _roots.readUnique(_account))?.value;
        if (remaining != null) {
          _core.clear(remaining);
          throw const PlatformProtectorFailure(
            PlatformProtectorFailureCode.resetIncomplete,
          );
        }
      });
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }
}

Future<T> _atSecretServiceBoundary<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on PlatformProtectorFailure {
    rethrow;
  } on V2EntropyFailure {
    rethrow;
  } on LinuxSecretServiceMultipleMatches {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.stateConflict,
    );
  } on LinuxSecretServiceInteractionRequired {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.interactionRequired,
    );
  } on LinuxSecretServiceProviderBusy {
    throw const PlatformProtectorFailure(PlatformProtectorFailureCode.busy);
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

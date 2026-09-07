import 'dart:typed_data';

import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/store_files.dart';

import 'v2_software_root_lease.dart';

final class FakeHostPlatform implements HostPlatform {
  FakeHostPlatform(this.host);

  final ResolvedHost host;
  int resolveCount = 0;

  @override
  Future<ResolvedHost> resolve() async {
    resolveCount++;
    return host;
  }
}

final class MemoryStoreFiles implements StoreFiles {
  MemoryStoreFiles(this.binding);

  @override
  final ResolvedApplicationBinding binding;

  bool hasLiveFile = false;
  bool hasTransactionArtifacts = false;
  int resetCount = 0;
  bool _transactionActive = false;

  /// Test-only lock-free snapshot of the disposable backing state.
  Future<StoreArtifacts> observeArtifacts() async => StoreArtifacts(
    hasLiveFile: hasLiveFile,
    hasTransactionArtifacts: hasTransactionArtifacts,
  );

  @override
  Future<PinnedStoreFile?> openPinnedLive() async {
    if (!hasLiveFile) return null;
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }

  @override
  Future<T> withExclusiveTransaction<T>(
    Future<T> Function(StoreTransaction transaction) operation,
  ) async {
    if (_transactionActive) {
      throw const StoreFilesFailure(StoreFilesFailureCode.busy);
    }
    _transactionActive = true;
    final transaction = _MemoryStoreFilesTransaction(this);
    try {
      return await operation(transaction);
    } finally {
      transaction._active = false;
      _transactionActive = false;
    }
  }
}

final class _MemoryStoreFilesTransaction implements StoreTransaction {
  _MemoryStoreFilesTransaction(this._owner);

  final MemoryStoreFiles _owner;
  bool _active = true;

  @override
  Future<StoreArtifacts> observeArtifacts() async {
    _ensureActive();
    return _owner.observeArtifacts();
  }

  @override
  Future<PinnedStoreFile?> openPinnedLive() async {
    _ensureActive();
    return _owner.openPinnedLive();
  }

  @override
  Future<StagedStoreFile> createStaging({required int expectedLength}) async {
    _ensureActive();
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }

  @override
  Future<void> discardAbandonedStaging() async {
    _ensureActive();
    if (!_owner.hasLiveFile || !_owner.hasTransactionArtifacts) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    _owner.hasTransactionArtifacts = false;
  }

  @override
  Future<void> resetManagedArtifacts() async {
    _ensureActive();
    _owner.resetCount++;
    _owner.hasLiveFile = false;
    _owner.hasTransactionArtifacts = false;
  }

  void _ensureActive() {
    if (!_active) throw StateError('The store transaction has ended.');
  }
}

final class InMemoryRootRegistry {
  final Map<String, _RootRecord> _roots = <String, _RootRecord>{};
  final Set<String> _preparedResets = <String>{};

  int get rootCount => _roots.length;
}

enum SoftwareResetFailure { incompleteAfterMutation }

final class SoftwareTestProtector implements PlatformProtector {
  SoftwareTestProtector({
    required this.binding,
    required InMemoryRootRegistry registry,
    this.resetFailure,
  }) : _registry = registry;

  @override
  final ResolvedApplicationBinding binding;

  final InMemoryRootRegistry _registry;
  final SoftwareResetFailure? resetFailure;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) async {
    _requireNoPreparedReset();
    final record = _registry._roots[binding.providerAddress];
    if (record == null) return null;
    _verifyDomain(record);
    if (!record.providerState.hasSameBytes(state)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    return SoftwareRootLease(
      root: record.root,
      providerState: record.providerState,
    );
  }

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) async {
    _requireNoPreparedReset();
    final existing = _registry._roots[binding.providerAddress];
    if (existing != null) {
      _verifyDomain(existing);
      return PlatformRootCreation(
        lease: SoftwareRootLease(
          root: existing.root,
          providerState: existing.providerState,
        ),
        disposition: RootCreationDisposition.adopted,
      );
    }

    final record = _RootRecord(
      domain: binding.domain,
      root: randomTestBytes(32),
      providerState: ProviderState(randomTestBytes(16)),
    );
    _registry._roots[binding.providerAddress] = record;
    return PlatformRootCreation(
      lease: SoftwareRootLease(
        root: record.root,
        providerState: record.providerState,
      ),
      disposition: RootCreationDisposition.created,
    );
  }

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) async {
    _requireNoPreparedReset();
    final existing = _registry._roots[binding.providerAddress];
    if (existing != null) _verifyDomain(existing);
    _registry._preparedResets.add(binding.providerAddress);
    return _SoftwarePreparedReset(
      registry: _registry,
      providerAddress: binding.providerAddress,
      expected: existing,
      failAfterMutation:
          resetFailure == SoftwareResetFailure.incompleteAfterMutation,
    );
  }

  void _requireNoPreparedReset() {
    if (_registry._preparedResets.contains(binding.providerAddress)) {
      throw const PlatformProtectorFailure(PlatformProtectorFailureCode.locked);
    }
  }

  void _verifyDomain(_RootRecord record) {
    if (record.domain != binding.domain) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.stateConflict,
      );
    }
  }
}

final class _SoftwarePreparedReset implements PreparedPlatformReset {
  _SoftwarePreparedReset({
    required InMemoryRootRegistry registry,
    required String providerAddress,
    required _RootRecord? expected,
    required bool failAfterMutation,
  }) : _registry = registry,
       _providerAddress = providerAddress,
       _expected = expected,
       _failAfterMutation = failAfterMutation;

  final InMemoryRootRegistry _registry;
  final String _providerAddress;
  final _RootRecord? _expected;
  final bool _failAfterMutation;
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

    final current = _registry._roots[_providerAddress];
    if (!identical(current, _expected)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
    if (current == null) return;

    _registry._roots.remove(_providerAddress);
    clearTestBytes(current.root);
    if (_failAfterMutation) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _registry._preparedResets.remove(_providerAddress);
  }
}

final class _RootRecord {
  _RootRecord({
    required this.domain,
    required Uint8List root,
    required this.providerState,
  }) : root = Uint8List.fromList(root);

  final StorageDomain domain;
  final Uint8List root;
  final ProviderState providerState;
}

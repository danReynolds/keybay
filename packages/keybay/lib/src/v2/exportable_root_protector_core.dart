/// Shared record and lease mechanics for providers with exportable root bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'entropy_source.dart';
import 'exportable_root_lease.dart';
import 'format/store_format.dart';
import 'host_binding.dart';
import 'platform_protector.dart';

/// The provider-independent mechanics of an exportable-root protector.
///
/// Provider adapters retain custody, creation, locking, reset-ownership, and
/// error-mapping policy. This helper owns only the fixed root-record grammar,
/// storage-domain checks, provider-state derivation, and short-lived leases.
final class ExportableRootProtectorCore {
  ExportableRootProtectorCore({
    required this.binding,
    required List<int> recordMagic,
    required String providerStateLabel,
    V2EntropySource? entropy,
  }) : _recordMagic = Uint8List.fromList(recordMagic),
       _recordLength =
           recordMagic.length +
           V2StoreLimits.digestBytes +
           V2StoreLimits.storeKeyBytes,
       _providerStateLabel = Uint8List.fromList(
         utf8.encode(providerStateLabel),
       ),
       _entropy = entropy ?? SecureV2EntropySource();

  final ResolvedApplicationBinding binding;
  final int _recordLength;
  final Uint8List _recordMagic;
  final Uint8List _providerStateLabel;
  final V2EntropySource _entropy;

  /// Rejects malformed provider continuation state before provider access.
  void requireExpectedState(ProviderState state) {
    if (state.length != V2StoreLimits.digestBytes) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
  }

  /// Opens one freshly owned record returned by [readRecord].
  ///
  /// The callback must return a mutable buffer owned by this operation. This
  /// method clears that buffer and the decoded root on every path.
  Future<PlatformRootLease?> openExisting(
    ProviderState expectedState,
    Future<Uint8List?> Function() readRecord,
  ) async {
    requireExpectedState(expectedState);
    final record = await readRecord();
    if (record == null) return null;
    Uint8List? root;
    try {
      root = decodeRoot(record);
      final actualState = providerState(root);
      if (!actualState.hasSameBytes(expectedState)) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.invalidated,
        );
      }
      return ExportableRootLease(
        root: root,
        providerState: actualState,
        entropy: _entropy,
      );
    } finally {
      clear(record);
      if (root != null) clear(root);
    }
  }

  /// Generates one candidate exportable root.
  Uint8List randomRoot() => _entropy.randomBytes(V2StoreLimits.storeKeyBytes);

  /// Encodes one root under this provider's frozen record magic and domain.
  Uint8List encodeRecord(Uint8List root) {
    if (root.length != V2StoreLimits.storeKeyBytes) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    final domain = binding.domain.copyBytes();
    final record = Uint8List(_recordLength);
    final domainStart = _recordMagic.length;
    final rootStart = domainStart + domain.length;
    record
      ..setRange(0, domainStart, _recordMagic)
      ..setRange(domainStart, rootStart, domain)
      ..setRange(rootStart, record.length, root);
    return record;
  }

  /// Constructs a creation result from a provider-selected record.
  ///
  /// The caller retains ownership of [record]. The decoded root is cleared
  /// after [ExportableRootLease] snapshots it.
  PlatformRootCreation creationFromRecord(
    Uint8List record,
    RootCreationDisposition disposition,
  ) {
    final root = decodeRoot(record);
    try {
      final state = providerState(root);
      return PlatformRootCreation(
        lease: ExportableRootLease(
          root: root,
          providerState: state,
          entropy: _entropy,
        ),
        disposition: disposition,
      );
    } finally {
      clear(root);
    }
  }

  /// Decodes a valid, domain-bound root record.
  Uint8List decodeRoot(Uint8List record) {
    validateRecord(record);
    verifyDomain(record);
    return Uint8List.fromList(
      Uint8List.sublistView(
        record,
        _recordMagic.length + V2StoreLimits.digestBytes,
      ),
    );
  }

  /// Rejects malformed record shape as provider invalidation.
  void validateRecord(Uint8List record) {
    if (!hasValidRecordShape(record)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
  }

  /// Whether [record] has this provider's exact frozen shape and magic.
  bool hasValidRecordShape(Uint8List record) =>
      record.length == _recordLength &&
      sameBytes(
        Uint8List.sublistView(record, 0, _recordMagic.length),
        _recordMagic,
      );

  /// Requires a structurally valid record to belong to this storage domain.
  void verifyDomain(Uint8List record) {
    final expected = binding.domain.copyBytes();
    final encoded = Uint8List.sublistView(
      record,
      _recordMagic.length,
      _recordMagic.length + V2StoreLimits.digestBytes,
    );
    if (!sameBytes(encoded, expected)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.stateConflict,
      );
    }
  }

  /// Derives the persisted provider-state fingerprint for [root].
  ProviderState providerState(Uint8List root) {
    final domain = binding.domain.copyBytes();
    final transcript = Uint8List(
      _providerStateLabel.length + 1 + domain.length + root.length,
    );
    try {
      final domainStart = _providerStateLabel.length + 1;
      final rootStart = domainStart + domain.length;
      transcript
        ..setRange(0, _providerStateLabel.length, _providerStateLabel)
        ..setRange(domainStart, rootStart, domain)
        ..setRange(rootStart, transcript.length, root);
      final digest = Uint8List.fromList(
        const DartSha256().hashSync(transcript).bytes,
      );
      return ProviderState(digest);
    } finally {
      clear(transcript);
    }
  }

  /// Captures one prepared reset target by digest without mutating it.
  PreparedPlatformReset prepareReset({
    required Uint8List? record,
    required Future<void> Function(Uint8List? expectedDigest) commit,
  }) {
    final digest = record == null
        ? null
        : Uint8List.fromList(const DartSha256().hashSync(record).bytes);
    return _ExportableRootPreparedReset(
      expectedDigest: digest,
      commitOperation: commit,
    );
  }

  /// Requires the current provider record to match a prepared reset target.
  void requirePreparedResetMatch(Uint8List current, Uint8List? expectedDigest) {
    if (expectedDigest == null) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
    final currentDigest = Uint8List.fromList(
      const DartSha256().hashSync(current).bytes,
    );
    if (!sameBytes(currentDigest, expectedDigest)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }

  /// Constant-time equality for the bounded provider values used here.
  bool sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  /// Best-effort clearing for mutable operation-owned buffers.
  void clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}

final class _ExportableRootPreparedReset implements PreparedPlatformReset {
  _ExportableRootPreparedReset({
    required Uint8List? expectedDigest,
    required Future<void> Function(Uint8List? expectedDigest) commitOperation,
  }) : _expectedDigest = expectedDigest == null
           ? null
           : Uint8List.fromList(expectedDigest),
       _commitOperation = commitOperation;

  final Future<void> Function(Uint8List? expectedDigest) _commitOperation;
  Uint8List? _expectedDigest;
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
    final expected = _expectedDigest == null
        ? null
        : Uint8List.fromList(_expectedDigest!);
    await _commitOperation(expected);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expectedDigest = null;
  }
}

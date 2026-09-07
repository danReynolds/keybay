/// Internal file-domain boundary for Keybay V2.
///
/// M2 defines the identity binding and fixed reset target, M4 adds pinned
/// reads, and M5 freezes the lock-scoped staging and replacement contract.
/// Qualified M7 host profiles supply the production implementation.
library;

import 'dart:typed_data';

import 'format/store_format.dart';
import 'host_binding.dart';

export 'host_binding.dart' show ResolvedApplicationBinding, StorageDomain;

/// A bounded observation of Keybay-managed file artifacts.
///
/// It intentionally contains no paths and is available only through a locked
/// [StoreTransaction]. The common state machine may inspect presence, but
/// cannot use file metadata to redirect later operations.
final class StoreArtifacts {
  /// Creates an immutable artifact observation.
  const StoreArtifacts({
    required this.hasLiveFile,
    required this.hasTransactionArtifacts,
  });

  /// Whether the identity-derived live file exists.
  final bool hasLiveFile;

  /// Whether identity-derived staging or recovery artifacts exist.
  ///
  /// This is classification input while the exclusive transaction lock is
  /// held. An already-open reader follows only its pinned live generation and
  /// does not route from transaction artifacts.
  final bool hasTransactionArtifacts;

  /// Whether no Keybay-managed file artifact exists.
  bool get isAbsent => !hasLiveFile && !hasTransactionArtifacts;
}

/// Stable internal failures from the fixed file boundary.
enum StoreFilesFailureCode {
  /// A file operation failed without a narrower classification.
  operationFailed,

  /// The fixed exclusive lock could not be acquired under its bounded policy.
  busy,

  /// An operation targeted a pin whose close had already begun.
  pinnedFileClosed,

  /// Reset failed before changing any managed file artifact.
  ///
  /// In particular, an existing authoritative live file remains available.
  resetNotStarted,

  /// Reset crossed the live-file revocation point but did not finish.
  ///
  /// The authoritative live target is unavailable, while transaction or
  /// recovery artifacts may remain. Retrying reset against the same fixed
  /// identity-derived targets is safe.
  resetIncomplete,
}

/// A redacted failure from identity-derived file storage.
final class StoreFilesFailure implements Exception {
  const StoreFilesFailure(this.code);

  final StoreFilesFailureCode code;

  @override
  String toString() => 'StoreFilesFailure(${code.name})';
}

/// One already-opened immutable view of the live store file.
///
/// The handle itself is the generation pin. It exposes no path or generation
/// identifier, never reopens the live target, and returns fresh exact-length
/// buffers. [close] is idempotent.
abstract interface class PinnedStoreFile {
  /// Infallible file length captured when this generation was opened.
  ///
  /// Implementations obtain this from file metadata; opening a pin must not
  /// materialize the untrusted complete file before the reader enforces its
  /// published bound. This getter returns the stored value without performing
  /// I/O and never throws.
  int get length;

  /// Reads exactly [length] bytes from this same opened generation.
  Future<Uint8List> readExact({required int offset, required int length});

  Future<void> close();
}

/// File state for one already-resolved application storage domain.
///
/// No method accepts a path, filename, identity, or provider value. Production
/// and test implementations both own pinned snapshots and atomic transactions
/// behind this same identity-derived object.
abstract interface class StoreFiles {
  /// The complete identity/profile/domain to which these fixed targets belong.
  ResolvedApplicationBinding get binding;

  /// Opens the then-current live file as one pinned generation.
  ///
  /// Returns `null` when no live file exists. The implementation must never
  /// reopen the live path to satisfy later reads on the returned handle.
  Future<PinnedStoreFile?> openPinnedLive();

  /// Runs one operation while holding this storage domain's exclusive lock.
  ///
  /// The implementation fixes the lock target and bounded acquisition policy.
  /// Failure to acquire it is [StoreFilesFailureCode.busy]. The callback is
  /// invoked exactly once after acquisition; its capability expires when the
  /// returned future settles. Before releasing the lock, the implementation
  /// aborts any uncommitted stage. A callback failure retains precedence over
  /// cleanup failure.
  Future<T> withExclusiveTransaction<T>(
    Future<T> Function(StoreTransaction transaction) operation,
  );
}

/// Lock-scoped file operations for one resolved storage domain.
///
/// This capability is valid only inside its owning
/// [StoreFiles.withExclusiveTransaction] callback. It accepts no path,
/// identity, provider value, lock timeout, or recovery selector. At most one
/// staging file may belong to a transaction.
abstract interface class StoreTransaction {
  /// Rereads this domain's managed-artifact state under the lock.
  Future<StoreArtifacts> observeArtifacts();

  /// Pins the then-current live generation under the lock.
  ///
  /// A returned pin is independently caller-owned, may outlive this
  /// transaction callback, and is not closed by transaction cleanup.
  Future<PinnedStoreFile?> openPinnedLive();

  /// Creates this domain's one fixed staging target with create-only semantics.
  ///
  /// [expectedLength] must be between 1 and [V2StoreLimits.storeBytes]. An
  /// existing transaction artifact is never adopted, overwritten, or resumed.
  Future<StagedStoreFile> createStaging({required int expectedLength});

  /// Durably discards this domain's one fixed abandoned staging file.
  ///
  /// The caller must already have pinned and authenticated the live generation
  /// while holding this transaction. The implementation requires that live
  /// target to remain present, removes only the fixed staging target, and
  /// never adopts, parses, or promotes staged bytes. Success means the live
  /// target remains and no staging target remains. Absence or any partial
  /// cleanup is [StoreFilesFailureCode.operationFailed].
  Future<void> discardAbandonedStaging();

  /// Removes only this domain's identity-derived live and transaction files.
  ///
  /// If a live file exists, making its authoritative target unavailable is the
  /// first managed-file mutation. Only then may the implementation remove
  /// staging or recovery artifacts. A failure before changing any artifact is
  /// [StoreFilesFailureCode.resetNotStarted]; every failure after the live-file
  /// revocation point is [StoreFilesFailureCode.resetIncomplete]. Success means
  /// every managed file artifact is absent. The stable lock target may remain.
  ///
  /// This is the file half of reset. The common engine prepares platform-root
  /// reset without mutation before calling this method, and commits that
  /// prepared provider reset only after this method reaches its live-revocation
  /// point. The two storage domains cannot form one atomic operation.
  Future<void> resetManagedArtifacts();
}

/// One sequential ciphertext staging file owned by a [StoreTransaction].
///
/// The capability expires with its transaction. It has no random name, path,
/// seek, truncate, or caller-selected offset. Leaving the transaction without
/// a successful replacement automatically aborts the stage.
abstract interface class StagedStoreFile {
  /// Appends a snapshot of [bytes] at the current end of the staging file.
  ///
  /// The implementation rejects an append that would exceed either the exact
  /// expected length or the fixed V2 store bound, and retains no alias after
  /// this future settles.
  Future<void> append(Uint8List bytes);

  /// Requires the exact expected length, flushes and closes the writer, then
  /// pins this same staged generation for authenticated verification.
  Future<PinnedStoreFile> finish();

  /// Durably installs the verified stage as the complete live generation.
  ///
  /// This is legal only after [finish] and after its verification pin closes.
  /// It performs the atomic replacement and required directory durability
  /// before success. A failure after rename may leave the old or new complete
  /// live generation, never a torn mixture. Transaction cleanup must never
  /// remove an already-installed live generation, including after a
  /// post-rename durability failure.
  Future<void> replaceLive();
}

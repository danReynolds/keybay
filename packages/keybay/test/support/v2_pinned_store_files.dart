import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/store_files.dart';

/// A read issued against one immutable in-memory generation.
final class MemoryPinnedRead {
  const MemoryPinnedRead({
    required this.generation,
    required this.offset,
    required this.length,
  });

  final int generation;
  final int offset;
  final int length;
}

typedef MemoryPinnedOpenHook = FutureOr<void> Function();
typedef MemoryPinnedReadHook =
    FutureOr<void> Function(MemoryPinnedStoreFile file, MemoryPinnedRead read);

/// Shared disposable targets for separately resolved fake file adapters.
final class MemoryPinnedStoreBacking {
  MemoryPinnedStoreBacking(ResolvedApplicationBinding binding)
    : domain = binding.domain;

  final StorageDomain domain;
  Uint8List? liveBytes;
  int? liveGeneration;
  int generationSequence = 0;
  bool hasTransactionArtifacts = false;
  bool transactionActive = false;
}

/// An in-memory [StoreFiles] fake with immutable generation pins.
///
/// Installing or replacing the live bytes never changes an already-opened
/// handle. Hooks and one-shot gates provide deterministic concurrency points
/// without adding test controls to the production file boundary.
final class MemoryPinnedStoreFiles implements StoreFiles {
  MemoryPinnedStoreFiles(
    this.binding, {
    MemoryPinnedStoreBacking? backing,
    List<int>? liveBytes,
    bool hasTransactionArtifacts = false,
    this.beforeOpen,
    this.beforeRead,
  }) : _backing = backing ?? MemoryPinnedStoreBacking(binding) {
    if (_backing.domain != binding.domain) {
      throw ArgumentError('The fake backing belongs to another domain.');
    }
    if (liveBytes != null) {
      if (_backing.liveBytes != null) {
        throw StateError('The fake backing already has a live generation.');
      }
      _setLiveBytes(liveBytes);
    }
    if (hasTransactionArtifacts) {
      _backing.hasTransactionArtifacts = true;
    }
  }

  @override
  final ResolvedApplicationBinding binding;
  final MemoryPinnedStoreBacking _backing;

  /// Optional hook run before an open captures the current live generation.
  MemoryPinnedOpenHook? beforeOpen;

  /// Optional hook run after a read is validated, copied, and logged.
  MemoryPinnedReadHook? beforeRead;

  Object? closeFailure;
  Exception? transactionCleanupFailure;
  Exception? stagingPinCloseFailure;
  Exception? stageAbortFailure;
  FutureOr<void> Function()? beforeStageFinish;
  FutureOr<void> Function(Uint8List bytes)? beforeStageVerification;
  FutureOr<void> Function()? beforeReplaceLive;
  FutureOr<void> Function()? afterReplaceLive;
  bool failResetBeforeLiveRevocation = false;
  bool failResetAfterLiveRevocation = false;
  int openCallCount = 0;
  int closedHandleCount = 0;

  Future<void>? _nextReadGate;
  final List<MemoryPinnedStoreFile> _openedHandles = <MemoryPinnedStoreFile>[];
  final List<MemoryPinnedRead> _reads = <MemoryPinnedRead>[];

  bool get hasLiveFile => _backing.liveBytes != null;

  int? get liveGeneration => _backing.liveGeneration;

  bool get hasTransactionArtifacts => _backing.hasTransactionArtifacts;

  set hasTransactionArtifacts(bool value) {
    _backing.hasTransactionArtifacts = value;
  }

  List<MemoryPinnedStoreFile> get openedHandles =>
      List<MemoryPinnedStoreFile>.unmodifiable(_openedHandles);

  List<MemoryPinnedRead> get reads =>
      List<MemoryPinnedRead>.unmodifiable(_reads);

  int get activeHandleCount =>
      _openedHandles.where((handle) => !handle.isClosed).length;

  /// Replaces the live generation without changing existing pins.
  void replaceLiveBytes(List<int> bytes) {
    final live = _backing.liveBytes;
    if (live == null) {
      throw StateError('No live generation is installed.');
    }
    final replacement = _copyBytes(bytes);
    _clear(live);
    _backing.liveBytes = replacement;
    _backing.liveGeneration = ++_backing.generationSequence;
  }

  /// Removes the live target without changing existing pins.
  void removeLiveBytes() {
    final live = _backing.liveBytes;
    if (live != null) _clear(live);
    _backing.liveBytes = null;
    _backing.liveGeneration = null;
  }

  /// Pauses the next exact read after its immutable result has been captured.
  void gateNextRead(Future<void> gate) {
    if (_nextReadGate != null) {
      throw StateError('A read gate is already installed.');
    }
    _nextReadGate = gate;
  }

  /// Test-only lock-free snapshot of the disposable backing state.
  Future<StoreArtifacts> observeArtifacts() async => StoreArtifacts(
    hasLiveFile: hasLiveFile,
    hasTransactionArtifacts: hasTransactionArtifacts,
  );

  @override
  Future<PinnedStoreFile?> openPinnedLive() async {
    openCallCount++;
    await beforeOpen?.call();

    final live = _backing.liveBytes;
    final generation = _backing.liveGeneration;
    if (live == null || generation == null) return null;

    final handle = MemoryPinnedStoreFile._(
      owner: this,
      generation: generation,
      bytes: Uint8List.fromList(live),
    );
    _openedHandles.add(handle);
    return handle;
  }

  @override
  Future<T> withExclusiveTransaction<T>(
    Future<T> Function(StoreTransaction transaction) operation,
  ) async {
    if (_backing.transactionActive) {
      throw const StoreFilesFailure(StoreFilesFailureCode.busy);
    }
    _backing.transactionActive = true;
    final transaction = _MemoryStoreTransaction(this);
    late T result;
    Object? primaryFailure;
    StackTrace? primaryStack;
    try {
      result = await operation(transaction);
    } on Object catch (error, stackTrace) {
      primaryFailure = error;
      primaryStack = stackTrace;
    }

    Object? cleanupFailure;
    StackTrace? cleanupStack;
    try {
      await transaction._close();
    } on Object catch (error, stackTrace) {
      cleanupFailure = error;
      cleanupStack = stackTrace;
    } finally {
      _backing.transactionActive = false;
    }

    final failure = primaryFailure ?? cleanupFailure;
    if (failure != null) {
      Error.throwWithStackTrace(
        failure,
        primaryStack ?? cleanupStack ?? StackTrace.current,
      );
    }
    return result;
  }

  void _setLiveBytes(List<int> bytes) {
    _backing.liveBytes = _copyBytes(bytes);
    _backing.liveGeneration = ++_backing.generationSequence;
  }

  Future<void>? _takeNextReadGate() {
    final gate = _nextReadGate;
    _nextReadGate = null;
    return gate;
  }

  void _recordRead(MemoryPinnedRead read) => _reads.add(read);

  void _recordClose() => closedHandleCount++;
}

final class _MemoryStoreTransaction implements StoreTransaction {
  _MemoryStoreTransaction(this._owner);

  final MemoryPinnedStoreFiles _owner;
  _MemoryStagedStoreFile? _stage;
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
    RangeError.checkValueInInterval(
      expectedLength,
      1,
      V2StoreLimits.storeBytes,
      'expectedLength',
    );
    if (_stage != null || _owner.hasTransactionArtifacts) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final stage = _MemoryStagedStoreFile(
      transaction: this,
      expectedLength: expectedLength,
    );
    _stage = stage;
    _owner.hasTransactionArtifacts = true;
    return stage;
  }

  @override
  Future<void> discardAbandonedStaging() async {
    _ensureActive();
    if (_stage != null ||
        !_owner.hasLiveFile ||
        !_owner.hasTransactionArtifacts) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    _owner.hasTransactionArtifacts = false;
  }

  @override
  Future<void> resetManagedArtifacts() async {
    _ensureActive();
    if (_owner.failResetBeforeLiveRevocation) {
      throw const StoreFilesFailure(StoreFilesFailureCode.resetNotStarted);
    }

    _owner.removeLiveBytes();
    try {
      if (_owner.failResetAfterLiveRevocation) {
        throw const StoreFilesFailure(StoreFilesFailureCode.resetIncomplete);
      }
      await _stage?._abort();
      _owner.hasTransactionArtifacts = false;
    } on Object {
      throw const StoreFilesFailure(StoreFilesFailureCode.resetIncomplete);
    }
  }

  Future<void> _close() async {
    if (!_active) return;
    Object? abortFailure;
    StackTrace? abortStack;
    try {
      await _stage?._abort();
    } on Object catch (error, stackTrace) {
      abortFailure = error;
      abortStack = stackTrace;
    }
    _active = false;
    final cleanupFailure = _owner.transactionCleanupFailure;
    if (abortFailure != null) {
      Error.throwWithStackTrace(abortFailure, abortStack!);
    }
    if (cleanupFailure != null) throw cleanupFailure;
  }

  void _ensureActive() {
    if (!_active) {
      throw StateError('The store transaction has ended.');
    }
  }
}

enum _MemoryStageState { writing, finished, replaced, aborted }

final class _MemoryStagedStoreFile implements StagedStoreFile {
  _MemoryStagedStoreFile({
    required _MemoryStoreTransaction transaction,
    required this.expectedLength,
  }) : _transaction = transaction;

  final _MemoryStoreTransaction _transaction;
  final int expectedLength;
  final List<Uint8List> _chunks = <Uint8List>[];
  int _writtenLength = 0;
  Uint8List? _finishedBytes;
  _MemoryStagingPin? _verificationPin;
  _MemoryStageState _state = _MemoryStageState.writing;

  @override
  Future<void> append(Uint8List bytes) async {
    _transaction._ensureActive();
    if (_state != _MemoryStageState.writing) {
      throw StateError('The staging writer is closed.');
    }
    if (bytes.length > expectedLength - _writtenLength) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final copy = Uint8List.fromList(bytes);
    _chunks.add(copy);
    _writtenLength += copy.length;
  }

  @override
  Future<PinnedStoreFile> finish() async {
    _transaction._ensureActive();
    if (_state != _MemoryStageState.writing) {
      throw StateError('The staging writer is closed.');
    }
    if (_writtenLength != expectedLength) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    await _transaction._owner.beforeStageFinish?.call();

    Uint8List? assembled;
    try {
      assembled = Uint8List(expectedLength);
      var offset = 0;
      for (final chunk in _chunks) {
        assembled.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      _finishedBytes = assembled;
      assembled = null;
    } finally {
      if (assembled != null) _clear(assembled);
      for (final chunk in _chunks) {
        _clear(chunk);
      }
      _chunks.clear();
    }

    await _transaction._owner.beforeStageVerification?.call(_finishedBytes!);
    _state = _MemoryStageState.finished;
    final pin = _MemoryStagingPin(_transaction._owner, _finishedBytes!);
    _verificationPin = pin;
    return pin;
  }

  @override
  Future<void> replaceLive() async {
    _transaction._ensureActive();
    if (_state != _MemoryStageState.finished ||
        _verificationPin?.isClosed != true) {
      throw StateError('The staging generation is not verified and closed.');
    }
    await _transaction._owner.beforeReplaceLive?.call();

    final bytes = _finishedBytes!;
    if (_transaction._owner.hasLiveFile) {
      _transaction._owner.replaceLiveBytes(bytes);
    } else {
      _transaction._owner._setLiveBytes(bytes);
    }
    _clear(bytes);
    _finishedBytes = null;
    _state = _MemoryStageState.replaced;
    _transaction._owner.hasTransactionArtifacts = false;
    await _transaction._owner.afterReplaceLive?.call();
  }

  Future<void> _abort() async {
    _transaction._ensureActive();
    if (_state == _MemoryStageState.replaced ||
        _state == _MemoryStageState.aborted) {
      return;
    }

    Object? pinFailure;
    StackTrace? pinStack;
    try {
      await _verificationPin?.close();
    } on Object catch (error, stackTrace) {
      pinFailure = error;
      pinStack = stackTrace;
    }
    for (final chunk in _chunks) {
      _clear(chunk);
    }
    _chunks.clear();
    final finished = _finishedBytes;
    if (finished != null) _clear(finished);
    _finishedBytes = null;
    _state = _MemoryStageState.aborted;
    _transaction._owner.hasTransactionArtifacts = false;
    final abortFailure = _transaction._owner.stageAbortFailure;
    if (pinFailure != null) {
      Error.throwWithStackTrace(pinFailure, pinStack!);
    }
    if (abortFailure != null) throw abortFailure;
  }
}

final class _MemoryStagingPin implements PinnedStoreFile {
  _MemoryStagingPin(this._owner, Uint8List bytes)
    : _length = bytes.length,
      _bytes = Uint8List.fromList(bytes);

  final MemoryPinnedStoreFiles _owner;
  final int _length;
  Uint8List _bytes;
  bool isClosed = false;

  @override
  int get length => _length;

  @override
  Future<Uint8List> readExact({
    required int offset,
    required int length,
  }) async {
    if (isClosed) {
      throw const StoreFilesFailure(StoreFilesFailureCode.pinnedFileClosed);
    }
    if (offset < 0 ||
        length < 0 ||
        offset > _bytes.length ||
        length > _bytes.length - offset) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    return Uint8List.fromList(
      Uint8List.sublistView(_bytes, offset, offset + length),
    );
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    _clear(_bytes);
    _bytes = Uint8List(0);
    final failure = _owner.stagingPinCloseFailure;
    if (failure != null) throw failure;
  }
}

/// One immutable generation opened by [MemoryPinnedStoreFiles].
final class MemoryPinnedStoreFile implements PinnedStoreFile {
  MemoryPinnedStoreFile._({
    required MemoryPinnedStoreFiles owner,
    required this.generation,
    required Uint8List bytes,
  }) : _owner = owner,
       _length = bytes.length,
       _bytes = bytes;

  final MemoryPinnedStoreFiles _owner;
  final int _length;

  /// Test-only generation label; the production boundary exposes no such ID.
  final int generation;

  Uint8List _bytes;
  final List<MemoryPinnedRead> _reads = <MemoryPinnedRead>[];
  Future<void>? _closeFuture;

  bool get isClosed => _closeFuture != null;

  List<MemoryPinnedRead> get reads =>
      List<MemoryPinnedRead>.unmodifiable(_reads);

  @override
  int get length => _length;

  @override
  Future<Uint8List> readExact({
    required int offset,
    required int length,
  }) async {
    if (isClosed) {
      throw const StoreFilesFailure(StoreFilesFailureCode.pinnedFileClosed);
    }
    if (offset < 0 ||
        length < 0 ||
        offset > _bytes.length ||
        length > _bytes.length - offset) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    final result = Uint8List.fromList(
      Uint8List.sublistView(_bytes, offset, offset + length),
    );
    final read = MemoryPinnedRead(
      generation: generation,
      offset: offset,
      length: length,
    );
    _reads.add(read);
    _owner._recordRead(read);
    final gate = _owner._takeNextReadGate();

    try {
      await _owner.beforeRead?.call(this, read);
      if (gate != null) await gate;
      return result;
    } on Object {
      _clear(result);
      rethrow;
    }
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;

    _clear(_bytes);
    _bytes = Uint8List(0);
    _owner._recordClose();
    final failure = _owner.closeFailure;
    final closed = failure == null
        ? Future<void>.value()
        : Future<void>.error(failure);
    _closeFuture = closed;
    return closed;
  }
}

Uint8List _copyBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 0xff) {
      throw ArgumentError.value(
        '<redacted>',
        'bytes',
        'store data must contain bytes',
      );
    }
  }
  return Uint8List.fromList(bytes);
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

/// Production POSIX file storage for the Keybay V2 framed store.
///
/// The canonical root is opened one component at a time from `/` with
/// `openat(O_DIRECTORY|O_NOFOLLOW)`. All mutable names are then fixed below and
/// every operation is relative to that pinned directory descriptor. Live
/// readers retain their opened descriptor, so replacing the live name cannot
/// redirect an existing pin to another generation.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'format/store_format.dart';
import 'store_files.dart';

const String _liveName = 'keybay.v2.store';
const String _stagingName = 'keybay.v2.stage';
const String _lockName = 'keybay.v2.lock';

const Duration _lockTimeout = Duration(seconds: 1);
const Duration _maximumLockBackoff = Duration(milliseconds: 64);
const int _nativeBufferBytes = 64 * 1024;
const String _linuxProviderLockDirectory = 'keybay-v2';
const String _linuxProviderLockSuffix = '.platform-root.lock';
final RegExp _linuxProviderAddressGrammar = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// A fixed, identity-bound POSIX implementation of [StoreFiles].
///
/// The constructor verifies [canonicalFileRoot] against the resolved binding's
/// physical root. This prevents accidentally combining a binding with a
/// different directory, including when its domain allows OS container moves.
final class PosixStoreFiles implements StoreFiles {
  /// Runs one ordinary-Linux provider initialization under its fixed lock.
  ///
  /// The canonical private runtime directory, `keybay-v2` child, and lock file
  /// are opened descriptor-relative with ABI-correct `O_NOFOLLOW` and
  /// `O_CLOEXEC`. The method accepts only the fixed provider-address grammar;
  /// callers cannot select another directory or lock-file shape.
  static Future<T> withLinuxSecretServiceCreationLock<T>({
    required Uri canonicalRuntimeDirectory,
    required String providerAddress,
    required Duration timeout,
    required Future<T> Function() operation,
  }) async {
    if (!_isPathWalkingPosixHost ||
        !_linuxProviderAddressGrammar.hasMatch(providerAddress) ||
        timeout <= Duration.zero) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    var runtime = -1;
    var directory = -1;
    var lock = -1;
    var acquired = false;
    Object? primaryFailure;
    StackTrace? primaryStack;
    Object? releaseFailure;
    StackTrace? releaseStack;
    T? result;

    try {
      runtime = _openCanonicalPrivateDirectory(canonicalRuntimeDirectory);
      directory = _openOrCreatePrivateDirectoryAt(
        runtime,
        _linuxProviderLockDirectory,
      );
      lock = _openNamedLock(
        directory,
        '$providerAddress$_linuxProviderLockSuffix',
      );
      await _acquireExclusive(lock, timeout: timeout);
      acquired = true;
      try {
        result = await operation();
      } on Object catch (error, stackTrace) {
        primaryFailure = error;
        primaryStack = stackTrace;
      }
    } on Object catch (error, stackTrace) {
      primaryFailure ??= _asStoreFailure(error);
      primaryStack ??= stackTrace;
    } finally {
      if (acquired) {
        try {
          _releaseExclusive(lock);
        } on Object catch (error, stackTrace) {
          releaseFailure = _asStoreFailure(error);
          releaseStack = stackTrace;
        }
      }
      for (final descriptor in <int>[lock, directory, runtime]) {
        if (descriptor < 0) continue;
        try {
          _closeDescriptor(descriptor);
        } on Object catch (error, stackTrace) {
          releaseFailure ??= _asStoreFailure(error);
          releaseStack ??= stackTrace;
        }
      }
    }

    final failure = primaryFailure ?? releaseFailure;
    if (failure != null) {
      Error.throwWithStackTrace(
        failure,
        primaryStack ?? releaseStack ?? StackTrace.current,
      );
    }
    return result as T;
  }

  /// Creates a known missing directory suffix beneath one canonical parent.
  ///
  /// Every component is opened relative to a pinned descriptor with
  /// `O_DIRECTORY|O_NOFOLLOW`. Caller-declared children are required to be
  /// 0700, free of extended ACLs where the host exposes them, and durably
  /// anchored before the walk continues. A child is repaired only when this
  /// call actually created it. Existing ancestors are only required to be
  /// directories; XDG data homes commonly sit below non-private home-directory
  /// components.
  static void durablyCreatePrivateDirectories({
    required Uri canonicalExistingParent,
    required List<String> childComponents,
  }) => _durablyCreatePrivateDirectories(
    canonicalExistingParent: canonicalExistingParent,
    childComponents: childComponents,
  );

  /// Exercises directory preparation with an operation-scoped failure probe.
  ///
  /// The observer runs after opening a newly created child, immediately before
  /// mode and ACL preparation. This internal test seam is not package API.
  static void debugDurablyCreatePrivateDirectories({
    required Uri canonicalExistingParent,
    required List<String> childComponents,
    required void Function(int descriptor) beforePrepareNewDirectory,
  }) => _durablyCreatePrivateDirectories(
    canonicalExistingParent: canonicalExistingParent,
    childComponents: childComponents,
    beforePrepareNewDirectory: beforePrepareNewDirectory,
  );

  /// Validates and persists one private directory and its parent entry.
  ///
  /// Mobile host profiles create their OS-selected storage root before a
  /// [PosixStoreFiles] instance exists. This internal assembly hook pins the
  /// exact parent, opens the final component relative to it, and applies the
  /// same no-follow and metadata checks used by the store adapter.
  static void durablyAnchorPrivateRoot({required Uri canonicalFileRoot}) {
    if (!_isDirectRootPosixHost) {
      throw UnsupportedError('POSIX store files are unavailable on this host');
    }
    final path = _withoutTrailingPosixSeparator(canonicalFileRoot.toFilePath());
    final components = _absolutePathComponents(path);
    final name = components.last;
    final parentPath = components.length == 1
        ? '/'
        : '/${components.take(components.length - 1).join('/')}';

    var parent = -1;
    var child = -1;
    Object? failure;
    StackTrace? failureStack;
    try {
      final openedParent = _openPath(
        parentPath,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
        0,
      );
      parent = openedParent.value;
      if (parent < 0) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      _validateDescriptor(parent, expectedType: FileSystemEntityType.directory);

      final openedChild = _openAt(
        parent,
        name,
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
        0,
      );
      child = openedChild.value;
      if (child < 0) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      _validateDescriptor(
        child,
        expectedType: FileSystemEntityType.directory,
        expectedPermissions: 0x1c0,
      );
      _syncDescriptor(child);
      _syncDescriptor(parent);
    } on Object catch (error, stackTrace) {
      failure = _asStoreFailure(error);
      failureStack = stackTrace;
    }

    for (final descriptor in <int>[child, parent]) {
      if (descriptor < 0) continue;
      try {
        _closeDescriptor(descriptor);
      } on Object catch (error, stackTrace) {
        failure ??= _asStoreFailure(error);
        failureStack ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }

  factory PosixStoreFiles({
    required ResolvedApplicationBinding binding,
    required Uri canonicalFileRoot,
  }) {
    if (!_isPathWalkingPosixHost) {
      throw UnsupportedError('POSIX store files are unavailable on this host');
    }
    if (canonicalFileRoot != binding.canonicalFileRoot) {
      throw ArgumentError(
        'The canonical file root does not match the resolved binding.',
        'canonicalFileRoot',
      );
    }
    return PosixStoreFiles._(
      binding: binding,
      rootComponents: _absolutePathComponents(canonicalFileRoot.toFilePath()),
      existingRootPath: null,
    );
  }

  /// Uses one already-existing private directory as the descriptor anchor.
  ///
  /// Sandboxed mobile profiles resolve and verify their OS-owned application
  /// directory before constructing this adapter. Opening that exact directory
  /// directly avoids traversing protected global ancestors such as Android's
  /// `/data/user`, while all mutable Keybay names remain descriptor-relative.
  factory PosixStoreFiles.fromExistingPrivateRoot({
    required ResolvedApplicationBinding binding,
    required Uri canonicalFileRoot,
  }) {
    if (!_isDirectRootPosixHost) {
      throw UnsupportedError('POSIX store files are unavailable on this host');
    }
    if (canonicalFileRoot != binding.canonicalFileRoot) {
      throw ArgumentError(
        'The canonical file root does not match the resolved binding.',
        'canonicalFileRoot',
      );
    }
    final path = _withoutTrailingPosixSeparator(canonicalFileRoot.toFilePath());
    _absolutePathComponents(path);
    return PosixStoreFiles._(
      binding: binding,
      rootComponents: null,
      existingRootPath: path,
    );
  }

  PosixStoreFiles._({
    required this.binding,
    required List<String>? rootComponents,
    required String? existingRootPath,
  }) : _rootComponents = rootComponents == null
           ? null
           : List<String>.unmodifiable(rootComponents),
       _existingRootPath = existingRootPath;

  @override
  final ResolvedApplicationBinding binding;

  final List<String>? _rootComponents;
  final String? _existingRootPath;

  @override
  Future<PinnedStoreFile?> openPinnedLive() => Future.sync(() {
    final root = _openRoot(create: false);
    if (root == null) return null;

    _PosixPinnedStoreFile? pin;
    Object? failure;
    StackTrace? failureStack;
    try {
      pin = _openPinnedLiveAt(root);
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }

    try {
      _closeDescriptor(root);
    } on Object catch (error, stackTrace) {
      failure ??= error;
      failureStack ??= stackTrace;
    }

    if (failure != null) {
      try {
        pin?._closeSync();
      } on Object {
        // Preserve the operation or directory-close failure.
      }
      Error.throwWithStackTrace(
        _asStoreFailure(failure),
        failureStack ?? StackTrace.current,
      );
    }
    return pin;
  });

  @override
  Future<T> withExclusiveTransaction<T>(
    Future<T> Function(StoreTransaction transaction) operation,
  ) async {
    int? root;
    int? lock;
    _PosixStoreTransaction? transaction;
    Object? primaryFailure;
    StackTrace? primaryStack;
    Object? cleanupFailure;
    StackTrace? cleanupStack;
    Object? releaseFailure;
    StackTrace? releaseStack;
    T? result;

    try {
      root = _openRoot(create: true);
      lock = _openLock(root!);
      await _acquireExclusive(lock);
      transaction = _PosixStoreTransaction(root);

      try {
        result = await operation(transaction);
      } on Object catch (error, stackTrace) {
        primaryFailure = error;
        primaryStack = stackTrace;
      }

      try {
        await transaction._close();
      } on Object catch (error, stackTrace) {
        cleanupFailure = error;
        cleanupStack = stackTrace;
      }
    } on Object catch (error, stackTrace) {
      primaryFailure ??= _asStoreFailure(error);
      primaryStack ??= stackTrace;
    } finally {
      transaction?._expire();
      if (lock != null) {
        try {
          _releaseExclusive(lock);
        } on Object catch (error, stackTrace) {
          releaseFailure = _asStoreFailure(error);
          releaseStack = stackTrace;
        }
        try {
          _closeDescriptor(lock);
        } on Object catch (error, stackTrace) {
          releaseFailure ??= _asStoreFailure(error);
          releaseStack ??= stackTrace;
        }
      }
      if (root != null) {
        try {
          _closeDescriptor(root);
        } on Object catch (error, stackTrace) {
          releaseFailure ??= _asStoreFailure(error);
          releaseStack ??= stackTrace;
        }
      }
    }

    final failure = primaryFailure ?? cleanupFailure ?? releaseFailure;
    if (failure != null) {
      Error.throwWithStackTrace(
        failure,
        primaryStack ?? cleanupStack ?? releaseStack ?? StackTrace.current,
      );
    }
    return result as T;
  }

  int? _openRoot({required bool create}) {
    final directPath = _existingRootPath;
    if (directPath != null) {
      return _openExistingRoot(directPath, absentIsNull: !create);
    }

    final components = _rootComponents!;
    if (!create) {
      return _openExistingDirectoryComponents(
        components,
        requirePrivateLeaf: true,
        absentIsNull: true,
      );
    }

    // Desktop initialization may create only the final private leaf. Its
    // ancestors must already exist; unlike Linux profile preparation, this
    // operation never creates a missing directory suffix.
    var parent = _openExistingDirectoryComponents(
      components.sublist(0, components.length - 1),
    )!;
    var child = -1;
    try {
      child = _openOrCreatePrivateDirectoryAt(
        parent,
        components.last,
        syncExisting: true,
      );
      final openedParent = parent;
      parent = -1;
      _closeDescriptor(openedParent);
      return child;
    } on Object catch (error, stackTrace) {
      _closeDescriptorIgnoringFailure(child);
      Error.throwWithStackTrace(_asStoreFailure(error), stackTrace);
    } finally {
      _closeDescriptorIgnoringFailure(parent);
    }
  }

  int? _openExistingRoot(String path, {required bool absentIsNull}) {
    final opened = _openPath(
      path,
      _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      0,
    );
    final descriptor = opened.value;
    if (descriptor < 0) {
      if (absentIsNull && opened.error == _eNoEntry) return null;
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    try {
      _validateDescriptor(
        descriptor,
        expectedType: FileSystemEntityType.directory,
        expectedPermissions: 0x1c0,
      );
      return descriptor;
    } on Object {
      _closeDescriptorIgnoringFailure(descriptor);
      rethrow;
    }
  }
}

final class _PosixStoreTransaction implements StoreTransaction {
  _PosixStoreTransaction(this._rootDescriptor);

  final int _rootDescriptor;
  _PosixStagedStoreFile? _stage;
  bool _active = true;

  @override
  Future<StoreArtifacts> observeArtifacts() => Future.sync(() {
    _ensureActive();
    return StoreArtifacts(
      hasLiveFile: _entryExists(_rootDescriptor, _liveName),
      hasTransactionArtifacts: _entryExists(_rootDescriptor, _stagingName),
    );
  });

  @override
  Future<PinnedStoreFile?> openPinnedLive() => Future.sync(() {
    _ensureActive();
    return _openPinnedLiveAt(_rootDescriptor);
  });

  @override
  Future<StagedStoreFile> createStaging({required int expectedLength}) =>
      Future.sync(() {
        _ensureActive();
        RangeError.checkValueInInterval(
          expectedLength,
          1,
          V2StoreLimits.storeBytes,
          'expectedLength',
        );
        if (_stage != null) {
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }

        final opened = _openAt(
          _rootDescriptor,
          _stagingName,
          _oReadWrite | _oCreate | _oExclusive | _oNoFollow | _oCloseOnExec,
          0x180,
        );
        final descriptor = opened.value;
        if (descriptor < 0) {
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }

        try {
          _setDescriptorMode(descriptor, 0x180);
          _clearDescriptorExtendedAcl(descriptor);
          _validateDescriptor(
            descriptor,
            expectedType: FileSystemEntityType.file,
            expectedPermissions: 0x180,
          );
          final stage = _PosixStagedStoreFile(
            transaction: this,
            descriptor: descriptor,
            expectedLength: expectedLength,
          );
          _stage = stage;
          return stage;
        } on Object catch (error, stackTrace) {
          _closeDescriptorIgnoringFailure(descriptor);
          try {
            _unlinkAtIfPresent(_rootDescriptor, _stagingName);
            _syncDescriptor(_rootDescriptor);
          } on Object {
            // The creation failure remains primary.
          }
          Error.throwWithStackTrace(_asStoreFailure(error), stackTrace);
        }
      });

  @override
  Future<void> discardAbandonedStaging() => Future.sync(() {
    _ensureActive();
    if (_stage != null) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    final before = StoreArtifacts(
      hasLiveFile: _entryExists(_rootDescriptor, _liveName),
      hasTransactionArtifacts: _entryExists(_rootDescriptor, _stagingName),
    );
    if (!before.hasLiveFile || !before.hasTransactionArtifacts) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    if (!_unlinkAtIfPresent(_rootDescriptor, _stagingName)) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    _syncDescriptor(_rootDescriptor);

    final after = StoreArtifacts(
      hasLiveFile: _entryExists(_rootDescriptor, _liveName),
      hasTransactionArtifacts: _entryExists(_rootDescriptor, _stagingName),
    );
    if (!after.hasLiveFile || after.hasTransactionArtifacts) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
  });

  @override
  Future<void> resetManagedArtifacts() => Future.sync(() {
    _ensureActive();
    var changedArtifact = false;
    Object? failure;

    try {
      if (_unlinkAtIfPresent(_rootDescriptor, _liveName)) {
        changedArtifact = true;
      }
    } on Object {
      throw const StoreFilesFailure(StoreFilesFailureCode.resetNotStarted);
    }

    try {
      if (_unlinkAtIfPresent(_rootDescriptor, _stagingName)) {
        changedArtifact = true;
      }
    } on Object catch (error) {
      failure ??= error;
    }

    if (changedArtifact) {
      try {
        _syncDescriptor(_rootDescriptor);
      } on Object catch (error) {
        failure ??= error;
      }
    }

    try {
      if (_entryExists(_rootDescriptor, _liveName) ||
          _entryExists(_rootDescriptor, _stagingName)) {
        failure ??= const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );
      }
    } on Object catch (error) {
      failure ??= error;
    }

    if (failure != null) {
      throw StoreFilesFailure(
        changedArtifact
            ? StoreFilesFailureCode.resetIncomplete
            : StoreFilesFailureCode.resetNotStarted,
      );
    }
    _stage?._markReset();
  });

  Future<void> _close() async {
    if (!_active) return;
    try {
      await _stage?._abort();
    } finally {
      _active = false;
    }
  }

  void _expire() => _active = false;

  void _ensureActive() {
    if (!_active) throw StateError('The store transaction has ended.');
  }
}

enum _StageState { writing, failed, finished, replaced, aborted }

final class _PosixStagedStoreFile implements StagedStoreFile {
  _PosixStagedStoreFile({
    required _PosixStoreTransaction transaction,
    required int descriptor,
    required this.expectedLength,
  }) : _transaction = transaction,
       _descriptor = descriptor;

  final _PosixStoreTransaction _transaction;
  final int expectedLength;
  int _descriptor;
  int _writtenLength = 0;
  _StageState _state = _StageState.writing;
  _PosixPinnedStoreFile? _verificationPin;

  @override
  Future<void> append(Uint8List bytes) {
    final snapshot = Uint8List.fromList(bytes);
    return Future.sync(() {
      _transaction._ensureActive();
      if (_state != _StageState.writing) {
        throw StateError('The staging writer is closed.');
      }
      if (snapshot.length > expectedLength - _writtenLength) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      try {
        _writeAll(_descriptor, snapshot);
      } on Object {
        _state = _StageState.failed;
        rethrow;
      }
      _writtenLength += snapshot.length;
    });
  }

  @override
  Future<PinnedStoreFile> finish() => Future.sync(() {
    _transaction._ensureActive();
    if (_state != _StageState.writing) {
      throw StateError('The staging writer is closed.');
    }
    if (_writtenLength != expectedLength) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    late final _DescriptorMetadata stat;
    try {
      _syncDescriptor(_descriptor);
      stat = _validateDescriptor(
        _descriptor,
        expectedType: FileSystemEntityType.file,
        expectedPermissions: 0x180,
      );
      if (stat.size != expectedLength) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
    } on Object {
      _state = _StageState.failed;
      rethrow;
    }
    _state = _StageState.finished;
    final pin = _PosixPinnedStoreFile(
      descriptor: _descriptor,
      length: stat.size,
      ownsDescriptor: false,
    );
    _verificationPin = pin;
    return pin;
  });

  @override
  Future<void> replaceLive() => Future.sync(() {
    _transaction._ensureActive();
    if (_state != _StageState.finished || _verificationPin?.isClosed != true) {
      throw StateError('The staging generation is not verified and closed.');
    }

    // The stage name is create-only and remains owned by this lock-scoped
    // transaction. The engine also authenticates the installed live file
    // before acknowledging the mutation, so out-of-band same-user
    // tampering cannot turn this rename into an accepted generation.
    _renameAt(
      _transaction._rootDescriptor,
      _stagingName,
      _transaction._rootDescriptor,
      _liveName,
    );
    _state = _StageState.replaced;

    Object? failure;
    try {
      _closeStageDescriptor();
    } on Object catch (error) {
      failure = error;
    }
    try {
      _syncDescriptor(_transaction._rootDescriptor);
    } on Object catch (error) {
      failure ??= error;
    }
    if (failure != null) throw _asStoreFailure(failure);
  });

  Future<void> _abort() => Future.sync(() {
    if (_state == _StageState.replaced || _state == _StageState.aborted) {
      return;
    }
    Object? failure;
    try {
      _verificationPin?._closeLogically();
      _closeStageDescriptor();
    } on Object catch (error) {
      failure = error;
    }
    var removed = false;
    try {
      removed = _unlinkAtIfPresent(_transaction._rootDescriptor, _stagingName);
    } on Object catch (error) {
      failure ??= error;
    }
    if (removed) {
      try {
        _syncDescriptor(_transaction._rootDescriptor);
      } on Object catch (error) {
        failure ??= error;
      }
    }
    _state = _StageState.aborted;
    if (failure != null) throw _asStoreFailure(failure);
  });

  void _markReset() {
    if (_state == _StageState.replaced || _state == _StageState.aborted) {
      return;
    }
    _verificationPin?._closeLogically();
    _closeDescriptorIgnoringFailure(_descriptor);
    _descriptor = -1;
    _state = _StageState.aborted;
  }

  void _closeStageDescriptor() {
    final descriptor = _descriptor;
    if (descriptor < 0) return;
    _descriptor = -1;
    _closeDescriptor(descriptor);
  }
}

final class _PosixPinnedStoreFile implements PinnedStoreFile {
  _PosixPinnedStoreFile({
    required int descriptor,
    required int length,
    required bool ownsDescriptor,
  }) : _descriptor = descriptor,
       _length = length,
       _ownsDescriptor = ownsDescriptor;

  int _descriptor;
  final int _length;
  final bool _ownsDescriptor;
  bool _closed = false;

  bool get isClosed => _closed;

  @override
  int get length => _length;

  @override
  Future<Uint8List> readExact({required int offset, required int length}) =>
      Future.sync(() {
        if (_closed) {
          throw const StoreFilesFailure(StoreFilesFailureCode.pinnedFileClosed);
        }
        if (offset < 0 ||
            length < 0 ||
            offset > _length ||
            length > _length - offset) {
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }
        return _readExact(_descriptor, offset: offset, length: length);
      });

  @override
  Future<void> close() => Future.sync(_closeSync);

  void _closeSync() {
    if (_closed) return;
    _closed = true;
    if (!_ownsDescriptor) return;
    final descriptor = _descriptor;
    _descriptor = -1;
    _closeDescriptor(descriptor);
  }

  void _closeLogically() {
    _closed = true;
  }
}

_PosixPinnedStoreFile? _openPinnedLiveAt(int rootDescriptor) {
  final opened = _openAt(
    rootDescriptor,
    _liveName,
    _oReadOnly | _oNoFollow | _oNonBlock | _oCloseOnExec,
    0,
  );
  final descriptor = opened.value;
  if (descriptor < 0) {
    if (opened.error == _eNoEntry) return null;
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  try {
    final stat = _validateDescriptor(
      descriptor,
      expectedType: FileSystemEntityType.file,
      expectedPermissions: 0x180,
    );
    return _PosixPinnedStoreFile(
      descriptor: descriptor,
      length: stat.size,
      ownsDescriptor: true,
    );
  } on Object {
    _closeDescriptorIgnoringFailure(descriptor);
    rethrow;
  }
}

void _durablyCreatePrivateDirectories({
  required Uri canonicalExistingParent,
  required List<String> childComponents,
  void Function(int descriptor)? beforePrepareNewDirectory,
}) {
  if (!_isPathWalkingPosixHost || childComponents.isEmpty) {
    throw UnsupportedError('POSIX directory preparation is unavailable');
  }
  final parentPath = _withoutTrailingPosixSeparator(
    canonicalExistingParent.toFilePath(),
  );
  final parentComponents = parentPath == '/'
      ? const <String>[]
      : _absolutePathComponents(parentPath);
  if (childComponents.any(
    (part) =>
        part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.contains('/') ||
        part.contains('\u0000'),
  )) {
    throw ArgumentError.value(
      '<redacted>',
      'childComponents',
      'contains an invalid POSIX path component',
    );
  }

  var current = _openExistingDirectoryComponents(parentComponents)!;
  try {
    // Only this explicitly supplied suffix may be created or required private.
    // Existing ancestors are directories, but need not have mode 0700.
    for (final component in childComponents) {
      final next = _openOrCreatePrivateDirectoryAt(
        current,
        component,
        syncExisting: true,
        beforePrepareNewDirectory: beforePrepareNewDirectory,
      );
      final previous = current;
      current = next;
      _closeDescriptor(previous);
    }
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(_asStoreFailure(error), stackTrace);
  } finally {
    _closeDescriptorIgnoringFailure(current);
  }
}

int _openCanonicalPrivateDirectory(Uri canonicalDirectory) =>
    _openExistingDirectoryComponents(
      _absolutePathComponents(
        _withoutTrailingPosixSeparator(canonicalDirectory.toFilePath()),
      ),
      requirePrivateLeaf: true,
    )!;

/// Opens existing components from `/`, transferring one directory descriptor
/// at each step. Creation policy stays with the caller; this walk never writes.
int? _openExistingDirectoryComponents(
  List<String> components, {
  bool requirePrivateLeaf = false,
  bool absentIsNull = false,
}) {
  var current = -1;
  try {
    final openedRoot = _openPath(
      '/',
      _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      0,
    );
    current = openedRoot.value;
    if (current < 0) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    for (var index = 0; index < components.length; index += 1) {
      final opened = _openAt(
        current,
        components[index],
        _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
        0,
      );
      final next = opened.value;
      if (next < 0) {
        if (absentIsNull && opened.error == _eNoEntry) {
          final descriptor = current;
          current = -1;
          _closeDescriptor(descriptor);
          return null;
        }
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      try {
        _validateDescriptor(
          next,
          expectedType: FileSystemEntityType.directory,
          expectedPermissions:
              requirePrivateLeaf && index == components.length - 1
              ? 0x1c0
              : null,
        );
      } on Object {
        _closeDescriptorIgnoringFailure(next);
        rethrow;
      }
      final previous = current;
      current = next;
      _closeDescriptor(previous);
    }

    final result = current;
    current = -1;
    return result;
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(_asStoreFailure(error), stackTrace);
  } finally {
    _closeDescriptorIgnoringFailure(current);
  }
}

int _openOrCreatePrivateDirectoryAt(
  int parentDescriptor,
  String name, {
  bool syncExisting = false,
  void Function(int descriptor)? beforePrepareNewDirectory,
}) {
  var observedMissing = false;
  var created = false;
  var opened = _openAt(
    parentDescriptor,
    name,
    _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
    0,
  );
  if (opened.value < 0 && opened.error == _eNoEntry) {
    observedMissing = true;
    created = _mkdirAtComponent(parentDescriptor, name);
    opened = _openAt(
      parentDescriptor,
      name,
      _oReadOnly | _oDirectory | _oNoFollow | _oCloseOnExec,
      0,
    );
  }
  final descriptor = opened.value;
  if (descriptor < 0) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  try {
    if (created) {
      beforePrepareNewDirectory?.call(descriptor);
      _setDescriptorMode(descriptor, 0x1c0);
      _clearDescriptorExtendedAcl(descriptor);
    }
    _validateDescriptor(
      descriptor,
      expectedType: FileSystemEntityType.directory,
      expectedPermissions: 0x1c0,
    );
    if (observedMissing || syncExisting) {
      // Sync even a concurrently created entry before a store can rely on it.
      _syncDescriptor(descriptor);
      _syncDescriptor(parentDescriptor);
    }
    return descriptor;
  } on Object {
    _closeDescriptorIgnoringFailure(descriptor);
    rethrow;
  }
}

int _openLock(int rootDescriptor) => _openNamedLock(rootDescriptor, _lockName);

int _openNamedLock(int rootDescriptor, String name) {
  var created = true;
  var opened = _openAt(
    rootDescriptor,
    name,
    _oReadWrite |
        _oCreate |
        _oExclusive |
        _oNoFollow |
        _oNonBlock |
        _oCloseOnExec,
    0x180,
  );
  if (opened.value < 0 && opened.error == _eAlreadyExists) {
    created = false;
    opened = _openAt(
      rootDescriptor,
      name,
      _oReadWrite | _oNoFollow | _oNonBlock | _oCloseOnExec,
      0,
    );
  }
  final descriptor = opened.value;
  if (descriptor < 0) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  try {
    if (created) {
      _setDescriptorMode(descriptor, 0x180);
      _clearDescriptorExtendedAcl(descriptor);
    }
    _validateDescriptor(
      descriptor,
      expectedType: FileSystemEntityType.file,
      expectedPermissions: 0x180,
    );
    if (created) {
      _syncDescriptor(descriptor);
      _syncDescriptor(rootDescriptor);
    }
    return descriptor;
  } on Object {
    _closeDescriptorIgnoringFailure(descriptor);
    rethrow;
  }
}

Future<void> _acquireExclusive(
  int descriptor, {
  Duration timeout = _lockTimeout,
}) async {
  final elapsed = Stopwatch()..start();
  var backoff = const Duration(milliseconds: 2);
  var firstAttempt = true;
  while (true) {
    if (!firstAttempt && elapsed.elapsed >= timeout) {
      throw const StoreFilesFailure(StoreFilesFailureCode.busy);
    }
    firstAttempt = false;
    final result = _flock(descriptor, _lockExclusive | _lockNonBlocking);
    final error = result < 0 ? _errno : 0;
    if (result == 0) return;
    if (error == _eInterrupted) continue;
    if (error != _eWouldBlock) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw const StoreFilesFailure(StoreFilesFailureCode.busy);
    }
    await Future<void>.delayed(backoff < remaining ? backoff : remaining);
    final doubled = backoff * 2;
    backoff = doubled > _maximumLockBackoff ? _maximumLockBackoff : doubled;
  }
}

void _releaseExclusive(int descriptor) {
  while (true) {
    final result = _flock(descriptor, _lockUnlock);
    final error = result < 0 ? _errno : 0;
    if (result == 0) return;
    if (error == _eInterrupted) continue;
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

Uint8List _readExact(
  int descriptor, {
  required int offset,
  required int length,
}) {
  final result = Uint8List(length);
  if (length == 0) return result;
  final native = malloc<Uint8>(_nativeBufferBytes);
  var copied = 0;
  try {
    while (copied < length) {
      final remaining = length - copied;
      final count = remaining < _nativeBufferBytes
          ? remaining
          : _nativeBufferBytes;
      final read = _pread(descriptor, native, count, offset + copied);
      final error = read < 0 ? _errno : 0;
      if (read < 0) {
        if (error == _eInterrupted) continue;
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      if (read == 0) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      result.setRange(copied, copied + read, native.asTypedList(read));
      copied += read;
    }
    return result;
  } finally {
    malloc.free(native);
  }
}

void _writeAll(int descriptor, Uint8List bytes) {
  if (bytes.isEmpty) return;
  final native = malloc<Uint8>(_nativeBufferBytes);
  var written = 0;
  try {
    while (written < bytes.length) {
      final remaining = bytes.length - written;
      final count = remaining < _nativeBufferBytes
          ? remaining
          : _nativeBufferBytes;
      native.asTypedList(count).setRange(0, count, bytes, written);
      var chunkWritten = 0;
      while (chunkWritten < count) {
        final result = _write(
          descriptor,
          native + chunkWritten,
          count - chunkWritten,
        );
        final error = result < 0 ? _errno : 0;
        if (result < 0) {
          if (error == _eInterrupted) continue;
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }
        if (result == 0) {
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }
        chunkWritten += result;
      }
      written += count;
    }
  } finally {
    malloc.free(native);
  }
}

final class _DescriptorMetadata {
  const _DescriptorMetadata({
    required this.type,
    required this.size,
    required this.mode,
  });

  final FileSystemEntityType type;
  final int size;
  final int mode;
}

_DescriptorMetadata _validateDescriptor(
  int descriptor, {
  required FileSystemEntityType expectedType,
  int? expectedPermissions,
}) {
  final stat = _readDescriptorMetadata(descriptor);
  if (stat.type != expectedType ||
      stat.size < 0 ||
      (expectedPermissions != null &&
          stat.mode & _permissionModeMask != expectedPermissions)) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  if (expectedPermissions != null) {
    _validateNoDescriptorExtendedAcl(descriptor);
  }
  return stat;
}

void _clearDescriptorExtendedAcl(int descriptor) {
  if (!Platform.isMacOS) return;
  try {
    final acl = _aclInit(0);
    if (acl.address == 0) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    StoreFilesFailure? failure;
    final setResult = _aclSetFdNp(descriptor, acl, _aclTypeExtended);
    if (setResult != 0) {
      final _ = _errno;
      failure = const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final freeResult = _aclFree(acl);
    if (freeResult != 0) {
      final _ = _errno;
      failure ??= const StoreFilesFailure(
        StoreFilesFailureCode.operationFailed,
      );
    }
    if (failure != null) throw failure;
  } on StoreFilesFailure {
    rethrow;
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

void _validateNoDescriptorExtendedAcl(int descriptor) {
  if (!Platform.isMacOS) return;
  try {
    final acl = _aclGetFdNp(descriptor, _aclTypeExtended);
    if (acl.address == 0) {
      final error = _errno;
      if (error == _eNoEntry) return;
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    StoreFilesFailure? failure;
    final entry = calloc<Pointer<Void>>();
    try {
      if (_aclValid(acl) != 0) {
        final _ = _errno;
        failure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );
      } else {
        final entryResult = _aclGetEntry(acl, _aclFirstEntry, entry);
        // Darwin reports 0 when it returned an entry and -1/EINVAL when a
        // valid ACL contains none. Any undocumented result fails closed.
        if (entryResult == 0) {
          failure = const StoreFilesFailure(
            StoreFilesFailureCode.operationFailed,
          );
        } else if (entryResult < 0) {
          final error = _errno;
          if (error != _eInvalid) {
            failure = const StoreFilesFailure(
              StoreFilesFailureCode.operationFailed,
            );
          }
        } else {
          failure = const StoreFilesFailure(
            StoreFilesFailureCode.operationFailed,
          );
        }
      }
    } finally {
      calloc.free(entry);
    }

    final freeResult = _aclFree(acl);
    if (freeResult != 0) {
      final _ = _errno;
      failure ??= const StoreFilesFailure(
        StoreFilesFailureCode.operationFailed,
      );
    }
    if (failure != null) throw failure;
  } on StoreFilesFailure {
    rethrow;
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

_DescriptorMetadata _readDescriptorMetadata(int descriptor) {
  if (!_isAppleHost) {
    try {
      final stat = FileStat.statSync('/proc/self/fd/$descriptor');
      return _DescriptorMetadata(
        type: stat.type,
        size: stat.size,
        mode: stat.mode,
      );
    } on Object {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
  }

  final abi = Abi.current();
  if (abi != Abi.macosArm64 &&
      abi != Abi.macosX64 &&
      abi != Abi.iosArm64 &&
      abi != Abi.iosX64) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  if (sizeOf<_DarwinStat>() != 144) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }

  final pointer = calloc<_DarwinStat>();
  try {
    final result = _darwinFstat(descriptor, pointer);
    final error = result < 0 ? _errno : 0;
    if (result < 0) _throwOperationFailure(error);
    final mode = pointer.ref.mode;
    final type = switch (mode & _fileTypeModeMask) {
      _directoryTypeMode => FileSystemEntityType.directory,
      _regularFileTypeMode => FileSystemEntityType.file,
      _ => FileSystemEntityType.notFound,
    };
    return _DescriptorMetadata(type: type, size: pointer.ref.size, mode: mode);
  } on StoreFilesFailure {
    rethrow;
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  } finally {
    calloc.free(pointer);
  }
}

bool _entryExists(int rootDescriptor, String name) {
  final opened = _openAt(
    rootDescriptor,
    name,
    _oReadOnly | _oNoFollow | _oNonBlock | _oCloseOnExec,
    0,
  );
  final descriptor = opened.value;
  if (descriptor >= 0) {
    _closeDescriptor(descriptor);
    return true;
  }
  if (opened.error == _eNoEntry) return false;
  if (opened.error == _eLoop) return true;
  throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
}

void _syncDescriptor(int descriptor) {
  while (true) {
    final result = _fsync(descriptor);
    final error = result < 0 ? _errno : 0;
    if (result == 0) break;
    if (error == _eInterrupted) continue;
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  if (_isAppleHost) {
    // Darwin's fsync(2) need not force volatile device caches. F_FULLFSYNC is
    // required as the second barrier for both store files and the directory
    // descriptor whose entries carry staging, replacement, and reset state.
    while (true) {
      final result = _fcntl(descriptor, _fFullFsync, 0);
      final error = result < 0 ? _errno : 0;
      if (result == 0) break;
      if (error == _eInterrupted) continue;
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
  }
}

bool _unlinkAtIfPresent(int rootDescriptor, String name) {
  final pointer = name.toNativeUtf8();
  late final int result;
  late final int error;
  try {
    result = _unlinkAt(rootDescriptor, pointer, 0);
    error = result < 0 ? _errno : 0;
  } finally {
    malloc.free(pointer);
  }
  if (result == 0) return true;
  if (error == _eNoEntry) return false;
  throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
}

void _renameAt(int oldRoot, String oldName, int newRoot, String newName) {
  final oldPointer = oldName.toNativeUtf8();
  final newPointer = newName.toNativeUtf8();
  late final int result;
  late final int error;
  try {
    result = _renameAtNative(oldRoot, oldPointer, newRoot, newPointer);
    error = result < 0 ? _errno : 0;
  } finally {
    malloc.free(newPointer);
    malloc.free(oldPointer);
  }
  if (result < 0) _throwOperationFailure(error);
}

bool _mkdirAtComponent(int parentDescriptor, String name) {
  final pointer = name.toNativeUtf8();
  late final int result;
  late final int error;
  try {
    result = _mkdirAt(parentDescriptor, pointer, 0x1c0);
    error = result < 0 ? _errno : 0;
  } finally {
    malloc.free(pointer);
  }
  if (result < 0 && error != _eAlreadyExists) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  return result == 0;
}

void _setDescriptorMode(int descriptor, int mode) {
  final result = _fchmod(descriptor, mode);
  final error = result < 0 ? _errno : 0;
  if (result < 0) _throwOperationFailure(error);
}

void _closeDescriptor(int descriptor) {
  final result = _close(descriptor);
  final error = result < 0 ? _errno : 0;
  if (result < 0) _throwOperationFailure(error);
}

void _closeDescriptorIgnoringFailure(int descriptor) {
  if (descriptor < 0) return;
  final result = _close(descriptor);
  if (result < 0) {
    final _ = _errno;
  }
}

Never _throwOperationFailure(int _) =>
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);

StoreFilesFailure _asStoreFailure(Object error) => error is StoreFilesFailure
    ? error
    : const StoreFilesFailure(StoreFilesFailureCode.operationFailed);

List<String> _absolutePathComponents(String path) {
  if (!path.startsWith('/')) {
    throw ArgumentError.value(
      '<redacted>',
      'canonicalFileRoot',
      'must resolve to an absolute POSIX path',
    );
  }
  final components = path.split('/').where((part) => part.isNotEmpty).toList();
  if (components.isEmpty ||
      components.any(
        (part) => part == '.' || part == '..' || part.contains('\u0000'),
      )) {
    throw ArgumentError.value(
      '<redacted>',
      'canonicalFileRoot',
      'contains an invalid POSIX path component',
    );
  }
  return components;
}

String _withoutTrailingPosixSeparator(String path) {
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2f) {
    end -= 1;
  }
  return end == path.length ? path : path.substring(0, end);
}

bool get _isAppleHost => Platform.isMacOS || Platform.isIOS;
// Availability expands only with a qualified host profile. The implementation
// uses POSIX primitives shared by mobile hosts, but iOS and Android still need
// their own directory, backup, and durability evidence before they may use it.
bool get _isPathWalkingPosixHost => Platform.isMacOS || Platform.isLinux;
bool get _isDirectRootPosixHost =>
    _isPathWalkingPosixHost || Platform.isAndroid || Platform.isIOS;

final class _DarwinTimespec extends Struct {
  @Int64()
  external int seconds;

  @Int64()
  external int nanoseconds;
}

/// Darwin's public 64-bit-inode `struct stat` layout.
/// macOS x64 selects fstat$INODE64; its plain fstat symbol uses a legacy layout.
///
/// Darwin `/dev/fd` status reports synthesize permissions from the descriptor's
/// access mode, so access bits must come directly from `fstat(2)` instead.
final class _DarwinStat extends Struct {
  @Int32()
  external int device;

  @Uint16()
  external int mode;

  @Uint16()
  external int linkCount;

  @Uint64()
  external int inode;

  @Uint32()
  external int user;

  @Uint32()
  external int group;

  @Int32()
  external int specialDevice;

  external _DarwinTimespec accessTime;
  external _DarwinTimespec modificationTime;
  external _DarwinTimespec changeTime;
  external _DarwinTimespec birthTime;

  @Int64()
  external int size;

  @Int64()
  external int blocks;

  @Int32()
  external int blockSize;

  @Uint32()
  external int flags;

  @Uint32()
  external int generation;

  @Int32()
  external int spare;

  @Array(2)
  external Array<Int64> reserved;
}

final DynamicLibrary _libc = DynamicLibrary.process();

final int Function(Pointer<Utf8>, int, int) _open = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
      int Function(Pointer<Utf8>, int, int)
    >('open');

({int value, int error}) _openPath(String path, int flags, int mode) {
  final pointer = path.toNativeUtf8();
  late final int value;
  late final int error;
  try {
    value = _open(pointer, flags, mode);
    error = value < 0 ? _errno : 0;
  } finally {
    malloc.free(pointer);
  }
  return (value: value, error: error);
}

({int value, int error}) _openAt(
  int rootDescriptor,
  String name,
  int flags,
  int mode,
) {
  final pointer = name.toNativeUtf8();
  late final int value;
  late final int error;
  try {
    value = _openAtNative(rootDescriptor, pointer, flags, mode);
    error = value < 0 ? _errno : 0;
  } finally {
    malloc.free(pointer);
  }
  return (value: value, error: error);
}

// Bound separately so callers never retain a native filename allocation.
final int Function(int, Pointer<Utf8>, int, int) _openAtNative = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
      int Function(int, Pointer<Utf8>, int, int)
    >('openat');

final int Function(int, Pointer<Uint8>, int) _write = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)
    >('write');

final int Function(int, Pointer<Uint8>, int, int) _pread = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
      int Function(int, Pointer<Uint8>, int, int)
    >(_isAppleHost ? 'pread' : 'pread64');

final int Function(int) _fsync = _libc
    .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');

final int Function(int, int, int) _fcntl = _libc
    .lookupFunction<
      Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
      int Function(int, int, int)
    >('fcntl');

final int Function(int, int) _fchmod = _libc
    .lookupFunction<Int32 Function(Int32, Uint32), int Function(int, int)>(
      'fchmod',
    );

final int Function(int, Pointer<_DarwinStat>) _darwinFstat = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_DarwinStat>),
      int Function(int, Pointer<_DarwinStat>)
    >(Abi.current() == Abi.macosX64 ? r'fstat$INODE64' : 'fstat');

final Pointer<Void> Function(int) _aclInit = _libc
    .lookupFunction<Pointer<Void> Function(Int32), Pointer<Void> Function(int)>(
      'acl_init',
    );

final int Function(int, Pointer<Void>, int) _aclSetFdNp = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Void>, Int32),
      int Function(int, Pointer<Void>, int)
    >('acl_set_fd_np');

final Pointer<Void> Function(int, int) _aclGetFdNp = _libc
    .lookupFunction<
      Pointer<Void> Function(Int32, Int32),
      Pointer<Void> Function(int, int)
    >('acl_get_fd_np');

final int Function(Pointer<Void>) _aclValid = _libc
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'acl_valid',
    );

final int Function(Pointer<Void>, int, Pointer<Pointer<Void>>) _aclGetEntry =
    _libc.lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<Pointer<Void>>),
      int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
    >('acl_get_entry');

final int Function(Pointer<Void>) _aclFree = _libc
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'acl_free',
    );

final int Function(int) _close = _libc
    .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

final int Function(int, int) _flock = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'flock',
    );

final int Function(int, Pointer<Utf8>, int) _mkdirAt = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Uint32),
      int Function(int, Pointer<Utf8>, int)
    >('mkdirat');

final int Function(int, Pointer<Utf8>, int) _unlinkAt = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32),
      int Function(int, Pointer<Utf8>, int)
    >('unlinkat');

final int Function(int, Pointer<Utf8>, int, Pointer<Utf8>) _renameAtNative =
    _libc.lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>, int, Pointer<Utf8>)
    >('renameat');

final Pointer<Int32> Function() _errnoLocation = _resolveErrnoLocation();

Pointer<Int32> Function() _resolveErrnoLocation() {
  final candidates = _isAppleHost
      ? const <String>['__error']
      : const <String>['__errno_location', '__errno'];
  for (final symbol in candidates) {
    try {
      return _libc
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            symbol,
          );
    } on ArgumentError {
      // Try the next libc spelling.
    }
  }
  throw UnsupportedError('No POSIX errno location is available.');
}

int get _errno => _errnoLocation().value;

const int _oReadOnly = 0;
const int _oReadWrite = 2;
final int _oCreate = _isAppleHost ? 0x0200 : 0x40;
final int _oExclusive = _isAppleHost ? 0x0800 : 0x80;
final int _oNonBlock = _isAppleHost ? 0x0004 : 0x0800;
final int _oCloseOnExec = _isAppleHost ? 0x01000000 : 0x80000;
final ({int directory, int noFollow}) _hostOpenFlags = _resolveHostOpenFlags();
final int _oDirectory = _hostOpenFlags.directory;
final int _oNoFollow = _hostOpenFlags.noFollow;

({int directory, int noFollow}) _resolveHostOpenFlags() {
  if (_isAppleHost) {
    return (directory: 0x00100000, noFollow: 0x0100);
  }

  // Linux keeps these two open(2) flags in its architecture ABI. ARM uses
  // the historical values while x86 and RISC-V use the asm-generic values.
  // Android exposes the same kernel ABI split. Unknown ABIs fail closed
  // instead of silently substituting a bit with different semantics.
  final abi = Abi.current();
  if (abi == Abi.linuxArm ||
      abi == Abi.linuxArm64 ||
      abi == Abi.androidArm ||
      abi == Abi.androidArm64) {
    return (directory: 0x4000, noFollow: 0x8000);
  }
  if (abi == Abi.linuxIA32 ||
      abi == Abi.linuxX64 ||
      abi == Abi.linuxRiscv32 ||
      abi == Abi.linuxRiscv64 ||
      abi == Abi.androidIA32 ||
      abi == Abi.androidX64 ||
      abi == Abi.androidRiscv64) {
    return (directory: 0x10000, noFollow: 0x20000);
  }
  throw UnsupportedError('Unsupported POSIX open flag ABI: $abi');
}

const int _lockExclusive = 2;
const int _lockNonBlocking = 4;
const int _lockUnlock = 8;
const int _fFullFsync = 51;
const int _permissionModeMask = 0x0fff;
const int _fileTypeModeMask = 0xf000;
const int _directoryTypeMode = 0x4000;
const int _regularFileTypeMode = 0x8000;
const int _aclTypeExtended = 0x00000100;
const int _aclFirstEntry = 0;

const int _eInterrupted = 4;
const int _eNoEntry = 2;
const int _eInvalid = 22;
const int _eAlreadyExists = 17;
final int _eLoop = _isAppleHost ? 62 : 40;
final int _eWouldBlock = _isAppleHost ? 35 : 11;

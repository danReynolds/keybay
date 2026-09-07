import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';

import 'v2_software_root_lease.dart';

/// Expected exit status when a cross-root worker reaches the bound provider.
const int disposableStateConflictExitCode = 20;

/// Exit status reserved for an unexpected worker failure.
const int disposableWorkerFailureExitCode = 70;

/// The test-only initialized-store proof written beneath the winning root.
const String disposableProofFileName = 'initialized.proof';

const int _providerRootLength = 32;
const int _providerStateLength = 16;
const int _domainCommitmentLength = 43;
const List<int> _providerMagic = <int>[75, 66, 80, 50, 84, 69, 83, 84];
const List<int> _proofMagic = <int>[75, 66, 80, 82, 79, 79, 70, 50];
const int _providerRecordLength =
    8 + _domainCommitmentLength + _providerRootLength + _providerStateLength;

/// A deliberately disposable, test-only file analogue of a platform provider.
///
/// Its identity-derived provider record and lock live outside candidate store
/// roots. The root is plaintext on disk, so this must never be used as a real
/// Keybay profile; it exists solely to exercise process coordination.
final class DisposableFileProtector implements PlatformProtector {
  DisposableFileProtector({
    required this.binding,
    required Directory providerDirectory,
    this.creationDelay = Duration.zero,
  }) : _providerDirectory = providerDirectory,
       _fileSystem = const _DisposableFileSystem() {
    if (_providerDirectory.absolute.path != _providerDirectory.path) {
      throw ArgumentError.value(
        '<redacted>',
        'providerDirectory',
        'must be absolute',
      );
    }
  }

  @override
  final ResolvedApplicationBinding binding;

  final Directory _providerDirectory;
  final _DisposableFileSystem _fileSystem;

  /// Widens a test race after absence is observed while the lock is held.
  final Duration creationDelay;

  String get _recordPath =>
      '${_providerDirectory.path}/${binding.providerAddress}.provider';

  String get _lockPath =>
      '${_providerDirectory.path}/${binding.providerAddress}.lock';

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) => _withProviderLock(() async {
    final record = _readRecord();
    if (record == null) return null;
    try {
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
    } finally {
      record.clearRoot();
    }
  });

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) => _withProviderLock(() async {
    final existing = _readRecord();
    if (existing != null) {
      try {
        _verifyDomain(existing);
        return PlatformRootCreation(
          lease: SoftwareRootLease(
            root: existing.root,
            providerState: existing.providerState,
          ),
          disposition: RootCreationDisposition.adopted,
        );
      } finally {
        existing.clearRoot();
      }
    }

    if (creationDelay > Duration.zero) {
      await Future<void>.delayed(creationDelay);
    }
    final record = _DisposableProviderRecord(
      domainCommitment: binding.domain.commitment,
      root: randomTestBytes(_providerRootLength),
      providerState: ProviderState(randomTestBytes(_providerStateLength)),
    );
    final encoded = record.encode();
    try {
      _fileSystem.writeAtomicSync(_recordPath, encoded);
      return PlatformRootCreation(
        lease: SoftwareRootLease(
          root: record.root,
          providerState: record.providerState,
        ),
        disposition: RootCreationDisposition.created,
      );
    } finally {
      clearTestBytes(encoded);
      record.clearRoot();
    }
  });

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) => _withProviderLock(() async {
    final record = _readRecord();
    if (record == null) {
      return _DisposablePreparedReset(owner: this, expectedState: null);
    }
    try {
      _verifyDomain(record);
      return _DisposablePreparedReset(
        owner: this,
        expectedState: record.providerState,
      );
    } finally {
      record.clearRoot();
    }
  });

  Future<void> _commitReset(ProviderState? expectedState) async {
    try {
      await _withProviderLock(() async {
        final record = _readRecord();
        if (record == null) return;
        try {
          _verifyDomain(record);
          if (expectedState == null ||
              !record.providerState.hasSameBytes(expectedState)) {
            throw const PlatformProtectorFailure(
              PlatformProtectorFailureCode.resetIncomplete,
            );
          }
          _fileSystem.deleteSync(_recordPath);
        } finally {
          record.clearRoot();
        }
      });
    } on PlatformProtectorFailure catch (failure) {
      if (failure.code == PlatformProtectorFailureCode.resetIncomplete) {
        rethrow;
      }
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
  }

  Future<T> _withProviderLock<T>(Future<T> Function() body) async {
    try {
      _fileSystem.ensurePrivateDirSync(_providerDirectory.path);
      return await _fileSystem.withExclusiveLock<T>(
        _lockPath,
        timeout: const Duration(seconds: 10),
        body: body,
      );
    } on PlatformProtectorFailure {
      rethrow;
    } catch (_) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
  }

  _DisposableProviderRecord? _readRecord() {
    Uint8List? bytes;
    try {
      bytes = _fileSystem.readCappedSync(
        _recordPath,
        maxBytes: _providerRecordLength,
        requirePrivate: true,
      );
      if (bytes == null) return null;
      return _DisposableProviderRecord.decode(bytes);
    } finally {
      if (bytes != null) clearTestBytes(bytes);
    }
  }

  void _verifyDomain(_DisposableProviderRecord record) {
    if (record.domainCommitment != binding.domain.commitment) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.stateConflict,
      );
    }
  }
}

final class _DisposablePreparedReset implements PreparedPlatformReset {
  _DisposablePreparedReset({
    required DisposableFileProtector owner,
    required ProviderState? expectedState,
  }) : _owner = owner,
       _expectedState = expectedState;

  final DisposableFileProtector _owner;
  final ProviderState? _expectedState;
  bool _commitAttempted = false;
  bool _closed = false;

  @override
  Future<void> commit() {
    if (_closed || _commitAttempted) {
      return Future<void>.error(
        const PlatformProtectorFailure(
          PlatformProtectorFailureCode.resetIncomplete,
        ),
      );
    }
    _commitAttempted = true;
    return _owner._commitReset(_expectedState);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

/// Persisted proof that a worker completed initialization under one root.
final class DisposableStoreProof {
  DisposableStoreProof({
    required ProviderState providerState,
    required Uint8List sealedPackage,
  }) : providerState = ProviderState(providerState.copyBytes()),
       _sealedPackage = Uint8List.fromList(sealedPackage);

  factory DisposableStoreProof.decode(Uint8List bytes) {
    if (bytes.length <= _proofMagic.length + _providerStateLength ||
        !sameTestBytes(
          Uint8List.sublistView(bytes, 0, _proofMagic.length),
          _proofMagic,
        )) {
      throw const FormatException('invalid disposable store proof');
    }
    final stateStart = _proofMagic.length;
    final sealedStart = stateStart + _providerStateLength;
    return DisposableStoreProof(
      providerState: ProviderState(
        Uint8List.sublistView(bytes, stateStart, sealedStart),
      ),
      sealedPackage: Uint8List.sublistView(bytes, sealedStart),
    );
  }

  final ProviderState providerState;
  final Uint8List _sealedPackage;

  Uint8List copySealedPackage() => Uint8List.fromList(_sealedPackage);

  Uint8List encode() => Uint8List.fromList(<int>[
    ..._proofMagic,
    ...providerState.copyBytes(),
    ..._sealedPackage,
  ]);
}

Uint8List disposableProofAad(ResolvedApplicationBinding binding) =>
    Uint8List.fromList(
      ascii.encode('keybay:v2:test:cross-root:${binding.domain.commitment}'),
    );

Uint8List disposableProofPlaintext() =>
    Uint8List.fromList(ascii.encode('initialized'));

void writeDisposableStoreProof(String path, DisposableStoreProof proof) {
  final encoded = proof.encode();
  try {
    const _DisposableFileSystem().writeAtomicSync(path, encoded);
  } finally {
    clearTestBytes(encoded);
  }
}

DisposableStoreProof readDisposableStoreProof(String path) {
  final bytes = const _DisposableFileSystem().readCappedSync(
    path,
    maxBytes: 4096,
    requirePrivate: true,
  );
  if (bytes == null) {
    throw const FormatException('missing disposable store proof');
  }
  try {
    return DisposableStoreProof.decode(bytes);
  } finally {
    clearTestBytes(bytes);
  }
}

/// Minimal private-file support for the disposable cross-process provider.
///
/// This deliberately lives in tests: production file safety is supplied and
/// exercised by `PosixStoreFiles`. The fixture needs only a private directory,
/// an advisory process lock, capped reads, and replace-by-rename writes.
final class _DisposableFileSystem {
  const _DisposableFileSystem();

  void ensurePrivateDirSync(String path) {
    final directory = Directory(path)..createSync(recursive: true);
    _chmod(directory.path, '700');
    final stat = directory.statSync();
    if (stat.type != FileSystemEntityType.directory ||
        (stat.mode & 0x1ff) != 0x1c0) {
      throw const FileSystemException('test directory is not private');
    }
  }

  Future<T> withExclusiveLock<T>(
    String path, {
    required Duration timeout,
    required Future<T> Function() body,
  }) async {
    final file = File(path)..createSync(recursive: true);
    _chmod(file.path, '600');
    final handle = await file.open(mode: FileMode.append);
    var locked = false;
    T? result;
    Object? primaryFailure;
    StackTrace? primaryStack;
    Object? cleanupFailure;
    StackTrace? cleanupStack;
    try {
      final deadline = DateTime.now().add(timeout);
      while (true) {
        try {
          await handle.lock(FileLock.exclusive);
          break;
        } on FileSystemException catch (error) {
          final code = error.osError?.errorCode;
          if ((code != 11 && code != 35) || DateTime.now().isAfter(deadline)) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      locked = true;
      try {
        result = await body();
      } on Object catch (error, stackTrace) {
        primaryFailure = error;
        primaryStack = stackTrace;
      }
    } finally {
      if (locked) {
        try {
          await handle.unlock();
        } on Object catch (error, stackTrace) {
          cleanupFailure = error;
          cleanupStack = stackTrace;
        }
      }
      try {
        await handle.close();
      } on Object catch (error, stackTrace) {
        cleanupFailure ??= error;
        cleanupStack ??= stackTrace;
      }
    }
    final failure = primaryFailure ?? cleanupFailure;
    if (failure != null) {
      Error.throwWithStackTrace(
        failure,
        primaryStack ?? cleanupStack ?? StackTrace.current,
      );
    }
    return result as T;
  }

  void writeAtomicSync(String path, Uint8List bytes) {
    final target = File(path);
    ensurePrivateDirSync(target.parent.path);
    final suffix =
        '${pid}_${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(1 << 32)}';
    final temporary = File(
      '${target.parent.path}/.${target.uri.pathSegments.last}.$suffix',
    );
    try {
      temporary.createSync(exclusive: true);
      _chmod(temporary.path, '600');
      final handle = temporary.openSync(mode: FileMode.writeOnly);
      try {
        handle.writeFromSync(bytes);
        handle.flushSync();
      } finally {
        handle.closeSync();
      }
      temporary.renameSync(path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  Uint8List? readCappedSync(
    String path, {
    required int maxBytes,
    required bool requirePrivate,
  }) {
    final file = File(path);
    final stat = file.statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;
    if (stat.type != FileSystemEntityType.file || stat.size > maxBytes) {
      throw const FileSystemException('invalid disposable test file');
    }
    if (requirePrivate && (stat.mode & 0x3f) != 0) {
      throw const FileSystemException('disposable test file is not private');
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length > maxBytes) {
      clearTestBytes(bytes);
      throw const FileSystemException('disposable test file is too large');
    }
    return bytes;
  }

  void deleteSync(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  static void _chmod(String path, String mode) {
    final result = Process.runSync('chmod', <String>[mode, path]);
    if (result.exitCode != 0) {
      throw const FileSystemException('could not set test permissions');
    }
  }
}

final class _DisposableProviderRecord {
  _DisposableProviderRecord({
    required this.domainCommitment,
    required Uint8List root,
    required ProviderState providerState,
  }) : root = Uint8List.fromList(root),
       providerState = ProviderState(providerState.copyBytes());

  factory _DisposableProviderRecord.decode(Uint8List bytes) {
    if (bytes.length != _providerRecordLength ||
        !sameTestBytes(
          Uint8List.sublistView(bytes, 0, _providerMagic.length),
          _providerMagic,
        )) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    final domainStart = _providerMagic.length;
    final rootStart = domainStart + _domainCommitmentLength;
    final stateStart = rootStart + _providerRootLength;
    final String domain;
    try {
      domain = ascii.decode(
        Uint8List.sublistView(bytes, domainStart, rootStart),
      );
    } on FormatException {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    return _DisposableProviderRecord(
      domainCommitment: domain,
      root: Uint8List.sublistView(bytes, rootStart, stateStart),
      providerState: ProviderState(Uint8List.sublistView(bytes, stateStart)),
    );
  }

  final String domainCommitment;
  final Uint8List root;
  final ProviderState providerState;

  Uint8List encode() {
    final domain = ascii.encode(domainCommitment);
    if (domain.length != _domainCommitmentLength ||
        root.length != _providerRootLength ||
        providerState.length != _providerStateLength) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    return Uint8List.fromList(<int>[
      ..._providerMagic,
      ...domain,
      ...root,
      ...providerState.copyBytes(),
    ]);
  }

  void clearRoot() => clearTestBytes(root);
}

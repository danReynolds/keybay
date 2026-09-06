@TestOn('mac-os || linux')
@Tags(<String>['unit'])
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/posix_store_files.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

const String _liveName = 'keybay.v2.store';
const String _stagingName = 'keybay.v2.stage';
const String _lockName = 'keybay.v2.lock';
const String _providerAddress = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _providerLockName = '$_providerAddress.platform-root.lock';

void main() {
  late Directory fixture;

  setUp(() {
    final created = Directory.systemTemp.createTempSync(
      'keybay_v2_posix_files_',
    );
    _chmod('0700', created.path);
    fixture = Directory(created.resolveSymbolicLinksSync());
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  test('binds the fixed root to the resolved storage domain', () {
    final firstRoot = Directory('${fixture.path}/first');
    final secondRoot = Directory('${fixture.path}/second');
    final binding = _binding(firstRoot);

    expect(
      () => PosixStoreFiles(
        binding: binding,
        canonicalFileRoot: Uri.directory(secondRoot.absolute.path),
      ),
      throwsArgumentError,
    );
    expect(
      () => PosixStoreFiles.fromExistingPrivateRoot(
        binding: binding,
        canonicalFileRoot: Uri.directory(secondRoot.absolute.path),
      ),
      throwsArgumentError,
    );
    expect(firstRoot.existsSync(), isFalse);
    expect(secondRoot.existsSync(), isFalse);
  });

  test('an absent read neither creates nor redirects the fixed root', () async {
    final root = Directory('${fixture.path}/store');
    final files = _files(root);

    expect(await files.openPinnedLive(), isNull);
    expect(root.existsSync(), isFalse);
  });

  test('uses ABI-correct directory and no-follow flags', () async {
    final root = Directory('${fixture.path}/store');
    await _replace(_files(root), <int>[1]);
    expect(File('${root.path}/$_liveName').readAsBytesSync(), <int>[1]);

    final target = Directory('${fixture.path}/target')..createSync();
    _chmod('0700', target.path);
    final redirected = Link('${fixture.path}/redirect')
      ..createSync(target.path);
    final redirectedRoot = Directory('${redirected.path}/store');
    await expectLater(
      _files(redirectedRoot).withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(Directory('${target.path}/store').existsSync(), isFalse);

    final source = File('lib/src/v2/posix_store_files.dart').readAsStringSync();
    expect(
      source,
      contains('return (directory: 0x4000, noFollow: 0x8000);'),
      reason: 'Linux ARM must retain its architecture-specific open flags',
    );
    expect(source, contains('_oCloseOnExec'));
    final providerSource = File(
      'lib/src/v2/linux_secret_service_root_store.dart',
    ).readAsStringSync();
    expect(providerSource, isNot(contains('SecureFileSystem')));
    expect(providerSource, contains('withLinuxSecretServiceCreationLock'));
  });

  test(
    'provider lock creates and reuses only fixed private artifacts',
    () async {
      final runtime = Directory('${fixture.path}/runtime')..createSync();
      _chmod('0700', runtime.path);
      var entries = 0;

      await _withProviderLock(runtime, () async {
        entries++;
      });
      await _withProviderLock(runtime, () async {
        entries++;
      });

      final directory = Directory('${runtime.path}/keybay-v2');
      final lock = File('${directory.path}/$_providerLockName');
      expect(entries, 2);
      expect(directory.statSync().type, FileSystemEntityType.directory);
      expect(lock.statSync().type, FileSystemEntityType.file);
      expect(_mode(directory.path), 0x1c0);
      expect(_mode(lock.path), 0x180);
    },
  );

  test(
    'provider lock rejects redirects, non-files, and insecure modes',
    () async {
      Future<void> expectRejected(Directory runtime) => expectLater(
        _withProviderLock(runtime, () async {}),
        throwsA(_failure(StoreFilesFailureCode.operationFailed)),
      );

      Directory runtime(String name) {
        final value = Directory('${fixture.path}/$name')..createSync();
        _chmod('0700', value.path);
        return value;
      }

      final redirectedDirectory = runtime('redirected-directory');
      final directoryTarget = Directory('${fixture.path}/directory-target')
        ..createSync();
      _chmod('0700', directoryTarget.path);
      Link(
        '${redirectedDirectory.path}/keybay-v2',
      ).createSync(directoryTarget.path);
      await expectRejected(redirectedDirectory);
      expect(
        File('${directoryTarget.path}/$_providerLockName').existsSync(),
        isFalse,
      );

      final nonDirectory = runtime('non-directory');
      File('${nonDirectory.path}/keybay-v2').writeAsBytesSync(<int>[]);
      _chmod('0600', '${nonDirectory.path}/keybay-v2');
      await expectRejected(nonDirectory);

      final looseDirectory = runtime('loose-directory');
      Directory('${looseDirectory.path}/keybay-v2').createSync();
      _chmod('0755', '${looseDirectory.path}/keybay-v2');
      await expectRejected(looseDirectory);

      final redirectedLock = runtime('redirected-lock');
      final redirectedLockDirectory = Directory(
        '${redirectedLock.path}/keybay-v2',
      )..createSync();
      _chmod('0700', redirectedLockDirectory.path);
      final lockTarget = File('${fixture.path}/lock-target')
        ..writeAsBytesSync(<int>[7]);
      _chmod('0600', lockTarget.path);
      Link(
        '${redirectedLockDirectory.path}/$_providerLockName',
      ).createSync(lockTarget.path);
      await expectRejected(redirectedLock);
      expect(lockTarget.readAsBytesSync(), <int>[7]);

      final nonFileLock = runtime('non-file-lock');
      final nonFileLockDirectory = Directory('${nonFileLock.path}/keybay-v2')
        ..createSync();
      _chmod('0700', nonFileLockDirectory.path);
      Directory('${nonFileLockDirectory.path}/$_providerLockName').createSync();
      await expectRejected(nonFileLock);

      final looseLock = runtime('loose-lock');
      final looseLockDirectory = Directory('${looseLock.path}/keybay-v2')
        ..createSync();
      _chmod('0700', looseLockDirectory.path);
      final looseLockFile = File(
        '${looseLockDirectory.path}/$_providerLockName',
      )..writeAsBytesSync(<int>[]);
      _chmod('0644', looseLockFile.path);
      await expectRejected(looseLock);
      expect(_mode(looseLockFile.path), 0x1a4);

      final looseRuntime = runtime('loose-runtime');
      _chmod('0755', looseRuntime.path);
      await expectRejected(looseRuntime);
    },
  );

  test('provider lock contention respects its bounded timeout', () async {
    final runtime = Directory('${fixture.path}/contended-runtime')
      ..createSync();
    _chmod('0700', runtime.path);
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = _withProviderLock(runtime, () async {
      entered.complete();
      await release.future;
    });
    await entered.future;

    await expectLater(
      PosixStoreFiles.withLinuxSecretServiceCreationLock(
        canonicalRuntimeDirectory: Uri.directory(runtime.path),
        providerAddress: _providerAddress,
        timeout: const Duration(milliseconds: 20),
        operation: () async {},
      ),
      throwsA(_failure(StoreFilesFailureCode.busy)),
    );
    release.complete();
    await first;
  });

  test('provider lock never retries after its bounded deadline', () async {
    final runtime = Directory('${fixture.path}/deadline-runtime')..createSync();
    _chmod('0700', runtime.path);
    final entered = Completer<void>();
    final first = _withProviderLock(runtime, () async {
      entered.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await entered.future;

    await expectLater(
      PosixStoreFiles.withLinuxSecretServiceCreationLock(
        canonicalRuntimeDirectory: Uri.directory(runtime.path),
        providerAddress: _providerAddress,
        timeout: const Duration(milliseconds: 80),
        operation: () async {
          fail('a retry acquired the lock after its deadline');
        },
      ),
      throwsA(_failure(StoreFilesFailureCode.busy)),
    );
    await first;
  });

  test('directory preparation closes the child when preparation fails', () {
    final parent = Directory('${fixture.path}/preparation-failure-parent')
      ..createSync();
    _chmod('0700', parent.path);
    int? openedChild;

    try {
      expect(
        () => PosixStoreFiles.debugDurablyCreatePrivateDirectories(
          canonicalExistingParent: Uri.directory(parent.path),
          childComponents: const <String>['child', 'unreached'],
          beforePrepareNewDirectory: (descriptor) {
            openedChild = descriptor;
            expect(_descriptorFlags(descriptor), isNonNegative);
            throw StateError('injected directory preparation failure');
          },
        ),
        throwsA(_failure(StoreFilesFailureCode.operationFailed)),
      );
      expect(openedChild, isNotNull);
      final flags = _descriptorFlags(openedChild!);
      final error = _descriptorErrno().value;
      expect(
        flags,
        -1,
        reason: 'The failed child acquisition must close its fd.',
      );
      expect(error, 9, reason: 'fcntl must report EBADF for the closed fd.');
      expect(Directory('${parent.path}/child/unreached').existsSync(), isFalse);
    } finally {
      // Also keep a failing regression run from leaking its fixture descriptor.
      final descriptor = openedChild;
      if (descriptor != null && _descriptorFlags(descriptor) >= 0) {
        _closeTestDescriptor(descriptor);
      }
    }
  });

  test(
    'directory preparation validates children that appeared before open',
    () {
      final parent = Directory('${fixture.path}/preparation-parent')
        ..createSync();
      _chmod('0700', parent.path);
      final appeared = Directory('${parent.path}/appeared')..createSync();
      _chmod('0755', appeared.path);

      expect(
        () => PosixStoreFiles.durablyCreatePrivateDirectories(
          canonicalExistingParent: Uri.directory(parent.path),
          childComponents: const <String>['appeared', 'leaf'],
        ),
        throwsA(_failure(StoreFilesFailureCode.operationFailed)),
      );
      expect(Directory('${appeared.path}/leaf').existsSync(), isFalse);
      expect(_mode(appeared.path), 0x1ed);

      _chmod('0700', appeared.path);
      PosixStoreFiles.durablyCreatePrivateDirectories(
        canonicalExistingParent: Uri.directory(parent.path),
        childComponents: const <String>['appeared', 'leaf'],
      );
      expect(_mode(appeared.path), 0x1c0);
      expect(_mode('${appeared.path}/leaf'), 0x1c0);
    },
  );

  test('directory preparation rejects an existing child extended ACL', () {
    final parent = Directory('${fixture.path}/preparation-acl-parent')
      ..createSync();
    _chmod('0700', parent.path);
    final appeared = Directory('${parent.path}/appeared')..createSync();
    _chmod('0700', appeared.path);
    if (!_tryAddAcl(appeared.path, 'everyone allow read')) {
      markTestSkipped('the fixture file system does not support Darwin ACLs');
      return;
    }

    expect(
      () => PosixStoreFiles.durablyCreatePrivateDirectories(
        canonicalExistingParent: Uri.directory(parent.path),
        childComponents: const <String>['appeared'],
      ),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_hasExtendedAcl(appeared.path), isTrue);
  }, skip: Platform.isMacOS ? false : 'Darwin extended ACLs only');

  test('durably anchors only an exact private directory', () {
    final parent = Directory('${fixture.path}/mobile-parent')..createSync();
    _chmod('0700', parent.path);
    final root = Directory('${parent.path}/keybay-v2')..createSync();
    _chmod('0700', root.path);

    PosixStoreFiles.durablyAnchorPrivateRoot(
      canonicalFileRoot: Uri.directory(root.path),
    );

    final target = Directory('${parent.path}/target')..createSync();
    _chmod('0700', target.path);
    final redirected = Link('${parent.path}/redirect')..createSync(target.path);
    expect(
      () => PosixStoreFiles.durablyAnchorPrivateRoot(
        canonicalFileRoot: Uri.directory(redirected.path),
      ),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );

    final redirectedParent = Link('${fixture.path}/parent-link')
      ..createSync(parent.path);
    expect(
      () => PosixStoreFiles.durablyAnchorPrivateRoot(
        canonicalFileRoot: Uri.directory('${redirectedParent.path}/keybay-v2'),
      ),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );

    _chmod('0755', root.path);
    expect(
      () => PosixStoreFiles.durablyAnchorPrivateRoot(
        canonicalFileRoot: Uri.directory(root.path),
      ),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
  });

  test('direct root requires an existing private descriptor anchor', () async {
    final root = Directory('${fixture.path}/mobile-anchor');
    final files = _directFiles(root);

    expect(await files.openPinnedLive(), isNull);
    await expectLater(
      files.withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(root.existsSync(), isFalse);

    root.createSync();
    _chmod('0700', root.path);
    await _replace(files, <int>[3, 4]);
    expect(File('${root.path}/$_liveName').readAsBytesSync(), <int>[3, 4]);
  });

  test(
    'direct root does not require reading protected global ancestors',
    () async {
      final protectedParent = Directory('${fixture.path}/execute-only')
        ..createSync();
      final root = Directory('${protectedParent.path}/mobile-anchor')
        ..createSync();
      _chmod('0700', root.path);
      _chmod('0111', protectedParent.path);
      try {
        await _replace(_directFiles(root), <int>[5]);
        expect(File('${root.path}/$_liveName').readAsBytesSync(), <int>[5]);
      } finally {
        _chmod('0700', protectedParent.path);
      }
    },
  );

  test('direct root rejects a redirected or non-private anchor', () async {
    final target = Directory('${fixture.path}/direct-target')..createSync();
    _chmod('0700', target.path);
    final redirected = Link('${fixture.path}/direct-link')
      ..createSync(target.path);

    await expectLater(
      _directFiles(Directory(redirected.path)).openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );

    _chmod('0755', target.path);
    await expectLater(
      _directFiles(target).withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(File('${target.path}/$_lockName').existsSync(), isFalse);
  });

  test('refuses to create missing canonical-root ancestors', () async {
    final missingParent = Directory('${fixture.path}/missing-parent');
    final root = Directory('${missingParent.path}/store');
    final files = _files(root);

    await expectLater(
      files.withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(missingParent.existsSync(), isFalse);
    expect(root.existsSync(), isFalse);
  });

  test('rejects a symlink in every canonical-root ancestor', () async {
    final target = Directory('${fixture.path}/target')..createSync();
    _chmod('0700', target.path);
    final link = Link('${fixture.path}/redirect')..createSync(target.path);
    final root = Directory('${link.path}/store');
    final files = _files(root);

    await expectLater(
      files.openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    await expectLater(
      files.withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(Directory('${target.path}/store').existsSync(), isFalse);
  });

  test('fails closed when a hostile umask prevents pinning the root', () async {
    final packageLibrary = await Isolate.resolvePackageUri(
      Uri.parse('package:keybay/keybay.dart'),
    );
    if (packageLibrary == null) fail('could not resolve package:keybay');
    final packageRoot = File.fromUri(packageLibrary).parent.parent;
    final worker = File(
      '${packageRoot.path}/test/support/'
      'v2_posix_store_files_umask_worker.dart',
    );
    final blockedRoot = Directory('${fixture.path}/blocked-hostile-umask');
    final blocked = await Process.run(Platform.resolvedExecutable, <String>[
      worker.path,
      blockedRoot.path,
    ], workingDirectory: packageRoot.path);

    final blockedMode = _mode(blockedRoot.path);
    _chmod('0700', blockedRoot.path);
    expect(blocked.exitCode, 3, reason: '${blocked.stderr}');
    expect(blockedMode, 0);
    expect(File('${blockedRoot.path}/$_lockName').existsSync(), isFalse);
    expect(File('${blockedRoot.path}/$_liveName').existsSync(), isFalse);

    final pinnedRoot = Directory('${fixture.path}/pinned-hostile-umask')
      ..createSync();
    _chmod('0700', pinnedRoot.path);
    final pinned = await Process.run(Platform.resolvedExecutable, <String>[
      worker.path,
      pinnedRoot.path,
    ], workingDirectory: packageRoot.path);

    expect(pinned.exitCode, 0, reason: '${pinned.stderr}');
    expect(_mode(pinnedRoot.path), 0x1c0);
    expect(_mode('${pinnedRoot.path}/$_lockName'), 0x180);
    expect(_mode('${pinnedRoot.path}/$_liveName'), 0x180);
  });

  test(
    'creates private fixed artifacts and installs a verified stage',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);

      await files.withExclusiveTransaction((transaction) async {
        expect((await transaction.observeArtifacts()).isAbsent, isTrue);
        final stage = await transaction.createStaging(expectedLength: 4);
        final caller = Uint8List.fromList(<int>[1, 2]);
        final appending = stage.append(caller);
        caller.fillRange(0, caller.length, 0);
        await appending;
        await stage.append(Uint8List.fromList(<int>[3, 4]));

        final artifacts = await transaction.observeArtifacts();
        expect(artifacts.hasLiveFile, isFalse);
        expect(artifacts.hasTransactionArtifacts, isTrue);

        final verification = await stage.finish();
        expect(await verification.readExact(offset: 0, length: 4), <int>[
          1,
          2,
          3,
          4,
        ]);
        await expectLater(stage.replaceLive(), throwsStateError);
        await verification.close();
        await stage.replaceLive();
      });

      expect(_mode(root.path), 0x1c0);
      expect(_mode('${root.path}/$_lockName'), 0x180);
      expect(_mode('${root.path}/$_liveName'), 0x180);
      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);

      final pin = await files.openPinnedLive();
      final live = pin!;
      try {
        expect(live.length, 4);
        expect(await live.readExact(offset: 1, length: 2), <int>[2, 3]);
        expect(await live.readExact(offset: 4, length: 0), isEmpty);
        await expectLater(
          live.readExact(offset: 3, length: 2),
          throwsA(_failure(StoreFilesFailureCode.operationFailed)),
        );
      } finally {
        await live.close();
      }
      await live.close();
      await expectLater(
        live.readExact(offset: 0, length: 0),
        throwsA(_failure(StoreFilesFailureCode.pinnedFileClosed)),
      );
    },
  );

  test(
    'an opened descriptor remains pinned across atomic replacement',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);
      await _replace(files, <int>[1, 2, 3]);

      final oldPin = await files.openPinnedLive();
      expect(oldPin, isNotNull);
      await _replace(files, <int>[7, 8, 9]);
      final newPin = await files.openPinnedLive();
      try {
        expect(await oldPin!.readExact(offset: 0, length: 3), <int>[1, 2, 3]);
        expect(await newPin!.readExact(offset: 0, length: 3), <int>[7, 8, 9]);
      } finally {
        await oldPin?.close();
        await newPin?.close();
      }
    },
  );

  test(
    'aborts an uncommitted stage and never adopts an abandoned stage',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);

      await files.withExclusiveTransaction((transaction) async {
        final stage = await transaction.createStaging(expectedLength: 1);
        await stage.append(Uint8List.fromList(<int>[4]));
      });
      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);

      File('${root.path}/$_stagingName').writeAsBytesSync(<int>[9]);
      _chmod('0600', '${root.path}/$_stagingName');
      await files.withExclusiveTransaction((transaction) async {
        final artifacts = await transaction.observeArtifacts();
        expect(artifacts.hasTransactionArtifacts, isTrue);
        await expectLater(
          transaction.createStaging(expectedLength: 1),
          throwsA(_failure(StoreFilesFailureCode.operationFailed)),
        );
        await transaction.resetManagedArtifacts();
      });
      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);
    },
  );

  test(
    'durably discards only abandoned staging beside a live generation',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);
      await _replace(files, <int>[1, 2]);
      final live = File('${root.path}/$_liveName');
      final original = live.readAsBytesSync();
      File('${root.path}/$_stagingName').writeAsBytesSync(<int>[9]);
      _chmod('0600', '${root.path}/$_stagingName');

      await files.withExclusiveTransaction((transaction) async {
        final pin = await transaction.openPinnedLive();
        expect(await pin!.readExact(offset: 0, length: 2), <int>[1, 2]);
        await transaction.discardAbandonedStaging();
        expect(await pin.readExact(offset: 0, length: 2), <int>[1, 2]);
        await pin.close();
      });

      expect(live.readAsBytesSync(), original);
      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);

      final stageOnlyRoot = Directory('${fixture.path}/stage-only');
      final stageOnlyFiles = _files(stageOnlyRoot);
      await stageOnlyFiles.withExclusiveTransaction((_) async {});
      final abandoned = File('${stageOnlyRoot.path}/$_stagingName')
        ..writeAsBytesSync(<int>[8]);
      _chmod('0600', abandoned.path);
      await expectLater(
        stageOnlyFiles.withExclusiveTransaction(
          (transaction) => transaction.discardAbandonedStaging(),
        ),
        throwsA(_failure(StoreFilesFailureCode.operationFailed)),
      );
      expect(abandoned.existsSync(), isTrue);
    },
  );

  test(
    'preserves callback failure precedence and expires capabilities',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);
      final primary = StateError('primary test failure');
      late StoreTransaction transaction;
      late StagedStoreFile stage;

      await expectLater(
        files.withExclusiveTransaction<void>((current) async {
          transaction = current;
          stage = await current.createStaging(expectedLength: 1);
          await stage.append(Uint8List.fromList(<int>[3]));
          throw primary;
        }),
        throwsA(same(primary)),
      );

      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);
      await expectLater(transaction.observeArtifacts(), throwsStateError);
      await expectLater(
        stage.append(Uint8List.fromList(<int>[4])),
        throwsStateError,
      );
      await files.withExclusiveTransaction((_) async {});
    },
  );

  test(
    'bounds staging before creation and preserves live on underfill',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);
      await _replace(files, <int>[8, 9]);

      await files.withExclusiveTransaction((transaction) async {
        await expectLater(
          transaction.createStaging(expectedLength: 0),
          throwsRangeError,
        );
        final stage = await transaction.createStaging(expectedLength: 2);
        await expectLater(
          stage.append(Uint8List.fromList(<int>[1, 2, 3])),
          throwsA(_failure(StoreFilesFailureCode.operationFailed)),
        );
        await stage.append(Uint8List.fromList(<int>[1]));
        await expectLater(
          stage.finish(),
          throwsA(_failure(StoreFilesFailureCode.operationFailed)),
        );
      });

      final pin = await files.openPinnedLive();
      try {
        expect(await pin!.readExact(offset: 0, length: 2), <int>[8, 9]);
      } finally {
        await pin?.close();
      }
    },
  );

  test(
    'finish pins measured staged length and rejects out-of-band resizing',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);

      await files.withExclusiveTransaction((transaction) async {
        final stage = await transaction.createStaging(expectedLength: 2);
        await stage.append(Uint8List.fromList(<int>[1, 2]));
        File(
          '${root.path}/$_stagingName',
        ).writeAsBytesSync(<int>[3], mode: FileMode.append, flush: true);
        await expectLater(
          stage.finish(),
          throwsA(_failure(StoreFilesFailureCode.operationFailed)),
        );
      });

      await files.withExclusiveTransaction((transaction) async {
        final stage = await transaction.createStaging(expectedLength: 2);
        await stage.append(Uint8List.fromList(<int>[1, 2]));
        File('${root.path}/$_stagingName').writeAsBytesSync(<int>[]);
        await expectLater(
          stage.finish(),
          throwsA(_failure(StoreFilesFailureCode.operationFailed)),
        );
      });
      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);
    },
  );

  test('rejects redirected or loose artifacts without chmod on read', () async {
    final root = Directory('${fixture.path}/store');
    final files = _files(root);
    await files.withExclusiveTransaction((_) async {});

    final target = File('${fixture.path}/target')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    Link('${root.path}/$_liveName').createSync(target.path);
    await expectLater(
      files.openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    Link('${root.path}/$_liveName').deleteSync();

    final live = File('${root.path}/$_liveName')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    _chmod('0600', live.path);
    final unchangedBefore = live.statSync().changed;
    final pin = await files.openPinnedLive();
    await pin!.close();
    expect(live.statSync().changed, unchangedBefore);

    _chmod('0644', live.path);
    final looseBefore = live.statSync().changed;
    await expectLater(
      files.openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_mode(live.path), 0x1a4);
    expect(live.statSync().changed, looseBefore);

    final lock = File('${root.path}/$_lockName');
    _chmod('0644', lock.path);
    await expectLater(
      files.withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_mode(lock.path), 0x1a4);

    _chmod('0600', lock.path);
    _chmod('0755', root.path);
    await expectLater(
      files.openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_mode(root.path), 0x1ed);
  });

  test('strips inherited ACLs from creations and rejects later ACLs', () async {
    final parent = Directory('${fixture.path}/acl-parent')..createSync();
    _chmod('0700', parent.path);
    if (!_tryAddAcl(
      parent.path,
      'everyone allow read,execute,file_inherit,directory_inherit',
    )) {
      markTestSkipped('the fixture file system does not support Darwin ACLs');
      return;
    }

    final root = Directory('${parent.path}/store');
    final files = _files(root);
    await files.withExclusiveTransaction((transaction) async {
      expect(_hasExtendedAcl(root.path), isFalse);
      expect(_hasExtendedAcl('${root.path}/$_lockName'), isFalse);

      final stage = await transaction.createStaging(expectedLength: 1);
      expect(_hasExtendedAcl('${root.path}/$_stagingName'), isFalse);
      await stage.append(Uint8List.fromList(<int>[1]));
      final verification = await stage.finish();
      await verification.close();
      await stage.replaceLive();
    });
    expect(_hasExtendedAcl(parent.path), isTrue);
    expect(_hasExtendedAcl('${root.path}/$_liveName'), isFalse);

    _addAcl('${root.path}/$_liveName', 'everyone allow read');
    await expectLater(
      files.openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_hasExtendedAcl('${root.path}/$_liveName'), isTrue);
    _removeAcl('${root.path}/$_liveName');

    _addAcl('${root.path}/$_lockName', 'everyone allow read');
    await expectLater(
      files.withExclusiveTransaction((_) async {}),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_hasExtendedAcl('${root.path}/$_lockName'), isTrue);
    _removeAcl('${root.path}/$_lockName');

    _addAcl(root.path, 'everyone allow read');
    await expectLater(
      files.openPinnedLive(),
      throwsA(_failure(StoreFilesFailureCode.operationFailed)),
    );
    expect(_hasExtendedAcl(root.path), isTrue);
  }, skip: Platform.isMacOS ? false : 'Darwin extended ACLs only');

  test(
    'reset revokes the live name while an old pin remains immutable',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);
      await _replace(files, <int>[5, 6]);
      final pin = await files.openPinnedLive();

      await files.withExclusiveTransaction((transaction) async {
        await transaction.resetManagedArtifacts();
      });

      expect(File('${root.path}/$_liveName').existsSync(), isFalse);
      expect(File('${root.path}/$_stagingName').existsSync(), isFalse);
      expect(File('${root.path}/$_lockName').existsSync(), isTrue);
      expect(await files.openPinnedLive(), isNull);
      try {
        expect(await pin!.readExact(offset: 0, length: 2), <int>[5, 6]);
      } finally {
        await pin?.close();
      }

      await files.withExclusiveTransaction((transaction) async {
        expect((await transaction.observeArtifacts()).isAbsent, isTrue);
        await transaction.resetManagedArtifacts();
      });
    },
  );

  test('reset classifies failures on either side of live revocation', () async {
    final root = Directory('${fixture.path}/store');
    final files = _files(root);
    await files.withExclusiveTransaction((_) async {});

    final invalidLive = Directory('${root.path}/$_liveName')..createSync();
    await expectLater(
      files.withExclusiveTransaction(
        (transaction) => transaction.resetManagedArtifacts(),
      ),
      throwsA(_failure(StoreFilesFailureCode.resetNotStarted)),
    );
    expect(invalidLive.existsSync(), isTrue);
    invalidLive.deleteSync();

    Directory('${root.path}/$_stagingName').createSync();

    await expectLater(
      files.withExclusiveTransaction(
        (transaction) => transaction.resetManagedArtifacts(),
      ),
      throwsA(_failure(StoreFilesFailureCode.resetNotStarted)),
    );

    Directory('${root.path}/$_stagingName').deleteSync();
    await _replace(files, <int>[1]);
    Directory('${root.path}/$_stagingName').createSync();

    await expectLater(
      files.withExclusiveTransaction(
        (transaction) => transaction.resetManagedArtifacts(),
      ),
      throwsA(_failure(StoreFilesFailureCode.resetIncomplete)),
    );
    expect(File('${root.path}/$_liveName').existsSync(), isFalse);
    expect(Directory('${root.path}/$_stagingName').existsSync(), isTrue);
  });

  test(
    'the fixed flock excludes a separate process under the bounded policy',
    () async {
      final root = Directory('${fixture.path}/store');
      final files = _files(root);
      await files.withExclusiveTransaction((_) async {});

      final ready = File('${fixture.path}/ready');
      final release = File('${fixture.path}/release');
      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/keybay.dart'),
      );
      if (packageLibrary == null) fail('could not resolve package:keybay');
      final packageRoot = File.fromUri(packageLibrary).parent.parent;
      final worker = File(
        '${packageRoot.path}/test/support/v2_posix_store_files_worker.dart',
      );
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        worker.path,
        root.path,
        ready.path,
        release.path,
      ], workingDirectory: packageRoot.path);
      addTearDown(process.kill);
      final standardError = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      await _waitFor(ready);

      await expectLater(
        files.withExclusiveTransaction((_) async {}),
        throwsA(_failure(StoreFilesFailureCode.busy)),
      );
      release.writeAsStringSync('release');
      expect(await process.exitCode, 0, reason: await standardError);

      await files.withExclusiveTransaction((_) async {});
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );
}

Future<void> _replace(PosixStoreFiles files, List<int> bytes) =>
    files.withExclusiveTransaction((transaction) async {
      final stage = await transaction.createStaging(
        expectedLength: bytes.length,
      );
      await stage.append(Uint8List.fromList(bytes));
      final verification = await stage.finish();
      await verification.close();
      await stage.replaceLive();
    });

Future<T> _withProviderLock<T>(
  Directory runtime,
  Future<T> Function() operation,
) => PosixStoreFiles.withLinuxSecretServiceCreationLock(
  canonicalRuntimeDirectory: Uri.directory(runtime.path),
  providerAddress: _providerAddress,
  timeout: const Duration(seconds: 1),
  operation: operation,
);

PosixStoreFiles _files(Directory root) {
  final canonicalRoot = Uri.directory(root.absolute.path);
  return PosixStoreFiles(
    binding: _binding(root),
    canonicalFileRoot: canonicalRoot,
  );
}

PosixStoreFiles _directFiles(Directory root) {
  final canonicalRoot = Uri.directory(root.absolute.path);
  return PosixStoreFiles.fromExistingPrivateRoot(
    binding: _binding(root),
    canonicalFileRoot: canonicalRoot,
  );
}

ResolvedApplicationBinding _binding(Directory root) {
  final canonicalRoot = Uri.directory(root.absolute.path);
  return ResolvedApplicationBinding.derive(
    identity: ApplicationIdentity(
      stableValue: 'dev.keybay.posix-store-files-test',
      source: ApplicationIdentitySource.test,
      assurance: ApplicationIdentityAssurance.namespaceOnly,
    ),
    profile: HostProfile('test.posix-store-files'),
    canonicalFileRoot: canonicalRoot,
  );
}

Matcher _failure(StoreFilesFailureCode code) =>
    isA<StoreFilesFailure>().having((failure) => failure.code, 'code', code);

// Read-only F_GETFD observes the exact descriptor handed to the failure probe.
// These calls do not replace or mock the production filesystem operations.
final _descriptorControl = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'fcntl',
    );
final _descriptorErrno = DynamicLibrary.process()
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );
final _closeTestDescriptor = DynamicLibrary.process()
    .lookupFunction<Int32 Function(Int32), int Function(int)>('close');

int _descriptorFlags(int descriptor) => _descriptorControl(descriptor, 1);

int _mode(String path) => File(path).statSync().mode & 0x1ff;

void _chmod(String mode, String path) {
  final result = Process.runSync('chmod', <String>[mode, path]);
  if (result.exitCode != 0) fail('chmod failed for a disposable fixture');
}

bool _tryAddAcl(String path, String rule) =>
    Process.runSync('chmod', <String>['+a', rule, path]).exitCode == 0;

void _addAcl(String path, String rule) {
  if (!_tryAddAcl(path, rule)) fail('could not add a disposable fixture ACL');
}

void _removeAcl(String path) {
  final result = Process.runSync('chmod', <String>['-N', path]);
  if (result.exitCode != 0) fail('could not remove a disposable fixture ACL');
}

bool _hasExtendedAcl(String path) {
  final result = Process.runSync('ls', <String>['-lde', path]);
  if (result.exitCode != 0) fail('could not inspect a disposable fixture ACL');
  return RegExp(r'^\s+\d+:', multiLine: true).hasMatch('${result.stdout}');
}

Future<void> _waitFor(File marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!marker.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('POSIX store worker did not acquire its lock');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

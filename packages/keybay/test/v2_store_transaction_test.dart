import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';

void main() {
  group('V2 store transaction boundary', () {
    test('admits one callback and expires its capability', () async {
      final files = _files();
      final entered = Completer<void>();
      final release = Completer<void>();
      late StoreTransaction expired;

      final first = files.withExclusiveTransaction((transaction) async {
        expired = transaction;
        entered.complete();
        await release.future;
      });
      await entered.future;

      await expectLater(
        files.withExclusiveTransaction((_) async {}),
        throwsA(_storeFailure(StoreFilesFailureCode.busy)),
      );
      release.complete();
      await first;

      await expectLater(expired.observeArtifacts(), throwsStateError);
    });

    test(
      'stages sequential bytes and installs only after verification closes',
      () async {
        final files = _files(liveBytes: <int>[9, 9]);

        await files.withExclusiveTransaction((transaction) async {
          final stage = await transaction.createStaging(expectedLength: 4);
          final callerBytes = Uint8List.fromList(<int>[1, 2]);
          final appending = stage.append(callerBytes);
          callerBytes.fillRange(0, callerBytes.length, 0);
          await appending;
          await stage.append(Uint8List.fromList(<int>[3, 4]));

          expect(
            (await transaction.observeArtifacts()).hasTransactionArtifacts,
            isTrue,
          );
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

        expect(
          (await files.observeArtifacts()).hasTransactionArtifacts,
          isFalse,
        );
        final live = await files.openPinnedLive();
        expect(live, isNotNull);
        try {
          expect(await live!.readExact(offset: 0, length: live.length), <int>[
            1,
            2,
            3,
            4,
          ]);
        } finally {
          await live?.close();
        }
      },
    );

    test(
      'same-domain adapters share the lock, staging, and live target',
      () async {
        final binding = _binding();
        final backing = MemoryPinnedStoreBacking(binding);
        final files = MemoryPinnedStoreFiles(
          binding,
          backing: backing,
          liveBytes: <int>[7, 8],
        );
        final peer = MemoryPinnedStoreFiles(binding, backing: backing);

        await files.withExclusiveTransaction((transaction) async {
          await transaction.createStaging(expectedLength: 1);
          await expectLater(
            peer.withExclusiveTransaction((_) async {}),
            throwsA(_storeFailure(StoreFilesFailureCode.busy)),
          );
          final live = await peer.openPinnedLive();
          expect(live, isNotNull);
          try {
            expect(await live!.readExact(offset: 0, length: live.length), <int>[
              7,
              8,
            ]);
          } finally {
            await live?.close();
          }
        });

        await peer.withExclusiveTransaction((transaction) async {
          expect(
            (await transaction.observeArtifacts()).hasTransactionArtifacts,
            isFalse,
          );
        });

        await files.withExclusiveTransaction((transaction) async {
          final stage = await transaction.createStaging(expectedLength: 2);
          await stage.append(Uint8List.fromList(<int>[9, 10]));
          final verification = await stage.finish();
          await verification.close();
          await stage.replaceLive();
        });
        final replaced = await peer.openPinnedLive();
        try {
          expect(await replaced!.readExact(offset: 0, length: 2), <int>[9, 10]);
        } finally {
          await replaced?.close();
        }

        await peer.withExclusiveTransaction(
          (transaction) => transaction.resetManagedArtifacts(),
        );
        await files.withExclusiveTransaction((transaction) async {
          expect((await transaction.observeArtifacts()).isAbsent, isTrue);
        });
      },
    );

    test('callback failure retains precedence and aborts its stage', () async {
      final files = _files(liveBytes: <int>[5]);
      final primary = StateError('primary test failure');

      await expectLater(
        files.withExclusiveTransaction((transaction) async {
          final stage = await transaction.createStaging(expectedLength: 1);
          await stage.append(Uint8List.fromList(<int>[6]));
          throw primary;
        }),
        throwsA(same(primary)),
      );

      expect((await files.observeArtifacts()).hasTransactionArtifacts, isFalse);
      final live = await files.openPinnedLive();
      try {
        expect(await live!.readExact(offset: 0, length: 1), <int>[5]);
      } finally {
        await live?.close();
      }
    });

    test(
      'cleanup failure is reported after clearing stage and releasing lock',
      () async {
        final files = _files(liveBytes: <int>[5]);
        files.stageAbortFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );

        await expectLater(
          files.withExclusiveTransaction((transaction) async {
            final stage = await transaction.createStaging(expectedLength: 1);
            await stage.append(Uint8List.fromList(<int>[6]));
          }),
          throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
        );
        expect(
          (await files.observeArtifacts()).hasTransactionArtifacts,
          isFalse,
        );

        files.stageAbortFailure = null;
        await files.withExclusiveTransaction((_) async {});
      },
    );

    test('primary callback failure wins over abort cleanup failure', () async {
      final files = _files(liveBytes: <int>[5]);
      final primary = StateError('primary test failure');
      files.stageAbortFailure = const StoreFilesFailure(
        StoreFilesFailureCode.operationFailed,
      );

      await expectLater(
        files.withExclusiveTransaction((transaction) async {
          await transaction.createStaging(expectedLength: 1);
          throw primary;
        }),
        throwsA(same(primary)),
      );
      expect((await files.observeArtifacts()).hasTransactionArtifacts, isFalse);

      files.stageAbortFailure = null;
      await files.withExclusiveTransaction((_) async {});
    });

    test(
      'automatic abort closes a finished-stage pin despite close failure',
      () async {
        final files = _files(liveBytes: <int>[5]);
        files.stagingPinCloseFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );

        await expectLater(
          files.withExclusiveTransaction((transaction) async {
            final stage = await transaction.createStaging(expectedLength: 1);
            await stage.append(Uint8List.fromList(<int>[6]));
            await stage.finish();
          }),
          throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
        );
        expect(
          (await files.observeArtifacts()).hasTransactionArtifacts,
          isFalse,
        );

        files.stagingPinCloseFailure = null;
        await files.withExclusiveTransaction((_) async {});
      },
    );

    test('a stage capability expires when its transaction ends', () async {
      final files = _files();
      late StagedStoreFile expired;

      await files.withExclusiveTransaction((transaction) async {
        expired = await transaction.createStaging(expectedLength: 1);
      });

      await expectLater(
        expired.append(Uint8List.fromList(<int>[1])),
        throwsStateError,
      );
    });

    test(
      'existing staging is never adopted and reset uses the same lock',
      () async {
        final files = _files(
          liveBytes: <int>[1],
          hasTransactionArtifacts: true,
        );

        await files.withExclusiveTransaction((transaction) async {
          await expectLater(
            transaction.createStaging(expectedLength: 1),
            throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
          );
          await transaction.resetManagedArtifacts();
        });

        expect((await files.observeArtifacts()).isAbsent, isTrue);
      },
    );

    test(
      'discarding abandoned staging preserves the pinned live generation',
      () async {
        final files = _files(
          liveBytes: <int>[1, 2],
          hasTransactionArtifacts: true,
        );

        await files.withExclusiveTransaction((transaction) async {
          final live = await transaction.openPinnedLive();
          expect(await live!.readExact(offset: 0, length: 2), <int>[1, 2]);
          await transaction.discardAbandonedStaging();
          expect(await live.readExact(offset: 0, length: 2), <int>[1, 2]);
          await live.close();

          final artifacts = await transaction.observeArtifacts();
          expect(artifacts.hasLiveFile, isTrue);
          expect(artifacts.hasTransactionArtifacts, isFalse);
        });

        final stageOnly = _files(hasTransactionArtifacts: true);
        await expectLater(
          stageOnly.withExclusiveTransaction(
            (transaction) => transaction.discardAbandonedStaging(),
          ),
          throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
        );
        expect(
          (await stageOnly.observeArtifacts()).hasTransactionArtifacts,
          isTrue,
        );
      },
    );

    test(
      'reset failure before revocation changes no managed artifact',
      () async {
        final files = _files(liveBytes: <int>[1], hasTransactionArtifacts: true)
          ..failResetBeforeLiveRevocation = true;

        await expectLater(
          files.withExclusiveTransaction(
            (transaction) => transaction.resetManagedArtifacts(),
          ),
          throwsA(_storeFailure(StoreFilesFailureCode.resetNotStarted)),
        );

        final artifacts = await files.observeArtifacts();
        expect(artifacts.hasLiveFile, isTrue);
        expect(artifacts.hasTransactionArtifacts, isTrue);
      },
    );

    test(
      'post-revocation reset failure cannot leave live authoritative',
      () async {
        final files = _files(liveBytes: <int>[1], hasTransactionArtifacts: true)
          ..failResetAfterLiveRevocation = true;

        await expectLater(
          files.withExclusiveTransaction(
            (transaction) => transaction.resetManagedArtifacts(),
          ),
          throwsA(_storeFailure(StoreFilesFailureCode.resetIncomplete)),
        );

        final artifacts = await files.observeArtifacts();
        expect(artifacts.hasLiveFile, isFalse);
        expect(artifacts.hasTransactionArtifacts, isTrue);
      },
    );

    test(
      'rejects overflow and underfilled staging without changing live',
      () async {
        final files = _files(liveBytes: <int>[4]);

        await files.withExclusiveTransaction((transaction) async {
          final stage = await transaction.createStaging(expectedLength: 2);
          await expectLater(
            stage.append(Uint8List.fromList(<int>[1, 2, 3])),
            throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
          );
          await stage.append(Uint8List.fromList(<int>[1]));
          await expectLater(
            stage.finish(),
            throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
          );
        });

        expect(
          (await files.observeArtifacts()).hasTransactionArtifacts,
          isFalse,
        );
        final live = await files.openPinnedLive();
        try {
          expect(await live!.readExact(offset: 0, length: 1), <int>[4]);
        } finally {
          await live?.close();
        }
      },
    );

    test(
      'validates expected length before creating a staging artifact',
      () async {
        final files = _files();

        await files.withExclusiveTransaction((transaction) async {
          await expectLater(
            transaction.createStaging(expectedLength: 0),
            throwsRangeError,
          );
          await expectLater(
            transaction.createStaging(
              expectedLength: V2StoreLimits.storeBytes + 1,
            ),
            throwsRangeError,
          );
          await transaction.createStaging(
            expectedLength: V2StoreLimits.storeBytes,
          );
        });

        expect((await files.observeArtifacts()).isAbsent, isTrue);
      },
    );
  });
}

MemoryPinnedStoreFiles _files({
  List<int>? liveBytes,
  bool hasTransactionArtifacts = false,
}) => MemoryPinnedStoreFiles(
  _binding(),
  liveBytes: liveBytes,
  hasTransactionArtifacts: hasTransactionArtifacts,
);

ResolvedApplicationBinding _binding() => ResolvedApplicationBinding.derive(
  identity: ApplicationIdentity(
    stableValue: 'dev.keybay.transaction-test',
    source: ApplicationIdentitySource.test,
    assurance: ApplicationIdentityAssurance.namespaceOnly,
  ),
  profile: HostProfile('transaction-test'),
  canonicalFileRoot: Uri.parse('file:///keybay-test/transaction/'),
);

Matcher _storeFailure(StoreFilesFailureCode code) =>
    isA<StoreFilesFailure>().having((failure) => failure.code, 'code', code);

@Tags(['unit'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/entropy_source.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show
        V2PassphraseDeriver,
        V2PassphraseDerivationFailure,
        V2PassphraseDerivationFailureCode,
        V2StoreEngine,
        V2StoreEngineTestProbe,
        V2StoreSession,
        debugStoreSessionKeyIsCleared;
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_fakes.dart';
import 'package:keybay/src/v2/platform_protector.dart';

void main() {
  group('M6 persistent open policy', () {
    test('protected first use implements the strict open matrix', () async {
      final deriver = _FastPassphraseDeriver();
      final environment = _Environment(deriver: deriver);
      addTearDown(environment.dispose);

      final original = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final phrase = Uint8List.fromList(original);
      final opening = environment.engine.open(
        credential: PassphraseCredential(phrase: phrase),
      );
      phrase.fillRange(0, phrase.length, 0);
      final initialized = await opening;
      addTearDown(initialized.close);

      expect(initialized.wasInitialized, isTrue);
      expect(deriver.seenPassphrases.single, original);
      expect(deriver.lastBorrowedInputIsCleared, isTrue);
      await initialized.set('service/token', 'preserved');
      await initialized.close();
      environment.files.hasTransactionArtifacts = true;

      await expectLater(
        environment.engine.open(),
        throwsA(_keybayFailure(KeybayErrorCode.authRequired)),
      );
      expect(environment.files.hasTransactionArtifacts, isTrue);
      await expectLater(
        environment.engine.open(credential: _credential(<int>[9, 9, 9, 9])),
        throwsA(_keybayFailure(KeybayErrorCode.unlockFailed)),
      );
      expect(deriver.lastBorrowedInputIsCleared, isTrue);
      expect(environment.files.hasTransactionArtifacts, isTrue);

      final reopened = await environment.engine.open(
        credential: _credential(original),
      );
      addTearDown(reopened.close);
      expect(environment.files.hasTransactionArtifacts, isFalse);
      expect(reopened.wasInitialized, isFalse);
      expect(await reopened.get('service/token'), 'preserved');
    });

    test(
      'a credential never upgrades an existing platform-only store',
      () async {
        final environment = _Environment();
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');
        environment.files.hasTransactionArtifacts = true;

        await expectLater(
          environment.engine.open(credential: _credential(<int>[1, 2, 3])),
          throwsA(_keybayFailure(KeybayErrorCode.protectionMismatch)),
        );

        expect(environment.files.hasTransactionArtifacts, isTrue);
        expect(await owner.get('service/token'), 'preserved');
        expect(await owner.auth.list(), isEmpty);
        final reopened = await environment.engine.open();
        addTearDown(reopened.close);
        expect(environment.files.hasTransactionArtifacts, isFalse);
        expect(reopened.wasInitialized, isFalse);
        expect(await reopened.get('service/token'), 'preserved');
      },
    );
  });

  test(
    'auth CRUD preserves data, reseals every frame, and invalidates peers',
    () async {
      final deriver = _FastPassphraseDeriver();
      final environment = _Environment(deriver: deriver);
      addTearDown(environment.dispose);
      final owner = await environment.engine.open();
      addTearDown(owner.close);
      await owner.set('alpha/value', 'alpha');
      await owner.set('middle/value', 'bravo');
      await owner.set('zulu/value', 'charl');

      final platformPeer = await environment.engine.open();
      addTearDown(platformPeer.close);
      final beforeAdd = await _copyLive(environment.files);
      final addPhrase = Uint8List.fromList(<int>[1, 2, 3]);
      final adding = owner.auth.add(PassphraseCredential(phrase: addPhrase));
      addPhrase.fillRange(0, addPhrase.length, 0);
      final added = await adding;
      final afterAdd = await _copyLive(environment.files);
      try {
        expect(added, isA<PassphraseMethod>());
        expect(added.id, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(deriver.lastBorrowedInputIsCleared, isTrue);
        _expectEveryFrameResealed(beforeAdd, afterAdd);
      } finally {
        _clear(beforeAdd);
        _clear(afterAdd);
      }
      await _expectRecords(owner);
      expect(debugStoreSessionKeyIsCleared(platformPeer), isTrue);
      await expectLater(
        platformPeer.get('alpha/value'),
        throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
      );

      final listed = await owner.auth.list();
      expect(listed, hasLength(1));
      expect(listed.single, isA<PassphraseMethod>());
      expect(listed.single.id, added.id);
      expect(() => listed.add(added), throwsUnsupportedError);
      await expectLater(
        owner.auth.add(_credential(<int>[7, 7, 7])),
        throwsA(_keybayFailure(KeybayErrorCode.authMethodAlreadyConfigured)),
      );

      final passphrasePeer = await environment.engine.open(
        credential: _credential(<int>[1, 2, 3]),
      );
      addTearDown(passphrasePeer.close);
      final beforeUpdate = await _copyLive(environment.files);
      final replacement = Uint8List.fromList(<int>[4, 5, 6]);
      final updating = owner.auth.update(
        PassphraseCredential(phrase: replacement),
      );
      replacement.fillRange(0, replacement.length, 0);
      final updated = await updating;
      final afterUpdate = await _copyLive(environment.files);
      try {
        expect(updated.id, added.id);
        expect(deriver.lastBorrowedInputIsCleared, isTrue);
        _expectEveryFrameResealed(beforeUpdate, afterUpdate);
      } finally {
        _clear(beforeUpdate);
        _clear(afterUpdate);
      }
      await _expectRecords(owner);
      expect(debugStoreSessionKeyIsCleared(passphrasePeer), isTrue);
      await expectLater(
        passphrasePeer.contains('alpha/value'),
        throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
      );
      await expectLater(
        environment.engine.open(credential: _credential(<int>[1, 2, 3])),
        throwsA(_keybayFailure(KeybayErrorCode.unlockFailed)),
      );

      final replacementPeer = await environment.engine.open(
        credential: _credential(<int>[4, 5, 6]),
      );
      addTearDown(replacementPeer.close);
      await expectLater(
        owner.auth.remove('0' * 32),
        throwsA(_keybayFailure(KeybayErrorCode.authMethodNotConfigured)),
      );
      expect((await owner.auth.list()).single.id, added.id);

      final beforeRemove = await _copyLive(environment.files);
      await owner.auth.remove(added.id);
      final afterRemove = await _copyLive(environment.files);
      try {
        _expectEveryFrameResealed(beforeRemove, afterRemove);
      } finally {
        _clear(beforeRemove);
        _clear(afterRemove);
      }
      expect(await owner.auth.list(), isEmpty);
      await _expectRecords(owner);
      expect(debugStoreSessionKeyIsCleared(replacementPeer), isTrue);
      await expectLater(
        replacementPeer.get('alpha/value'),
        throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
      );
      await expectLater(
        environment.engine.open(credential: _credential(<int>[4, 5, 6])),
        throwsA(_keybayFailure(KeybayErrorCode.protectionMismatch)),
      );

      final platformOnly = await environment.engine.open();
      addTearDown(platformOnly.close);
      await _expectRecords(platformOnly);
      await expectLater(
        owner.auth.remove(added.id),
        throwsA(_keybayFailure(KeybayErrorCode.authMethodNotConfigured)),
      );
    },
  );

  test(
    'separate engines classify every auth rotation as a stale session',
    () async {
      final deriver = _FastPassphraseDeriver();
      final environment = _Environment(deriver: deriver);
      addTearDown(environment.dispose);
      final owner = await environment.engine.open();
      addTearDown(owner.close);
      await owner.set('service/token', 'preserved');

      final beforeAdd = await environment.separateEngine(deriver).open();
      addTearDown(beforeAdd.close);
      final added = await owner.auth.add(_credential(<int>[1, 2, 3]));
      await _expectCrossEngineAuthListFailure(beforeAdd);

      final beforeUpdate = await environment
          .separateEngine(deriver)
          .open(credential: _credential(<int>[1, 2, 3]));
      addTearDown(beforeUpdate.close);
      final updated = await owner.auth.update(_credential(<int>[4, 5, 6]));
      expect(updated.id, added.id);
      await _expectCrossEngineAuthenticationFailure(beforeUpdate);

      final beforeRemove = await environment
          .separateEngine(deriver)
          .open(credential: _credential(<int>[4, 5, 6]));
      addTearDown(beforeRemove.close);
      await owner.auth.remove(added.id);
      await _expectCrossEngineAuthenticationFailure(beforeRemove);

      expect(await owner.get('service/token'), 'preserved');
    },
  );

  group('M6 adversarial auth lifecycle', () {
    test('releases the credential snapshot before staging can pause', () async {
      final deriver = _FastPassphraseDeriver();
      final environment = _Environment(deriver: deriver);
      addTearDown(environment.dispose);
      final owner = await environment.engine.open();
      addTearDown(owner.close);

      final stageReached = Completer<void>();
      final releaseStage = Completer<void>();
      addTearDown(() {
        if (!releaseStage.isCompleted) releaseStage.complete();
      });
      environment.files.beforeStageFinish = () async {
        if (!stageReached.isCompleted) stageReached.complete();
        await releaseStage.future;
      };

      final callerPhrase = Uint8List.fromList(<int>[1, 3, 3, 7]);
      final adding = owner.auth.add(PassphraseCredential(phrase: callerPhrase));
      callerPhrase.fillRange(0, callerPhrase.length, 0);
      await stageReached.future;
      final kdfRanBeforeStage = deriver.seenPassphrases.isNotEmpty;
      final snapshotWasClearedWhilePaused = deriver.lastBorrowedInputIsCleared;
      releaseStage.complete();
      final added = await adding;
      environment.files.beforeStageFinish = null;

      expect(kdfRanBeforeStage, isTrue);
      expect(snapshotWasClearedWhilePaused, isTrue);
      expect((await owner.auth.list()).single.id, added.id);
    });

    test(
      'an open pinned before rotation fails after generation advances',
      () async {
        final deriver = _FastPassphraseDeriver();
        final probe = V2StoreEngineTestProbe();
        final environment = _Environment(deriver: deriver, probe: probe);
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');

        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        addTearDown(() {
          if (!releaseRead.isCompleted) releaseRead.complete();
        });
        environment.files.beforeRead = (_, __) {
          if (!readStarted.isCompleted) readStarted.complete();
        };
        environment.files.gateNextRead(releaseRead.future);

        final opening = environment.engine.open();
        final openingFailure = expectLater(
          opening,
          throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
        );
        await readStarted.future;
        await owner.auth.add(_credential(<int>[2, 4, 6, 8]));
        releaseRead.complete();
        await openingFailure;
        environment.files.beforeRead = null;

        expect(probe.failedOpenKeyMaterialWasCleared, isTrue);
        expect(await owner.get('service/token'), 'preserved');
      },
    );

    test(
      'pre-replacement failure preserves old policy, data, and sessions',
      () async {
        final environment = _Environment();
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');
        final peer = await environment.engine.open();
        addTearDown(peer.close);
        final generation = environment.files.liveGeneration;
        final before = await _copyLive(environment.files);
        environment.files.beforeReplaceLive = _failStorage;

        await expectLater(
          owner.auth.add(_credential(<int>[3, 1, 4, 1, 5])),
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        environment.files.beforeReplaceLive = null;
        final after = await _copyLive(environment.files);
        try {
          expect(environment.files.liveGeneration, generation);
          expect(environment.files.hasTransactionArtifacts, isFalse);
          expect(after, before);
        } finally {
          _clear(before);
          _clear(after);
        }

        expect(await owner.auth.list(), isEmpty);
        expect(await owner.get('service/token'), 'preserved');
        expect(await peer.get('service/token'), 'preserved');
        await expectLater(
          environment.engine.open(
            credential: _credential(<int>[3, 1, 4, 1, 5]),
          ),
          throwsA(_keybayFailure(KeybayErrorCode.protectionMismatch)),
        );
      },
    );

    test(
      'post-replacement error adopts the authenticated replacement',
      () async {
        final environment = _Environment();
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');
        final peer = await environment.engine.open();
        addTearDown(peer.close);
        environment.files.afterReplaceLive = _failStorage;

        await expectLater(
          owner.auth.add(_credential(<int>[5, 8, 13, 21])),
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        environment.files.afterReplaceLive = null;

        final methods = await owner.auth.list();
        expect(methods, hasLength(1));
        expect(await owner.get('service/token'), 'preserved');
        expect(debugStoreSessionKeyIsCleared(peer), isTrue);
        await expectLater(
          peer.get('service/token'),
          throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
        );
        await expectLater(
          environment.engine.open(),
          throwsA(_keybayFailure(KeybayErrorCode.authRequired)),
        );
        final reopened = await environment.engine.open(
          credential: _credential(<int>[5, 8, 13, 21]),
        );
        addTearDown(reopened.close);
        expect(await reopened.get('service/token'), 'preserved');
        expect((await reopened.auth.list()).single.id, methods.single.id);
      },
    );

    test(
      'classifier I/O failure immediately invalidates owner and peers',
      () async {
        final environment = _Environment();
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');
        final peer = await environment.engine.open();
        addTearDown(peer.close);

        var replacementInstalled = false;
        environment.files.beforeOpen = () {
          if (replacementInstalled) {
            throw const StoreFilesFailure(
              StoreFilesFailureCode.operationFailed,
            );
          }
        };
        environment.files.afterReplaceLive = () {
          replacementInstalled = true;
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        };

        await expectLater(
          owner.auth.add(_credential(<int>[9, 7, 5, 3, 1])),
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        environment.files.beforeOpen = null;
        environment.files.afterReplaceLive = null;

        expect(debugStoreSessionKeyIsCleared(owner), isTrue);
        expect(debugStoreSessionKeyIsCleared(peer), isTrue);
        await expectLater(
          owner.get('service/token'),
          throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
        );
        await expectLater(
          peer.get('service/token'),
          throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
        );

        final reopened = await environment.engine.open(
          credential: _credential(<int>[9, 7, 5, 3, 1]),
        );
        addTearDown(reopened.close);
        expect(await reopened.get('service/token'), 'preserved');
      },
    );

    test(
      'rotation rejects an older valid frame under the current manifest',
      () async {
        final environment = _Environment();
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);

        await owner.set('service/token', 'before');
        expect(await owner.get('service/token'), 'before');
        final oldSnapshot = await _copyLive(environment.files);
        final oldFrame = _extractFrames(oldSnapshot, const <int>[6]).single;
        final oldFrameOffset = _frameRegionOffset(oldSnapshot);

        await owner.set('service/token', 'after!');
        expect(await owner.get('service/token'), 'after!');
        final currentSnapshot = await _copyLive(environment.files);
        final currentFrame = _extractFrames(currentSnapshot, const <int>[
          6,
        ]).single;
        final frameOffset = _frameRegionOffset(currentSnapshot);
        final spliced = Uint8List.fromList(currentSnapshot);
        spliced.setRange(frameOffset, frameOffset + oldFrame.length, oldFrame);
        environment.files.replaceLiveBytes(spliced);

        final retained = await _copyLive(environment.files);
        final generation = environment.files.liveGeneration;
        var replacementReached = false;
        environment.files.beforeReplaceLive = () {
          replacementReached = true;
        };
        Uint8List? after;
        try {
          expect(currentSnapshot, hasLength(oldSnapshot.length));
          expect(frameOffset, oldFrameOffset);
          expect(
            Uint8List.sublistView(currentSnapshot, 0, frameOffset),
            Uint8List.sublistView(oldSnapshot, 0, oldFrameOffset),
            reason: 'ordinary writes must retain the same sealed key package',
          );
          expect(oldFrame, isNot(equals(currentFrame)));
          await expectLater(
            owner.auth.add(_credential(<int>[2, 7, 1, 8, 2, 8])),
            throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
          );
          after = await _copyLive(environment.files);
          expect(replacementReached, isFalse);
          expect(environment.files.liveGeneration, generation);
          expect(after, retained);
          expect(environment.files.hasTransactionArtifacts, isFalse);
        } finally {
          environment.files.beforeReplaceLive = null;
          _clear(oldSnapshot);
          _clear(oldFrame);
          _clear(currentSnapshot);
          _clear(currentFrame);
          _clear(spliced);
          _clear(retained);
          if (after != null) _clear(after);
        }
      },
    );
  });

  group('M6 KDF failure atomicity', () {
    test('protected first-use failure creates no root or file', () async {
      final deriver = _FastPassphraseDeriver()
        ..nextFailure = const V2PassphraseDerivationFailure(
          V2PassphraseDerivationFailureCode.operationFailed,
        );
      final environment = _Environment(deriver: deriver);
      addTearDown(environment.dispose);
      final callerPhrase = Uint8List.fromList(<int>[1, 2, 3]);
      final opening = environment.engine.open(
        credential: PassphraseCredential(phrase: callerPhrase),
      );
      callerPhrase.fillRange(0, callerPhrase.length, 0);

      await expectLater(
        opening,
        throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
      );

      expect(deriver.lastBorrowedInputIsCleared, isTrue);
      expect(environment.registry.rootCount, 0);
      expect(environment.files.hasLiveFile, isFalse);
      expect(environment.files.hasTransactionArtifacts, isFalse);
    });

    test('auth.add failure preserves platform-only state exactly', () async {
      final deriver = _FastPassphraseDeriver();
      final environment = _Environment(deriver: deriver);
      addTearDown(environment.dispose);
      final owner = await environment.engine.open();
      addTearDown(owner.close);
      await owner.set('service/token', 'preserved');
      final peer = await environment.engine.open();
      addTearDown(peer.close);
      final generation = environment.files.liveGeneration;
      final before = await _copyLive(environment.files);
      deriver.nextFailure = const V2PassphraseDerivationFailure(
        V2PassphraseDerivationFailureCode.operationFailed,
      );
      final callerPhrase = Uint8List.fromList(<int>[3, 1, 4]);
      final adding = owner.auth.add(PassphraseCredential(phrase: callerPhrase));
      callerPhrase.fillRange(0, callerPhrase.length, 0);

      await expectLater(
        adding,
        throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
      );
      final after = await _copyLive(environment.files);
      try {
        expect(after, before);
        expect(environment.files.liveGeneration, generation);
      } finally {
        _clear(before);
        _clear(after);
      }

      expect(deriver.lastBorrowedInputIsCleared, isTrue);
      expect(environment.files.hasTransactionArtifacts, isFalse);
      expect(await owner.auth.list(), isEmpty);
      expect(await owner.get('service/token'), 'preserved');
      expect(await peer.get('service/token'), 'preserved');
    });

    test(
      'auth.update failure preserves the old route and sessions exactly',
      () async {
        final deriver = _FastPassphraseDeriver();
        final environment = _Environment(deriver: deriver);
        addTearDown(environment.dispose);
        final owner = await environment.engine.open();
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');
        final method = await owner.auth.add(_credential(<int>[1, 2, 3]));
        final peer = await environment.engine.open(
          credential: _credential(<int>[1, 2, 3]),
        );
        addTearDown(peer.close);
        final generation = environment.files.liveGeneration;
        final before = await _copyLive(environment.files);
        deriver.nextFailure = const V2PassphraseDerivationFailure(
          V2PassphraseDerivationFailureCode.operationFailed,
        );
        final callerPhrase = Uint8List.fromList(<int>[4, 5, 6]);
        final updating = owner.auth.update(
          PassphraseCredential(phrase: callerPhrase),
        );
        callerPhrase.fillRange(0, callerPhrase.length, 0);

        await expectLater(
          updating,
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        final after = await _copyLive(environment.files);
        try {
          expect(after, before);
          expect(environment.files.liveGeneration, generation);
        } finally {
          _clear(before);
          _clear(after);
        }

        expect(deriver.lastBorrowedInputIsCleared, isTrue);
        expect(environment.files.hasTransactionArtifacts, isFalse);
        expect((await owner.auth.list()).single.id, method.id);
        expect(await owner.get('service/token'), 'preserved');
        expect(await peer.get('service/token'), 'preserved');
        final oldRoute = await environment.engine.open(
          credential: _credential(<int>[1, 2, 3]),
        );
        addTearDown(oldRoute.close);
        expect(await oldRoute.get('service/token'), 'preserved');
        await expectLater(
          environment.engine.open(credential: _credential(<int>[4, 5, 6])),
          throwsA(_keybayFailure(KeybayErrorCode.unlockFailed)),
        );
      },
    );
  });

  group('queued operation input cleanup', () {
    for (final invalidation in <String>['reset', 'peer auth rotation']) {
      test(
        '$invalidation clears inputs of operations that never start',
        () async {
          final capturedInputs = <Uint8List>[];
          final deriver = _FastPassphraseDeriver();
          final environment = _Environment(
            deriver: deriver,
            probe: V2StoreEngineTestProbe(onOperationInput: capturedInputs.add),
          );
          addTearDown(environment.dispose);
          final session = await environment.engine.open();
          addTearDown(session.close);
          final peer = await environment.engine.open();
          addTearDown(peer.close);
          await session.set('service/token', 'preserved');

          final readStarted = Completer<void>();
          final releaseRead = Completer<void>();
          addTearDown(() {
            if (!releaseRead.isCompleted) releaseRead.complete();
          });
          environment.files.beforeRead = (_, __) {
            if (!readStarted.isCompleted) readStarted.complete();
          };
          environment.files.gateNextRead(releaseRead.future);
          final reading = session.get('service/token');
          await readStarted.future;

          final inputStart = capturedInputs.length;
          final queuedRead = session.getManyBytes(<String>['service/token']);
          final value = Uint8List.fromList(<int>[11, 12, 13]);
          final queuedWrite = session.setBytes('service/next', value);
          final phrase = Uint8List.fromList(<int>[21, 22, 23]);
          final queuedAuth = session.auth.add(
            PassphraseCredential(phrase: phrase),
          );
          final queuedInputs = capturedInputs.sublist(inputStart);
          _clear(value);
          _clear(phrase);
          expect(queuedInputs, hasLength(4));
          expect(
            queuedInputs.every((bytes) => bytes.any((byte) => byte != 0)),
            isTrue,
          );
          final failures = <Future<void>>[
            for (final operation in <Future<Object?>>[
              queuedRead,
              queuedWrite,
              queuedAuth,
            ])
              expectLater(
                operation,
                throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
              ),
          ];

          final priorGeneration = environment.files.liveGeneration!;
          var invalidationFinished = false;
          final invalidating =
              (invalidation == 'reset'
                      ? environment.engine.reset()
                      : peer.auth.add(_credential(<int>[31, 32, 33])))
                  .whenComplete(() => invalidationFinished = true);
          await Future<void>.delayed(Duration.zero);
          expect(invalidationFinished, isFalse);
          if (invalidation == 'reset') {
            expect(environment.files.hasLiveFile, isFalse);
          } else {
            expect(
              environment.files.liveGeneration,
              greaterThan(priorGeneration),
            );
          }

          releaseRead.complete();
          expect(await reading, 'preserved');
          await Future.wait(failures);
          await invalidating;

          expect(queuedInputs, everyElement(everyElement(0)));
          expect(debugStoreSessionKeyIsCleared(session), isTrue);
          expect(
            deriver.seenPassphrases,
            hasLength(invalidation == 'reset' ? 0 : 1),
            reason: 'The rejected queued credential must never reach the KDF.',
          );
        },
      );
    }

    test(
      'close drains accepted work and clears its inputs after completion',
      () async {
        final capturedInputs = <Uint8List>[];
        final environment = _Environment(
          probe: V2StoreEngineTestProbe(onOperationInput: capturedInputs.add),
        );
        addTearDown(environment.dispose);
        final session = await environment.engine.open();
        addTearDown(session.close);
        await session.set('service/token', 'preserved');

        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        addTearDown(() {
          if (!releaseRead.isCompleted) releaseRead.complete();
        });
        environment.files.beforeRead = (_, __) {
          if (!readStarted.isCompleted) readStarted.complete();
        };
        environment.files.gateNextRead(releaseRead.future);
        final reading = session.get('service/token');
        await readStarted.future;

        final inputStart = capturedInputs.length;
        final queuedRead = session.getManyBytes(<String>['service/token']);
        final value = Uint8List.fromList(<int>[41, 42, 43]);
        final queuedWrite = session.setBytes('service/next', value);
        final phrase = Uint8List.fromList(<int>[51, 52, 53]);
        final queuedAuth = session.auth.add(
          PassphraseCredential(phrase: phrase),
        );
        final queuedInputs = capturedInputs.sublist(inputStart);
        _clear(value);
        _clear(phrase);
        final closing = session.close();
        expect(session.isClosed, isTrue);
        expect(queuedInputs, hasLength(4));
        expect(
          queuedInputs.every((bytes) => bytes.any((byte) => byte != 0)),
          isTrue,
          reason:
              'Closing must preserve inputs until accepted work consumes them.',
        );

        releaseRead.complete();
        expect(await reading, 'preserved');
        final readValues = await queuedRead;
        expect(readValues['service/token'], 'preserved'.codeUnits);
        _clear(readValues['service/token']!);
        await queuedWrite;
        await queuedAuth;
        await closing;

        expect(queuedInputs, everyElement(everyElement(0)));
        expect(debugStoreSessionKeyIsCleared(session), isTrue);
        final reopened = await environment.engine.open(
          credential: _credential(<int>[51, 52, 53]),
        );
        addTearDown(reopened.close);
        final persisted = await reopened.getBytes('service/next');
        expect(persisted, <int>[41, 42, 43]);
        _clear(persisted!);
      },
    );
  });

  test('reset needs no passphrase and removes a protected store', () async {
    final environment = _Environment();
    addTearDown(environment.dispose);
    final protected = await environment.engine.open(
      credential: _credential(<int>[8, 6, 7, 5, 3, 0, 9]),
    );
    addTearDown(protected.close);
    await protected.set('service/token', 'secret');

    await environment.engine.reset();

    expect(environment.files.hasLiveFile, isFalse);
    expect(environment.registry.rootCount, 0);
    expect(debugStoreSessionKeyIsCleared(protected), isTrue);
    await expectLater(
      protected.get('service/token'),
      throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
    );

    final replacement = await environment.engine.open();
    addTearDown(replacement.close);
    expect(replacement.wasInitialized, isTrue);
    expect(await replacement.get('service/token'), isNull);
    expect(await replacement.auth.list(), isEmpty);
  });
}

final class _Environment {
  _Environment({V2PassphraseDeriver? deriver, V2StoreEngineTestProbe? probe})
    : binding = ResolvedApplicationBinding.derive(
        identity: ApplicationIdentity(
          stableValue: 'dev.keybay.m6-engine',
          source: ApplicationIdentitySource.test,
          assurance: ApplicationIdentityAssurance.namespaceOnly,
        ),
        profile: HostProfile('m6-test'),
        canonicalFileRoot: Uri.parse('file:///keybay-test/m6-engine/'),
      ),
      entropy = _DeterministicEntropy() {
    registry = InMemoryRootRegistry();
    files = MemoryPinnedStoreFiles(binding);
    protector = SoftwareTestProtector(binding: binding, registry: registry);
    host = ResolvedHost(binding: binding, files: files, protector: protector);
    final platform = FakeHostPlatform(host);
    final passphraseDeriver = deriver ?? _FastPassphraseDeriver();
    engine = probe == null
        ? V2StoreEngine(
            platform,
            entropy: entropy,
            passphraseDeriver: passphraseDeriver,
          )
        : V2StoreEngine.debug(
            platform,
            probe,
            entropy: entropy,
            passphraseDeriver: passphraseDeriver,
          );
  }

  final ResolvedApplicationBinding binding;
  final _DeterministicEntropy entropy;
  late final InMemoryRootRegistry registry;
  late final MemoryPinnedStoreFiles files;
  late final SoftwareTestProtector protector;
  late final ResolvedHost host;
  late final V2StoreEngine engine;

  V2StoreEngine separateEngine(V2PassphraseDeriver deriver) => V2StoreEngine(
    FakeHostPlatform(host),
    entropy: _DeterministicEntropy(),
    passphraseDeriver: deriver,
  );

  Future<void> dispose() async {
    try {
      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      try {
        await files.withExclusiveTransaction(
          (transaction) => transaction.resetManagedArtifacts(),
        );
        await reset.commit();
      } finally {
        await reset.close();
      }
    } on Object {
      // A failed assertion may leave deliberately partial disposable state.
    }
  }
}

final class _DeterministicEntropy implements V2EntropySource {
  int _request = 0;

  @override
  Uint8List randomBytes(int length) {
    final request = ++_request;
    return Uint8List.fromList(<int>[
      for (var index = 0; index < length; index++)
        (request * 73 + index * 29) & 0xff,
    ]);
  }
}

/// Fast deterministic lifecycle-test derivation, never production crypto.
///
/// [borrowedInputs] intentionally retains test-only aliases so the tests can
/// observe that the engine clears each operation-owned credential snapshot.
final class _FastPassphraseDeriver implements V2PassphraseDeriver {
  final List<Uint8List> borrowedInputs = <Uint8List>[];
  final List<List<int>> seenPassphrases = <List<int>>[];
  V2PassphraseDerivationFailure? nextFailure;

  bool get lastBorrowedInputIsCleared =>
      borrowedInputs.isNotEmpty &&
      borrowedInputs.last.every((byte) => byte == 0);

  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) async {
    if (profileId != v2FirstPassphraseProfile) {
      throw StateError('Unexpected test KDF profile.');
    }
    borrowedInputs.add(passphrase);
    seenPassphrases.add(List<int>.of(passphrase));
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    final input = Uint8List.fromList(<int>[profileId, ...passphrase, ...salt]);
    try {
      return Uint8List.fromList(const DartSha256().hashSync(input).bytes);
    } finally {
      _clear(input);
    }
  }
}

PassphraseCredential _credential(List<int> bytes) =>
    PassphraseCredential(phrase: Uint8List.fromList(bytes));

Future<void> _expectRecords(KeybaySession session) async {
  expect(await session.get('alpha/value'), 'alpha');
  expect(await session.get('middle/value'), 'bravo');
  expect(await session.get('zulu/value'), 'charl');
}

Future<void> _expectCrossEngineAuthenticationFailure(
  V2StoreSession session,
) async {
  await expectLater(
    session.get('service/token'),
    throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
  );
  await session.close();
  expect(debugStoreSessionKeyIsCleared(session), isTrue);
}

Future<void> _expectCrossEngineAuthListFailure(V2StoreSession session) async {
  await expectLater(
    session.auth.list(),
    throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
  );
  await session.close();
  expect(debugStoreSessionKeyIsCleared(session), isTrue);
}

Future<Uint8List> _copyLive(MemoryPinnedStoreFiles files) async {
  final pin = await files.openPinnedLive();
  if (pin == null) throw StateError('No live test generation.');
  try {
    return await pin.readExact(offset: 0, length: pin.length);
  } finally {
    await pin.close();
  }
}

void _expectEveryFrameResealed(Uint8List before, Uint8List after) {
  const valueLengths = <int>[5, 5, 5];
  final oldFrames = _extractFrames(before, valueLengths);
  final newFrames = _extractFrames(after, valueLengths);
  try {
    expect(newFrames, hasLength(oldFrames.length));
    for (var index = 0; index < oldFrames.length; index++) {
      expect(
        newFrames[index],
        isNot(equals(oldFrames[index])),
        reason: 'auth rotation must reseal source frame $index',
      );
    }
  } finally {
    for (final frame in oldFrames) {
      _clear(frame);
    }
    for (final frame in newFrames) {
      _clear(frame);
    }
  }
}

List<Uint8List> _extractFrames(Uint8List store, List<int> plaintextLengths) {
  final fixed = Uint8List.fromList(
    Uint8List.sublistView(store, 0, v2BootstrapCoreFixedBytes),
  );
  V2Bootstrap? bootstrap;
  Uint8List? bootstrapBytes;
  Uint8List? trailer;
  try {
    final coreLength = decodeBootstrapCoreLength(fixed);
    final bootstrapLength = coreLength + v2BootstrapLengthBytes;
    bootstrapBytes = Uint8List.fromList(
      Uint8List.sublistView(store, 0, bootstrapLength),
    );
    bootstrap = decodeBootstrap(bootstrapBytes);
    trailer = Uint8List.fromList(
      Uint8List.sublistView(store, store.length - v2ManifestLengthBytes),
    );
    final manifestLength = decodeManifestLength(trailer);
    final layout = deriveStoreLayout(
      fileLength: store.length,
      bootstrap: bootstrap,
      sealedManifestLength: manifestLength,
    );
    var offset = layout.frameRegionOffset;
    final frames = <Uint8List>[];
    for (final plaintextLength in plaintextLengths) {
      final frameLength = plaintextLength + V2StoreLimits.sealedFrameOverhead;
      frames.add(
        Uint8List.fromList(
          Uint8List.sublistView(store, offset, offset + frameLength),
        ),
      );
      offset += frameLength;
    }
    expect(offset, layout.manifestOffset);
    return frames;
  } finally {
    _clear(fixed);
    if (bootstrapBytes != null) _clear(bootstrapBytes);
    if (trailer != null) _clear(trailer);
    final providerState = bootstrap?.core.providerState;
    if (providerState != null) _clear(providerState);
  }
}

int _frameRegionOffset(Uint8List store) {
  final fixed = Uint8List.fromList(
    Uint8List.sublistView(store, 0, v2BootstrapCoreFixedBytes),
  );
  Uint8List? bootstrapBytes;
  Uint8List? trailer;
  V2Bootstrap? bootstrap;
  try {
    final coreLength = decodeBootstrapCoreLength(fixed);
    final bootstrapLength = coreLength + v2BootstrapLengthBytes;
    bootstrapBytes = Uint8List.fromList(
      Uint8List.sublistView(store, 0, bootstrapLength),
    );
    bootstrap = decodeBootstrap(bootstrapBytes);
    trailer = Uint8List.fromList(
      Uint8List.sublistView(store, store.length - v2ManifestLengthBytes),
    );
    final manifestLength = decodeManifestLength(trailer);
    return deriveStoreLayout(
      fileLength: store.length,
      bootstrap: bootstrap,
      sealedManifestLength: manifestLength,
    ).frameRegionOffset;
  } finally {
    _clear(fixed);
    if (bootstrapBytes != null) _clear(bootstrapBytes);
    if (trailer != null) _clear(trailer);
    final providerState = bootstrap?.core.providerState;
    if (providerState != null) _clear(providerState);
  }
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

Future<void> _failStorage() => Future<void>.error(
  const StoreFilesFailure(StoreFilesFailureCode.operationFailed),
);

Matcher _keybayFailure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

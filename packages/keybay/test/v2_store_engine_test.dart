@Tags(['unit'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/entropy_source.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2StoreEngineTestProbe, V2StoreEngine, debugStoreSessionKeyIsCleared;
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_entropy_source.dart';
import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_fakes.dart';
import 'package:keybay/src/v2/platform_protector.dart';

void main() {
  group('M5 platform-only store engine', () {
    test(
      'host resolution retries failure and caches only successful binding',
      () async {
        final environment = _Environment(entropyResponses: _happyEntropy());
        addTearDown(environment.dispose);
        final platform = _RetryingHostPlatform(
          environment.host,
          failuresBeforeSuccess: 1,
        );
        final engine = V2StoreEngine(platform, entropy: environment.entropy);

        await expectLater(
          engine.openPlatformOnly(),
          throwsA(
            _keybayFailure(KeybayErrorCode.applicationIdentityUnavailable),
          ),
        );
        expect(platform.resolveCalls, 1);

        final first = await engine.openPlatformOnly();
        addTearDown(first.close);
        final second = await engine.openPlatformOnly();
        addTearDown(second.close);
        expect(platform.resolveCalls, 2);
      },
    );

    test(
      'concurrent opens share host resolution before lock policy applies',
      () async {
        final environment = _Environment(entropyResponses: _happyEntropy());
        addTearDown(environment.dispose);
        final release = Completer<void>();
        final platform = _RetryingHostPlatform(
          environment.host,
          release: release.future,
        );
        final engine = V2StoreEngine(platform, entropy: environment.entropy);

        final firstOpening = engine.openPlatformOnly();
        final secondOpening = engine.openPlatformOnly();
        await platform.firstResolveStarted.future;
        expect(platform.resolveCalls, 1);
        release.complete();

        final outcomes = await Future.wait<Object>([
          firstOpening.then<Object>(
            (session) => session,
            onError: (Object error) => error,
          ),
          secondOpening.then<Object>(
            (session) => session,
            onError: (Object error) => error,
          ),
        ]);
        final sessions = outcomes.whereType<KeybaySession>().toList();
        final failures = outcomes.whereType<KeybayException>().toList();
        for (final session in sessions) {
          addTearDown(session.close);
        }
        expect(sessions, hasLength(1));
        expect(failures, hasLength(1));
        expect(failures.single.code, KeybayErrorCode.storeBusy);
        expect(platform.resolveCalls, 1);
      },
    );

    test(
      'first use initializes once and persistent record operations reopen',
      () async {
        final environment = _Environment(entropyResponses: _happyEntropy());
        addTearDown(environment.dispose);

        final session = await environment.engine.openPlatformOnly();
        addTearDown(session.close);
        expect(session.wasInitialized, isTrue);
        expect(await session.get('service/missing'), isNull);
        expect(environment.files.hasTransactionArtifacts, isFalse);

        await session.set('service/token', 'alpha');
        final caller = Uint8List.fromList(<int>[0, 1, 0xff]);
        final settingBytes = session.setBytes('service/blob', caller);
        caller.fillRange(0, caller.length, 9);
        await settingBytes;
        expect(await session.get('service/token'), 'alpha');
        expect(await session.getBytes('service/blob'), <int>[0, 1, 0xff]);

        await session.set('service/token', 'replacement');
        expect(await session.delete('service/missing'), isFalse);
        expect(await session.delete('service/blob'), isTrue);
        expect(await session.contains('service/blob'), isFalse);

        final reopened = await environment.engine.openPlatformOnly();
        addTearDown(reopened.close);
        expect(reopened.wasInitialized, isFalse);
        expect(await reopened.get('service/token'), 'replacement');

        await reopened.clearAll();
        expect(await session.get('service/token'), isNull);
        expect(environment.files.hasTransactionArtifacts, isFalse);
      },
    );

    test(
      'reset revokes the file before invalidating same-runtime sessions',
      () async {
        final environment = _Environment(
          entropyResponses: <List<int>>[
            ..._initializationEntropy(0x10),
            _sequence(0x40, V2StoreLimits.nonceBytes),
            _sequence(0x50, V2StoreLimits.nonceBytes),
            ..._initializationEntropy(0x80),
          ],
        );
        addTearDown(environment.dispose);

        final session = await environment.engine.openPlatformOnly();
        await session.set('service/token', 'secret');
        final otherRuntime = V2StoreEngine(environment.platform);
        final otherSession = await otherRuntime.openPlatformOnly();
        addTearDown(otherSession.close);

        await environment.engine.reset();

        expect(environment.files.hasLiveFile, isFalse);
        expect(environment.registry.rootCount, 0);
        expect(debugStoreSessionKeyIsCleared(session), isTrue);
        await expectLater(
          session.get('service/token'),
          throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
        );
        await expectLater(
          otherSession.set('service/token', 'resurrected'),
          throwsA(_keybayFailure(KeybayErrorCode.storeStateConflict)),
        );
        expect(environment.files.hasLiveFile, isFalse);

        final fresh = await environment.engine.openPlatformOnly();
        addTearDown(fresh.close);
        expect(fresh.wasInitialized, isTrue);
        expect(await fresh.get('service/token'), isNull);
      },
    );

    test('root-only, file-only, and stage-only state fail closed', () async {
      final rootOnly = _Environment(
        entropyResponses: _initializationEntropy(0x10),
      );
      addTearDown(rootOnly.dispose);
      final creation = await rootOnly.protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await creation.lease.close();
      await expectLater(
        rootOnly.engine.openPlatformOnly(),
        throwsA(_keybayFailure(KeybayErrorCode.storeStateConflict)),
      );
      expect(rootOnly.files.hasLiveFile, isFalse);

      final staged = _Environment(
        entropyResponses: _initializationEntropy(0x30),
        hasTransactionArtifacts: true,
      );
      addTearDown(staged.dispose);
      await expectLater(
        staged.engine.openPlatformOnly(),
        throwsA(_keybayFailure(KeybayErrorCode.storeStateConflict)),
      );
      expect(staged.registry.rootCount, 0);

      final fileOnly = _Environment(
        entropyResponses: _initializationEntropy(0x50),
      );
      addTearDown(fileOnly.dispose);
      final initialized = await fileOnly.engine.openPlatformOnly();
      await initialized.close();
      final reset = await fileOnly.protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      await reset.commit();
      await reset.close();
      await expectLater(
        fileOnly.engine.openPlatformOnly(),
        throwsA(_keybayFailure(KeybayErrorCode.platformKeyInvalidated)),
      );
      expect(fileOnly.files.hasLiveFile, isTrue);
    });

    test('open authenticates live then discards abandoned staging', () async {
      final environment = _Environment(
        entropyResponses: _initializationEntropy(0x60),
      );
      addTearDown(environment.dispose);
      final initialized = await environment.engine.openPlatformOnly();
      await initialized.close();
      final generation = environment.files.liveGeneration;
      environment.files.hasTransactionArtifacts = true;

      final reopened = await environment.engine.openPlatformOnly();
      addTearDown(reopened.close);

      expect(reopened.wasInitialized, isFalse);
      expect(environment.files.liveGeneration, generation);
      expect(environment.files.hasLiveFile, isTrue);
      expect(environment.files.hasTransactionArtifacts, isFalse);
      expect(await reopened.contains('service/missing'), isFalse);
    });

    test(
      'existing sessions leave abandoned staging for a later open',
      () async {
        final environment = _Environment(entropyResponses: _happyEntropy());
        addTearDown(environment.dispose);
        final session = await environment.engine.openPlatformOnly();
        addTearDown(session.close);
        environment.files.hasTransactionArtifacts = true;

        expect(await session.get('service/missing'), isNull);
        await expectLater(
          session.set('service/token', 'must-not-commit'),
          throwsA(_keybayFailure(KeybayErrorCode.storeStateConflict)),
        );
        expect(environment.files.hasTransactionArtifacts, isTrue);

        await session.close();
        final reopened = await environment.engine.openPlatformOnly();
        addTearDown(reopened.close);
        expect(environment.files.hasTransactionArtifacts, isFalse);
        expect(await reopened.get('service/token'), isNull);
      },
    );

    test('entropy failure precedes provider and file creation', () async {
      final environment = _Environment(
        entropyResponses: _initializationEntropy(0x10),
      );
      addTearDown(environment.dispose);
      environment.entropy.nextFailure = const V2EntropyFailure();

      await expectLater(
        environment.engine.openPlatformOnly(),
        throwsA(_keybayFailure(KeybayErrorCode.entropyUnavailable)),
      );
      expect(environment.registry.rootCount, 0);
      expect(environment.files.hasLiveFile, isFalse);
      expect(environment.files.hasTransactionArtifacts, isFalse);
    });

    test('reset failures respect the live-file revocation boundary', () async {
      final before = _Environment(
        entropyResponses: _initializationEntropy(0x30),
      );
      addTearDown(before.dispose);
      final beforeSession = await before.engine.openPlatformOnly();
      addTearDown(beforeSession.close);
      before.files.failResetBeforeLiveRevocation = true;
      await expectLater(
        before.engine.reset(),
        throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
      );
      expect(before.files.hasLiveFile, isTrue);
      expect(before.registry.rootCount, 1);
      expect(await beforeSession.get('service/missing'), isNull);

      final after = _Environment(
        entropyResponses: _initializationEntropy(0x50),
      );
      addTearDown(after.dispose);
      final afterSession = await after.engine.openPlatformOnly();
      addTearDown(afterSession.close);
      after.files.failResetAfterLiveRevocation = true;
      await expectLater(
        after.engine.reset(),
        throwsA(_keybayFailure(KeybayErrorCode.resetIncomplete)),
      );
      expect(after.files.hasLiveFile, isFalse);
      expect(after.registry.rootCount, 0);
      await expectLater(
        afterSession.get('service/missing'),
        throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
      );
      after.files.failResetAfterLiveRevocation = false;
      await after.engine.reset();
    });

    test('provider failure after file revocation is retryable', () async {
      final environment = _Environment(
        entropyResponses: _initializationEntropy(0x70),
        resetFailure: SoftwareResetFailure.incompleteAfterMutation,
      );
      addTearDown(environment.dispose);
      final session = await environment.engine.openPlatformOnly();
      addTearDown(session.close);

      await expectLater(
        environment.engine.reset(),
        throwsA(_keybayFailure(KeybayErrorCode.resetIncomplete)),
      );
      expect(environment.files.hasLiveFile, isFalse);
      expect(environment.registry.rootCount, 0);
      await expectLater(
        session.get('service/missing'),
        throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
      );

      await environment.engine.reset();
      expect(environment.files.hasLiveFile, isFalse);
      expect(environment.registry.rootCount, 0);
    });

    test(
      'reset lets a pinned read finish but rejects its queued mutation',
      () async {
        final environment = _Environment(
          entropyResponses: <List<int>>[
            ..._initializationEntropy(0x20),
            _sequence(0x50, V2StoreLimits.nonceBytes),
            _sequence(0x60, V2StoreLimits.nonceBytes),
          ],
        );
        addTearDown(environment.dispose);
        final session = await environment.engine.openPlatformOnly();
        addTearDown(session.close);
        await session.set('service/token', 'old-value');

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
        final queuedWrite = session.set('service/new', 'must-not-commit');
        final queuedFailure = expectLater(
          queuedWrite,
          throwsA(_keybayFailure(KeybayErrorCode.staleSession)),
        );
        final resetting = environment.engine.reset();
        var resetFinished = false;
        unawaited(resetting.whenComplete(() => resetFinished = true));
        await Future<void>.delayed(Duration.zero);

        expect(resetFinished, isFalse);
        expect(environment.files.hasLiveFile, isFalse);
        releaseRead.complete();
        expect(await reading, 'old-value');
        await queuedFailure;
        await resetting;
        expect(debugStoreSessionKeyIsCleared(session), isTrue);
        expect(environment.files.hasLiveFile, isFalse);
      },
    );

    test(
      'post-commit transaction cleanup failure clears the withheld session',
      () async {
        final environment = _Environment(
          entropyResponses: _initializationEntropy(0x40),
        );
        addTearDown(environment.dispose);
        final probe = V2StoreEngineTestProbe();
        final engine = V2StoreEngine.debug(
          environment.platform,
          probe,
          entropy: environment.entropy,
        );
        environment.files.transactionCleanupFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );

        await expectLater(
          engine.openPlatformOnly(),
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        expect(probe.failedOpenKeyMaterialWasCleared, isTrue);
        expect(environment.files.hasLiveFile, isTrue);
        expect(environment.registry.rootCount, 1);

        environment.files.transactionCleanupFailure = null;
        final reopened = await engine.openPlatformOnly();
        addTearDown(reopened.close);
        expect(reopened.wasInitialized, isFalse);
      },
    );

    test(
      'pre-replacement initialization failure leaves recoverable root-only state',
      () async {
        final environment = _Environment(
          entropyResponses: <List<int>>[
            ..._initializationEntropy(0x20),
            ..._initializationEntropy(0x60),
          ],
        );
        addTearDown(environment.dispose);
        environment.files.beforeReplaceLive = () =>
            throw const StoreFilesFailure(
              StoreFilesFailureCode.operationFailed,
            );

        await expectLater(
          environment.engine.openPlatformOnly(),
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        expect(environment.files.hasLiveFile, isFalse);
        expect(environment.files.hasTransactionArtifacts, isFalse);
        expect(environment.registry.rootCount, 1);

        environment.files.beforeReplaceLive = null;
        await environment.engine.reset();
        final recovered = await environment.engine.openPlatformOnly();
        addTearDown(recovered.close);
        expect(recovered.wasInitialized, isTrue);
      },
    );

    test(
      'post-replacement initialization failure reopens the committed store',
      () async {
        final environment = _Environment(
          entropyResponses: _initializationEntropy(0x30),
        );
        addTearDown(environment.dispose);
        environment.files.afterReplaceLive = () =>
            throw const StoreFilesFailure(
              StoreFilesFailureCode.operationFailed,
            );

        await expectLater(
          environment.engine.openPlatformOnly(),
          throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
        );
        expect(environment.files.hasLiveFile, isTrue);
        expect(environment.files.hasTransactionArtifacts, isFalse);
        expect(environment.registry.rootCount, 1);

        environment.files.afterReplaceLive = null;
        final reopened = await environment.engine.openPlatformOnly();
        addTearDown(reopened.close);
        expect(reopened.wasInitialized, isFalse);
        expect(await reopened.get('service/missing'), isNull);
      },
    );

    test('corrupted initialization staging is never installed', () async {
      final environment = _Environment(
        entropyResponses: _initializationEntropy(0x40),
      );
      addTearDown(environment.dispose);
      environment.files.beforeStageVerification = (bytes) {
        bytes[bytes.length - v2ManifestLengthBytes - 1] ^= 1;
      };

      await expectLater(
        environment.engine.openPlatformOnly(),
        throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
      );
      expect(environment.files.hasLiveFile, isFalse);
      expect(environment.files.hasTransactionArtifacts, isFalse);
      expect(environment.registry.rootCount, 1);
    });

    test(
      'transaction cleanup failure after reset reports incomplete',
      () async {
        final environment = _Environment(
          entropyResponses: _initializationEntropy(0x60),
        );
        addTearDown(environment.dispose);
        final session = await environment.engine.openPlatformOnly();
        addTearDown(session.close);
        environment.files.transactionCleanupFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );

        await expectLater(
          environment.engine.reset(),
          throwsA(_keybayFailure(KeybayErrorCode.resetIncomplete)),
        );
        expect(environment.files.hasLiveFile, isFalse);
        expect(environment.registry.rootCount, 0);
        expect(debugStoreSessionKeyIsCleared(session), isTrue);

        environment.files.transactionCleanupFailure = null;
        await environment.engine.reset();
      },
    );
  });
}

final class _Environment {
  _Environment({
    required Iterable<List<int>> entropyResponses,
    bool hasTransactionArtifacts = false,
    SoftwareResetFailure? resetFailure,
  }) : entropy = ScriptedV2EntropySource(entropyResponses),
       binding = ResolvedApplicationBinding.derive(
         identity: ApplicationIdentity(
           stableValue: 'dev.keybay.m5-engine',
           source: ApplicationIdentitySource.test,
           assurance: ApplicationIdentityAssurance.namespaceOnly,
         ),
         profile: HostProfile('m5-test'),
         canonicalFileRoot: Uri.parse('file:///keybay-test/m5-engine/'),
       ) {
    registry = InMemoryRootRegistry();
    files = MemoryPinnedStoreFiles(
      binding,
      hasTransactionArtifacts: hasTransactionArtifacts,
    );
    protector = SoftwareTestProtector(
      binding: binding,
      registry: registry,
      resetFailure: resetFailure,
    );
    host = ResolvedHost(binding: binding, files: files, protector: protector);
    platform = FakeHostPlatform(host);
    engine = V2StoreEngine(platform, entropy: entropy);
  }

  final ScriptedV2EntropySource entropy;
  final ResolvedApplicationBinding binding;
  late final InMemoryRootRegistry registry;
  late final MemoryPinnedStoreFiles files;
  late final SoftwareTestProtector protector;
  late final ResolvedHost host;
  late final FakeHostPlatform platform;
  late final V2StoreEngine engine;

  Future<void> dispose() async {
    try {
      final prepared = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      try {
        await files.withExclusiveTransaction(
          (transaction) => transaction.resetManagedArtifacts(),
        );
        await prepared.commit();
      } finally {
        await prepared.close();
      }
    } on Object {
      // A test may intentionally leave a partial disposable state.
    } finally {
      entropy.dispose();
    }
  }
}

final class _RetryingHostPlatform implements HostPlatform {
  _RetryingHostPlatform(
    this.host, {
    this.failuresBeforeSuccess = 0,
    this.release,
  });

  final ResolvedHost host;
  final int failuresBeforeSuccess;
  final Future<void>? release;
  final Completer<void> firstResolveStarted = Completer<void>();
  int resolveCalls = 0;

  @override
  Future<ResolvedHost> resolve() async {
    resolveCalls++;
    if (!firstResolveStarted.isCompleted) firstResolveStarted.complete();
    if (resolveCalls <= failuresBeforeSuccess) {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.unavailable,
      );
    }
    await release;
    return host;
  }
}

List<List<int>> _happyEntropy() => <List<int>>[
  ..._initializationEntropy(0x10),
  for (var index = 0; index < 8; index++)
    _sequence(0x40 + index * 7, V2StoreLimits.nonceBytes),
];

List<List<int>> _initializationEntropy(int seed) => <List<int>>[
  _sequence(seed, V2StoreLimits.storeIdBytes),
  _sequence(seed + 0x10, V2StoreLimits.storeKeyBytes),
  _sequence(seed + 0x20, V2StoreLimits.nonceBytes),
];

Uint8List _sequence(int seed, int length) => Uint8List.fromList(
  List<int>.generate(length, (index) => (seed + index) & 0xff),
);

Matcher _keybayFailure(KeybayErrorCode code) =>
    isA<KeybayException>().having((error) => error.code, 'code', code);

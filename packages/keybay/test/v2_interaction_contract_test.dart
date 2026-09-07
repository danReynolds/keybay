@Tags(['unit'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngine;
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_fakes.dart';
import 'support/v2_test_keybay.dart' show FastTestPassphraseDeriver;

void main() {
  test(
    'open, passphrase changes, and reset explicitly allow provider UI',
    () async {
      final environment = _Environment(requiresInteraction: true);
      addTearDown(environment.dispose);
      final first = await environment.engine.open(credential: _credential());
      await first.close();
      final session = await environment.engine.open(credential: _credential());
      addTearDown(session.close);
      final updated = await session.auth.update(_credential());
      await session.auth.remove(updated.id);
      await session.auth.add(_credential());
      await environment.engine.reset();

      expect(environment.protector.calls, <_ProviderCall>[
        (operation: 'create', interaction: PlatformInteraction.allowed),
        (operation: 'open', interaction: PlatformInteraction.allowed),
        (operation: 'open', interaction: PlatformInteraction.allowed),
        (operation: 'open', interaction: PlatformInteraction.allowed),
        (operation: 'open', interaction: PlatformInteraction.allowed),
        (operation: 'reset', interaction: PlatformInteraction.allowed),
      ]);
    },
  );

  test(
    'queued record operations and auth.list never acquire the provider',
    () async {
      final environment = _Environment(requiresInteraction: true);
      addTearDown(environment.dispose);
      final session = await environment.engine.open(credential: _credential());
      addTearDown(session.close);
      await session.set('service/token', 'preserved');
      environment.protector.calls.clear();

      final readStarted = Completer<void>();
      final releaseRead = Completer<void>();
      addTearDown(() {
        if (!releaseRead.isCompleted) releaseRead.complete();
      });
      environment.files.beforeRead = (_, __) {
        if (!readStarted.isCompleted) readStarted.complete();
      };
      environment.files.gateNextRead(releaseRead.future);
      final first = session.get('service/token');
      await readStarted.future;
      final operations = <Future<Object?>>[
        session.getBytes('service/token'),
        session.getManyBytes(<String>['service/token']),
        session.set('service/next', 'next'),
        session.setBytes('service/binary', Uint8List.fromList(<int>[1, 2, 3])),
        session.listKeys(),
        session.contains('service/token'),
        session.delete('service/next'),
        session.clearAll(),
        session.auth.list(),
      ];
      expect(environment.protector.calls, isEmpty);
      releaseRead.complete();
      expect(await first, 'preserved');
      final results = await Future.wait(operations);
      (results[0] as Uint8List).fillRange(0, 'preserved'.length, 0);
      final many = results[1] as Map<String, Uint8List?>;
      for (final value in many.values) {
        value?.fillRange(0, value.length, 0);
      }
      expect(await session.listKeys(), isEmpty);
      await session.close();
      expect(environment.protector.calls, isEmpty);
    },
  );

  for (final damage in [false, true]) {
    test(
      '${damage ? 'damaged' : 'peer-rotated'} record operations never acquire the provider',
      () async {
        final environment = _Environment();
        addTearDown(environment.dispose);
        final owner = await environment.engine.open(credential: _credential());
        addTearDown(owner.close);
        await owner.set('service/token', 'preserved');
        final reader = await environment.newEngine().open(
          credential: _credential(),
        );
        addTearDown(reader.close);
        if (damage) {
          final damaged = await _copyLive(environment.files);
          damaged[damaged.length - 5] ^= 1;
          environment.files.replaceLiveBytes(damaged);
        } else {
          await owner.auth.update(_credential());
        }
        environment.protector.calls.clear();
        final accesses = environment.protector.providerAccesses;

        for (final operation in <Future<Object?> Function()>[
          () => reader.get('service/token'),
          () => reader.getBytes('service/token'),
          () => reader.getManyBytes(['service/token']),
          () => reader.set('service/token', 'rejected'),
          () => reader.setBytes('service/token', Uint8List(1)),
          reader.listKeys,
          () => reader.contains('service/token'),
          () => reader.delete('service/token'),
          reader.clearAll,
          reader.auth.list,
        ]) {
          await expectLater(
            operation(),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );
          expect(environment.protector.calls, isEmpty);
          expect(environment.protector.providerAccesses, accesses);
        }
        if (!damage) expect(await owner.get('service/token'), 'preserved');
      },
    );
  }

  test(
    'reusable roots survive failed initialization and reset without adoption',
    () async {
      final environment = _Environment(reusableRoot: true);
      addTearDown(environment.dispose);
      environment.files.beforeStageVerification = (bytes) {
        bytes[bytes.length - 5] ^= 1;
      };
      await expectLater(
        environment.engine.open(),
        throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
      );
      expect(environment.registry.rootCount, 1);
      expect(environment.files.hasLiveFile, isFalse);
      expect(environment.files.hasTransactionArtifacts, isFalse);

      environment.files.beforeStageVerification = null;
      final original = await environment.engine.open();
      addTearDown(original.close);
      expect(original.wasInitialized, isTrue);
      await original.set('service/token', 'old snapshot');
      final oldSnapshot = await _copyLive(environment.files);
      await environment.engine.reset();
      expect(environment.registry.rootCount, 1);
      expect(environment.files.hasLiveFile, isFalse);
      final fresh = await environment.engine.open();
      addTearDown(fresh.close);
      expect(fresh.wasInitialized, isTrue);
      expect(await fresh.listKeys(), isEmpty);
      await fresh.close();

      // A retained provider root does not give reset rollback resistance.
      environment.files.replaceLiveBytes(oldSnapshot);
      final restored = await environment.engine.open();
      addTearDown(restored.close);
      expect(await restored.get('service/token'), 'old snapshot');
    },
  );
}

typedef _ProviderCall = ({String operation, PlatformInteraction interaction});

final class _Environment {
  _Environment({bool requiresInteraction = false, bool reusableRoot = false}) {
    final binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.interaction-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('interaction-test'),
      canonicalFileRoot: Uri.parse('file:///keybay-test/interaction/'),
    );
    files = MemoryPinnedStoreFiles(binding);
    delegate = SoftwareTestProtector(binding: binding, registry: registry);
    protector = _ObservedProtector(
      delegate,
      requiresInteraction: requiresInteraction,
      reusableRoot: reusableRoot,
    );
    platform = FakeHostPlatform(
      ResolvedHost(binding: binding, files: files, protector: protector),
    );
    engine = newEngine();
  }

  final registry = InMemoryRootRegistry();
  late final MemoryPinnedStoreFiles files;
  late final SoftwareTestProtector delegate;
  late final _ObservedProtector protector;
  late final FakeHostPlatform platform;
  late final V2StoreEngine engine;

  V2StoreEngine newEngine() =>
      V2StoreEngine(platform, passphraseDeriver: FastTestPassphraseDeriver());

  Future<void> dispose() async {
    final reset = await delegate.prepareReset(
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
  }
}

final class _ObservedProtector implements PlatformProtector {
  _ObservedProtector(
    this.delegate, {
    required this.requiresInteraction,
    required this.reusableRoot,
  });

  final SoftwareTestProtector delegate;
  final bool requiresInteraction;
  final bool reusableRoot;
  final calls = <_ProviderCall>[];
  int providerAccesses = 0;

  @override
  ResolvedApplicationBinding get binding => delegate.binding;

  void _acquire(String operation, PlatformInteraction interaction) {
    calls.add((operation: operation, interaction: interaction));
    if (requiresInteraction && interaction == PlatformInteraction.forbidden) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.interactionRequired,
      );
    }
    providerAccesses++;
  }

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) async {
    _acquire('open', interaction);
    return delegate.openExisting(state, interaction: interaction);
  }

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) async {
    _acquire('create', interaction);
    final creation = await delegate.createOnly(interaction: interaction);
    return reusableRoot
        ? PlatformRootCreation(
            lease: creation.lease,
            disposition: RootCreationDisposition.reused,
          )
        : creation;
  }

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) async {
    _acquire('reset', interaction);
    return reusableRoot
        ? _RetainedRootReset()
        : delegate.prepareReset(interaction: interaction);
  }
}

final class _RetainedRootReset implements PreparedPlatformReset {
  bool _used = false;

  @override
  Future<void> commit() async {
    if (_used) throw StateError('Reset capability is no longer live.');
    _used = true;
  }

  @override
  Future<void> close() async => _used = true;
}

PassphraseCredential _credential() =>
    PassphraseCredential(phrase: Uint8List.fromList(<int>[1, 2, 3, 4]));

Future<Uint8List> _copyLive(MemoryPinnedStoreFiles files) async {
  final pin = (await files.openPinnedLive())!;
  try {
    return await pin.readExact(offset: 0, length: pin.length);
  } finally {
    await pin.close();
  }
}

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((error) => error.code, 'code', code);

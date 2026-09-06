@Tags(['unit'])
library;

import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_contract.dart';
import 'support/v2_platform_fakes.dart';

void main() {
  runDisposablePlatformProtectorContract(
    name: 'software test protector',
    createFixture: () {
      final registry = InMemoryRootRegistry();
      final binding = _binding(root: '/test/contract');

      SoftwareTestProtector newInstance() =>
          SoftwareTestProtector(binding: binding, registry: registry);

      return (
        newInstance: newInstance,
        dispose: () async {
          await _commitReset(newInstance());
        },
      );
    },
  );

  group('provider state', () {
    test('enforces the frozen bound and byte domain before copying', () {
      expect(
        () => ProviderState(
          List<int>.filled(V2StoreLimits.providerStateBytes + 1, 0),
        ),
        throwsArgumentError,
      );
      expect(() => ProviderState(<int>[-1]), throwsArgumentError);
      expect(() => ProviderState(<int>[256]), throwsArgumentError);
    });
  });

  test('provider reset failure after mutation is resetIncomplete', () async {
    final binding = _binding(root: '/test/reset-phases');
    final registry = InMemoryRootRegistry();
    final baseline = SoftwareTestProtector(
      binding: binding,
      registry: registry,
    );
    final created = await baseline.createOnly(
      interaction: PlatformInteraction.forbidden,
    );
    await created.lease.close();

    final incomplete = SoftwareTestProtector(
      binding: binding,
      registry: registry,
      resetFailure: SoftwareResetFailure.incompleteAfterMutation,
    );
    final preparation = await incomplete.prepareReset(
      interaction: PlatformInteraction.forbidden,
    );
    await expectLater(
      preparation.commit(),
      throwsA(_protectorFailure(PlatformProtectorFailureCode.resetIncomplete)),
    );
    await preparation.close();
    expect(registry.rootCount, 0);
  });

  test(
    'prepared provider reset commits only after live-file revocation',
    () async {
      final binding = _binding(root: '/test/prepared-reset-order');
      final registry = InMemoryRootRegistry();
      final protector = SoftwareTestProtector(
        binding: binding,
        registry: registry,
      );
      final files = MemoryPinnedStoreFiles(binding, liveBytes: <int>[1]);
      final created = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await created.lease.close();

      final preparation = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      try {
        expect(files.hasLiveFile, isTrue);
        expect(registry.rootCount, 1);

        await files.withExclusiveTransaction(
          (transaction) => transaction.resetManagedArtifacts(),
        );
        expect(files.hasLiveFile, isFalse);
        expect(registry.rootCount, 1);

        await preparation.commit();
        expect(registry.rootCount, 0);
      } finally {
        await preparation.close();
      }
    },
  );

  test(
    'pre-revocation file failure leaves prepared provider untouched',
    () async {
      final binding = _binding(root: '/test/prepared-reset-abort');
      final registry = InMemoryRootRegistry();
      final protector = SoftwareTestProtector(
        binding: binding,
        registry: registry,
      );
      final files = MemoryPinnedStoreFiles(binding, liveBytes: <int>[1])
        ..failResetBeforeLiveRevocation = true;
      final created = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await created.lease.close();

      final preparation = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      try {
        await expectLater(
          files.withExclusiveTransaction(
            (transaction) => transaction.resetManagedArtifacts(),
          ),
          throwsA(_storeFailure(StoreFilesFailureCode.resetNotStarted)),
        );
      } finally {
        await preparation.close();
      }

      expect(files.hasLiveFile, isTrue);
      expect(registry.rootCount, 1);
      files.failResetBeforeLiveRevocation = false;
      await files.withExclusiveTransaction(
        (transaction) => transaction.resetManagedArtifacts(),
      );
      await _commitReset(protector);
      expect(registry.rootCount, 0);
    },
  );

  test(
    'post-revocation file failure still permits fixed provider commit',
    () async {
      final binding = _binding(root: '/test/prepared-reset-incomplete');
      final registry = InMemoryRootRegistry();
      final protector = SoftwareTestProtector(
        binding: binding,
        registry: registry,
      );
      final files = MemoryPinnedStoreFiles(
        binding,
        liveBytes: <int>[1],
        hasTransactionArtifacts: true,
      )..failResetAfterLiveRevocation = true;
      final created = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await created.lease.close();

      final preparation = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      try {
        await expectLater(
          files.withExclusiveTransaction(
            (transaction) => transaction.resetManagedArtifacts(),
          ),
          throwsA(_storeFailure(StoreFilesFailureCode.resetIncomplete)),
        );
        expect(files.hasLiveFile, isFalse);
        await preparation.commit();
      } finally {
        await preparation.close();
      }

      expect(registry.rootCount, 0);
      expect(files.hasTransactionArtifacts, isTrue);
    },
  );

  group('resolved host', () {
    test('binds one immutable identity, file domain, and protector', () async {
      final binding = _binding(root: '/test/root-a');
      final files = MemoryStoreFiles(binding);
      final protector = SoftwareTestProtector(
        binding: binding,
        registry: InMemoryRootRegistry(),
      );
      final host = ResolvedHost(
        binding: binding,
        files: files,
        protector: protector,
      );
      final resolver = FakeHostPlatform(host);

      expect(await resolver.resolve(), same(host));
      expect(resolver.resolveCount, 1);
      expect(host.binding, same(binding));
      expect(host.identity, same(binding.identity));
      expect(host.profile, same(binding.profile));
      expect(host.files, same(files));
      expect(host.protector, same(protector));
    });

    test('rejects independently resolved bindings even when values match', () {
      final filesBinding = _binding(root: '/test/root-a');
      final protectorBinding = _binding(root: '/test/root-a');
      expect(identical(filesBinding, protectorBinding), isFalse);
      expect(filesBinding.domain, protectorBinding.domain);
      expect(filesBinding.providerAddress, protectorBinding.providerAddress);

      final files = MemoryStoreFiles(filesBinding);
      final protector = SoftwareTestProtector(
        binding: protectorBinding,
        registry: InMemoryRootRegistry(),
      );

      expect(
        () => ResolvedHost(
          binding: filesBinding,
          files: files,
          protector: protector,
        ),
        throwsArgumentError,
      );
    });
  });

  group('storage-domain binding', () {
    test('commits identity, assurance, profile, and canonical root', () {
      final baseline = _binding(root: '/test/root-a');
      final sameInputs = _binding(root: '/test/root-a');
      final differentSource = _binding(
        root: '/test/root-a',
        source: ApplicationIdentitySource.buildEmbedded,
      );

      expect(sameInputs.domain, baseline.domain);
      expect(
        baseline.domain.commitment,
        'J5yl8H6Xi3rAAxRdsoSm-8GBOMy8uekILHraxA8RoJU',
      );
      expect(
        baseline.providerAddress,
        'XD2BXyQn8VdYWWEOROLW9AhEby8aB7poMAjNC8Roep4',
      );
      expect(differentSource.domain, baseline.domain);
      expect(
        _binding(id: 'dev.example.other', root: '/test/root-a').domain,
        isNot(baseline.domain),
      );
      expect(
        _binding(
          root: '/test/root-a',
          assurance: ApplicationIdentityAssurance.osEnforced,
        ).domain,
        isNot(baseline.domain),
      );
      expect(
        _binding(root: '/test/root-a', profile: 'test.other').domain,
        isNot(baseline.domain),
      );
      expect(_binding(root: '/test/root-b').domain, isNot(baseline.domain));
      expect(baseline.domain.toString(), 'StorageDomain(<redacted>)');
    });

    test(
      'one provider identity cannot initialize two storage domains',
      () async {
        final registry = InMemoryRootRegistry();
        final firstBinding = _binding(root: '/test/root-a');
        final secondBinding = _binding(root: '/test/root-b');
        expect(firstBinding.providerAddress, secondBinding.providerAddress);
        expect(firstBinding.domain, isNot(secondBinding.domain));
        final first = SoftwareTestProtector(
          binding: firstBinding,
          registry: registry,
        );
        final second = SoftwareTestProtector(
          binding: secondBinding,
          registry: registry,
        );

        final created = await first.createOnly(
          interaction: PlatformInteraction.forbidden,
        );
        await created.lease.close();
        await expectLater(
          second.createOnly(interaction: PlatformInteraction.forbidden),
          throwsA(
            isA<PlatformProtectorFailure>().having(
              (failure) => failure.code,
              'code',
              PlatformProtectorFailureCode.stateConflict,
            ),
          ),
        );
        expect(registry.rootCount, 1);
      },
    );

    test(
      'persisted provider state cannot redirect either reset target',
      () async {
        final firstBinding = _binding(id: 'dev.example.first', root: '/test/a');
        final secondBinding = _binding(
          id: 'dev.example.second',
          root: '/test/b',
        );
        final firstFiles = MemoryStoreFiles(firstBinding)
          ..hasLiveFile = true
          ..hasTransactionArtifacts = true;
        final secondFiles = MemoryStoreFiles(secondBinding)..hasLiveFile = true;
        final registry = InMemoryRootRegistry();
        final firstProtector = SoftwareTestProtector(
          binding: firstBinding,
          registry: registry,
        );
        final secondProtector = SoftwareTestProtector(
          binding: secondBinding,
          registry: registry,
        );
        final firstRoot = await firstProtector.createOnly(
          interaction: PlatformInteraction.forbidden,
        );
        final secondRoot = await secondProtector.createOnly(
          interaction: PlatformInteraction.forbidden,
        );
        final secondState = secondRoot.lease.providerState;
        await firstRoot.lease.close();
        await secondRoot.lease.close();

        await expectLater(
          firstProtector.openExisting(
            secondState,
            interaction: PlatformInteraction.forbidden,
          ),
          throwsA(
            isA<PlatformProtectorFailure>().having(
              (failure) => failure.code,
              'code',
              PlatformProtectorFailureCode.invalidated,
            ),
          ),
        );
        await firstFiles.withExclusiveTransaction(
          (transaction) => transaction.resetManagedArtifacts(),
        );
        expect((await firstFiles.observeArtifacts()).isAbsent, isTrue);
        expect((await secondFiles.observeArtifacts()).hasLiveFile, isTrue);
        await _commitReset(firstProtector);
        expect(registry.rootCount, 1);
        final survivingRoot = await secondProtector.openExisting(
          secondState,
          interaction: PlatformInteraction.forbidden,
        );
        expect(survivingRoot, isNotNull);
        await survivingRoot!.close();
        await _commitReset(secondProtector);
        expect(registry.rootCount, 0);
      },
    );
  });
}

Future<void> _commitReset(PlatformProtector protector) async {
  final preparation = await protector.prepareReset(
    interaction: PlatformInteraction.forbidden,
  );
  try {
    await preparation.commit();
  } finally {
    await preparation.close();
  }
}

ResolvedApplicationBinding _binding({
  String id = 'dev.example.test',
  required String root,
  ApplicationIdentitySource source = ApplicationIdentitySource.test,
  ApplicationIdentityAssurance assurance =
      ApplicationIdentityAssurance.namespaceOnly,
  String profile = 'test.memory',
}) => ResolvedApplicationBinding.derive(
  identity: ApplicationIdentity(
    stableValue: id,
    source: source,
    assurance: assurance,
  ),
  profile: HostProfile(profile),
  canonicalFileRoot: Uri.directory(root),
);

Matcher _protectorFailure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

Matcher _storeFailure(StoreFilesFailureCode code) =>
    isA<StoreFilesFailure>().having((failure) => failure.code, 'code', code);

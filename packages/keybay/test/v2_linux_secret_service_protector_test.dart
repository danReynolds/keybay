@Tags(<String>['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/linux_secret_service_protector.dart';
import 'package:keybay/src/v2/linux_secret_service_root_store.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

void main() {
  test('forbidden acquisitions never enter Secret Service', () async {
    final roots = _MemoryRootStore();
    final protector = LinuxSecretServiceProtector(
      binding: _binding(root: '/test/linux-no-interaction'),
      roots: roots,
    );
    for (final operation in <Future<Object?> Function()>[
      () => protector.createOnly(interaction: PlatformInteraction.forbidden),
      () => protector.openExisting(
        ProviderState(Uint8List(32)),
        interaction: PlatformInteraction.forbidden,
      ),
      () => protector.prepareReset(interaction: PlatformInteraction.forbidden),
    ]) {
      await expectLater(
        operation(),
        throwsA(_failure(PlatformProtectorFailureCode.interactionRequired)),
      );
    }
    expect(roots.lockedAddresses, isEmpty);
    expect([roots.readCount, roots.createCount, roots.deleteCount], [0, 0, 0]);
  });

  test('creates, seals, and reopens through one fixed provider root', () async {
    final roots = _MemoryRootStore();
    final protector = LinuxSecretServiceProtector(
      binding: _binding(root: '/test/linux-root'),
      roots: roots,
    );

    final creation = await protector.createOnly(
      interaction: PlatformInteraction.allowed,
    );
    expect(creation.disposition, RootCreationDisposition.created);
    expect(roots.itemCount, 1);
    expect(roots.lockedAddresses, <String>[protector.binding.providerAddress]);
    final state = ProviderState(creation.lease.providerState.copyBytes());
    final plaintext = Uint8List.fromList(<int>[1, 2, 3]);
    final aad = Uint8List.fromList(<int>[4, 5, 6]);
    final sealed = await creation.lease.sealPackage(
      plaintext: plaintext,
      aad: aad,
    );
    await creation.lease.close();

    final reopened = await protector.openExisting(
      state,
      interaction: PlatformInteraction.allowed,
    );
    expect(reopened, isNotNull);
    expect(
      await reopened!.openPackage(sealedPackage: sealed, aad: aad),
      plaintext,
    );
    await reopened.close();
    roots.dispose();
  });

  test('adopts one existing root and never creates a replacement', () async {
    final roots = _MemoryRootStore();
    final protector = LinuxSecretServiceProtector(
      binding: _binding(root: '/test/linux-adopt'),
      roots: roots,
    );
    final first = await protector.createOnly(
      interaction: PlatformInteraction.allowed,
    );
    final state = first.lease.providerState.copyBytes();
    await first.lease.close();
    final record = roots.copyOnly(protector.binding.providerAddress);

    final second = await protector.createOnly(
      interaction: PlatformInteraction.allowed,
    );

    expect(second.disposition, RootCreationDisposition.adopted);
    expect(second.lease.providerState.copyBytes(), state);
    expect(roots.createCount, 1);
    expect(roots.copyOnly(protector.binding.providerAddress), record);
    await second.lease.close();
    roots.dispose();
  });

  test(
    'zero, one, and multiple matches never collapse to arbitrary choice',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/linux-duplicates');
      final protector = LinuxSecretServiceProtector(
        binding: binding,
        roots: roots,
      );
      roots.addRaw(binding.providerAddress, Uint8List.fromList(<int>[1]));
      roots.addRaw(binding.providerAddress, Uint8List.fromList(<int>[2]));

      await expectLater(
        protector.createOnly(interaction: PlatformInteraction.allowed),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      await expectLater(
        protector.openExisting(
          ProviderState(List<int>.filled(32, 0)),
          interaction: PlatformInteraction.allowed,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      await expectLater(
        protector.prepareReset(interaction: PlatformInteraction.allowed),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      expect(roots.itemCount, 2);
      roots.dispose();
    },
  );

  test(
    'create re-query rejects a duplicate or changed provider winner',
    () async {
      final duplicateRoots = _MemoryRootStore()..duplicateOnCreate = true;
      final duplicateProtector = LinuxSecretServiceProtector(
        binding: _binding(root: '/test/linux-create-duplicate'),
        roots: duplicateRoots,
      );
      await expectLater(
        duplicateProtector.createOnly(interaction: PlatformInteraction.allowed),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      expect(duplicateRoots.itemCount, 2);
      duplicateRoots.dispose();

      final changedRoots = _MemoryRootStore()..alterOnCreate = true;
      final changedProtector = LinuxSecretServiceProtector(
        binding: _binding(root: '/test/linux-create-changed'),
        roots: changedRoots,
      );
      await expectLater(
        changedProtector.createOnly(interaction: PlatformInteraction.allowed),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      expect(changedRoots.itemCount, 1);
      changedRoots.dispose();
    },
  );

  test('same provider identity rejects a different XDG file domain', () async {
    final roots = _MemoryRootStore();
    final firstBinding = _binding(root: '/test/linux-domain-a');
    final secondBinding = _binding(root: '/test/linux-domain-b');
    expect(firstBinding.providerAddress, secondBinding.providerAddress);
    expect(firstBinding.domain, isNot(secondBinding.domain));
    final first = LinuxSecretServiceProtector(
      binding: firstBinding,
      roots: roots,
    );
    final second = LinuxSecretServiceProtector(
      binding: secondBinding,
      roots: roots,
    );
    final created = await first.createOnly(
      interaction: PlatformInteraction.allowed,
    );
    await created.lease.close();

    await expectLater(
      second.createOnly(interaction: PlatformInteraction.allowed),
      throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
    );
    expect(roots.itemCount, 1);
    roots.dispose();
  });

  test('root replacement is invalidated before package opening', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/linux-replacement');
    final protector = LinuxSecretServiceProtector(
      binding: binding,
      roots: roots,
    );
    final created = await protector.createOnly(
      interaction: PlatformInteraction.allowed,
    );
    final state = ProviderState(created.lease.providerState.copyBytes());
    await created.lease.close();
    roots.flipLastValueByte(binding.providerAddress);

    await expectLater(
      protector.openExisting(state, interaction: PlatformInteraction.allowed),
      throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
    );
    expect(roots.itemCount, 1);
    roots.dispose();
  });

  test(
    'wrong-sized provider state is rejected without a provider query',
    () async {
      final roots = _MemoryRootStore();
      final protector = LinuxSecretServiceProtector(
        binding: _binding(root: '/test/linux-state'),
        roots: roots,
      );

      await expectLater(
        protector.openExisting(
          ProviderState(<int>[1]),
          interaction: PlatformInteraction.allowed,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
      expect(roots.readCount, 0);
      roots.dispose();
    },
  );

  test(
    'prepared reset revalidates, deletes, and verifies fixed-target absence',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/linux-reset');
      final protector = LinuxSecretServiceProtector(
        binding: binding,
        roots: roots,
      );
      final created = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      await created.lease.close();

      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );
      await reset.commit();
      await reset.close();
      expect(roots.itemCount, 0);
      expect(roots.deleteCount, 1);
      expect(roots.lockedAddresses.last, binding.providerAddress);
      roots.dispose();
    },
  );

  test('prepared reset preserves a root changed after preparation', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/linux-reset-race');
    final protector = LinuxSecretServiceProtector(
      binding: binding,
      roots: roots,
    );
    final created = await protector.createOnly(
      interaction: PlatformInteraction.allowed,
    );
    await created.lease.close();
    final reset = await protector.prepareReset(
      interaction: PlatformInteraction.allowed,
    );
    roots.flipLastValueByte(binding.providerAddress);

    await expectLater(
      reset.commit(),
      throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
    );
    await reset.close();
    expect(roots.itemCount, 1);
    expect(roots.deleteCount, 0);
    roots.dispose();
  });

  test(
    'an absent reset never deletes a root created after preparation',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/linux-reset-absent-race');
      final protector = LinuxSecretServiceProtector(
        binding: binding,
        roots: roots,
      );
      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );
      final created = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      await created.lease.close();

      await expectLater(
        reset.commit(),
        throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
      );
      await reset.close();
      expect(roots.itemCount, 1);
      expect(roots.deleteCount, 0);
      roots.dispose();
    },
  );

  test(
    'reset fails after a no-op delete instead of claiming success',
    () async {
      final roots = _MemoryRootStore()..deleteIsNoop = true;
      final binding = _binding(root: '/test/linux-reset-verify');
      final protector = LinuxSecretServiceProtector(
        binding: binding,
        roots: roots,
      );
      final created = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      await created.lease.close();
      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );

      await expectLater(
        reset.commit(),
        throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
      );
      await reset.close();
      expect(roots.itemCount, 1);
      roots.dispose();
    },
  );

  test(
    'malformed fixed-address state is resettable but not openable',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/linux-malformed');
      final protector = LinuxSecretServiceProtector(
        binding: binding,
        roots: roots,
      );
      roots.addRaw(binding.providerAddress, Uint8List.fromList(<int>[1, 2, 3]));

      await expectLater(
        protector.openExisting(
          ProviderState(List<int>.filled(32, 0)),
          interaction: PlatformInteraction.allowed,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );
      await reset.commit();
      await reset.close();
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );

  test('provider failures map to redacted V2 failures', () async {
    final roots = _MemoryRootStore();
    final protector = LinuxSecretServiceProtector(
      binding: _binding(root: '/test/linux-errors'),
      roots: roots,
    );
    roots.nextFailure = const KeystoreLocked('sensitive detail');
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.locked)),
    );
    roots.nextFailure = const KeystoreUnreachable('sensitive detail');
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.unavailable)),
    );
    roots.nextFailure = const LinuxSecretServiceInteractionRequired();
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.interactionRequired)),
    );
    roots.nextFailure = const LinuxSecretServiceProviderBusy();
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.busy)),
    );
    roots.dispose();
  });
}

ResolvedApplicationBinding _binding({required String root}) =>
    ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.linux-protector-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('linux.desktop.secret-service-file.v1'),
      canonicalFileRoot: Uri.directory(root),
    );

Matcher _failure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

final class _MemoryRootStore implements LinuxSecretServiceRootStore {
  final Map<String, List<Uint8List>> _items = <String, List<Uint8List>>{};
  final List<String> lockedAddresses = <String>[];
  Exception? nextFailure;
  int createCount = 0;
  int readCount = 0;
  int deleteCount = 0;
  bool deleteIsNoop = false;
  bool duplicateOnCreate = false;
  bool alterOnCreate = false;

  int get itemCount =>
      _items.values.fold<int>(0, (total, values) => total + values.length);

  @override
  Future<void> createNew(String providerAddress, Uint8List value) async {
    createCount++;
    final stored = Uint8List.fromList(value);
    if (alterOnCreate) stored[stored.length - 1] ^= 0xff;
    final values = _items.putIfAbsent(providerAddress, () => <Uint8List>[])
      ..add(stored);
    if (duplicateOnCreate) {
      final duplicate = Uint8List.fromList(value);
      duplicate[duplicate.length - 1] ^= 0x01;
      values.add(duplicate);
    }
  }

  @override
  Future<void> delete(LinuxSecretServiceRoot root) async {
    deleteCount++;
    if (deleteIsNoop) return;
    if (root is! _MemoryRoot || !identical(root.owner, this)) {
      throw StateError('foreign root');
    }
    final values = _items[root.address];
    if (values == null || !values.remove(root.token)) {
      throw StateError('stale root');
    }
    root.token.fillRange(0, root.token.length, 0);
    if (values.isEmpty) {
      _items.remove(root.address);
    }
  }

  @override
  Future<LinuxSecretServiceRoot?> readUnique(String providerAddress) async {
    readCount++;
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    final values = _items[providerAddress] ?? const <Uint8List>[];
    if (values.length > 1) {
      throw const LinuxSecretServiceMultipleMatches();
    }
    return values.isEmpty
        ? null
        : _MemoryRoot(
            owner: this,
            address: providerAddress,
            token: values.single,
            value: Uint8List.fromList(values.single),
          );
  }

  @override
  Future<T> withCreationLock<T>(
    String providerAddress,
    Future<T> Function() operation,
  ) async {
    lockedAddresses.add(providerAddress);
    return operation();
  }

  void addRaw(String providerAddress, Uint8List value) {
    _items
        .putIfAbsent(providerAddress, () => <Uint8List>[])
        .add(Uint8List.fromList(value));
  }

  Uint8List copyOnly(String providerAddress) =>
      Uint8List.fromList(_items[providerAddress]!.single);

  void flipLastValueByte(String providerAddress) {
    final value = _items[providerAddress]!.single;
    value[value.length - 1] ^= 0xff;
  }

  void dispose() {
    for (final values in _items.values) {
      for (final value in values) {
        value.fillRange(0, value.length, 0);
      }
    }
    _items.clear();
  }
}

final class _MemoryRoot implements LinuxSecretServiceRoot {
  _MemoryRoot({
    required this.owner,
    required this.address,
    required this.token,
    required this.value,
  });

  final _MemoryRootStore owner;
  final String address;
  final Uint8List token;

  @override
  final Uint8List value;
}

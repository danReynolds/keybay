@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/entropy_source.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/macos_login_keychain_protector.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_platform_contract.dart';
import 'support/v2_entropy_source.dart';

void main() {
  test('forbidden acquisitions never touch the classic Keychain', () async {
    final roots = _MemoryRootStore();
    final protector = MacOSLoginKeychainProtector(
      binding: _binding(root: '/test/macos-no-interaction'),
      roots: roots,
    );
    final failure = throwsA(
      _failure(PlatformProtectorFailureCode.interactionRequired),
    );
    await expectLater(
      protector.createOnly(interaction: PlatformInteraction.forbidden),
      failure,
    );
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.forbidden,
      ),
      failure,
    );
    await expectLater(
      protector.prepareReset(interaction: PlatformInteraction.forbidden),
      failure,
    );
    expect(roots.reads, isEmpty);
    expect(roots.creates, isEmpty);
    expect(roots.itemCount, 0);
  });

  runDisposablePlatformProtectorContract(
    name: 'macOS login Keychain',
    createFixture: () {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/macos-contract');

      MacOSLoginKeychainProtector newInstance() =>
          MacOSLoginKeychainProtector(binding: binding, roots: roots);

      return (
        newInstance: newInstance,
        dispose: () async {
          final reset = await newInstance().prepareReset(
            interaction: PlatformInteraction.allowed,
          );
          try {
            await reset.commit();
          } finally {
            await reset.close();
            roots.dispose();
          }
        },
      );
    },
  );

  test(
    'uses the exact binding-derived address in the narrow root store',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/macos-address');
      final protector = MacOSLoginKeychainProtector(
        binding: binding,
        roots: roots,
      );

      final created = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      expect(created.disposition, RootCreationDisposition.created);
      expect(created.lease.providerState.length, 32);
      final state = ProviderState(created.lease.providerState.copyBytes());
      expect(roots.creates, hasLength(1));
      expect(roots.creates.single.providerAddress, binding.providerAddress);
      expect(roots.creates.single.valueLength, 72);
      await created.lease.close();

      final opened = await protector.openExisting(
        state,
        interaction: PlatformInteraction.allowed,
      );
      expect(opened, isNotNull);
      expect(roots.reads.last, binding.providerAddress);
      await opened!.close();
      roots.dispose();
    },
  );

  test(
    'same provider address rejects a different storage-domain root',
    () async {
      final roots = _MemoryRootStore();
      final firstBinding = _binding(root: '/test/macos-root-a');
      final secondBinding = _binding(root: '/test/macos-root-b');
      expect(firstBinding.providerAddress, secondBinding.providerAddress);
      expect(firstBinding.domain, isNot(secondBinding.domain));

      final first = MacOSLoginKeychainProtector(
        binding: firstBinding,
        roots: roots,
      );
      final second = MacOSLoginKeychainProtector(
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
    },
  );

  test(
    'reset cannot delete a valid root owned by another storage domain',
    () async {
      final roots = _MemoryRootStore();
      final first = MacOSLoginKeychainProtector(
        binding: _binding(root: '/test/macos-reset-domain-a'),
        roots: roots,
      );
      final second = MacOSLoginKeychainProtector(
        binding: _binding(root: '/test/macos-reset-domain-b'),
        roots: roots,
      );
      final created = await first.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      await created.lease.close();

      await expectLater(
        second.prepareReset(interaction: PlatformInteraction.allowed),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      expect(roots.itemCount, 1);
      roots.dispose();
    },
  );

  test(
    'rejects wrong-sized provider state without touching the Keychain',
    () async {
      final roots = _MemoryRootStore();
      final protector = MacOSLoginKeychainProtector(
        binding: _binding(root: '/test/macos-state'),
        roots: roots,
      );

      await expectLater(
        protector.openExisting(
          ProviderState(<int>[1]),
          interaction: PlatformInteraction.allowed,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
      expect(roots.reads, isEmpty);
      roots.dispose();
    },
  );

  test('maps Keychain failures to redacted provider states', () async {
    final roots = _MemoryRootStore();
    final protector = MacOSLoginKeychainProtector(
      binding: _binding(root: '/test/macos-errors'),
      roots: roots,
    );

    roots.nextReadFailure = const KeystoreLocked('sensitive detail');
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.locked)),
    );
    roots.nextReadFailure = const KeystoreUnreachable('sensitive detail');
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.unavailable)),
    );
    roots.nextReadFailure = const KeystoreOperationFailed(
      'sensitive detail',
      status: -1,
    );
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.operationFailed)),
    );
    roots.nextReadFailure = const KeystoreOperationFailed(
      'sensitive detail',
      status: -25293,
    );
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.operationFailed)),
    );
    roots.nextReadFailure = const KeystoreOperationFailed(
      'sensitive detail',
      status: -25315,
    );
    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.interactionRequired)),
    );
    roots.dispose();
  });

  test('a create collision followed by deletion fails closed', () async {
    final roots = _MemoryRootStore()..duplicateThenMissing = true;
    final protector = MacOSLoginKeychainProtector(
      binding: _binding(root: '/test/macos-disappeared'),
      roots: roots,
    );

    await expectLater(
      protector.createOnly(interaction: PlatformInteraction.allowed),
      throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
    );
    expect(roots.itemCount, 0);
    roots.dispose();
  });

  test('successful create must read back the exact provider record', () async {
    final roots = _MemoryRootStore()..alterSuccessfulCreate = true;
    final protector = MacOSLoginKeychainProtector(
      binding: _binding(root: '/test/macos-create-readback'),
      roots: roots,
    );

    await expectLater(
      protector.createOnly(interaction: PlatformInteraction.allowed),
      throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
    );
    expect(roots.itemCount, 1);
    roots.dispose();
  });

  test(
    'entropy failures remain distinguishable at the engine boundary',
    () async {
      final roots = _MemoryRootStore();
      final entropy = ScriptedV2EntropySource(<List<int>>[
        List<int>.filled(32, 7),
      ]);
      final protector = MacOSLoginKeychainProtector(
        binding: _binding(root: '/test/macos-entropy'),
        roots: roots,
        entropy: entropy,
      );
      final created = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      entropy.nextFailure = const V2EntropyFailure();

      await expectLater(
        created.lease.sealPackage(
          plaintext: Uint8List.fromList(<int>[1]),
          aad: Uint8List.fromList(<int>[2]),
        ),
        throwsA(isA<V2EntropyFailure>()),
      );
      await created.lease.close();
      entropy.dispose();
      roots.dispose();
    },
  );

  test('root-generation entropy failure creates no provider state', () async {
    final roots = _MemoryRootStore();
    final entropy = ScriptedV2EntropySource(const <List<int>>[])
      ..nextFailure = const V2EntropyFailure();
    final protector = MacOSLoginKeychainProtector(
      binding: _binding(root: '/test/macos-root-entropy'),
      roots: roots,
      entropy: entropy,
    );

    await expectLater(
      protector.createOnly(interaction: PlatformInteraction.allowed),
      throwsA(isA<V2EntropyFailure>()),
    );
    expect(roots.itemCount, 0);
    entropy.dispose();
    roots.dispose();
  });

  test('malformed provider records are invalidation, not absence', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/macos-malformed');
    final protector = MacOSLoginKeychainProtector(
      binding: binding,
      roots: roots,
    );
    roots.putRaw(binding.providerAddress, Uint8List.fromList(<int>[1, 2, 3]));

    await expectLater(
      protector.openExisting(
        ProviderState(List<int>.filled(32, 0)),
        interaction: PlatformInteraction.allowed,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
    );
    expect(roots.itemCount, 1);
    roots.dispose();
  });

  test('root replacement is invalidated before package opening', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/macos-root-replaced');
    final protector = MacOSLoginKeychainProtector(
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
    'prepared reset can remove malformed state at its fixed address',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/macos-malformed-reset');
      final protector = MacOSLoginKeychainProtector(
        binding: binding,
        roots: roots,
      );
      roots.putRaw(binding.providerAddress, Uint8List.fromList(<int>[1, 2, 3]));

      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );
      await reset.commit();
      await reset.close();
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );

  test(
    'provider deletion is reported as absence for the expected generation',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/macos-root-deleted');
      final protector = MacOSLoginKeychainProtector(
        binding: binding,
        roots: roots,
      );
      final created = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      final state = ProviderState(created.lease.providerState.copyBytes());
      await created.lease.close();
      await roots.delete(binding.providerAddress);

      expect(
        await protector.openExisting(
          state,
          interaction: PlatformInteraction.allowed,
        ),
        isNull,
      );
      roots.dispose();
    },
  );

  test('prepared reset refuses a replaced root and preserves it', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/macos-reset-race');
    final protector = MacOSLoginKeychainProtector(
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
    roots.dispose();
  });

  test('absent prepared reset never deletes a later-created root', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/macos-reset-absent-race');
    final protector = MacOSLoginKeychainProtector(
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
    roots.dispose();
  });
}

ResolvedApplicationBinding _binding({required String root}) =>
    ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.macos-protector-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('macos.login-file-keychain'),
      canonicalFileRoot: Uri.directory(root),
    );

Matcher _failure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

final class _MemoryRootStore implements MacOSLoginKeychainRootStore {
  final Map<String, Uint8List> _items = <String, Uint8List>{};
  final List<String> reads = <String>[];
  final List<({String providerAddress, int valueLength})> creates =
      <({String providerAddress, int valueLength})>[];

  Exception? nextReadFailure;
  bool duplicateThenMissing = false;
  bool alterSuccessfulCreate = false;

  int get itemCount => _items.length;

  @override
  Future<bool> createIfAbsent(String providerAddress, Uint8List value) async {
    creates.add((providerAddress: providerAddress, valueLength: value.length));
    if (duplicateThenMissing) return false;
    if (_items.containsKey(providerAddress)) return false;
    final stored = Uint8List.fromList(value);
    if (alterSuccessfulCreate) stored[stored.length - 1] ^= 0xff;
    _items[providerAddress] = stored;
    return true;
  }

  @override
  Future<Uint8List?> read(String providerAddress) async {
    reads.add(providerAddress);
    final failure = nextReadFailure;
    nextReadFailure = null;
    if (failure != null) throw failure;
    final value = _items[providerAddress];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<bool> exists(String providerAddress) async =>
      _items.containsKey(providerAddress);

  @override
  Future<void> delete(String providerAddress) async {
    final removed = _items.remove(providerAddress);
    if (removed != null) _clear(removed);
  }

  void putRaw(String providerAddress, Uint8List value) {
    _items[providerAddress] = Uint8List.fromList(value);
  }

  void flipLastValueByte(String providerAddress) {
    final value = _items[providerAddress]!;
    value[value.length - 1] ^= 0xff;
  }

  void dispose() {
    for (final value in _items.values) {
      _clear(value);
    }
    _items.clear();
  }
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

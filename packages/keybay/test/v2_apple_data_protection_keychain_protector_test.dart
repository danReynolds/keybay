@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/errors.dart';
import 'package:keybay/src/ffi/keychain.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_protector.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_root_store.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_platform_contract.dart';

void main() {
  test('V2 exact-group factory rejects empty and wildcard selectors', () {
    expect(
      () => AppleKeychainApi.v2DataProtection(
        exactApplicationIdentifierAccessGroup: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => AppleKeychainApi.v2DataProtection(
        exactApplicationIdentifierAccessGroup: 'ABCDE12345.*',
      ),
      throwsArgumentError,
    );
  });

  runDisposablePlatformProtectorContract(
    name: 'Apple Data Protection Keychain',
    createFixture: () {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/apple-dpk-contract');

      AppleDataProtectionKeychainProtector newInstance() =>
          AppleDataProtectionKeychainProtector(binding: binding, roots: roots);

      return (
        newInstance: newInstance,
        dispose: () async {
          final reset = await newInstance().prepareReset(
            interaction: PlatformInteraction.forbidden,
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
    'uses one binding-derived address and commits the storage domain',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/apple-dpk-address');
      final protector = AppleDataProtectionKeychainProtector(
        binding: binding,
        roots: roots,
      );

      final created = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await created.lease.close();
      expect(roots.creates, <String>[binding.providerAddress]);
      final record = roots.copyOnly(binding.providerAddress);
      final expectedDomain = binding.domain.copyBytes();
      try {
        expect(record.length, v2AppleDataProtectionRootRecordBytes);
        expect(record.sublist(0, 8), 'KBV2AP01'.codeUnits);
        expect(record.sublist(8, 40), expectedDomain);
      } finally {
        _clear(record);
        _clear(expectedDomain);
        roots.dispose();
      }
    },
  );

  test(
    'old-domain state is never opened or adopted but explicit reset owns it',
    () async {
      final roots = _MemoryRootStore();
      final oldProtector = AppleDataProtectionKeychainProtector(
        binding: _binding(root: '/test/apple-dpk-old-root'),
        roots: roots,
      );
      final currentProtector = AppleDataProtectionKeychainProtector(
        binding: _binding(root: '/test/apple-dpk-current-root'),
        roots: roots,
      );
      final old = await oldProtector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      final oldState = ProviderState(old.lease.providerState.copyBytes());
      await old.lease.close();

      await expectLater(
        currentProtector.openExisting(
          oldState,
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      await expectLater(
        currentProtector.createOnly(interaction: PlatformInteraction.forbidden),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      final reset = await currentProtector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      await reset.commit();
      await reset.close();
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );

  test(
    'malformed state is not healed on open but explicit reset owns it',
    () async {
      final roots = _MemoryRootStore();
      final binding = _binding(root: '/test/apple-dpk-malformed');
      final protector = AppleDataProtectionKeychainProtector(
        binding: binding,
        roots: roots,
      );
      roots.putRaw(binding.providerAddress, Uint8List.fromList(<int>[1, 2, 3]));

      await expectLater(
        protector.openExisting(
          ProviderState(List<int>.filled(32, 0)),
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
      expect(roots.itemCount, 1);
      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      await reset.commit();
      await reset.close();
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );

  test('root replacement is rejected by provider-state continuity', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/apple-dpk-continuity');
    final protector = AppleDataProtectionKeychainProtector(
      binding: binding,
      roots: roots,
    );
    final created = await protector.createOnly(
      interaction: PlatformInteraction.forbidden,
    );
    final state = ProviderState(created.lease.providerState.copyBytes());
    await created.lease.close();
    roots.flipLastByte(binding.providerAddress);

    await expectLater(
      protector.openExisting(state, interaction: PlatformInteraction.forbidden),
      throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
    );
    roots.dispose();
  });

  test(
    'successful creation must read back the exact inserted record',
    () async {
      final roots = _MemoryRootStore()..alterSuccessfulCreate = true;
      final protector = AppleDataProtectionKeychainProtector(
        binding: _binding(root: '/test/apple-dpk-readback'),
        roots: roots,
      );

      await expectLater(
        protector.createOnly(interaction: PlatformInteraction.forbidden),
        throwsA(_failure(PlatformProtectorFailureCode.stateConflict)),
      );
      expect(roots.itemCount, 1);
      roots.dispose();
    },
  );

  test('prepared reset refuses changed bytes and preserves them', () async {
    final roots = _MemoryRootStore();
    final binding = _binding(root: '/test/apple-dpk-reset-race');
    final protector = AppleDataProtectionKeychainProtector(
      binding: binding,
      roots: roots,
    );
    final created = await protector.createOnly(
      interaction: PlatformInteraction.forbidden,
    );
    await created.lease.close();
    final reset = await protector.prepareReset(
      interaction: PlatformInteraction.forbidden,
    );
    roots.flipLastByte(binding.providerAddress);

    await expectLater(
      reset.commit(),
      throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
    );
    await reset.close();
    expect(roots.itemCount, 1);
    roots.dispose();
  });

  test('wrong-sized provider state fails before a Keychain read', () async {
    final roots = _MemoryRootStore();
    final protector = AppleDataProtectionKeychainProtector(
      binding: _binding(root: '/test/apple-dpk-state'),
      roots: roots,
    );

    await expectLater(
      protector.openExisting(
        ProviderState(<int>[1]),
        interaction: PlatformInteraction.forbidden,
      ),
      throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
    );
    expect(roots.reads, isEmpty);
    roots.dispose();
  });

  test(
    'Keychain errors cross the protector seam as redacted failures',
    () async {
      final roots = _MemoryRootStore();
      final protector = AppleDataProtectionKeychainProtector(
        binding: _binding(root: '/test/apple-dpk-errors'),
        roots: roots,
      );
      final state = ProviderState(List<int>.filled(32, 0));

      roots.nextReadFailure = const KeystoreLocked('sensitive detail');
      await expectLater(
        protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.locked)),
      );
      roots.nextReadFailure = const KeystoreOperationFailed(
        'sensitive detail',
        status: -25315,
      );
      await expectLater(
        protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.interactionRequired)),
      );
      roots.nextReadFailure = const KeystoreUnreachable('sensitive detail');
      await expectLater(
        protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.unavailable)),
      );
      roots.dispose();
    },
  );
}

ResolvedApplicationBinding _binding({required String root}) =>
    ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'ABCDE12345.dev.keybay.apple-dpk-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.osEnforced,
      ),
      profile: HostProfile('apple.data-protection-keychain'),
      canonicalFileRoot: Uri.directory(root),
    );

Matcher _failure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

final class _MemoryRootStore implements DataProtectionKeychainRootStore {
  final Map<String, Uint8List> _items = <String, Uint8List>{};
  final List<String> reads = <String>[];
  final List<String> creates = <String>[];

  Exception? nextReadFailure;
  bool alterSuccessfulCreate = false;

  int get itemCount => _items.length;

  @override
  Future<bool> createIfAbsent(String providerAddress, Uint8List value) async {
    creates.add(providerAddress);
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

  Uint8List copyOnly(String providerAddress) =>
      Uint8List.fromList(_items[providerAddress]!);

  void putRaw(String providerAddress, Uint8List value) {
    _items[providerAddress] = Uint8List.fromList(value);
  }

  void flipLastByte(String providerAddress) {
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

@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/android_keystore_protector.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

void main() {
  test(
    'uses one fixed identity-derived alias and proves its first key',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final binding = _binding('/android/no-backup/keybay');
      final protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: keystore,
      );

      final created = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      expect(created.disposition, RootCreationDisposition.created);
      expect(created.lease.providerState.length, 60);
      expect(keystore.aliases, <String>{
        'keybay.v2.${binding.providerAddress}',
      });
      expect(keystore.createdAliases, <String>[
        'keybay.v2.${binding.providerAddress}',
      ]);
      expect(
        keystore.openCount,
        1,
        reason: 'creation must read back its proof',
      );
      await created.lease.close();
    },
  );

  test(
    'opens byte-identical provider state and detects root replacement',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final binding = _binding('/android/no-backup/keybay');
      final protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: keystore,
      );
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      final state = ProviderState(creation.lease.providerState.copyBytes());
      await creation.lease.close();

      final opened = await protector.openExisting(
        state,
        interaction: PlatformInteraction.forbidden,
      );
      expect(opened, isNotNull);
      expect(opened!.providerState.hasSameBytes(state), isTrue);
      await opened.close();

      keystore.replaceOnlyKey();
      await expectLater(
        protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
    },
  );

  test(
    'rejects malformed and tampered provider state before leasing',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final protector = AndroidKeystoreProtector(
        binding: _binding('/android/no-backup/keybay'),
        keystore: keystore,
      );

      await expectLater(
        protector.openExisting(
          ProviderState(<int>[1]),
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
      expect(keystore.containsCount, 0);

      final creation = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      final tampered = creation.lease.providerState.copyBytes()..[20] ^= 0xff;
      await creation.lease.close();
      await expectLater(
        protector.openExisting(
          ProviderState(tampered),
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
    },
  );

  test(
    'adopts an existing root without replacing it and verifies read-back',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final binding = _binding('/android/no-backup/keybay');
      AndroidKeystoreProtector protector() =>
          AndroidKeystoreProtector(binding: binding, keystore: keystore);

      final first = await protector().createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      final firstKeyGeneration = keystore.keyGeneration;
      final plaintext = Uint8List.fromList(<int>[1, 2, 3]);
      final aad = Uint8List.fromList(<int>[4, 5, 6]);
      final sealed = await first.lease.sealPackage(
        plaintext: plaintext,
        aad: aad,
      );
      await first.lease.close();

      final second = await protector().createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      expect(second.disposition, RootCreationDisposition.adopted);
      expect(keystore.keyGeneration, firstKeyGeneration);
      expect(
        await second.lease.openPackage(sealedPackage: sealed, aad: aad),
        plaintext,
      );
      await second.lease.close();
    },
  );

  test(
    'refuses a freshly generated root that fails cryptographic read-back',
    () async {
      final keystore = _MemoryAndroidKeystore()
        ..failNextOpenAuthentication = true;
      final protector = AndroidKeystoreProtector(
        binding: _binding('/android/no-backup/keybay'),
        keystore: keystore,
      );

      await expectLater(
        protector.createOnly(interaction: PlatformInteraction.forbidden),
        throwsA(_failure(PlatformProtectorFailureCode.operationFailed)),
      );
      expect(keystore.aliases, hasLength(1));
    },
  );

  test(
    'authenticates the exact caller AAD and snapshots mutable inputs',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final protector = AndroidKeystoreProtector(
        binding: _binding('/android/no-backup/keybay'),
        keystore: keystore,
      );
      final lease = (await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      )).lease;

      final plaintext = Uint8List.fromList(<int>[1, 2, 3]);
      final aad = Uint8List.fromList(<int>[4, 5, 6]);
      final sealing = lease.sealPackage(plaintext: plaintext, aad: aad);
      plaintext.fillRange(0, plaintext.length, 9);
      aad.fillRange(0, aad.length, 9);
      final sealed = await sealing;

      expect(
        await lease.openPackage(
          sealedPackage: sealed,
          aad: Uint8List.fromList(<int>[4, 5, 6]),
        ),
        <int>[1, 2, 3],
      );
      await expectLater(
        lease.openPackage(
          sealedPackage: sealed,
          aad: Uint8List.fromList(<int>[4, 5, 7]),
        ),
        throwsA(_failure(PlatformProtectorFailureCode.authenticationFailed)),
      );
      await expectLater(
        lease.openPackage(
          sealedPackage: Uint8List.fromList(<int>[...sealed, 0]),
          aad: Uint8List.fromList(<int>[4, 5, 6]),
        ),
        throwsA(_failure(PlatformProtectorFailureCode.authenticationFailed)),
      );
      await lease.close();
    },
  );

  test('clears transient caller copies and provider result buffers', () async {
    final keystore = _MemoryAndroidKeystore();
    final protector = AndroidKeystoreProtector(
      binding: _binding('/android/no-backup/keybay'),
      keystore: keystore,
    );
    final lease = (await protector.createOnly(
      interaction: PlatformInteraction.forbidden,
    )).lease;
    final sealed = await lease.sealPackage(
      plaintext: Uint8List.fromList(<int>[1, 2, 3]),
      aad: Uint8List.fromList(<int>[4, 5, 6]),
    );
    await lease.openPackage(
      sealedPackage: sealed,
      aad: Uint8List.fromList(<int>[4, 5, 6]),
    );

    expect(keystore.observedPlaintexts, isNotEmpty);
    expect(keystore.observedAads, isNotEmpty);
    expect(keystore.observedNonces, isNotEmpty);
    expect(keystore.returnedPlaintexts, isNotEmpty);
    for (final buffer in <Uint8List>[
      ...keystore.observedPlaintexts,
      ...keystore.observedAads,
      ...keystore.observedNonces,
      ...keystore.observedCiphertexts,
      ...keystore.returnedPlaintexts,
    ]) {
      expect(buffer, everyElement(0));
    }
    await lease.close();
  });

  test(
    'reset is non-mutating until commit and owns only the fixed alias',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final binding = _binding('/android/no-backup/keybay');
      final protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: keystore,
      );
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await creation.lease.close();
      final alias = keystore.aliases.single;

      final aborted = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      expect(keystore.aliases, contains(alias));
      await aborted.close();
      expect(keystore.aliases, contains(alias));

      final prepared = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      keystore.replaceOnlyKey();
      await prepared.commit();
      expect(keystore.aliases, isEmpty);
      expect(keystore.deletedAliases, <String>[alias]);
      await prepared.close();
    },
  );

  test(
    'an absent reset cannot delete a key created after preparation',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final binding = _binding('/android/no-backup/keybay');
      final protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: keystore,
      );
      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      await creation.lease.close();

      await expectLater(
        reset.commit(),
        throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
      );
      expect(keystore.aliases, isNotEmpty);
      expect(keystore.deletedAliases, isEmpty);
      await reset.close();
    },
  );

  test(
    'explicit reset removes an unusable fixed alias and permits reinit',
    () async {
      final keystore = _MemoryAndroidKeystore();
      final binding = _binding('/android/no-backup/keybay');
      final protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: keystore,
      );
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      final state = ProviderState(creation.lease.providerState.copyBytes());
      await creation.lease.close();

      keystore.cryptoFailure = const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
      await expectLater(
        protector.openExisting(
          state,
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );

      final reset = await protector.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      await reset.commit();
      await reset.close();
      expect(keystore.aliases, isEmpty);

      keystore.cryptoFailure = null;
      final reinitialized = await protector.createOnly(
        interaction: PlatformInteraction.forbidden,
      );
      expect(reinitialized.disposition, RootCreationDisposition.created);
      await reinitialized.lease.close();
    },
  );

  test('provider failures are precise and redacted', () async {
    final keystore = _MemoryAndroidKeystore()
      ..failure = const KeystoreUnreachable('secret marker');
    final protector = AndroidKeystoreProtector(
      binding: _binding('/android/no-backup/private-name'),
      keystore: keystore,
    );

    Object? caught;
    try {
      await protector.openExisting(
        ProviderState(List<int>.filled(60, 0)),
        interaction: PlatformInteraction.forbidden,
      );
    } on Object catch (error) {
      caught = error;
    }
    expect(caught, _failure(PlatformProtectorFailureCode.unavailable));
    expect(caught.toString(), isNot(contains('secret marker')));
    expect(caught.toString(), isNot(contains('private-name')));
  });

  test('closed leases retain no operation authority', () async {
    final protector = AndroidKeystoreProtector(
      binding: _binding('/android/no-backup/keybay'),
      keystore: _MemoryAndroidKeystore(),
    );
    final lease = (await protector.createOnly(
      interaction: PlatformInteraction.forbidden,
    )).lease;
    await lease.close();
    await lease.close();
    await expectLater(
      lease.sealPackage(plaintext: Uint8List(0), aad: Uint8List(0)),
      throwsA(_failure(PlatformProtectorFailureCode.leaseClosed)),
    );
    await expectLater(
      lease.openPackage(sealedPackage: Uint8List(0), aad: Uint8List(0)),
      throwsA(_failure(PlatformProtectorFailureCode.leaseClosed)),
    );
  });
}

ResolvedApplicationBinding _binding(String path) =>
    ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'com.example.keybay-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.osEnforced,
      ),
      profile: HostProfile('android-api31'),
      canonicalFileRoot: Uri.directory(path),
    );

Matcher _failure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

final class _MemoryAndroidKeystore implements AndroidKeystoreAead {
  static final DartAesGcm _aead = DartAesGcm.with256bits();

  final Map<String, Uint8List> _keys = <String, Uint8List>{};
  final List<String> createdAliases = <String>[];
  final List<String> deletedAliases = <String>[];
  final List<Uint8List> observedPlaintexts = <Uint8List>[];
  final List<Uint8List> observedAads = <Uint8List>[];
  final List<Uint8List> observedNonces = <Uint8List>[];
  final List<Uint8List> observedCiphertexts = <Uint8List>[];
  final List<Uint8List> returnedPlaintexts = <Uint8List>[];

  Exception? failure;
  Exception? cryptoFailure;
  int containsCount = 0;
  int openCount = 0;
  int keyGeneration = 0;
  int _nonceCounter = 0;
  bool failNextOpenAuthentication = false;

  Set<String> get aliases => _keys.keys.toSet();

  @override
  Future<bool> contains(String alias) async {
    containsCount++;
    _throwFailure();
    return _keys.containsKey(alias);
  }

  @override
  Future<bool> createUnderExclusiveLock(String alias) async {
    _throwFailure();
    if (_keys.containsKey(alias)) return false;
    keyGeneration++;
    createdAliases.add(alias);
    _keys[alias] = Uint8List.fromList(
      List<int>.generate(32, (index) => (keyGeneration + index) & 0xff),
    );
    return true;
  }

  @override
  Future<AndroidKeystoreBox> seal({
    required String alias,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    _throwFailure();
    _throwCryptoFailure();
    observedPlaintexts.add(plaintext);
    observedAads.add(aad);
    final key = _keys[alias];
    if (key == null) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    _nonceCounter++;
    final nonce = Uint8List(12)
      ..buffer.asByteData().setUint32(8, _nonceCounter);
    final secretKey = SecretKeyData(Uint8List.fromList(key));
    try {
      final box = _aead.encryptSync(
        plaintext,
        secretKeyData: secretKey,
        nonce: nonce,
        aad: aad,
      );
      return AndroidKeystoreBox(
        nonce: Uint8List.fromList(box.nonce),
        ciphertext: Uint8List.fromList(<int>[
          ...box.cipherText,
          ...box.mac.bytes,
        ]),
      );
    } finally {
      secretKey.destroy();
      nonce.fillRange(0, nonce.length, 0);
    }
  }

  @override
  Future<Uint8List> open({
    required String alias,
    required AndroidKeystoreBox box,
    required Uint8List aad,
  }) async {
    _throwFailure();
    _throwCryptoFailure();
    openCount++;
    observedNonces.add(box.nonce);
    observedCiphertexts.add(box.ciphertext);
    observedAads.add(aad);
    if (failNextOpenAuthentication) {
      failNextOpenAuthentication = false;
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    }
    final key = _keys[alias];
    if (key == null) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    final tagStart = box.ciphertext.length - 16;
    if (tagStart < 0) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    }
    final secretKey = SecretKeyData(Uint8List.fromList(key));
    try {
      final plaintext = _aead.decryptSync(
        SecretBox(
          Uint8List.sublistView(box.ciphertext, 0, tagStart),
          nonce: box.nonce,
          mac: Mac(Uint8List.sublistView(box.ciphertext, tagStart)),
        ),
        secretKeyData: secretKey,
        aad: aad,
      );
      final result = Uint8List.fromList(plaintext);
      returnedPlaintexts.add(result);
      return result;
    } on SecretBoxAuthenticationError {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.authenticationFailed,
      );
    } finally {
      secretKey.destroy();
    }
  }

  @override
  Future<void> delete(String alias) async {
    _throwFailure();
    final removed = _keys.remove(alias);
    if (removed != null) {
      removed.fillRange(0, removed.length, 0);
      deletedAliases.add(alias);
    }
  }

  void replaceOnlyKey() {
    final alias = _keys.keys.single;
    final previous = _keys[alias]!;
    previous.fillRange(0, previous.length, 0);
    keyGeneration++;
    _keys[alias] = Uint8List.fromList(
      List<int>.generate(32, (index) => (0x80 + keyGeneration + index) & 0xff),
    );
  }

  void _throwFailure() {
    final current = failure;
    if (current != null) throw current;
  }

  void _throwCryptoFailure() {
    final current = cryptoFailure;
    if (current != null) throw current;
  }
}

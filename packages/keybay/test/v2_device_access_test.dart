@TestOn('mac-os || linux')
@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/android_keystore_protector.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_protector.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_root_store.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/posix_store_files.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_platform_fakes.dart';
import 'support/v2_test_keybay.dart';

void main() {
  group('Apple Data Protection Keychain deviceAccess', () {
    late Directory root;
    late _TestAppleRootStore roots;
    late _TrackingStoreFiles files;
    late V2StoreEngine engine;
    late ResolvedApplicationBinding binding;

    setUp(() {
      root = Directory.systemTemp.createTempSync('keybay-dp-access-');
      final canonicalRoot = Uri.directory(root.resolveSymbolicLinksSync());
      binding = ResolvedApplicationBinding.derive(
        identity: ApplicationIdentity(
          stableValue: 'TEAMID1234.dev.keybay.testapp',
          source: ApplicationIdentitySource.operatingSystem,
          assurance: ApplicationIdentityAssurance.osEnforced,
        ),
        profile: HostProfile('ios.signed.data-protection-file.v1'),
        canonicalFileRoot: canonicalRoot,
      );
      roots = _TestAppleRootStore();
      files = _TrackingStoreFiles(
        PosixStoreFiles.fromExistingPrivateRoot(
          binding: binding,
          canonicalFileRoot: canonicalRoot,
        ),
      );
      engine = V2StoreEngine(
        _StaticHostPlatform(
          ResolvedHost(
            binding: binding,
            files: files,
            protector: AppleDataProtectionKeychainProtector(
              binding: binding,
              roots: roots,
            ),
          ),
        ),
        passphraseDeriver: FastTestPassphraseDeriver(),
      );
    });

    tearDown(() {
      roots.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'defaults to whenUnlocked and never silently downgrades on open',
      () async {
        final first = await engine.open();
        expect(first.wasInitialized, isTrue);
        await first.set('db/key', 'alpha');
        await first.close();

        expect(
          roots.accessOf(binding.providerAddress),
          KeybayDeviceAccess.whenUnlocked,
        );

        // Opening an existing store with relaxed options must NOT mutate it.
        final second = await engine.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        expect(second.wasInitialized, isFalse);
        expect(await second.get('db/key'), 'alpha');
        expect(
          roots.accessOf(binding.providerAddress),
          KeybayDeviceAccess.whenUnlocked,
        );
        expect(roots.updateCalls, isEmpty);
        await second.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'initializes directly as afterFirstUnlock when explicitly opted in',
      () async {
        final session = await engine.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        expect(session.wasInitialized, isTrue);
        expect(
          roots.accessOf(binding.providerAddress),
          KeybayDeviceAccess.afterFirstUnlock,
        );
        await session.set('token', 'live');
        await session.close();

        final reopened = await engine.open();
        expect(await reopened.get('token'), 'live');
        expect(
          roots.accessOf(binding.providerAddress),
          KeybayDeviceAccess.afterFirstUnlock,
        );
        await reopened.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'setDeviceAccess updates in place, closes pins on every path, verifies read-back, preserves auth methods, and fails closed when locked',
      () async {
        final session = await engine.open();
        await session.set('k1', 'v1');
        await session.auth.add(
          PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('secret')),
          ),
        );
        final rootBefore = roots.copyOf(binding.providerAddress);

        await session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(files.openPins, 0);
        expect(
          roots.accessOf(binding.providerAddress),
          KeybayDeviceAccess.afterFirstUnlock,
        );
        expect(roots.copyOf(binding.providerAddress), rootBefore);
        expect(roots.updateCalls, [KeybayDeviceAccess.afterFirstUnlock]);

        // Repeating the same target is a verified no-op and still closes pins.
        await session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(files.openPins, 0);
        expect(roots.updateCalls, [KeybayDeviceAccess.afterFirstUnlock]);

        // Read-back mismatch fails closed.
        roots.ignoreNextUpdate = true;
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.platformOperationFailed,
            ),
          ),
        );
        expect(files.openPins, 0);

        // Locked keychain fails closed with platformProtectorLocked.
        roots.nextUpdateFailure = const KeystoreLocked('device locked');
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.platformProtectorLocked,
            ),
          ),
        );
        expect(files.openPins, 0);

        // Tightening back succeeds and keeps passphrase + record intact.
        await session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(files.openPins, 0);
        expect(
          roots.accessOf(binding.providerAddress),
          KeybayDeviceAccess.whenUnlocked,
        );
        await session.close();

        // Closed session refuses setDeviceAccess.
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.sessionClosed,
            ),
          ),
        );

        final reopened = await engine.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('secret')),
          ),
        );
        expect(await reopened.get('k1'), 'v1');
        await reopened.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'Apple createOnly read-back mismatch and updateDeviceAccess missing-item fail closed',
      () async {
        final protector = AppleDataProtectionKeychainProtector(
          binding: binding,
          roots: roots,
        );

        roots.wrongCreateReadBack = KeybayDeviceAccess.afterFirstUnlock;
        await expectLater(
          protector.createOnly(
            interaction: PlatformInteraction.forbidden,
            deviceAccess: KeybayDeviceAccess.whenUnlocked,
          ),
          throwsA(
            isA<PlatformProtectorFailure>().having(
              (e) => e.code,
              'code',
              PlatformProtectorFailureCode.operationFailed,
            ),
          ),
        );

        await roots.delete(binding.providerAddress);
        final created = await protector.createOnly(
          interaction: PlatformInteraction.forbidden,
          deviceAccess: KeybayDeviceAccess.whenUnlocked,
        );
        final prepared = await protector.prepareDeviceAccessChange(
          created.lease.providerState,
          deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          interaction: PlatformInteraction.allowed,
        );
        expect(prepared, isNotNull);
        roots.returnFalseOnNextUpdate = true;
        await expectLater(
          prepared!.commit(),
          throwsA(
            isA<PlatformProtectorFailure>().having(
              (e) => e.code,
              'code',
              PlatformProtectorFailureCode.invalidated,
            ),
          ),
        );
        await prepared.close();
        await created.lease.close();
      },
    );

    test(
      'stale session and abandoned staging fail closed without touching Keychain',
      () async {
        final session = await engine.open();
        await session.set('k', 'v');
        // Abandoned staging artifact alongside live store -> storeStateConflict.
        final stagingFile = File('${root.path}/keybay.v2.stage');
        stagingFile.writeAsBytesSync(const <int>[1, 2, 3]);
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.storeStateConflict,
            ),
          ),
        );
        expect(roots.updateCalls, isEmpty);
        expect(files.openPins, 0);
        stagingFile.deleteSync();

        // Reset invalidates the existing session -> staleSession.
        await engine.reset();
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.staleSession,
            ),
          ),
        );
        expect(roots.updateCalls, isEmpty);
        await session.close();
      },
    );
  });

  group('Android 12+ Keystore deviceAccess', () {
    late Directory root;
    late _TestAndroidKeystore keystore;
    late _TrackingStoreFiles files;
    late V2StoreEngine engine;
    late ResolvedApplicationBinding binding;
    late AndroidKeystoreProtector protector;

    String primaryAlias() => 'keybay.v2.${binding.providerAddress}';
    String alternateAlias() => 'keybay.v2.${binding.providerAddress}.alt';

    setUp(() {
      root = Directory.systemTemp.createTempSync('keybay-android-access-');
      final canonicalRoot = Uri.directory(root.resolveSymbolicLinksSync());
      binding = ResolvedApplicationBinding.derive(
        identity: ApplicationIdentity(
          stableValue: 'dev.keybay.androidtest',
          source: ApplicationIdentitySource.operatingSystem,
          assurance: ApplicationIdentityAssurance.osEnforced,
        ),
        profile: HostProfile('android.api31.keystore-file.v1'),
        canonicalFileRoot: canonicalRoot,
      );
      keystore = _TestAndroidKeystore();
      protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: keystore,
      );
      files = _TrackingStoreFiles(
        PosixStoreFiles.fromExistingPrivateRoot(
          binding: binding,
          canonicalFileRoot: canonicalRoot,
        ),
      );
      engine = V2StoreEngine(
        _StaticHostPlatform(
          ResolvedHost(binding: binding, files: files, protector: protector),
        ),
        passphraseDeriver: FastTestPassphraseDeriver(),
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'aligns Android default to strict whenUnlocked (setUnlockedDeviceRequired: true) and never silently downgrades',
      () async {
        final first = await engine.open();
        await first.set('k', 'v');
        await first.close();

        expect(keystore.aliases, {primaryAlias()});
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isTrue);

        final second = await engine.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        expect(await second.get('k'), 'v');
        expect(keystore.aliases, {primaryAlias()});
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isTrue);
        await second.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'initializes directly as afterFirstUnlock (setUnlockedDeviceRequired: false)',
      () async {
        final session = await engine.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        await session.set('bg', 'ok');
        await session.close();

        expect(keystore.aliases, {primaryAlias()});
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isFalse);

        final reopened = await engine.open();
        expect(await reopened.get('bg'), 'ok');
        await reopened.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'setDeviceAccess rotates A/B aliases atomically, preserves records & passphrase, retires old alias, and resets both slots',
      () async {
        final session = await engine.open();
        await session.set('a', 'one');
        await session.set('b', 'two');
        await session.auth.add(
          PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('pass-1')),
          ),
        );
        expect(keystore.aliases, {primaryAlias()});
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isTrue);

        // No-op when already at whenUnlocked.
        final gensBeforeNoop = keystore.generations;
        await session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(keystore.generations, gensBeforeNoop);
        expect(files.openPins, 0);

        // Rotate slot 0 -> slot 1 (afterFirstUnlock).
        await session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(keystore.aliases, {alternateAlias()});
        expect(keystore.unlockedDeviceRequired[alternateAlias()], isFalse);
        expect(await session.get('a'), 'one');
        expect(await session.get('b'), 'two');
        expect(files.openPins, 0);

        // Rotate slot 1 -> slot 0 (back to whenUnlocked).
        await session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(keystore.aliases, {primaryAlias()});
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isTrue);
        await session.close();

        // Reopen using the enrolled passphrase (preserved without reprompting).
        final reopened = await engine.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('pass-1')),
          ),
        );
        expect(await reopened.get('a'), 'one');
        expect(await reopened.get('b'), 'two');
        // Rotate back onto alternate slot, then verify reset deletes alternate slot.
        await reopened.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(keystore.aliases, {alternateAlias()});
        await reopened.close();

        await engine.reset();
        expect(keystore.aliases, isEmpty);
        expect(files.openPins, 0);
      },
    );

    test(
      'failed rotation before replaceLive cleans up unused replacement alias without harming live vault',
      () async {
        final session = await engine.open();
        await session.set('safe', 'intact');

        // Fail sealing the key package during rotation (reset counter first).
        keystore.resetSealCounter();
        keystore.failNthSeal =
            2; // 1st seal is continuity state, 2nd is package.
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock),
          throwsA(isA<KeybayException>()),
        );

        expect(keystore.aliases, {primaryAlias()});
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isTrue);
        expect(await session.get('safe'), 'intact');
        await session.close();

        final reopened = await engine.open();
        expect(await reopened.get('safe'), 'intact');
        await reopened.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'post-rename replaceLive failure preserves replacement alias so live vault is never lost',
      () async {
        final session = await engine.open();
        await session.set('precious', 'survives');

        // Inject a failure AFTER the atomic rename succeeds (e.g., post-rename
        // directory fsync failure). The live file now depends on alternateAlias.
        files.throwAfterReplaceLive = true;
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock),
          throwsA(isA<KeybayException>()),
        );
        expect(files.openPins, 0);

        // alternateAlias MUST still exist so the rotated live file opens cleanly.
        expect(keystore.aliases, contains(alternateAlias()));
        await session.close();

        final reopened = await engine.open();
        expect(await reopened.get('precious'), 'survives');
        // Retrying the same target cleans up the lingering retired primaryAlias.
        await reopened.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(keystore.aliases, {alternateAlias()});
        await reopened.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'failed post-rename verification preserves replacement alias and retry cleans retired alias',
      () async {
        final session = await engine.open();
        await session.set('precious', 'still-here');

        // Inject a failure when opening live for post-rename verification.
        files.failNextOpenLiveAfterNextReplace();
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock),
          throwsA(isA<KeybayException>()),
        );
        expect(files.openPins, 0);

        expect(keystore.aliases, contains(alternateAlias()));
        await session.close();

        final reopened = await engine.open();
        expect(await reopened.get('precious'), 'still-here');
        await reopened.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(keystore.aliases, {alternateAlias()});
        await reopened.close();
      },
    );

    test(
      'failed retired-alias deletion on commit leaves live intact and retry deletes weaker leftover key',
      () async {
        final session = await engine.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        await session.set('secret', 'protected');

        // Tightening afterFirstUnlock (slot 0) -> whenUnlocked (slot 1): fail
        // deleting retired slot 0 on commit.
        keystore.failNextDeleteFor = primaryAlias();
        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.platformOperationFailed,
            ),
          ),
        );
        expect(keystore.aliases, {primaryAlias(), alternateAlias()});

        // Retrying whenUnlocked must clean up the lingering retired slot 0 key
        // without performing another full key rotation.
        final gensBeforeRetry = keystore.generations;
        await session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(keystore.generations, gensBeforeRetry);
        expect(keystore.aliases, {alternateAlias()});
        expect(keystore.unlockedDeviceRequired[alternateAlias()], isTrue);
        expect(await session.get('secret'), 'protected');
        await session.close();
      },
    );

    test(
      'rotation clears a leftover inactive-slot key before generating replacement',
      () async {
        final session = await engine.open();
        await session.set('item', 'kept');
        await keystore.createUnderExclusiveLock(
          alternateAlias(),
          unlockedDeviceRequired: false,
        );
        expect(keystore.aliases, {primaryAlias(), alternateAlias()});

        await session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(keystore.aliases, {alternateAlias()});
        expect(keystore.unlockedDeviceRequired[alternateAlias()], isFalse);
        expect(await session.get('item'), 'kept');
        await session.close();
      },
    );

    test(
      'end-to-end V2StoreEngine opens a legacy 60-byte Android store with passphrase and migrates via setDeviceAccess',
      () async {
        // Initialize a genuine V2 store using a protector that writes the exact
        // pre-0.4 60-byte Android continuity state on primaryAlias.
        final legacyProtector = _Legacy60ByteAndroidProtector(
          binding: binding,
          keystore: keystore,
          primaryAlias: primaryAlias(),
        );
        final legacyEngine = V2StoreEngine(
          _StaticHostPlatform(
            ResolvedHost(
              binding: binding,
              files: files,
              protector: legacyProtector,
            ),
          ),
          passphraseDeriver: FastTestPassphraseDeriver(),
        );
        final legacySession = await legacyEngine.open();
        await legacySession.set('legacy/key', 'legacy-value');
        await legacySession.auth.add(
          PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('legacy-pass')),
          ),
        );
        await legacySession.close();
        expect(keystore.unlockedDeviceRequired[primaryAlias()], isFalse);

        // Open with the current AndroidKeystoreProtector engine, verify secret,
        // migrate to strict whenUnlocked, and reopen cleanly.
        final migrated = await engine.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('legacy-pass')),
          ),
        );
        expect(migrated.wasInitialized, isFalse);
        expect(await migrated.get('legacy/key'), 'legacy-value');

        await migrated.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(keystore.aliases, {alternateAlias()});
        expect(keystore.unlockedDeviceRequired[alternateAlias()], isTrue);
        await migrated.close();

        final reopened = await engine.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList(utf8.encode('legacy-pass')),
          ),
        );
        expect(await reopened.get('legacy/key'), 'legacy-value');
        await reopened.close();
        expect(files.openPins, 0);
      },
    );

    test(
      'tampered Android continuity tag, version, slot, reserved bits, strip, and spoof are all rejected',
      () async {
        final created = await protector.createOnly(
          interaction: PlatformInteraction.forbidden,
          deviceAccess: KeybayDeviceAccess.whenUnlocked,
        );
        final tagged = created.lease.providerState.copyBytes();
        await created.lease.close();
        expect(tagged.length, 62);

        // Create alternate alias too so slot-flip fails AAD, not mere absence.
        await keystore.createUnderExclusiveLock(
          alternateAlias(),
          unlockedDeviceRequired: true,
        );

        final mutations = <String, Uint8List>{
          'flipped access bit': Uint8List.fromList(tagged)..[1] ^= 0x02,
          'flipped slot bit': Uint8List.fromList(tagged)..[1] ^= 0x01,
          'wrong version byte': Uint8List.fromList(tagged)..[0] ^= 0x01,
          'reserved flag bit': Uint8List.fromList(tagged)..[1] |= 0x04,
          '62->60 header strip': Uint8List.fromList(tagged.sublist(2)),
        };

        for (final entry in mutations.entries) {
          await expectLater(
            protector.openExisting(
              ProviderState(entry.value),
              interaction: PlatformInteraction.forbidden,
            ),
            throwsA(
              isA<PlatformProtectorFailure>().having(
                (e) => e.code,
                'code',
                PlatformProtectorFailureCode.invalidated,
              ),
            ),
            reason: 'mutation "${entry.key}" must fail closed',
          );
        }

        // Also test 60->62 header-prepend spoof against a genuine 60-byte box.
        final legacyAad = Uint8List.fromList(
          utf8.encode(
            'keybay:v2:android-keystore:continuity\u0000${binding.providerAddress}',
          ),
        );
        final legacyBox = await keystore.seal(
          alias: primaryAlias(),
          plaintext: binding.domain.copyBytes(),
          aad: legacyAad,
        );
        final spoofed62 = Uint8List.fromList(<int>[
          2,
          0,
          ...legacyBox.nonce,
          ...legacyBox.ciphertext,
        ]);
        await expectLater(
          protector.openExisting(
            ProviderState(spoofed62),
            interaction: PlatformInteraction.forbidden,
          ),
          throwsA(
            isA<PlatformProtectorFailure>().having(
              (e) => e.code,
              'code',
              PlatformProtectorFailureCode.invalidated,
            ),
          ),
          reason: '60->62 header-prepend spoof must fail closed',
        );
      },
    );

    test(
      'abandoned alternate slot blocks new initialization (fail closed)',
      () async {
        await keystore.createUnderExclusiveLock(
          alternateAlias(),
          unlockedDeviceRequired: false,
        );
        await expectLater(
          protector.createOnly(interaction: PlatformInteraction.forbidden),
          throwsA(
            isA<PlatformProtectorFailure>().having(
              (e) => e.code,
              'code',
              PlatformProtectorFailureCode.stateConflict,
            ),
          ),
        );
        expect(keystore.aliases, {alternateAlias()});
      },
    );
  });

  group('Desktop login keyring no-op semantics', () {
    test(
      'setDeviceAccess is a clean verified no-op, closes pins, and rejects closed sessions',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'keybay-desktop-access-',
        );
        addTearDown(() {
          if (root.existsSync()) root.deleteSync(recursive: true);
        });
        final canonicalRoot = Uri.directory(root.resolveSymbolicLinksSync());
        final binding = ResolvedApplicationBinding.derive(
          identity: ApplicationIdentity(
            stableValue: 'dev.keybay.desktoptest',
            source: ApplicationIdentitySource.sourcePubspec,
            assurance: ApplicationIdentityAssurance.namespaceOnly,
          ),
          profile: HostProfile('linux.desktop.secret-service-file.v1'),
          canonicalFileRoot: canonicalRoot,
        );
        final files = _TrackingStoreFiles(
          PosixStoreFiles.fromExistingPrivateRoot(
            binding: binding,
            canonicalFileRoot: canonicalRoot,
          ),
        );
        final engine = V2StoreEngine(
          _StaticHostPlatform(
            ResolvedHost(
              binding: binding,
              files: files,
              protector: SoftwareTestProtector(
                binding: binding,
                registry: InMemoryRootRegistry(),
              ),
            ),
          ),
        );

        final session = await engine.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        await session.set('item', 'value');
        await session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(files.openPins, 0);
        await session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(files.openPins, 0);
        expect(await session.get('item'), 'value');
        await session.close();

        await expectLater(
          session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked),
          throwsA(
            isA<KeybayException>().having(
              (e) => e.code,
              'code',
              KeybayErrorCode.sessionClosed,
            ),
          ),
        );
        expect(files.openPins, 0);
      },
    );
  });
}

final class _StaticHostPlatform implements HostPlatform {
  const _StaticHostPlatform(this._host);
  final ResolvedHost _host;
  @override
  Future<ResolvedHost> resolve() async => _host;
}

final class _TrackingStoreFiles implements StoreFiles {
  _TrackingStoreFiles(this._inner);
  final StoreFiles _inner;

  int openPins = 0;
  bool throwAfterReplaceLive = false;
  bool _failOpenAfterNextReplace = false;
  bool _replacedSinceArm = false;

  void failNextOpenLiveAfterNextReplace() {
    _failOpenAfterNextReplace = true;
    _replacedSinceArm = false;
  }

  @override
  ResolvedApplicationBinding get binding => _inner.binding;

  @override
  Future<PinnedStoreFile?> openPinnedLive() async {
    final pin = await _inner.openPinnedLive();
    if (pin == null) return null;
    openPins++;
    return _TrackingPinnedStoreFile(pin, () => openPins--);
  }

  @override
  Future<T> withExclusiveTransaction<T>(
    Future<T> Function(StoreTransaction transaction) operation,
  ) => _inner.withExclusiveTransaction(
    (tx) => operation(_TrackingStoreTransaction(this, tx)),
  );
}

final class _TrackingStoreTransaction implements StoreTransaction {
  _TrackingStoreTransaction(this._owner, this._inner);
  final _TrackingStoreFiles _owner;
  final StoreTransaction _inner;

  @override
  Future<StoreArtifacts> observeArtifacts() => _inner.observeArtifacts();

  @override
  Future<PinnedStoreFile?> openPinnedLive() async {
    if (_owner._replacedSinceArm && _owner._failOpenAfterNextReplace) {
      _owner._failOpenAfterNextReplace = false;
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final pin = await _inner.openPinnedLive();
    if (pin == null) return null;
    _owner.openPins++;
    return _TrackingPinnedStoreFile(pin, () => _owner.openPins--);
  }

  @override
  Future<StagedStoreFile> createStaging({required int expectedLength}) async {
    final stage = await _inner.createStaging(expectedLength: expectedLength);
    return _TrackingStagedStoreFile(_owner, stage);
  }

  @override
  Future<void> discardAbandonedStaging() => _inner.discardAbandonedStaging();

  @override
  Future<void> resetManagedArtifacts() => _inner.resetManagedArtifacts();
}

final class _TrackingStagedStoreFile implements StagedStoreFile {
  _TrackingStagedStoreFile(this._owner, this._inner);
  final _TrackingStoreFiles _owner;
  final StagedStoreFile _inner;

  @override
  Future<void> append(Uint8List bytes) => _inner.append(bytes);

  @override
  Future<PinnedStoreFile> finish() async {
    final pin = await _inner.finish();
    _owner.openPins++;
    return _TrackingPinnedStoreFile(pin, () => _owner.openPins--);
  }

  @override
  Future<void> replaceLive() async {
    await _inner.replaceLive();
    _owner._replacedSinceArm = true;
    if (_owner.throwAfterReplaceLive) {
      _owner.throwAfterReplaceLive = false;
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
  }
}

final class _TrackingPinnedStoreFile implements PinnedStoreFile {
  _TrackingPinnedStoreFile(this._inner, this._onClose);
  final PinnedStoreFile _inner;
  final void Function() _onClose;
  bool _closed = false;

  @override
  int get length => _inner.length;

  @override
  Future<Uint8List> readExact({required int offset, required int length}) =>
      _inner.readExact(offset: offset, length: length);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _inner.close();
    } finally {
      _onClose();
    }
  }
}

final class _Legacy60ByteAndroidProtector implements PlatformProtector {
  _Legacy60ByteAndroidProtector({
    required this.binding,
    required this.keystore,
    required this.primaryAlias,
  });

  @override
  final ResolvedApplicationBinding binding;
  final _TestAndroidKeystore keystore;
  final String primaryAlias;

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
    KeybayDeviceAccess deviceAccess = KeybayDeviceAccess.whenUnlocked,
  }) async {
    await keystore.createUnderExclusiveLock(
      primaryAlias,
      unlockedDeviceRequired: false,
    );
    final aad = Uint8List.fromList(
      utf8.encode(
        'keybay:v2:android-keystore:continuity\u0000${binding.providerAddress}',
      ),
    );
    final box = await keystore.seal(
      alias: primaryAlias,
      plaintext: binding.domain.copyBytes(),
      aad: aad,
    );
    final state = ProviderState(
      Uint8List.fromList(<int>[...box.nonce, ...box.ciphertext]),
    );
    return PlatformRootCreation(
      lease: _LegacyAndroidLease(primaryAlias, state, keystore),
      disposition: RootCreationDisposition.created,
    );
  }

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) async => _LegacyAndroidLease(primaryAlias, state, keystore);

  @override
  Future<PreparedPlatformDeviceAccessChange?> prepareDeviceAccessChange(
    ProviderState state, {
    required KeybayDeviceAccess deviceAccess,
    required PlatformInteraction interaction,
  }) async => null;

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) => throw UnimplementedError();
}

final class _LegacyAndroidLease implements PlatformRootLease {
  _LegacyAndroidLease(this._alias, this.providerState, this._keystore);
  final String _alias;
  @override
  final ProviderState providerState;
  final _TestAndroidKeystore _keystore;

  @override
  Future<Uint8List> sealPackage({
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    final box = await _keystore.seal(
      alias: _alias,
      plaintext: plaintext,
      aad: aad,
    );
    return Uint8List.fromList(<int>[...box.nonce, ...box.ciphertext]);
  }

  @override
  Future<Uint8List> openPackage({
    required Uint8List sealedPackage,
    required Uint8List aad,
  }) => _keystore.open(
    alias: _alias,
    box: AndroidKeystoreBox(
      nonce: sealedPackage.sublist(0, 12),
      ciphertext: sealedPackage.sublist(12),
    ),
    aad: aad,
  );

  @override
  Future<void> close() async {}
}

final class _TestAppleRootStore implements DataProtectionKeychainRootStore {
  final Map<String, Uint8List> _items = <String, Uint8List>{};
  final Map<String, KeybayDeviceAccess> _access =
      <String, KeybayDeviceAccess>{};
  final List<KeybayDeviceAccess> updateCalls = <KeybayDeviceAccess>[];
  Exception? nextUpdateFailure;
  bool ignoreNextUpdate = false;
  bool returnFalseOnNextUpdate = false;
  KeybayDeviceAccess? wrongCreateReadBack;

  KeybayDeviceAccess? accessOf(String address) => _access[address];

  Uint8List copyOf(String address) => Uint8List.fromList(_items[address]!);

  @override
  Future<bool> createIfAbsent(
    String providerAddress,
    Uint8List value, {
    KeybayDeviceAccess deviceAccess = KeybayDeviceAccess.whenUnlocked,
  }) async {
    if (_items.containsKey(providerAddress)) return false;
    _items[providerAddress] = Uint8List.fromList(value);
    _access[providerAddress] = wrongCreateReadBack ?? deviceAccess;
    wrongCreateReadBack = null;
    return true;
  }

  @override
  Future<KeybayDeviceAccess?> readDeviceAccess(String providerAddress) async =>
      _access[providerAddress];

  @override
  Future<bool> updateDeviceAccess(
    String providerAddress,
    KeybayDeviceAccess deviceAccess,
  ) async {
    final failure = nextUpdateFailure;
    nextUpdateFailure = null;
    if (failure != null) throw failure;
    if (returnFalseOnNextUpdate) {
      returnFalseOnNextUpdate = false;
      return false;
    }
    if (!_items.containsKey(providerAddress)) return false;
    updateCalls.add(deviceAccess);
    if (ignoreNextUpdate) {
      ignoreNextUpdate = false;
      return true;
    }
    _access[providerAddress] = deviceAccess;
    return true;
  }

  @override
  Future<Uint8List?> read(String providerAddress) async {
    final v = _items[providerAddress];
    return v == null ? null : Uint8List.fromList(v);
  }

  @override
  Future<bool> exists(String providerAddress) async =>
      _items.containsKey(providerAddress);

  @override
  Future<void> delete(String providerAddress) async {
    final removed = _items.remove(providerAddress);
    _access.remove(providerAddress);
    removed?.fillRange(0, removed.length, 0);
  }

  void dispose() {
    for (final v in _items.values) {
      v.fillRange(0, v.length, 0);
    }
    _items.clear();
    _access.clear();
  }
}

final class _TestAndroidKeystore implements AndroidKeystoreAead {
  static final DartAesGcm _aead = DartAesGcm.with256bits();

  final Map<String, Uint8List> _keys = <String, Uint8List>{};
  final Map<String, bool> unlockedDeviceRequired = <String, bool>{};
  int generations = 0;
  int _nonceCounter = 0;
  int? failNthSeal;
  int _sealCalls = 0;
  String? failNextDeleteFor;

  void resetSealCounter() => _sealCalls = 0;

  Set<String> get aliases => _keys.keys.toSet();

  @override
  Future<bool> contains(String alias) async => _keys.containsKey(alias);

  @override
  Future<bool> createUnderExclusiveLock(
    String alias, {
    bool unlockedDeviceRequired = true,
    String? conflictAlias,
  }) async {
    return createAndroidKeystoreKeyUnderExclusiveLock(
      hasKey: () => _keys.containsKey(alias),
      containsAlias: () => _keys.containsKey(alias),
      hasConflictAlias: conflictAlias == null
          ? null
          : () => _keys.containsKey(conflictAlias),
      generateAndVerify: () {
        generations++;
        this.unlockedDeviceRequired[alias] = unlockedDeviceRequired;
        _keys[alias] = Uint8List.fromList(
          List<int>.generate(32, (i) => ((generations * 37) + i) & 0xff),
        );
      },
    );
  }

  @override
  Future<AndroidKeystoreBox> seal({
    required String alias,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    _sealCalls++;
    if (failNthSeal != null && _sealCalls == failNthSeal) {
      failNthSeal = null;
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    final key = _keys[alias];
    if (key == null) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    _nonceCounter++;
    final nonce = Uint8List(12)
      ..[8] = (_nonceCounter >> 24) & 0xff
      ..[9] = (_nonceCounter >> 16) & 0xff
      ..[10] = (_nonceCounter >> 8) & 0xff
      ..[11] = _nonceCounter & 0xff;
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return AndroidKeystoreBox(
      nonce: nonce,
      ciphertext: Uint8List.fromList(<int>[
        ...box.cipherText,
        ...box.mac.bytes,
      ]),
    );
  }

  @override
  Future<Uint8List> open({
    required String alias,
    required AndroidKeystoreBox box,
    required Uint8List aad,
  }) async {
    final key = _keys[alias];
    if (key == null) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    if (box.ciphertext.length < 16) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    final cipherText = box.ciphertext.sublist(0, box.ciphertext.length - 16);
    final mac = Mac(box.ciphertext.sublist(box.ciphertext.length - 16));
    try {
      final clear = await _aead.decrypt(
        SecretBox(cipherText, nonce: box.nonce, mac: mac),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
  }

  @override
  Future<void> delete(String alias) async {
    if (failNextDeleteFor == alias) {
      failNextDeleteFor = null;
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
    final removed = _keys.remove(alias);
    unlockedDeviceRequired.remove(alias);
    removed?.fillRange(0, removed.length, 0);
  }
}

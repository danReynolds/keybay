import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/ffi/apple_host.dart';
import 'package:keybay/src/v2/apple_data_protection_host_platform.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_root_store.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngine;

import 'mobile_security_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isIOS) return;
    const channel = MethodChannel(
      'dev.keybay.securityharness/keybay_device_security',
    );
    const timeout = Duration(seconds: 10);
    if (await channel.invokeMethod<bool>('isSimulator').timeout(timeout) !=
        true) {
      return;
    }

    // Flutter enables native semantics on simulators after view startup.
    // Wait before testWidgets records its handle baseline, so the persistent
    // platform-owned handle is not mistaken for a handle leaked by a test.
    final ready = Completer<void>();
    void semanticsChanged() {
      if (binding.platformDispatcher.semanticsEnabled && !ready.isCompleted) {
        ready.complete();
      }
    }

    binding.addSemanticsEnabledListener(semanticsChanged);
    try {
      semanticsChanged();
      await ready.future.timeout(timeout);
    } finally {
      binding.removeSemanticsEnabledListener(semanticsChanged);
    }
  });
  registerSecurityMetadata();
  setUp(() {
    if (!Platform.isIOS) return;
    expect(AppleHostApi.ios().bundleIdentifier(), 'dev.keybay.securityharness');
  });

  testWidgets('KB-IOS-010 iOS V2 ciphertext, reopen, passphrase, and reset', (
    WidgetTester _,
  ) async {
    if (!Platform.isIOS) {
      markTestSkipped('iOS-only');
      return;
    }

    final api = AppleHostApi.ios();
    final bundleIdentifier = api.bundleIdentifier();
    final applicationIdentifier = api.infoString(
      iosApplicationIdentifierInfoKey,
    );
    // Successful real-profile resolution includes Foundation backup-exclusion
    // write and immediate readback on the iOS application store directory.
    final resolved = await IOSHostPlatform().resolve();
    final facts = resolveIOSHostFacts(
      bundleIdentifier: bundleIdentifier,
      applicationIdentifier: applicationIdentifier,
      applicationSupportRoot: Uri.directory(api.applicationSupportDirectory()),
    );
    final roots = AppleDataProtectionKeychainRootStore(
      exactApplicationIdentifierAccessGroup: applicationIdentifier,
    );
    final store = File.fromUri(
      facts.canonicalFileRoot.resolve('keybay.v2.store'),
    );

    await Keybay.reset();
    KeybaySession? session;
    try {
      expect(await roots.exists(resolved.binding.providerAddress), isFalse);

      session = await Keybay.open();
      expect(session.wasInitialized, isTrue);
      await session.set('service/token', 'ios-v2-plaintext-marker');
      await session.setBytes(
        'service/binary',
        Uint8List.fromList(<int>[0, 1, 2, 255]),
      );
      expect(await session.get('service/token'), 'ios-v2-plaintext-marker');
      expect(await session.getBytes('service/binary'), <int>[0, 1, 2, 255]);
      await session.close();
      session = null;

      expect(await roots.exists(resolved.binding.providerAddress), isTrue);
      expect(store.existsSync(), isTrue);
      expect(store.parent.statSync().mode & 0x1ff, 0x1c0);
      expect(store.statSync().mode & 0x1ff, 0x180);
      expect(
        latin1.decode(store.readAsBytesSync(), allowInvalid: true),
        isNot(contains('ios-v2-plaintext-marker')),
      );

      // A separate engine has no retained state from the public singleton.
      // This establishes reopen behavior, not force-stop/relaunch continuity.
      session = await V2StoreEngine(IOSHostPlatform()).open();
      expect(session.wasInitialized, isFalse);
      expect(await session.get('service/token'), 'ios-v2-plaintext-marker');

      final phrase = Uint8List.fromList(utf8.encode('ios-test-passphrase'));
      final adding = session.auth.add(PassphraseCredential(phrase: phrase));
      phrase.fillRange(0, phrase.length, 0);
      final method = await adding;
      await session.close();
      session = null;

      await expectLater(
        Keybay.open(),
        throwsA(_failure(KeybayErrorCode.authRequired)),
      );
      final unlock = Uint8List.fromList(utf8.encode('ios-test-passphrase'));
      final opening = Keybay.open(
        credential: PassphraseCredential(phrase: unlock),
      );
      unlock.fillRange(0, unlock.length, 0);
      session = await opening;
      expect(await session.get('service/token'), 'ios-v2-plaintext-marker');
      await session.auth.remove(method);
    } finally {
      await session?.close();
      await Keybay.reset();
    }

    expect(await roots.exists(resolved.binding.providerAddress), isFalse);
    expect(store.existsSync(), isFalse);
  });

  testWidgets('KB-IOS-020 iOS V2 concurrent isolate updates', (_) async {
    if (!Platform.isIOS) {
      markTestSkipped('iOS-only');
      return;
    }
    await checkConcurrentMobileUpdates();
  });

  testWidgets(
    'iOS V2 deviceAccess defaults, opt-in init, and in-place SecItemUpdate',
    (_) async {
      if (!Platform.isIOS) {
        markTestSkipped('iOS-only');
        return;
      }

      final api = AppleHostApi.ios();
      final applicationIdentifier = api.infoString(
        iosApplicationIdentifierInfoKey,
      );
      final resolved = await IOSHostPlatform().resolve();
      final address = resolved.binding.providerAddress;
      final roots = AppleDataProtectionKeychainRootStore(
        exactApplicationIdentifierAccessGroup: applicationIdentifier,
      );

      await Keybay.reset();
      KeybaySession? session;
      try {
        // 1. Default open initializes with strict whenUnlocked.
        session = await Keybay.open();
        expect(session.wasInitialized, isTrue);
        expect(
          await roots.readDeviceAccess(address),
          KeybayDeviceAccess.whenUnlocked,
        );
        await session.set('bg/marker', 'ios-real-keychain');
        final rootBefore = await roots.read(address);
        expect(rootBefore, isNotNull);
        await session.close();
        session = null;

        // 2. Opening existing store with relaxed options never silently downgrades.
        session = await Keybay.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        expect(session.wasInitialized, isFalse);
        expect(
          await roots.readDeviceAccess(address),
          KeybayDeviceAccess.whenUnlocked,
        );

        // 3. Explicit setDeviceAccess updates kSecAttrAccessible in place via SecItemUpdate.
        await session.setDeviceAccess(KeybayDeviceAccess.afterFirstUnlock);
        expect(
          await roots.readDeviceAccess(address),
          KeybayDeviceAccess.afterFirstUnlock,
        );
        expect(await roots.read(address), rootBefore);
        expect(await session.get('bg/marker'), 'ios-real-keychain');

        // 4. Tightening back to whenUnlocked works in place too.
        await session.setDeviceAccess(KeybayDeviceAccess.whenUnlocked);
        expect(
          await roots.readDeviceAccess(address),
          KeybayDeviceAccess.whenUnlocked,
        );
        expect(await roots.read(address), rootBefore);
        await session.close();
        session = null;

        // 5. Fresh initialization with explicit afterFirstUnlock option.
        await Keybay.reset();
        session = await Keybay.open(
          options: const KeybayOptions(
            deviceAccess: KeybayDeviceAccess.afterFirstUnlock,
          ),
        );
        expect(session.wasInitialized, isTrue);
        expect(
          await roots.readDeviceAccess(address),
          KeybayDeviceAccess.afterFirstUnlock,
        );
        await session.set('bg/marker', 'born-after-first-unlock');
        expect(await session.get('bg/marker'), 'born-after-first-unlock');
      } finally {
        await session?.close();
        await Keybay.reset();
      }
      expect(await roots.exists(address), isFalse);
    },
  );
}

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

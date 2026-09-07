import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/ffi/apple_host.dart';
import 'package:keybay/src/v2/apple_data_protection_host_platform.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_root_store.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/macos_host_platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('entitled macOS V2 profile is isolated and resettable', (
    WidgetTester _,
  ) async {
    if (!Platform.isMacOS) {
      markTestSkipped('macOS-only');
      return;
    }

    final api = AppleHostApi.macOS();
    final bundleIdentifier = api.bundleIdentifier();
    final applicationIdentifier = api.macOSSignedApplicationIdentifier();
    final sandboxed = api.macOSAppSandboxEnabled();
    final resolved = await MacOSHostPlatform().resolve();
    final facts = resolveMacOSEntitledHostFacts(
      bundleIdentifier: bundleIdentifier,
      applicationIdentifier: applicationIdentifier,
      applicationSupportRoot: Uri.directory(api.applicationSupportDirectory()),
    );
    expect(sandboxed, isTrue);
    expect(applicationIdentifier, endsWith('.$bundleIdentifier'));
    expect(resolved.identity.stableValue, applicationIdentifier);
    expect(
      resolved.identity.assurance,
      ApplicationIdentityAssurance.osEnforced,
    );
    expect(resolved.profile.code, macOSEntitledDataProtectionProfileCode);
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
      await session.set('service/token', 'macos-v2-plaintext-marker');
      await session.setBytes(
        'service/binary',
        Uint8List.fromList(<int>[0, 1, 2, 255]),
      );
      expect(await session.get('service/token'), 'macos-v2-plaintext-marker');
      expect(await session.getBytes('service/binary'), <int>[0, 1, 2, 255]);
      await session.close();
      session = null;

      expect(await roots.exists(resolved.binding.providerAddress), isTrue);
      expect(store.existsSync(), isTrue);
      expect(store.parent.statSync().mode & 0x1ff, 0x1c0);
      expect(store.statSync().mode & 0x1ff, 0x180);
      expect(
        latin1.decode(store.readAsBytesSync(), allowInvalid: true),
        isNot(contains('macos-v2-plaintext-marker')),
      );

      session = await Keybay.open();
      expect(session.wasInitialized, isFalse);
      expect(await session.get('service/token'), 'macos-v2-plaintext-marker');

      final phrase = Uint8List.fromList(utf8.encode('macos-test-passphrase'));
      final adding = session.auth.add(PassphraseCredential(phrase: phrase));
      phrase.fillRange(0, phrase.length, 0);
      final method = await adding;
      await session.close();
      session = null;

      await expectLater(
        Keybay.open(),
        throwsA(_failure(KeybayErrorCode.authRequired)),
      );
      final unlock = Uint8List.fromList(utf8.encode('macos-test-passphrase'));
      final opening = Keybay.open(
        credential: PassphraseCredential(phrase: unlock),
      );
      unlock.fillRange(0, unlock.length, 0);
      session = await opening;
      expect(await session.get('service/token'), 'macos-v2-plaintext-marker');
      await session.auth.remove(method.id);
    } finally {
      await session?.close();
      await Keybay.reset();
    }

    expect(await roots.exists(resolved.binding.providerAddress), isFalse);
    expect(store.existsSync(), isFalse);
  });
}

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/ffi/apple_host.dart';
import 'package:keybay/src/v2/apple_data_protection_host_platform.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_root_store.dart';
import 'package:keybay/src/v2/macos_host_platform.dart';

/// Run `seed`, then rebuild/sign the same application as a new build and run
/// `reopen`. Both phases must use the same team, bundle ID, and exact group.
/// Only the dedicated Keybay harness namespace is reset.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('KEYBAY_MACOS_CONTINUITY_PHASE');
  testWidgets(
    'signed macOS $phase phase preserves its V2 store across replacement',
    (WidgetTester _) async {
      if (!Platform.isMacOS || (phase != 'seed' && phase != 'reopen')) {
        markTestSkipped('macOS with seed/reopen continuity phase required');
        return;
      }
      final host = AppleHostApi.macOS();
      expect(host.bundleIdentifier(), 'dev.keybay.securityharness');
      expect(host.macOSAppSandboxEnabled(), isTrue);
      expect(
        host.macOSSignedApplicationIdentifier(),
        endsWith('.dev.keybay.securityharness'),
      );

      const marker = 'keybay-signed-build-continuity';
      final phrase = Uint8List.fromList(utf8.encode('fixed continuity phrase'));
      KeybaySession? session;
      try {
        if (phase == 'seed') {
          await Keybay.reset();
          session = await Keybay.open();
          expect(session.wasInitialized, isTrue);
          await session.set('continuity/marker', marker);
          await session.auth.add(PassphraseCredential(phrase: phrase));
        } else {
          await expectLater(
            Keybay.open(),
            throwsA(
              isA<KeybayException>().having(
                (error) => error.code,
                'code',
                KeybayErrorCode.authRequired,
              ),
            ),
          );
          session = await Keybay.open(
            credential: PassphraseCredential(phrase: phrase),
          );
          expect(session.wasInitialized, isFalse);
          expect(await session.get('continuity/marker'), marker);
        }
      } finally {
        phrase.fillRange(0, phrase.length, 0);
        await session?.close();
        if (phase == 'reopen') {
          await Keybay.reset();
          final resolved = await MacOSHostPlatform().resolve();
          final applicationIdentifier = host.macOSSignedApplicationIdentifier();
          final roots = AppleDataProtectionKeychainRootStore(
            exactApplicationIdentifierAccessGroup: applicationIdentifier,
          );
          expect(await roots.exists(resolved.binding.providerAddress), isFalse);
          final facts = resolveMacOSEntitledHostFacts(
            bundleIdentifier: host.bundleIdentifier(),
            applicationIdentifier: applicationIdentifier,
            applicationSupportRoot: Uri.directory(
              host.applicationSupportDirectory(),
            ),
          );
          for (final name in ['keybay.v2.store', 'keybay.v2.stage']) {
            expect(
              File.fromUri(facts.canonicalFileRoot.resolve(name)).existsSync(),
              isFalse,
            );
          }
        }
      }
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/android_host_platform.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngine;

import 'mobile_security_support.dart';

const _channel = MethodChannel(
  'dev.keybay.securityharness/keybay_device_security',
);
const _packageName = 'dev.keybay.securityharness';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerSecurityMetadata();
  const mode = String.fromEnvironment('SECURITY_MODE', defaultValue: 'tamper');
  const expectedLevel = String.fromEnvironment('EXPECT_ANDROID_LEVEL');

  setUp(() async {
    if (!Platform.isAndroid) return;
    final facts = await _channel.invokeMethod<Map<Object?, Object?>>(
      'hostFacts',
    );
    expect(facts, containsPair('packageName', _packageName));
    expect(mode, anyOf('baseline', 'tamper'));
    expect(expectedLevel, anyOf('', 'hardware', 'software'));
  });

  testWidgets('KB-AND-010 Android V2 native key properties', (_) async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }
    await Keybay.reset();
    KeybaySession? session;
    try {
      session = await Keybay.open();
      final keyInfo = await _channel.invokeMethod<Map<Object?, Object?>>(
        'keyInfo',
        <String, Object?>{'alias': await _alias()},
      );
      expect(keyInfo, isNotNull);
      expect(keyInfo, containsPair('present', true));
      expect(keyInfo, containsPair('algorithm', 'AES'));
      expect(keyInfo, containsPair('keySize', 256));
      expect(keyInfo, containsPair('purposes', 3));
      expect(keyInfo!['blockModes'], contains('GCM'));
      expect(keyInfo['encryptionPaddings'], contains('NoPadding'));
      expect(keyInfo, containsPair('userAuthenticationRequired', false));
      final level = keyInfo['securityLevelName'];
      expect(
        level,
        anyOf('software', 'trustedEnvironment', 'strongBox', 'unknownSecure'),
      );
      if (expectedLevel == 'hardware') {
        expect(level, anyOf('trustedEnvironment', 'strongBox'));
      } else if (expectedLevel == 'software') {
        expect(level, 'software');
      }
    } finally {
      await session?.close();
      await Keybay.reset();
    }
  });

  testWidgets(
    'KB-AND-011 Android V2 ciphertext, reopen, passphrase, and reset',
    (WidgetTester _) async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }

      await Keybay.reset();
      KeybaySession? session;
      try {
        session = await Keybay.open();
        expect(session.wasInitialized, isTrue);
        expect(await session.get('service/token'), isNull);

        await session.set('service/token', 'android-v2-plaintext-marker');
        await session.setBytes(
          'service/binary',
          Uint8List.fromList(<int>[0, 1, 2, 255]),
        );
        expect(
          await session.get('service/token'),
          'android-v2-plaintext-marker',
        );
        expect(await session.getBytes('service/binary'), <int>[0, 1, 2, 255]);

        await session.close();
        session = null;
        // A fresh engine owns no state from Keybay's production singleton. This
        // is the in-test portion of restart qualification; a retained
        // force-stop/relaunch receipt remains a separate device gate.
        session = await V2StoreEngine(AndroidHostPlatform()).open();
        expect(session.wasInitialized, isFalse);
        expect(
          await session.get('service/token'),
          'android-v2-plaintext-marker',
        );
        expect(await session.getBytes('service/binary'), <int>[0, 1, 2, 255]);

        final noBackup = await _channel.invokeMethod<String>(
          'noBackupFilesDir',
        );
        expect(noBackup, isNotNull);
        final root = Directory('$noBackup/keybay-v2');
        final store = File('${root.path}/keybay.v2.store');
        expect(root.existsSync(), isTrue);
        expect(root.statSync().mode & 0x1ff, 0x1c0);
        expect(store.existsSync(), isTrue);
        expect(store.statSync().mode & 0x1ff, 0x180);
        expect(
          latin1.decode(store.readAsBytesSync(), allowInvalid: true),
          isNot(contains('android-v2-plaintext-marker')),
        );

        final phrase = Uint8List.fromList(
          utf8.encode('device-test-passphrase'),
        );
        final add = session.auth.add(PassphraseCredential(phrase: phrase));
        phrase.fillRange(0, phrase.length, 0);
        final method = await add;
        expect(method, isA<PassphraseMethod>());
        await session.close();
        session = null;

        await expectLater(
          Keybay.open(),
          throwsA(
            isA<KeybayException>().having(
              (failure) => failure.code,
              'code',
              KeybayErrorCode.authRequired,
            ),
          ),
        );

        final unlock = Uint8List.fromList(
          utf8.encode('device-test-passphrase'),
        );
        final opening = Keybay.open(
          credential: PassphraseCredential(phrase: unlock),
        );
        unlock.fillRange(0, unlock.length, 0);
        session = await opening;
        expect(
          await session.get('service/token'),
          'android-v2-plaintext-marker',
        );

        await session.auth.remove(method.id);
        await session.close();
        session = await Keybay.open();
        expect(
          await session.get('service/token'),
          'android-v2-plaintext-marker',
        );
      } finally {
        await session?.close();
        await Keybay.reset();
      }
    },
  );

  testWidgets('KB-AND-020 Android V2 concurrent isolate updates', (_) async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }
    await checkConcurrentMobileUpdates();
  });

  testWidgets(
    'KB-AND-030 Android V2 detects manifest ciphertext tamper on access',
    (WidgetTester _) async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }

      if (mode != 'tamper') {
        markTestSkipped('Requires the harness tamper selection');
        return;
      }

      await Keybay.reset();
      KeybaySession? session;
      File? store;
      Uint8List? original;
      try {
        session = await Keybay.open();
        await session.set('service/token', 'tamper-marker');
        await session.close();
        session = null;

        store = await _storeFile();
        original = store.readAsBytesSync();
        final bytes = Uint8List.fromList(original);
        expect(bytes.length, greaterThan(v2ManifestLengthBytes));
        bytes[bytes.length - v2ManifestLengthBytes - 1] ^= 0x01;
        store.writeAsBytesSync(bytes, flush: true);

        // Opening authenticates only the package. The first record access must
        // authenticate the manifest and reject its changed ciphertext.
        session = await Keybay.open();
        expect(session.wasInitialized, isFalse);
        await expectLater(
          session.get('service/token'),
          throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
        );
        await session.close();
        session = null;

        expect(store.readAsBytesSync(), bytes);
        store.writeAsBytesSync(original, flush: true);
        session = await Keybay.open();
        expect(await session.get('service/token'), 'tamper-marker');
      } finally {
        await session?.close();
        if (store != null && original != null) {
          store.writeAsBytesSync(original, flush: true);
        }
        await Keybay.reset();
      }
    },
  );

  testWidgets('KB-AND-040 Android V2 resets after provider-root loss', (
    WidgetTester _,
  ) async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }

    if (mode != 'tamper') {
      markTestSkipped('Requires the harness tamper selection');
      return;
    }

    await Keybay.reset();
    KeybaySession? session;
    try {
      session = await Keybay.open();
      await session.set('service/token', 'root-loss-marker');
      final alias = await _alias();
      final store = await _storeFile();
      final original = store.readAsBytesSync();

      expect(
        await _channel.invokeMethod<bool>('deleteAlias', <String, Object?>{
          'alias': alias,
        }),
        isTrue,
      );
      // Record operations use the Kstore retained by this authenticated
      // session; deleting the platform root cannot retroactively revoke it.
      expect(await session.get('service/token'), 'root-loss-marker');
      await expectLater(
        Keybay.open(),
        throwsA(_failure(KeybayErrorCode.platformKeyInvalidated)),
      );
      expect(store.readAsBytesSync(), original);
      expect(
        await _channel.invokeMethod<Map<Object?, Object?>>(
          'keyInfo',
          <String, Object?>{'alias': alias},
        ),
        containsPair('present', false),
      );
      await session.close();
      session = null;

      await Keybay.reset();
      session = await Keybay.open();
      expect(session.wasInitialized, isTrue);
      expect(await session.get('service/token'), isNull);
    } finally {
      await session?.close();
      await Keybay.reset();
    }
  });

  testWidgets('Android V2 resets after same-alias root replacement', (
    WidgetTester _,
  ) async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }

    if (mode != 'tamper') {
      markTestSkipped('Requires the harness tamper selection');
      return;
    }

    await Keybay.reset();
    KeybaySession? session;
    try {
      session = await Keybay.open();
      await session.set('service/token', 'root-replacement-marker');
      final alias = await _alias();
      await session.close();
      session = null;

      expect(
        await _channel.invokeMethod<bool>(
          'replaceAliasWithFreshAesKey',
          <String, Object?>{'alias': alias},
        ),
        isTrue,
      );
      await expectLater(
        Keybay.open(),
        throwsA(_failure(KeybayErrorCode.platformKeyInvalidated)),
      );

      await Keybay.reset();
      final keyInfo = await _channel.invokeMethod<Map<Object?, Object?>>(
        'keyInfo',
        <String, Object?>{'alias': alias},
      );
      expect(keyInfo, containsPair('present', false));
      session = await Keybay.open();
      expect(session.wasInitialized, isTrue);
      expect(await session.get('service/token'), isNull);
    } finally {
      await session?.close();
      await Keybay.reset();
    }
  });
}

Future<File> _storeFile() async {
  final noBackup = await _channel.invokeMethod<String>('noBackupFilesDir');
  if (noBackup == null) {
    throw StateError('Android did not report noBackupFilesDir.');
  }
  return File('$noBackup/keybay-v2/keybay.v2.store');
}

Future<String> _alias() async {
  final store = await _storeFile();
  return _v2Alias(Uri.directory(store.parent.path));
}

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

String _v2Alias(Uri root) {
  final binding = ResolvedApplicationBinding.derive(
    identity: ApplicationIdentity(
      stableValue: _packageName,
      source: ApplicationIdentitySource.operatingSystem,
      assurance: ApplicationIdentityAssurance.osEnforced,
    ),
    profile: HostProfile(androidHostProfileCode),
    canonicalFileRoot: root,
  );
  return 'keybay.v2.${binding.providerAddress}';
}

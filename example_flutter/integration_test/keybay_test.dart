// The mobile/desktop integration tier: exercises SecretStorage(appId:) against
// the REAL platform keystore from inside a real Flutter app bundle.
//
// Run via tool/test_e2e.sh, which passes the per-environment EXPECT_SCHEME /
// EXPECT_LEVEL dart-defines. The expectations by leg (see
// doc/device-security-suite.md):
//   macOS, ad-hoc signing (no entitlement): file + loginBound (−34018 branch
//     inside a real .app — the same branch every CLI takes).
//   macOS, Keychain Sharing + development signing: native items; no inferred
//     hardware level.
//   iOS simulator: native items; no inferred hardware level.
//   Android (API 31+): encrypted file + AndroidKeyStore-wrapped key via the
//     pure-FFI JNI shim; level measured from the KEK after a write. Emulator
//     runs default to software; physical-device runs pass hardware explicitly.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/android_keystore_key_source.dart';
import 'package:keybay/src/app_paths.dart';
import 'package:keybay/src/backends/encrypted_file_backend.dart';
import 'package:keybay/src/ffi/jni.dart';

/// What this leg expects — set per environment, not detected (detection is
/// what the test is *checking*). `EXPECT_SCHEME` is `native` | `file` (the
/// deterministic storage shape); `EXPECT_LEVEL` is `hardware` | `software` |
/// `login` and may be empty when the level can't be asserted up front (Android
/// measures from a KEK that doesn't exist until the first write — see the
/// dedicated test below). `EXPECT_ANDROID_LEVEL` sets that post-write Android
/// assertion and defaults to the emulator's `software` result. Apple
/// native-item paths deliberately leave the level null.
const String expectScheme = String.fromEnvironment('EXPECT_SCHEME');
const String expectLevel = String.fromEnvironment('EXPECT_LEVEL');
const String expectAndroidLevel =
    String.fromEnvironment('EXPECT_ANDROID_LEVEL', defaultValue: 'software');

/// The macOS entitled and unentitled legs run on the *same machine* and would
/// otherwise share one app-support dir — where the entitled leg would trip
/// the scheme-migration guard on the unentitled leg's container file. Each
/// macOS leg passes a distinct APP_ID so they stay isolated; mobile legs use
/// the default.
const appId =
    String.fromEnvironment('APP_ID', defaultValue: 'com.example.keybayHarness');

const _androidChannel =
    MethodChannel('dev.keybay.securityharness/keybay_device_security');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SecretStorage store;

  setUpAll(() {
    store = SecretStorage(appId: appId);
  });

  tearDown(() async {
    // Leave no test entries behind (the store itself — container/key or
    // keychain items — persists like a real app's would).
    await store.deleteAll();
  });

  test('resolver picked the scheme and any inspectable level', () async {
    final info = await store.backend.describe();

    final wantScheme = switch (expectScheme) {
      'native' => StorageScheme.nativeItems,
      'file' => StorageScheme.encryptedFile,
      // Defaults for legs that don't pass EXPECT_SCHEME: iOS is always native,
      // everything else here is the file scheme.
      _ => Platform.isIOS
          ? StorageScheme.nativeItems
          : StorageScheme.encryptedFile,
    };
    expect(info.scheme, wantScheme, reason: 'wrong storage shape');

    final wantLevel = switch (expectLevel) {
      'hardware' => SecurityLevel.hardwareBacked,
      'software' => SecurityLevel.softwareBacked,
      'login' => SecurityLevel.loginBound,
      _ => null,
    };
    if (wantLevel != null) {
      // Measured, not assumed: Android reads KeyInfo and macOS login uses the
      // login-bound file-key path. Apple native items leave the level null.
      expect(info.level, wantLevel, reason: 'wrong measured level');
    } else if ((Platform.isIOS || Platform.isMacOS) &&
        wantScheme == StorageScheme.nativeItems) {
      // This is an explicit contract, not merely a missing expectation: an
      // Apple capability probe cannot attest the backing of this Keychain
      // item, so native-item diagnostics must not manufacture a level.
      expect(info.level, isNull,
          reason: 'Apple native items are not hardware-attested by Keybay');
    }

    expect(info.available, isTrue);
    expect(info.locked, isFalse);
  });

  test('Android: security level is measured from the KEK', () async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }
    // Provision the KEK, then read the level the hardware actually claims.
    await store.writeString('__lvl', 'x');
    final info = await store.backend.describe();
    final wantLevel = switch (expectAndroidLevel) {
      'hardware' => SecurityLevel.hardwareBacked,
      'software' => SecurityLevel.softwareBacked,
      _ => throw StateError(
          'EXPECT_ANDROID_LEVEL must be hardware or software',
        ),
    };
    // The expected result belongs to the environment, not detection code: an
    // emulator uses software, while physical TEE/StrongBox hardware reports
    // hardware. Either way this proves Keybay reports KeyInfo rather than
    // assuming every Android Keystore is hardware-backed.
    expect(info.level, wantLevel,
        reason: 'Android Keystore level differs from the test-leg contract');
  });

  test('macOS entitled: a pre-existing file store blocks native (migration)',
      () async {
    if (!(Platform.isMacOS && expectScheme == 'native')) {
      markTestSkipped('entitled-macOS-only');
      return;
    }
    const migAppId = 'com.example.keybayHarness.migration';
    final dir = Directory(
        '${Platform.environment['HOME']}/Library/Application Support/$migAppId');
    final container = File('${dir.path}/secrets.enc');
    try {
      dir.createSync(recursive: true);
      // A leftover encrypted-file container from before the app gained the
      // Keychain Sharing entitlement. Resolving to native items now must refuse
      // rather than silently present an empty store and strand these secrets.
      container.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
      expect(
        () => SecretStorage(appId: migAppId),
        throwsA(isA<MigrationRequired>()
            .having((e) => e.from, 'from', StorageScheme.encryptedFile)
            .having((e) => e.to, 'to', StorageScheme.nativeItems)),
      );
    } finally {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('full round-trip: bytes, strings, labels, enumeration, delete',
      () async {
    expect(await store.read('token'), isNull);
    expect(await store.containsKey('token'), isFalse);

    final binary = Uint8List.fromList(List.generate(64, (i) => (i * 7) % 256));
    await store.write('binary', binary, label: 'harness binary');
    expect(await store.read('binary'), binary);

    await store.writeString('token', 's3cr3t-value', label: 'harness token');
    expect(await store.readString('token'), 's3cr3t-value');
    expect(await store.containsKey('token'), isTrue);

    // Overwrite replaces.
    await store.writeString('token', 'rotated');
    expect(await store.readString('token'), 'rotated');

    expect((await store.readAll()).keys.toSet(),
        containsAll(<String>{'binary', 'token'}));

    await store.delete('token');
    expect(await store.readString('token'), isNull);
    await store.delete('token'); // idempotent
  });

  test('a second store instance reads the same data (shared backing)',
      () async {
    await store.writeString('shared', 'visible');
    final second = SecretStorage(appId: appId);
    expect(await second.readString('shared'), 'visible');
  });

  test('unicode values survive the round-trip', () async {
    await store.writeString('unicode', 'café ☕ 名前 — ключ');
    expect(await store.readString('unicode'), 'café ☕ 名前 — ключ');
  });

  test('Android: ciphertext + wrapped-key blob stay under no-backup', () async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }
    await store.writeString('android-proof', 'pl4in-t3xt-pr00f');
    // Cross-check the pure-Dart resolver against the host's independent use of
    // the public Context.getNoBackupFilesDir() API. This catches an Android
    // layout change without adding a production plugin or hidden-API call.
    final hostNoBackup =
        await _androidChannel.invokeMethod<String>('noBackupFilesDir');
    // Match the production resolver's Java property exactly. Dart's
    // Directory.systemTemp points at a Flutter test-runner child directory on
    // Android and is intentionally not the source used by SecretStorage.
    final tmpdir = Jni.instance().systemProperty('java.io.tmpdir');
    final derivedNoBackup = androidNoBackupDirFromTmpdir(tmpdir);
    expect(derivedNoBackup, hostNoBackup);
    final dir = '$derivedNoBackup/$appId';
    final container = File('$dir/secrets.enc');
    final blob = File('$dir/store-key.wrapped');
    expect(container.existsSync(), isTrue,
        reason: 'container missing at derived path $dir');
    expect(blob.existsSync(), isTrue,
        reason: 'wrapped-key blob missing at derived path $dir');
    expect(String.fromCharCodes(container.readAsBytesSync()),
        isNot(contains('pl4in-t3xt-pr00f')),
        reason: 'container must be ciphertext');
    // The blob is our versioned format ('SKW1'), and small (wrapped 32-byte
    // key + GCM overhead — no plaintext store key is written beside it).
    final blobBytes = blob.readAsBytesSync();
    expect(blobBytes.sublist(0, 4), [0x53, 0x4B, 0x57, 0x31]);
    expect(blobBytes.length, lessThan(128));
    expect(String.fromCharCodes(blobBytes), isNot(contains('pl4in')));
    expect(
      Directory(
        '${androidDataDirFromTmpdir(tmpdir)}/files/$appId',
      ).existsSync(),
      isFalse,
      reason: 'a fresh store must not create the legacy backup-eligible path',
    );
  });

  test('Android: an existing files-dir store migrates without rekeying',
      () async {
    if (!Platform.isAndroid) {
      markTestSkipped('Android-only');
      return;
    }
    const migrationAppId = 'com.example.keybayHarness.ci.legacyMigration';
    final tmpdir = Jni.instance().systemProperty('java.io.tmpdir');
    final legacyContainer =
        androidLegacyContainerPathFor(migrationAppId, tmpdir: tmpdir);
    final currentContainer =
        androidContainerPathFor(migrationAppId, tmpdir: tmpdir);
    final legacyDir = File(legacyContainer).parent;
    final currentDir = File(currentContainer).parent;
    final legacySource = AndroidKeystoreKeySource(
      alias: '$migrationAppId.store-key',
      blobPath: '${legacyDir.path}/store-key.wrapped',
    );
    final currentSource = AndroidKeystoreKeySource(
      alias: '$migrationAppId.store-key',
      blobPath: '${currentDir.path}/store-key.wrapped',
    );
    try {
      if (legacyDir.existsSync()) legacyDir.deleteSync(recursive: true);
      if (currentDir.existsSync()) currentDir.deleteSync(recursive: true);
      await currentSource.delete();

      final legacy = EncryptedFileBackend(
        path: legacyContainer,
        keySource: legacySource,
      );
      final expected = Uint8List.fromList([7, 11, 19, 23]);
      await legacy.write('legacy', expected);

      final migrated = SecretStorage(appId: migrationAppId);
      expect(await migrated.read('legacy'), expected);
      expect(legacyDir.existsSync(), isFalse);
      expect(File(currentContainer).existsSync(), isTrue);
      expect(File('${currentDir.path}/store-key.wrapped').existsSync(), isTrue);
    } finally {
      await currentSource.delete();
      if (legacyDir.existsSync()) legacyDir.deleteSync(recursive: true);
      if (currentDir.existsSync()) currentDir.deleteSync(recursive: true);
    }
  });
}

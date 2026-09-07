@TestOn('mac-os || linux')
@Tags(<String>['unit'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/v2/android_host_platform.dart';
import 'package:keybay/src/v2/android_keystore_protector.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

void main() {
  group('Android host facts', () {
    test('bind package, Android user, and package-owned process names', () {
      final primary = resolveAndroidHostFactsFromCanonicalCache(
        canonicalCache: '/data/user/0/dev.keybay.example/cache',
        processName: 'dev.keybay.example',
        uid: 10234,
      );
      expect(primary.packageName, 'dev.keybay.example');
      expect(primary.uid, 10234);
      expect(
        primary.noBackupRoot,
        Uri.directory('/data/user/0/dev.keybay.example/no_backup/keybay-v2'),
      );

      final secondary = resolveAndroidHostFactsFromCanonicalCache(
        canonicalCache: '/data/user/10/dev.keybay.example/cache',
        processName: 'dev.keybay.example:worker_1',
        uid: 1010234,
      );
      expect(secondary.packageName, primary.packageName);
      expect(secondary.uid, 1010234);
    });

    test('reject unrelated process names, users, and unqualified layouts', () {
      for (final input in <({String cache, String process, int uid})>[
        (
          cache: '/data/user/0/dev.keybay.example/cache',
          process: 'dev.other.example',
          uid: 10234,
        ),
        (
          cache: '/data/user/0/dev.keybay.example/cache',
          process: 'dev.keybay.example:',
          uid: 10234,
        ),
        (
          cache: '/data/user/10/dev.keybay.example/cache',
          process: 'dev.keybay.example',
          uid: 10234,
        ),
        (
          cache: '/data/data/dev.keybay.example/cache',
          process: 'dev.keybay.example',
          uid: 10234,
        ),
        (
          cache: '/data/user/0/dev/keybay/cache',
          process: 'dev.keybay.example',
          uid: 10234,
        ),
      ]) {
        expect(
          () => resolveAndroidHostFactsFromCanonicalCache(
            canonicalCache: input.cache,
            processName: input.process,
            uid: input.uid,
          ),
          throwsA(isA<ApplicationIdentityFailure>()),
        );
      }
    });
  });

  group('Android host binding', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('keybay_android_host_');
      _chmod('0700', root.path);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'shares one OS identity and domain across files and protector',
      () async {
        final host = await AndroidHostPlatform.test(
          facts: AndroidHostFacts(
            packageName: 'dev.keybay.example',
            uid: 10234,
            noBackupRoot: Uri.directory(root.resolveSymbolicLinksSync()),
          ),
          keystore: _UnusedAndroidKeystore(),
        ).resolve();

        expect(host.profile.code, androidHostProfileCode);
        expect(host.identity.stableValue, 'dev.keybay.example');
        expect(host.identity.source, ApplicationIdentitySource.operatingSystem);
        expect(
          host.identity.assurance,
          ApplicationIdentityAssurance.osEnforced,
        );
        expect(identical(host.files.binding, host.binding), isTrue);
        expect(identical(host.protector.binding, host.binding), isTrue);
      },
    );

    test('never exposes the profile on a non-Android host', () async {
      await expectLater(
        AndroidHostPlatform.test(
          facts: AndroidHostFacts(
            packageName: 'dev.keybay.example',
            uid: 10234,
            noBackupRoot: Uri.directory(root.resolveSymbolicLinksSync()),
          ),
          keystore: _UnusedAndroidKeystore(),
          isAndroid: false,
        ).resolve(),
        throwsA(
          isA<PlatformProtectorFailure>().having(
            (failure) => failure.code,
            'code',
            PlatformProtectorFailureCode.unavailable,
          ),
        ),
      );
    });
  });
}

final class _UnusedAndroidKeystore implements AndroidKeystoreAead {
  Never _unused() =>
      throw StateError('host resolution must not touch Keystore');

  @override
  Future<bool> contains(String alias) async => _unused();

  @override
  Future<bool> createUnderExclusiveLock(String alias) async => _unused();

  @override
  Future<void> delete(String alias) async => _unused();

  @override
  Future<Uint8List> open({
    required String alias,
    required AndroidKeystoreBox box,
    required Uint8List aad,
  }) async => _unused();

  @override
  Future<AndroidKeystoreBox> seal({
    required String alias,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async => _unused();
}

void _chmod(String mode, String path) {
  final result = Process.runSync('chmod', <String>[mode, path]);
  if (result.exitCode != 0) fail('chmod failed for a disposable fixture');
}

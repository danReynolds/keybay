@TestOn('linux')
@Tags(<String>['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/linux_desktop_host_platform.dart';
import 'package:keybay/src/v2/linux_secret_service_root_store.dart';
import 'package:test/test.dart';

void main() {
  final runtimeDirectory = Platform.environment['XDG_RUNTIME_DIR'];
  final enabled =
      Platform.environment['KEYBAY_INTEGRATION'] == '1' &&
      runtimeDirectory != null &&
      runtimeDirectory.startsWith('/');
  final skip = enabled
      ? false
      : 'set KEYBAY_INTEGRATION=1 and a private absolute XDG_RUNTIME_DIR '
            'inside a disposable dbus-run-session with an unlocked keyring';

  test(
    'raw D-Bus root create, read, and exact delete round-trip',
    () async {
      final roots = DbusLinuxSecretServiceRootStore(
        runtimeDirectory: runtimeDirectory!,
      );
      final address = base64Url
          .encode(
            const DartSha256()
                .hashSync(utf8.encode(_integrationIdentity()))
                .bytes,
          )
          .replaceAll('=', '');
      final value = Uint8List.fromList(
        List<int>.generate(72, (index) => index),
      );
      LinuxSecretServiceRoot? observed;
      try {
        await roots.createNew(address, value);
        observed = await roots.readUnique(address);
        expect(observed?.value, value);
        await roots.delete(observed!);
        observed = null;
        expect(await roots.readUnique(address), isNull);
      } finally {
        final remaining = observed ?? await roots.readUnique(address);
        if (remaining != null) await roots.delete(remaining);
        value.fillRange(0, value.length, 0);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'real Secret Service profile round-trips and rejects a second data root',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_linux_secret_service_',
      );
      expect(
        Process.runSync('chmod', <String>['700', fixture.path]).exitCode,
        0,
      );
      final rootA = Uri.directory('${fixture.path}/root-a');
      final rootB = Uri.directory('${fixture.path}/root-b');
      final roots = DbusLinuxSecretServiceRootStore(
        runtimeDirectory: runtimeDirectory!,
      );
      final identity = ApplicationIdentity(
        stableValue: _integrationIdentity(),
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      );
      final providerAddress = ResolvedApplicationBinding.derive(
        identity: identity,
        profile: HostProfile(linuxDesktopProfileCode),
        canonicalFileRoot: rootA,
      ).providerAddress;
      final first = V2StoreEngine(
        LinuxDesktopHostPlatform.test(
          identity: identity,
          canonicalFileRoot: rootA,
          rootStore: roots,
        ),
      );
      final second = V2StoreEngine(
        LinuxDesktopHostPlatform.test(
          identity: identity,
          canonicalFileRoot: rootB,
          rootStore: roots,
        ),
      );

      try {
        final session = await first.open();
        await session.set('service/token', 'real-secret-service');
        expect(await session.get('service/token'), 'real-secret-service');
        await session.close();

        await expectLater(
          second.open(),
          throwsA(
            isA<KeybayException>().having(
              (failure) => failure.code,
              'code',
              KeybayErrorCode.storeStateConflict,
            ),
          ),
        );
        await first.reset();
      } finally {
        try {
          final remaining = await roots.readUnique(providerAddress);
          if (remaining != null) {
            await roots.delete(remaining);
          }
        } on Object {
          // Preserve the primary test failure. The production seam deliberately
          // has no address-wide delete that could remove an unobserved item.
        }
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'public facade resolves, persists, protects, and resets',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_linux_public_facade_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      expect(
        Process.runSync('chmod', <String>['700', fixture.path]).exitCode,
        0,
      );
      final home = Directory('${fixture.path}/home')..createSync();
      expect(Process.runSync('chmod', <String>['700', home.path]).exitCode, 0);
      final dataHome = Directory('${home.path}/.local/share');
      expect(dataHome.existsSync(), isFalse);

      final environment = Map<String, String>.of(Platform.environment)
        ..remove('XDG_DATA_HOME')
        ..['HOME'] = home.path;
      final packageConfig = await Isolate.packageConfig;
      final keybayLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/keybay.dart'),
      );
      expect(packageConfig?.scheme, 'file');
      expect(keybayLibrary?.scheme, 'file');
      final packageRoot = File.fromUri(keybayLibrary!).parent.parent;
      final workerSource = File(
        '${packageRoot.path}/test/support/linux_public_facade_app/main.dart',
      );
      final application = Directory('${fixture.path}/application')
        ..createSync();
      File('${application.path}/pubspec.yaml').writeAsStringSync('''
name: keybay_linux_public_facade_fixture
publish_to: none
environment:
  sdk: ^3.6.0
keybay:
  application_id: dev.keybay.integration.public-linux
''');
      final worker = workerSource.copySync('${application.path}/main.dart');

      Future<void> run(String operation) async {
        final result = await Process.run(
          Platform.resolvedExecutable,
          <String>[
            '--packages=${File.fromUri(packageConfig!).path}',
            worker.path,
            operation,
          ],
          workingDirectory: packageRoot.path,
          environment: environment,
          includeParentEnvironment: false,
        );
        expect(
          result.exitCode,
          0,
          reason: '$operation failed:\n${result.stdout}\n${result.stderr}',
        );
      }

      await run('initialize');
      expect(dataHome.existsSync(), isTrue);
      expect(FileStat.statSync('${home.path}/.local').mode & 0x1ff, 0x1c0);
      expect(FileStat.statSync(dataHome.path).mode & 0x1ff, 0x1c0);
      await run('reopen');

      final liveFiles = dataHome
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('keybay.v2.store'))
          .toList(growable: false);
      expect(liveFiles, hasLength(1));
      expect(
        _containsBytes(
          liveFiles.single.readAsBytesSync(),
          utf8.encode('public-v2-secret'),
        ),
        isFalse,
      );

      await run('reset');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

String _integrationIdentity() {
  final digest = const DartSha256()
      .hashSync(
        utf8.encode(
          'keybay-v2-linux-itest:$pid:${DateTime.now().microsecondsSinceEpoch}',
        ),
      )
      .bytes;
  return 'itest-${base64Url.encode(digest).replaceAll('=', '')}';
}

bool _containsBytes(List<int> haystack, List<int> needle) {
  for (var start = 0; start + needle.length <= haystack.length; start += 1) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset += 1) {
      if (haystack[start + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

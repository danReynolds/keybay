@TestOn('mac-os || linux')
@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/flatpak_host_platform.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngine;
import 'package:keybay/src/v2/linux_host_platform.dart';
import 'package:keybay/src/v2/linux_secret_portal.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_test_keybay.dart' show FastTestPassphraseDeriver;

void main() {
  test('identity and fixed files come from Flatpak metadata alone', () {
    final info = FlatpakApplicationInfo.parse(
      _info('/home/person/.var/app/org.example.App'),
    );
    expect(info.identity.stableValue, 'org.example.App');
    expect(info.identity.source, ApplicationIdentitySource.operatingSystem);
    expect(info.identity.assurance, ApplicationIdentityAssurance.osEnforced);
    expect(
      info.fileRoot.path,
      '/home/person/.var/app/org.example.App/data/keybay-v2/',
    );
  });

  test('decodes GKeyFile path escaping before constructing the domain', () {
    final info = FlatpakApplicationInfo.parse(_info(r'/home/a\sb/app'));
    expect(info.fileRoot.toFilePath(), '/home/a b/app/data/keybay-v2/');
  });

  test('rejects missing, ambiguous, malformed, or unbounded identity', () {
    final valid = utf8.decode(_info('/home/person/app'));
    for (final bad in <List<int>>[
      const [],
      utf8.encode(valid.replaceFirst('[Application]', '[Runtime]')),
      utf8.encode(valid.replaceFirst('org.example.App', 'no-dots')),
      utf8.encode(valid.replaceFirst('org.example.App', 'org.3bad.App')),
      utf8.encode('$valid\n[Application]\nname=org.other.App\n'),
      utf8.encode(valid.replaceFirst('name=', 'name=org.other.App\nname=')),
      utf8.encode(
        valid.replaceFirst(
          'instance-path=',
          'instance-path=/other\ninstance-path=',
        ),
      ),
      utf8.encode(valid.replaceFirst('/home/person/app', '../app')),
      utf8.encode(valid.replaceFirst('/home/person/app', '/home/../app')),
      utf8.encode(valid.replaceFirst('/home/person/app', '/home//app')),
      utf8.encode(valid.replaceFirst('/home/person/app', '/home/app/')),
      utf8.encode(valid.replaceFirst('/home/person/app', r'/home/app\')),
      utf8.encode('$valid\u0000'),
      <int>[0xff],
      List<int>.filled(64 * 1024 + 1, 65),
    ]) {
      expect(
        () => FlatpakApplicationInfo.parse(bad),
        throwsA(isA<ApplicationIdentityFailure>()),
      );
    }
  });

  test('refuses host xdg-data mounts that cover the fixed private target', () {
    for (final grant in <String>[
      'xdg-data/keybay-v2',
      'xdg-data/keybay-v2:ro',
      'xdg-data/keybay-v2:rw',
      'xdg-data/keybay-v2:create',
      'xdg-data/keybay-v2/child:ro',
    ]) {
      expect(
        () => FlatpakApplicationInfo.parse(_info('/home/app', grants: grant)),
        throwsA(isA<ApplicationIdentityFailure>()),
      );
    }
    expect(
      FlatpakApplicationInfo.parse(
        _info('/home/app', grants: 'xdg-download:ro;xdg-data/unrelated:rw'),
      ).identity.stableValue,
      'org.example.App',
    );
  });

  test(
    'Flatpak selection never tries ordinary Linux after any failure',
    () async {
      final desktop = _FailingHost();
      final flatpak = _FailingHost();
      final dispatcher = LinuxHostPlatform.test(
        hasFlatpakMarker: () => true,
        flatpak: flatpak,
        desktop: desktop,
      );
      await expectLater(
        dispatcher.resolve(),
        throwsA(isA<ApplicationIdentityFailure>()),
      );
      expect(flatpak.calls, 1);
      expect(desktop.calls, 0);
      final brokenProbe = LinuxHostPlatform.test(
        hasFlatpakMarker: () => throw const FileSystemException('redacted'),
        flatpak: flatpak,
        desktop: desktop,
      );
      await expectLater(
        brokenProbe.resolve(),
        throwsA(isA<FileSystemException>()),
      );
      expect(desktop.calls, 0);
    },
  );

  group('Flatpak over the common engine and real private files', () {
    late Directory fixture;
    late String instancePath;
    late _Portal portal;
    late FlatpakHostPlatform host;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('keybay-flatpak-host-');
      instancePath = fixture.resolveSymbolicLinksSync();
      Directory('$instancePath/data').createSync();
      portal = _Portal();
      host = FlatpakHostPlatform.test(
        readInfo: () => _info(instancePath),
        portal: portal,
      );
    });
    tearDown(() => fixture.deleteSync(recursive: true));

    V2StoreEngine engine() =>
        V2StoreEngine(host, passphraseDeriver: FastTestPassphraseDeriver());

    test(
      'resolving identity creates no state and retrieves no secret',
      () async {
        final resolved = await host.resolve();
        expect(resolved.profile.code, flatpakProfileCode);
        expect(identical(resolved.files.binding, resolved.binding), isTrue);
        expect(identical(resolved.protector.binding, resolved.binding), isTrue);
        expect(Directory('$instancePath/data/keybay-v2').existsSync(), isFalse);
        expect(portal.calls, 0);
      },
    );

    test(
      'open, queued CRUD, passphrase changes, reset and backup semantics',
      () async {
        final store = engine();
        final session = await store.open();
        expect(session.wasInitialized, isTrue);
        expect(portal.calls, 1);
        await Future.wait([
          session.set('first', 'value'),
          session.set('second', 'other'),
        ]);
        expect(await session.get('first'), 'value');
        expect(await session.listKeys(), ['first', 'second']);
        expect(await session.auth.list(), isEmpty);
        expect(portal.calls, 1);

        final phrase = Uint8List.fromList(utf8.encode('test-only passphrase'));
        final credential = PassphraseCredential(phrase: phrase);
        await session.auth.add(credential);
        expect(portal.calls, 2);
        await session.close();
        final reopened = await store.open(credential: credential);
        expect(await reopened.get('second'), 'other');
        await reopened.close();
        final live = File('$instancePath/data/keybay-v2/keybay.v2.store');
        final oldEncryptedStore = live.readAsBytesSync();
        final beforeReset = portal.calls;
        await store.reset();
        expect(portal.calls, beforeReset);
        expect(live.existsSync(), isFalse);
        final fresh = await store.open();
        expect(fresh.wasInitialized, isTrue);
        expect(await fresh.listKeys(), isEmpty);
        expect(live.readAsBytesSync(), isNot(orderedEquals(oldEncryptedStore)));
        await fresh.close();

        // Portal custody survives reset. Restoring the complete old encrypted
        // snapshot deliberately restores access with its original credential.
        live.writeAsBytesSync(oldEncryptedStore);
        final restored = await engine().open(credential: credential);
        expect(await restored.get('first'), 'value');
        await restored.close();
        phrase.fillRange(0, phrase.length, 0);
        expect(
          portal.returned.every((bytes) => bytes.every((byte) => byte == 0)),
          isTrue,
        );
      },
    );

    test(
      'concurrent first opens use one store under the existing file lock',
      () async {
        final sessions = await Future.wait([engine().open(), engine().open()]);
        expect(sessions.where((s) => s.wasInitialized).length, 1);
        await sessions.first.set('shared', 'value');
        expect(await sessions.last.get('shared'), 'value');
        await Future.wait(sessions.map((session) => session.close()));
      },
    );

    test(
      'missing or redirected data ancestors fail before portal access',
      () async {
        Directory('$instancePath/data').deleteSync();
        await expectLater(
          engine().open(),
          throwsA(_failure(KeybayErrorCode.storageOperationFailed)),
        );
        final other = Directory('$instancePath/other')..createSync();
        Link('$instancePath/data').createSync(other.path);
        await expectLater(
          engine().open(),
          throwsA(_failure(KeybayErrorCode.storageOperationFailed)),
        );
        expect(portal.calls, 0);
      },
    );

    test('unavailable portal never initializes a live store', () async {
      portal.failure = const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
      await expectLater(
        engine().open(),
        throwsA(_failure(KeybayErrorCode.platformProtectorUnavailable)),
      );
      expect(
        File('$instancePath/data/keybay-v2/keybay.v2.store').existsSync(),
        isFalse,
      );
      expect(portal.calls, 1);
    });
  });
}

List<int> _info(String instance, {String? grants}) => utf8.encode('''
[Application]
name=org.example.App
runtime=org.freedesktop.Platform/x86_64/25.08
[Instance]
instance-path=$instance
app-path=/host/irrelevant/payload
[Context]
${grants == null ? '' : 'filesystems=$grants;'}
''');

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((e) => e.code, 'code', code);

final class _Portal implements LinuxSecretPortal {
  int calls = 0;
  PlatformProtectorFailure? failure;
  final List<Uint8List> returned = [];

  @override
  Future<Uint8List> retrieveSecret({
    required PlatformInteraction interaction,
  }) async {
    expect(interaction, PlatformInteraction.allowed);
    calls++;
    if (failure != null) throw failure!;
    final value = Uint8List.fromList(
      List<int>.generate(64, (index) => index + 1),
    );
    returned.add(value);
    return value;
  }
}

final class _FailingHost implements HostPlatform {
  int calls = 0;
  @override
  Future<ResolvedHost> resolve() async {
    calls++;
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }
}

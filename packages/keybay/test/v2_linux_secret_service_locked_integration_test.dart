@TestOn('linux')
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/linux_desktop_host_platform.dart';
import 'package:keybay/src/v2/linux_secret_service_root_store.dart';
import 'package:test/test.dart';

const String _recordKey = 'integration/locked-token';
const String _recordValue = 'locked-provider-secret';

void main() {
  final runtimeDirectory = Platform.environment['XDG_RUNTIME_DIR'];
  final enabled =
      Platform.environment['KEYBAY_INTEGRATION'] == '1' &&
      Platform.environment['KEYBAY_LOCKED_TEST'] == '1' &&
      runtimeDirectory != null &&
      runtimeDirectory.startsWith('/');
  final skip = enabled
      ? false
      : 'requires a private disposable dbus-run-session with '
            'KEYBAY_INTEGRATION=1, KEYBAY_LOCKED_TEST=1, and XDG_RUNTIME_DIR';

  test(
    'a locked provider fails closed without changing the V2 store',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_linux_locked_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      expect(
        Process.runSync('chmod', <String>['700', fixture.path]).exitCode,
        0,
      );
      final fileRoot = Uri.directory('${fixture.path}/store');
      final roots = DbusLinuxSecretServiceRootStore(
        runtimeDirectory: runtimeDirectory!,
      );
      final identity = ApplicationIdentity(
        stableValue: 'dev.keybay.integration.locked-v2.$pid',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      );
      final providerAddress = ResolvedApplicationBinding.derive(
        identity: identity,
        profile: HostProfile(linuxDesktopProfileCode),
        canonicalFileRoot: fileRoot,
      ).providerAddress;

      V2StoreEngine engine() => V2StoreEngine(
        LinuxDesktopHostPlatform.test(
          identity: identity,
          canonicalFileRoot: fileRoot,
          rootStore: roots,
        ),
      );

      final initialized = await engine().open();
      try {
        expect(initialized.wasInitialized, isTrue);
        await initialized.set(_recordKey, _recordValue);
        expect(await initialized.get(_recordKey), _recordValue);
      } finally {
        await initialized.close();
      }

      final storeFile = File.fromUri(fileRoot.resolve('keybay.v2.store'));
      expect(storeFile.existsSync(), isTrue);
      final storeBeforeLock = storeFile.readAsBytesSync();

      final observed = await roots.readUnique(providerAddress);
      expect(observed, isNotNull);
      expect(observed!.value, isNotEmpty);
      observed.value.fillRange(0, observed.value.length, 0);

      final lock = await Process.run('dbus-send', const <String>[
        '--session',
        '--print-reply',
        '--dest=org.freedesktop.secrets',
        '/org/freedesktop/secrets',
        'org.freedesktop.Secret.Service.Lock',
        'array:objpath:/org/freedesktop/secrets/collection/login',
      ]);
      expect(lock.exitCode, 0, reason: 'could not lock the login collection');

      await expectLater(
        roots.readUnique(providerAddress),
        throwsA(isA<KeystoreLocked>()),
      );
      await expectLater(
        roots.delete(observed),
        throwsA(
          anyOf(
            isA<KeystoreLocked>(),
            isA<LinuxSecretServiceInteractionRequired>(),
          ),
        ),
      );

      await expectLater(
        engine().open(),
        throwsA(
          isA<KeybayException>().having(
            (failure) => failure.code,
            'code',
            KeybayErrorCode.platformProtectorLocked,
          ),
        ),
      );
      expect(storeFile.existsSync(), isTrue);
      expect(storeFile.readAsBytesSync(), storeBeforeLock);
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

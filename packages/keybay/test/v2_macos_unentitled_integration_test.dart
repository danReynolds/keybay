@Tags(<String>['integration'])
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/macos_account_home.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:keybay/src/v2/macos_unentitled_host_platform.dart';
import 'package:test/test.dart';

import 'support/macos_integration_home.dart';

/// Opt-in qualification of the complete macOS unentitled V2 host slice.
///
/// The ciphertext root is always a fresh system-temporary directory. The only
/// persistent platform state is one login-Keychain item whose account is
/// derived from a random test identity and that temporary root. Cleanup never
/// enumerates a service or addresses production application state.
///
/// Run explicitly with:
///
///     KEYBAY_INTEGRATION=1 dart test test/v2_macos_unentitled_integration_test.dart
void main() {
  final enabled = Platform.environment['KEYBAY_INTEGRATION'] == '1';
  final skip = enabled ? false : 'set KEYBAY_INTEGRATION=1';

  test(
    'real login Keychain and POSIX files persist and reset V2 state',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_macos_integration_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });

      final nonce = _randomHex(16);
      final identity = ApplicationIdentity(
        stableValue: 'dev.keybay.v2.integration.$nonce',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      );
      final fileRoot = Uri.directory(fixture.resolveSymbolicLinksSync());
      final roots = AppleMacOSLoginKeychainRootStore(
        accountHome: macOSIntegrationAccountHome(),
      );
      final platform = MacOSUnentitledHostPlatform.test(
        identity: identity,
        canonicalFileRoot: fileRoot,
        rootStore: roots,
      );
      final resolved = await platform.resolve();
      final providerAddress = resolved.binding.providerAddress;

      // Never adopt or delete an item that this run did not create.
      expect(await roots.exists(providerAddress), isFalse);
      addTearDown(() => roots.delete(providerAddress));

      final first = V2StoreEngine(platform);
      final initialized = await first.open();
      try {
        expect(initialized.wasInitialized, isTrue);
        await initialized.set('service/token', 'first value');
        expect(await initialized.get('service/token'), 'first value');
      } finally {
        await initialized.close();
      }

      final platformReopen = await V2StoreEngine(platform).open();
      late final AuthMethod added;
      try {
        expect(platformReopen.wasInitialized, isFalse);
        expect(await platformReopen.get('service/token'), 'first value');
        added = await _withPassphrase(
          'correct-$nonce',
          platformReopen.auth.add,
        );
        expect(added, isA<PassphraseMethod>());
      } finally {
        await platformReopen.close();
      }

      final protectedEngine = V2StoreEngine(platform);
      await expectLater(
        protectedEngine.open(),
        throwsA(_keybayFailure(KeybayErrorCode.authRequired)),
      );
      await expectLater(
        _withPassphrase(
          'wrong-$nonce',
          (credential) => protectedEngine.open(credential: credential),
        ),
        throwsA(_keybayFailure(KeybayErrorCode.unlockFailed)),
      );

      final authenticated = await _withPassphrase(
        'correct-$nonce',
        (credential) => protectedEngine.open(credential: credential),
      );
      try {
        expect(authenticated.wasInitialized, isFalse);
        expect(await authenticated.get('service/token'), 'first value');
        final updated = await _withPassphrase(
          'replacement-$nonce',
          authenticated.auth.update,
        );
        expect(updated.id, added.id);
      } finally {
        await authenticated.close();
      }

      final replacementReopen = await _withPassphrase(
        'replacement-$nonce',
        (credential) => V2StoreEngine(platform).open(credential: credential),
      );
      try {
        expect(replacementReopen.wasInitialized, isFalse);
        expect(await replacementReopen.get('service/token'), 'first value');
      } finally {
        await replacementReopen.close();
      }

      // Reset deliberately takes no application credential. It revokes the
      // ciphertext generation before deleting this exact Keychain item.
      await V2StoreEngine(platform).reset();
      expect(await roots.exists(providerAddress), isFalse);
      expect(
        File.fromUri(fileRoot.resolve('keybay.v2.store')).existsSync(),
        isFalse,
      );
    },
    skip: skip,
  );

  test(
    'public Keybay facade uses only declared V2 state',
    () async {
      final packageConfig = await Isolate.packageConfig;
      expect(packageConfig, isNotNull);

      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_public_runtime_',
      );
      final applicationId = 'dev.keybay.v2.public.${_randomHex(16)}';
      final entrypoint = File('${fixture.path}/main.dart');
      File('${fixture.path}/pubspec.yaml').writeAsStringSync('''
name: keybay_v2_public_runtime_fixture
environment:
  sdk: ^3.6.0
keybay:
  application_id: $applicationId
''');
      entrypoint.writeAsStringSync(_publicRuntimeProbeSource);

      final packagesArgument =
          '--packages=${File.fromUri(packageConfig!).path}';
      addTearDown(() async {
        await Process.run(Platform.resolvedExecutable, <String>[
          packagesArgument,
          entrypoint.path,
          applicationId,
          'cleanup',
        ]);
        _removeTestDirectories(applicationId);
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });

      final result = await Process.run(Platform.resolvedExecutable, <String>[
        packagesArgument,
        entrypoint.path,
        applicationId,
        'exercise',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'public-v2-ok');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<T> _withPassphrase<T>(
  String phrase,
  Future<T> Function(KeybayCredential credential) operation,
) async {
  final bytes = Uint8List.fromList(utf8.encode(phrase));
  try {
    return await operation(PassphraseCredential(phrase: bytes));
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

String _randomHex(int byteLength) {
  final random = Random.secure();
  return List<int>.generate(
    byteLength,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

void _removeTestDirectories(String applicationId) {
  final applicationSupport = Directory(
    '${resolveMacOSAccountHome()}/Library/Application Support',
  );
  if (!applicationSupport.existsSync()) return;

  final prefix = '$applicationId-';
  for (final entity in applicationSupport.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (name.startsWith(prefix) && name.endsWith('.keybay-v2')) {
      Directory(entity.path).deleteSync(recursive: true);
    }
  }
}

const String _publicRuntimeProbeSource = r'''
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';

Future<void> main(List<String> arguments) async {
  final mode = arguments[1];

  if (mode == 'cleanup') {
    try {
      await Keybay.reset();
    } on Object {
      // The parent also removes the random test directory.
    }
    return;
  }

  KeybaySession? openSession;
  try {
    openSession = await Keybay.open();
    _require(openSession.wasInitialized, 'V2 did not initialize');
    await openSession.set('service/token', 'v2-value');
    await _withPassphrase('correct horse', openSession.auth.add);
    await openSession.close();
    openSession = null;

    try {
      openSession = await Keybay.open();
      throw StateError('protected V2 state opened without a credential');
    } on KeybayException catch (error) {
      _require(error.code == KeybayErrorCode.authRequired, 'wrong open error');
    }

    final authenticated = await _withPassphrase(
      'correct horse',
      (credential) => Keybay.open(credential: credential),
    );
    openSession = authenticated;
    _require(
      await authenticated.get('service/token') == 'v2-value',
      'V2 value did not persist',
    );
    await authenticated.close();
    openSession = null;

    await Keybay.reset();

    openSession = await Keybay.open();
    _require(openSession.wasInitialized, 'V2 did not reinitialize after reset');
    _require(
      await openSession.get('service/token') == null,
      'V2 reset retained a record',
    );
    await openSession.close();
    openSession = null;
    await Keybay.reset();
    stdout.write('public-v2-ok');
  } finally {
    await openSession?.close();
    try {
      await Keybay.reset();
    } on Object {
      // Parent teardown makes one more scoped cleanup attempt.
    }
  }
}

Future<T> _withPassphrase<T>(
  String phrase,
  Future<T> Function(KeybayCredential credential) operation,
) async {
  final bytes = Uint8List.fromList(utf8.encode(phrase));
  try {
    return await operation(PassphraseCredential(phrase: bytes));
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
''';

Matcher _keybayFailure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

// Repeatable, evidence-producing security challenges for the real platform
// backends. Platform-neutral scenarios can grow in this file; platform APIs
// stay behind small host-app oracles such as MainActivity's Android KeyInfo
// channel.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keybay/keybay.dart';

/// Required for Android runs because the expected result belongs to the test
/// environment, not to Keybay's detection code. Use `hardware` for a physical
/// TEE/StrongBox device and `software` for an emulator.
const expectedAndroidLevel = String.fromEnvironment('EXPECT_ANDROID_LEVEL');

/// `baseline` runs observation/normal operations. `tamper` also performs
/// self-restoring fault injection against the dedicated test store.
const securityMode =
    String.fromEnvironment('SECURITY_MODE', defaultValue: 'baseline');

const expectedScheme = String.fromEnvironment('EXPECT_SCHEME');
const expectedLevel = String.fromEnvironment('EXPECT_LEVEL');
const securityRunNonce = String.fromEnvironment('SECURITY_RUN_NONCE');
const securitySubjectIdentity =
    String.fromEnvironment('SECURITY_SUBJECT_IDENTITY');
const configuredAppId = String.fromEnvironment(
  'APP_ID',
  defaultValue: 'com.example.keybayDeviceSecurity.shared',
);

const _appIdPrefix = 'com.example.keybayDeviceSecurity';
const _androidChannel =
    MethodChannel('dev.keybay.securityharness/keybay_device_security');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
      'KEYBAY-SECURITY-METADATA nonce=$securityRunNonce '
      'subject=$securitySubjectIdentity', () {
    expect(
      securityRunNonce,
      matches(RegExp(r'^[0-9a-f]{64}$')),
      reason: 'qualification requires a runner-generated 256-bit nonce',
    );
    expect(
      securitySubjectIdentity,
      matches(RegExp(r'^core-pub-content-sha256:[0-9a-f]{64}$')),
      reason: 'qualification must identify the exact core package contents',
    );
  });

  group('Shared native platform security', () {
    test(
        '${_appleScenarioId('010')} platform policy and round-trip match the '
        'declared leg', () async {
      if (!(Platform.isIOS || Platform.isMacOS)) {
        markTestSkipped('Apple physical-host scenario');
        return;
      }
      await _withCleanSharedStore((store) async {
        final canary = 'keybay-shared-${DateTime.now().microsecondsSinceEpoch}';
        await store.writeString('canary', canary);
        expect(await store.readString('canary') == canary, isTrue,
            reason: 'the native-platform canary did not round-trip');

        final info = await store.backend.describe();
        expect(info.available, isTrue);
        expect(info.locked, isFalse);
        expect(info.scheme, _requiredScheme());
        expect(info.level, _requiredSharedLevel());

        if (Platform.isMacOS && info.scheme == StorageScheme.encryptedFile) {
          final container = _macOSContainer(configuredAppId);
          expect(container.existsSync(), isTrue);
          expect(
            _containsBytes(container.readAsBytesSync(), utf8.encode(canary)),
            isFalse,
            reason: 'the macOS encrypted container exposed plaintext',
          );
        }
      });
    });

    test(
        '${_appleScenarioId('020')} spawned isolates retain every same-store '
        'update', () async {
      if (!(Platform.isIOS || Platform.isMacOS)) {
        markTestSkipped('Apple physical-host scenario');
        return;
      }
      final isolatedAppIds = [
        for (var worker = 0; worker < 4; worker++)
          '$configuredAppId.isolate$worker',
      ];
      await _withCleanSharedStores([configuredAppId, ...isolatedAppIds],
          () async {
        const workerCount = 4;
        final isolatedResults = await Future.wait([
          for (var worker = 0; worker < workerCount; worker++)
            Isolate.run(
                () => _sharedIsolateWrite(isolatedAppIds[worker], worker)),
        ]);
        expect(isolatedResults, everyElement(isTrue));
        for (var worker = 0; worker < workerCount; worker++) {
          final isolated = SecretStorage(appId: isolatedAppIds[worker]);
          final all = await isolated.readAll();
          expect(all.keys, ['worker-$worker'],
              reason: 'native stores must not cross appId boundaries');
          expect(
              utf8.decode(all['worker-$worker']!) == 'value-$worker', isTrue);
          final info = await isolated.backend.describe();
          expect(info.available, isTrue);
          expect(info.locked, isFalse);
          expect(info.scheme, _requiredScheme());
          expect(info.level, _requiredSharedLevel());
        }

        final sharedResults = await Future.wait([
          for (var worker = 0; worker < workerCount; worker++)
            Isolate.run(() => _sharedIsolateWrite(configuredAppId, worker)),
        ]);
        expect(sharedResults, everyElement(isTrue));
        final store = SecretStorage(appId: configuredAppId);
        final all = await store.readAll();
        expect(all, hasLength(workerCount));
        for (var worker = 0; worker < workerCount; worker++) {
          expect(
              utf8.decode(all['worker-$worker']!) == 'value-$worker', isTrue);
        }
      });
    });

    test('KB-MAC-030 encrypted container tamper fails closed and recovers',
        () async {
      if (!(Platform.isMacOS &&
          _requiredScheme() == StorageScheme.encryptedFile)) {
        markTestSkipped('macOS encrypted-file scenario');
        return;
      }
      if (_requiredSecurityMode() != 'tamper') {
        markTestSkipped('file tamper requires SECURITY_MODE=tamper');
        return;
      }
      await _withCleanSharedStore((store) async {
        final canary =
            'KB-MAC-030-${DateTime.now().microsecondsSinceEpoch}-plaintext';
        await store.writeString('canary', canary);
        final container = _macOSContainer(configuredAppId);
        expect(container.existsSync(), isTrue);
        final original = container.readAsBytesSync();
        final tampered = Uint8List.fromList(original)
          ..[original.length - 1] ^= 0x01;
        try {
          container.writeAsBytesSync(tampered, flush: true);
          expect(
            await _captureError(() => store.readString('canary')),
            isA<AuthenticationFailed>(),
            reason: 'tampered container must fail authentication',
          );
          expect(
            _bytesEqual(container.readAsBytesSync(), tampered),
            isTrue,
            reason: 'failed read must not replace or heal a tampered container',
          );
        } finally {
          container.writeAsBytesSync(original, flush: true);
        }
        expect(await store.readString('canary') == canary, isTrue,
            reason: 'restoring the exact container must restore readability');
      });
    });
  });

  group('Android device security', () {
    setUp(() {
      if (Platform.isAndroid) _requiredSecurityMode();
    });

    test('KB-AND-010 KeyInfo independently confirms Keybay protection level',
        () async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }
      final expected = _requiredAndroidLevel();
      await _withFreshAndroidStore('keyInfo', (store, appId) async {
        expect(await _androidKeyInfo(appId), containsPair('present', false));

        await store.writeString('provision', 'keybay-test-material');
        final info = await store.backend.describe();
        final oracle = await _androidKeyInfo(appId);
        final rawSecurityLevel = oracle['securityLevel'];
        debugPrint(
          'KB-AND-010 oracle: algorithm=${oracle['algorithm']} '
          'keySize=${oracle['keySize']} origin=${oracle['origin']} '
          'purposes=${oracle['purposes']} '
          'securityLevel=${oracle['securityLevelName']}($rawSecurityLevel) '
          'keybayLevel=${info.level?.name}',
        );

        expect(oracle['present'], isTrue);
        expect(oracle['algorithm'], 'AES');
        expect(oracle['keySize'], 256);
        expect(oracle['origin'], 1,
            reason: 'KEK must be generated inside Android Keystore');
        expect(oracle['purposes'], 3,
            reason: 'KEK must permit encrypt and decrypt only');
        expect(oracle['blockModes'], contains('GCM'));
        expect(oracle['encryptionPaddings'], contains('NoPadding'));
        expect(oracle['userAuthenticationRequired'], isFalse);
        expect(rawSecurityLevel, isA<int>());

        final oracleMapping = rawSecurityLevel == 1 || rawSecurityLevel == 2
            ? SecurityLevel.hardwareBacked
            : SecurityLevel.softwareBacked;
        expect(info.level, oracleMapping,
            reason: 'Keybay must map the independent KeyInfo result honestly');
        expect(info.level, expected,
            reason:
                'the observed level differs from this device leg\'s contract; '
                'oracle=${oracle['securityLevelName']}');
        expect(info.available, isTrue);
        expect(info.locked, isFalse);
      });
    });

    test('KB-AND-011 container and wrapped blob contain no canary plaintext',
        () async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }
      await _withFreshAndroidStore('atRest', (store, appId) async {
        final canary =
            'KB-AND-011-${DateTime.now().microsecondsSinceEpoch}-plaintext';
        await store.writeString('canary', canary, label: '$canary-label');

        final paths = _androidStorePaths(appId);
        expect(paths.container.existsSync(), isTrue);
        expect(paths.blob.existsSync(), isTrue);
        final containerBytes = paths.container.readAsBytesSync();
        final blobBytes = paths.blob.readAsBytesSync();
        final canaryBytes = utf8.encode(canary);

        expect(_containsBytes(containerBytes, canaryBytes), isFalse,
            reason: 'authenticated container exposed the plaintext canary');
        expect(_containsBytes(blobBytes, canaryBytes), isFalse,
            reason: 'wrapped-key blob exposed the plaintext canary');
        expect(blobBytes.sublist(0, 4), [0x53, 0x4b, 0x57, 0x31]);
        expect(blobBytes.length, lessThan(128));
        expect(await store.readString('canary') == canary, isTrue,
            reason: 'canary did not round-trip');
      });
    });

    test('KB-AND-020 spawned-isolate JNI stores stay isolated and atomic',
        () async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }
      final expected = _requiredAndroidLevel();
      const workerCount = 4;
      final appIds = [
        for (var worker = 0; worker < workerCount; worker++)
          '$_appIdPrefix.isolateConcurrency$worker',
      ];
      const sharedAppId = '$_appIdPrefix.isolateSharedFirstWrite';
      await _withFreshAndroidStores([...appIds, sharedAppId], () async {
        final isolatedResults = await Future.wait([
          for (var worker = 0; worker < workerCount; worker++)
            Isolate.run(() => _isolateWrite(appIds[worker], worker)),
        ]);

        for (var worker = 0; worker < workerCount; worker++) {
          expect(isolatedResults[worker]['value'], 'value-$worker');
          expect(isolatedResults[worker]['level'], expected.name);
          final all = await SecretStorage(appId: appIds[worker]).readAll();
          expect(all.keys, ['worker-$worker'],
              reason: 'concurrent JNI stores must remain isolated');
          expect(utf8.decode(all['worker-$worker']!), 'value-$worker');
        }

        // Start from an entirely fresh alias/blob/container and make every
        // isolate race the first write. The per-location file lock must leave
        // exactly one usable KEK and retain every read-modify-write update.
        final sharedResults = await Future.wait([
          for (var worker = 0; worker < workerCount; worker++)
            Isolate.run(() => _isolateWrite(sharedAppId, worker)),
        ]);
        for (var worker = 0; worker < workerCount; worker++) {
          expect(sharedResults[worker]['value'], 'value-$worker');
          expect(sharedResults[worker]['level'], expected.name);
        }
        final shared = await SecretStorage(appId: sharedAppId).readAll();
        expect(
            shared.keys,
            containsAll([
              for (var worker = 0; worker < workerCount; worker++)
                'worker-$worker',
            ]),
            reason: 'simultaneous first writers must not lose an update');
        expect(shared, hasLength(workerCount));
        for (var worker = 0; worker < workerCount; worker++) {
          expect(utf8.decode(shared['worker-$worker']!), 'value-$worker');
        }
      });
    });

    test('KB-AND-030 container and wrapped-blob tamper fail closed and recover',
        () async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }
      if (_requiredSecurityMode() != 'tamper') {
        markTestSkipped('KB-AND-030 requires SECURITY_MODE=tamper');
        return;
      }
      await _withFreshAndroidStore('tamper', (store, appId) async {
        final canary =
            'KB-AND-030-${DateTime.now().microsecondsSinceEpoch}-plaintext';
        await store.writeString('canary', canary);
        final paths = _androidStorePaths(appId);

        final originalContainer = paths.container.readAsBytesSync();
        final tamperedContainer = Uint8List.fromList(originalContainer)
          ..[originalContainer.length - 1] ^= 0x01;
        try {
          paths.container.writeAsBytesSync(tamperedContainer, flush: true);
          expect(
            await _captureError(() => store.readString('canary')),
            isA<AuthenticationFailed>(),
            reason: 'tampered container must fail authentication',
          );
          expect(
            _bytesEqual(paths.container.readAsBytesSync(), tamperedContainer),
            isTrue,
            reason: 'failed read must not replace or heal a tampered container',
          );
        } finally {
          paths.container.writeAsBytesSync(originalContainer, flush: true);
        }
        expect(await store.readString('canary') == canary, isTrue,
            reason: 'restoring the exact container must restore readability');

        final originalBlob = paths.blob.readAsBytesSync();
        final tamperedBlob = Uint8List.fromList(originalBlob)
          ..[originalBlob.length - 1] ^= 0x01;
        try {
          paths.blob.writeAsBytesSync(tamperedBlob, flush: true);
          expect(
            await _captureError(() => store.readString('canary')),
            isA<KeyInvalidated>(),
            reason: 'tampered wrapped key must fail closed',
          );
          expect(
            _bytesEqual(paths.blob.readAsBytesSync(), tamperedBlob),
            isTrue,
            reason: 'failed read must not replace or heal a tampered key blob',
          );
          expect(
            _bytesEqual(paths.container.readAsBytesSync(), originalContainer),
            isTrue,
            reason: 'key-blob failure must leave the container unchanged',
          );
        } finally {
          paths.blob.writeAsBytesSync(originalBlob, flush: true);
        }
        expect(await store.readString('canary') == canary, isTrue,
            reason:
                'restoring the exact wrapped blob must restore readability');
      });
    });

    test('KB-AND-040 restored state without its KEK fails without self-heal',
        () async {
      if (!Platform.isAndroid) {
        markTestSkipped('Android-only');
        return;
      }
      if (_requiredSecurityMode() != 'tamper') {
        markTestSkipped('KB-AND-040 requires SECURITY_MODE=tamper');
        return;
      }
      await _withFreshAndroidStore('missingKek', (store, appId) async {
        final canary =
            'KB-AND-040-${DateTime.now().microsecondsSinceEpoch}-plaintext';
        await store.writeString('canary', canary);
        final paths = _androidStorePaths(appId);
        final originalContainer = paths.container.readAsBytesSync();
        final originalBlob = paths.blob.readAsBytesSync();

        expect(await _deleteAndroidAlias(appId), isTrue,
            reason: 'the challenge must remove the provisioned test KEK');
        expect(await _androidKeyInfo(appId), containsPair('present', false));
        expect(
          await _captureError(() => store.readString('canary')),
          isA<KeyInvalidated>(),
          reason: 'restored artifacts without their original KEK must fail',
        );
        expect(
          _bytesEqual(paths.container.readAsBytesSync(), originalContainer),
          isTrue,
          reason: 'missing-KEK failure must leave the container unchanged',
        );
        expect(
          _bytesEqual(paths.blob.readAsBytesSync(), originalBlob),
          isTrue,
          reason: 'missing-KEK failure must not replace the wrapped key blob',
        );
        expect(await _androidKeyInfo(appId), containsPair('present', false),
            reason: 'a failed read must not silently provision a replacement');
      });
    });
  });
}

String _appleScenarioId(String suffix) =>
    Platform.isMacOS ? 'KB-MAC-$suffix' : 'KB-IOS-$suffix';

StorageScheme _requiredScheme() => switch (expectedScheme) {
      'native' => StorageScheme.nativeItems,
      'file' => StorageScheme.encryptedFile,
      _ => throw StateError('EXPECT_SCHEME must be native or file'),
    };

SecurityLevel? _requiredSharedLevel() => switch (expectedLevel) {
      'hardware' => SecurityLevel.hardwareBacked,
      'software' => SecurityLevel.softwareBacked,
      'login' => SecurityLevel.loginBound,
      '' => null,
      _ => throw StateError(
          'EXPECT_LEVEL must be hardware, software, login, or empty',
        ),
    };

Future<void> _withCleanSharedStore(
  Future<void> Function(SecretStorage store) body,
) async {
  final store = SecretStorage(appId: configuredAppId);
  await store.deleteAll();
  try {
    await body(store);
  } finally {
    await store.deleteAll();
  }
}

Future<void> _withCleanSharedStores(
  List<String> appIds,
  Future<void> Function() body,
) async {
  final stores = [for (final appId in appIds) SecretStorage(appId: appId)];
  for (final store in stores) {
    await store.deleteAll();
  }
  try {
    await body();
  } finally {
    for (final store in stores) {
      await store.deleteAll();
    }
  }
}

File _macOSContainer(String appId) {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is required for the macOS file scenario');
  }
  return File('$home/Library/Application Support/$appId/secrets.enc');
}

Future<bool> _sharedIsolateWrite(String appId, int worker) async {
  final store = SecretStorage(appId: appId);
  final key = 'worker-$worker';
  final value = 'value-$worker';
  await store.writeString(key, value);
  return await store.readString(key) == value;
}

SecurityLevel _requiredAndroidLevel() => switch (expectedAndroidLevel) {
      'hardware' => SecurityLevel.hardwareBacked,
      'software' => SecurityLevel.softwareBacked,
      _ => throw StateError(
          'Android device-security runs require '
          '--dart-define=EXPECT_ANDROID_LEVEL=hardware|software',
        ),
    };

String _requiredSecurityMode() => switch (securityMode) {
      'baseline' || 'tamper' => securityMode,
      _ => throw StateError(
          'device-security runs require '
          '--dart-define=SECURITY_MODE=baseline|tamper',
        ),
    };

Future<Map<String, String?>> _isolateWrite(String appId, int worker) async {
  final store = SecretStorage(appId: appId);
  final key = 'worker-$worker';
  final value = 'value-$worker';
  await store.writeString(key, value);
  final readBack = await store.readString(key);
  final info = await store.backend.describe();
  return {'value': readBack, 'level': info.level?.name};
}

Future<void> _withFreshAndroidStore(
  String suffix,
  Future<void> Function(SecretStorage store, String appId) body,
) async {
  final appId = '$_appIdPrefix.$suffix';
  await _resetAndroidStore(appId);
  try {
    await body(SecretStorage(appId: appId), appId);
  } finally {
    await _resetAndroidStore(appId);
  }
}

Future<void> _withFreshAndroidStores(
  List<String> appIds,
  Future<void> Function() body,
) async {
  for (final appId in appIds) {
    await _resetAndroidStore(appId);
  }
  try {
    await body();
  } finally {
    for (final appId in appIds) {
      await _resetAndroidStore(appId);
    }
  }
}

Future<Map<Object?, Object?>> _androidKeyInfo(String appId) async {
  final result = await _androidChannel.invokeMethod<Map<Object?, Object?>>(
    'keyInfo',
    {'alias': '$appId.store-key'},
  );
  if (result == null) throw StateError('Android KeyInfo oracle returned null');
  return result;
}

Future<bool> _deleteAndroidAlias(String appId) async =>
    await _androidChannel.invokeMethod<bool>(
      'deleteAlias',
      {'alias': '$appId.store-key'},
    ) ??
    false;

Future<void> _resetAndroidStore(String appId) async {
  if (!appId.startsWith('$_appIdPrefix.')) {
    throw StateError('refusing to reset a non-security-harness appId');
  }
  final paths = _androidStorePaths(appId);
  if (paths.directory.existsSync()) {
    paths.directory.deleteSync(recursive: true);
  }
  await _deleteAndroidAlias(appId);
}

({Directory directory, File container, File blob}) _androidStorePaths(
  String appId,
) {
  final dataDir = Directory.systemTemp.parent.path;
  final directory = Directory('$dataDir/files/$appId');
  return (
    directory: directory,
    container: File('${directory.path}/secrets.enc'),
    blob: File('${directory.path}/store-key.wrapped'),
  );
}

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var start = 0; start <= haystack.length - needle.length; start++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[start + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

Future<Object?> _captureError(Future<Object?> Function() operation) async {
  try {
    await operation();
    return null;
  } on Object catch (error) {
    return error;
  }
}

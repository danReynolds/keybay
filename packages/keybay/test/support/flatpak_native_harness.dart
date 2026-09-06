// Native qualification only. No portal secret or Keybay plaintext is logged.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:dbus/dbus.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/flatpak_host_platform.dart';
import 'package:keybay/src/v2/linux_secret_portal.dart';
import 'package:keybay/src/v2/platform_protector.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || !Platform.isLinux) {
      throw StateError('Invalid native qualification invocation');
    }
    switch (arguments.first) {
      case 'sandbox-state':
        _require(arguments.length == 1, 'Unexpected sandbox state arguments');
        stdout.writeln(jsonEncode(_sandboxState()));
      case 'portal-challenge':
        _require(arguments.length == 2, 'Missing challenge');
        final secret = await DbusLinuxSecretPortal().retrieveSecret(
          interaction: PlatformInteraction.allowed,
        );
        final key = SecretKeyData(secret, overwriteWhenDestroyed: true);
        try {
          final response = await const DartHmac(
            DartSha256(),
          ).calculateMac(utf8.encode(arguments[1]), secretKey: key);
          // The controller captures this in memory and emits booleans only.
          stdout.writeln(
            response.bytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
          );
        } finally {
          key.destroy();
          secret.fillRange(0, secret.length, 0);
        }
      case 'file-root':
        stdout.writeln(_fileRoot());
      case 'exercise':
        await _exercise();
        stdout.writeln('ok');
      case 'reopen':
        final session = await Keybay.open();
        try {
          _require(
            await session.get('continuity') == 'qualified',
            'Reopen failed',
          );
          _require(
            await session.get('application') ==
                _applicationInfo().identity.stableValue,
            'Application store binding changed',
          );
        } finally {
          await session.close();
        }
        stdout.writeln('ok');
      case 'verify-peer':
        _require(arguments.length == 2, 'Missing peer path');
        _require(
          FileSystemEntity.typeSync(arguments[1]) ==
              FileSystemEntityType.notFound,
          'Peer private store was visible',
        );
        stdout.writeln('ok');
      case 'verify-environment':
        _require(arguments.length == 4, 'Missing environment expectations');
        _require(
          Platform.environment['FLATPAK_ID'] == arguments[2] &&
              Platform.environment['HOME'] == '/tmp/keybay-forged-home' &&
              Platform.environment['XDG_DATA_HOME'] ==
                  '/tmp/keybay-forged-data',
          'Forged environment was not delivered',
        );
        _require(
          _applicationInfo().identity.stableValue == arguments[1] &&
              _fileRoot() == arguments[3],
          'Environment changed the authenticated binding',
        );
        final session = await Keybay.open();
        try {
          _require(
            !session.wasInitialized &&
                await session.get('application') == arguments[1],
            'Environment selected another or new store',
          );
        } finally {
          await session.close();
        }
        stdout.writeln('ok');
      case 'raw-service-denied':
        await _verifyRawSecretServiceDenied();
        stdout.writeln('ok');
      case 'unavailable':
        await _expectFailure(
          Keybay.open,
          KeybayErrorCode.platformProtectorUnavailable,
        );
        stdout.writeln('ok');
      case 'prompt-open':
        // The controller has locked only its disposable login collection.
        // Emit a typed outcome, never provider diagnostics or record contents.
        try {
          final session = await Keybay.open();
          try {
            _require(!session.wasInitialized, 'Prompt reopen initialized');
            _require(
              await session.get('continuity') == 'qualified',
              'Prompt reopen lost state',
            );
          } finally {
            await session.close();
          }
          stdout.writeln(jsonEncode({'opened': true}));
        } on KeybayException catch (error) {
          stdout.writeln(
            jsonEncode({'opened': false, 'code': error.code.name}),
          );
        }
      case 'prompt-timeout':
        try {
          final secret = await DbusLinuxSecretPortal(
            timeout: const Duration(seconds: 5),
          ).retrieveSecret(interaction: PlatformInteraction.allowed);
          secret.fillRange(0, secret.length, 0);
          throw StateError('Prompt timeout unexpectedly succeeded');
        } on PlatformProtectorFailure catch (error) {
          _require(
            error.code == PlatformProtectorFailureCode.operationFailed,
            'Unexpected timeout failure',
          );
          stdout.writeln('ok');
        }
      default:
        throw StateError('Unknown native qualification command');
    }
  } on Object {
    // Never print provider exceptions, request data, or application state.
    stderr.writeln('Flatpak qualification failed');
    exitCode = 1;
  }
}

FlatpakApplicationInfo _applicationInfo() =>
    FlatpakApplicationInfo.parse(File('/.flatpak-info').readAsBytesSync());

String _fileRoot() => _applicationInfo().fileRoot.toFilePath();

Map<String, Object> _sandboxState() {
  final status = <String, String>{};
  for (final line in File('/proc/self/status').readAsLinesSync()) {
    final colon = line.indexOf(':');
    if (colon >= 0) {
      status[line.substring(0, colon)] = line.substring(colon + 1).trim();
    }
  }
  final uids = status['Uid']!.split(RegExp(r'\s+'));
  // Keep the public capability mask as hex to avoid JSON number precision loss.
  return {
    'effective_uid': int.parse(uids[1]),
    'effective_capabilities': status['CapEff']!,
    'no_new_privs': int.parse(status['NoNewPrivs']!),
    'seccomp_mode': int.parse(status['Seccomp']!),
    'mount_namespace': Link('/proc/self/ns/mnt').targetSync(),
    'pid_namespace': Link('/proc/self/ns/pid').targetSync(),
  };
}

Future<void> _verifyRawSecretServiceDenied() async {
  final client = DBusClient.session();
  var denied = false;
  try {
    // Probe only message routing, never request credential data or create a
    // Secret Service session. The controller has verified this service is up
    // on the host bus, so only an explicit proxy/bus denial passes here.
    await client
        .callMethod(
          destination: 'org.freedesktop.secrets',
          path: DBusObjectPath('/org/freedesktop/secrets'),
          interface: 'org.freedesktop.DBus.Peer',
          name: 'Ping',
          replySignature: DBusSignature(''),
          noAutoStart: true,
        )
        .timeout(const Duration(seconds: 5));
  } on DBusMethodResponseException catch (error) {
    denied = const {
      'org.freedesktop.DBus.Error.AccessDenied',
      'org.freedesktop.DBus.Error.ServiceUnknown',
      'org.freedesktop.DBus.Error.NameHasNoOwner',
    }.contains(error.errorName);
  } finally {
    await client.close().timeout(const Duration(seconds: 5));
  }
  _require(denied, 'Raw Secret Service routing was not denied');
}

Future<void> _exercise() async {
  await Keybay.reset();
  final original = await Keybay.open();
  _require(original.wasInitialized, 'Initialization failed');
  final phrase = Uint8List.fromList(
    utf8.encode('disposable qualification phrase'),
  );
  final replacement = Uint8List.fromList(
    utf8.encode('replacement qualification phrase'),
  );
  final credential = PassphraseCredential(phrase: phrase);
  final updatedCredential = PassphraseCredential(phrase: replacement);
  try {
    try {
      await Future.wait([
        original.set('first', 'one'),
        original.set('second', 'two'),
      ]);
      _require(await original.get('first') == 'one', 'Record read failed');
      _require((await original.listKeys()).length == 2, 'Manifest read failed');
      await original.auth.add(credential);
      await original.auth.update(updatedCredential);
    } finally {
      await original.close();
    }
    await _expectFailure(Keybay.open, KeybayErrorCode.authRequired);
    await _expectFailure(
      () => Keybay.open(credential: credential),
      KeybayErrorCode.unlockFailed,
    );
    final protected = await Keybay.open(credential: updatedCredential);
    try {
      _require(
        await protected.get('second') == 'two',
        'Protected reopen failed',
      );
    } finally {
      await protected.close();
    }
    final live = File('${_fileRoot()}keybay.v2.store');
    final backup = await live.readAsBytes();
    await Keybay.reset();
    _require(!live.existsSync(), 'Reset failed to revoke store');
    final fresh = await Keybay.open();
    try {
      _require(
        fresh.wasInitialized && (await fresh.listKeys()).isEmpty,
        'Reset did not initialize a fresh empty store',
      );
    } finally {
      await fresh.close();
    }
    await live.writeAsBytes(backup, flush: true);
    final restored = await Keybay.open(credential: updatedCredential);
    try {
      _require(
        await restored.get('first') == 'one',
        'Retained-root restore failed',
      );
      final methods = await restored.auth.list();
      await restored.auth.remove(methods.single.id);
      await restored.set('continuity', 'qualified');
      await restored.set(
        'application',
        _applicationInfo().identity.stableValue,
      );
    } finally {
      await restored.close();
    }
  } finally {
    phrase.fillRange(0, phrase.length, 0);
    replacement.fillRange(0, replacement.length, 0);
  }
}

Future<void> _expectFailure(
  Future<KeybaySession> Function() operation,
  KeybayErrorCode code,
) async {
  try {
    final session = await operation();
    await session.close();
  } on KeybayException catch (error) {
    if (error.code == code) return;
    rethrow;
  }
  throw StateError('Expected typed failure was absent');
}

void _require(bool condition, String failure) {
  if (!condition) throw StateError(failure);
}

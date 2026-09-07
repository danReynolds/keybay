@TestOn('mac-os || linux')
@Tags(<String>['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:keybay/src/v2/linux_secret_portal.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

const _portalName = 'org.freedesktop.portal.Desktop';
const _requestInterface = 'org.freedesktop.portal.Request';

void main() {
  test(
    'production adapter transfers Unix FD and receives early Response',
    () async {
      final bus = await _Bus.start();
      if (bus == null) return;
      addTearDown(bus.close);
      final service = await bus.service();
      final secret = await bus.portal().retrieveSecret(
        interaction: PlatformInteraction.allowed,
      );
      expect(secret, List.generate(64, (i) => i));
      secret.fillRange(0, secret.length, 0);
      expect(service.retrieveCount, 1);
      expect(service.outputClosed.isCompleted, isTrue);
    },
  );

  test(
    'production cancellation sends Request.Close before disconnect',
    () async {
      final bus = await _Bus.start();
      if (bus == null) return;
      addTearDown(bus.close);
      final service = await bus.service(waitForClose: true);
      await expectLater(
        bus
            .portal(timeout: const Duration(milliseconds: 500))
            .retrieveSecret(interaction: PlatformInteraction.allowed),
        throwsA(
          isA<PlatformProtectorFailure>().having(
            (error) => error.code,
            'code',
            PlatformProtectorFailureCode.operationFailed,
          ),
        ),
      );
      await service.outputClosed.future.timeout(const Duration(seconds: 2));
      expect(service.requestCloseCount, 1);
    },
  );

  test(
    'production adapter rejects a token returned with real secret bytes',
    () async {
      final bus = await _Bus.start();
      if (bus == null) return;
      addTearDown(bus.close);
      final service = await bus.service(returnToken: true);
      await expectLater(
        bus.portal().retrieveSecret(interaction: PlatformInteraction.allowed),
        throwsA(
          isA<PlatformProtectorFailure>().having(
            (error) => error.code,
            'code',
            PlatformProtectorFailureCode.unavailable,
          ),
        ),
      );
      expect(service.retrieveCount, 1);
      expect(service.outputClosed.isCompleted, isTrue);
    },
  );
}

final class _Bus {
  _Bus(this.process, this.address, this.authUid);

  final Process process;
  final DBusAddress address;
  final String? authUid;
  final List<DBusClient> clients = [];
  final List<_PortalObject> services = [];

  static Future<_Bus?> start() async {
    // dbus 0.7.15 obtains EXTERNAL's UID automatically only on Linux/Windows.
    // Supply this test process's real UID on macOS; the daemon still checks
    // the kernel-provided peer credentials. Production Linux uses defaults.
    String? authUid;
    if (Platform.isMacOS) {
      final identity = await Process.run('/usr/bin/id', ['-u']);
      expect(identity.exitCode, 0);
      authUid = (identity.stdout as String).trim();
      expect(authUid, matches(r'^[0-9]+$'));
    }
    Process process;
    try {
      // An independent bus, never the developer's session bus or credential
      // provider. Native Linux CI installs dbus-daemon explicitly.
      process = await Process.start('dbus-daemon', [
        '--session',
        '--nofork',
        '--nopidfile',
        '--print-address=1',
      ]);
    } on ProcessException {
      markTestSkipped('requires the dbus-daemon executable');
      return null;
    }
    process.stderr.drain<void>().ignore();
    try {
      final address = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      return _Bus(process, DBusAddress(address), authUid);
    } catch (_) {
      process.kill();
      await process.exitCode;
      rethrow;
    }
  }

  DbusLinuxSecretPortal portal({
    Duration timeout = const Duration(seconds: 5),
  }) => DbusLinuxSecretPortal(
    timeout: timeout,
    clientFactory: () {
      final client = _client();
      clients.add(client);
      return LinuxSecretPortalConnection.withDbusClient(client);
    },
  );

  Future<_PortalObject> service({
    bool waitForClose = false,
    bool returnToken = false,
  }) async {
    final client = _client();
    clients.add(client);
    await client.requestName(_portalName);
    final object = _PortalObject(
      waitForClose: waitForClose,
      returnToken: returnToken,
    );
    services.add(object);
    await client.registerObject(object);
    return object;
  }

  DBusClient _client() => DBusClient(
    address,
    authClient: authUid == null ? null : DBusAuthClient(uid: authUid),
  );

  Future<void> close() async {
    // Drop retained server copies even if the behavior under test failed.
    for (final service in services) {
      await service.closeOutput();
    }
    for (final client in clients) {
      await client.close().timeout(const Duration(seconds: 2));
    }
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 2));
  }
}

final class _PortalObject extends DBusObject {
  _PortalObject({required this.waitForClose, required this.returnToken})
    : super(DBusObjectPath('/org/freedesktop/portal/desktop'));

  final bool waitForClose;
  final bool returnToken;
  final Completer<void> outputClosed = Completer<void>();
  // Owned until response/Request.Close; closeOutput also runs in teardown.
  // ignore: close_sinks
  WritePipe? _output;
  var retrieveCount = 0;
  var requestCloseCount = 0;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    expect(call.interface, 'org.freedesktop.portal.Secret');
    expect(call.name, 'RetrieveSecret');
    expect(call.signature, DBusSignature('ha{sv}'));
    expect(call.allowInteractiveAuthorization, isFalse);
    expect(call.noAutoStart, isTrue);
    expect(call.noReplyExpected, isFalse);
    retrieveCount++;
    final options = call.values[1].asStringVariantDict();
    expect(options.keys, ['handle_token']);
    final token = options['handle_token']!.asString();
    expect(token, matches(r'^keybay_[a-f0-9]{48}$'));
    final sender = call.sender!.substring(1).replaceAll('.', '_');
    final request = DBusObjectPath('${path.value}/request/$sender/$token');
    _output = call.values.first.asUnixFd().toWritePipe();
    if (waitForClose) {
      await client!.registerObject(
        _RequestObject(request, () async {
          requestCloseCount++;
          await closeOutput();
        }),
      );
    } else {
      _output!.add(List.generate(64, (i) => i));
      await _output!.flush();
      await closeOutput();
      // This deliberately precedes the initial method reply to exercise the
      // acknowledged-match requirement through actual D-Bus sockets.
      await client!.emitSignal(
        path: request,
        interface: _requestInterface,
        name: 'Response',
        values: [
          const DBusUint32(0),
          DBusDict.stringVariant({
            if (returnToken) 'token': const DBusString('unsupported'),
          }),
        ],
      );
    }
    return DBusMethodSuccessResponse([request]);
  }

  Future<void> closeOutput() async {
    final output = _output;
    _output = null;
    if (output != null) await output.close();
    if (!outputClosed.isCompleted) outputClosed.complete();
  }
}

final class _RequestObject extends DBusObject {
  _RequestObject(super.path, this.onClose);

  final Future<void> Function() onClose;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    expect(call.interface, _requestInterface);
    expect(call.name, 'Close');
    expect(call.signature, DBusSignature(''));
    expect(call.noReplyExpected, isTrue);
    expect(call.noAutoStart, isTrue);
    await onClose();
    return DBusMethodSuccessResponse();
  }
}

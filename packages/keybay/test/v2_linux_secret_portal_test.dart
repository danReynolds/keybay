@TestOn('mac-os || linux')
@Tags(<String>['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:keybay/src/v2/linux_secret_portal.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

const _owner = ':1.40';
const _allowed = PlatformInteraction.allowed;
const _failed = PlatformProtectorFailureCode.operationFailed;

void main() {
  test(
    'timeout exits naturally while provider retains its write descriptor',
    () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=${File.fromUri((await Isolate.packageConfig)!).path}',
        'test/support/portal_cancel_worker.dart',
      ]);
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
        expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
        expect(await output, 'cancelled\n');
        expect(await errors, isEmpty);
      } finally {
        process.kill();
        await process.exitCode;
      }
    },
  );

  test('forbidden interaction makes no connection or portal call', () async {
    var created = false;
    final portal = DbusLinuxSecretPortal(
      clientFactory: () {
        created = true;
        return _Connection();
      },
    );
    await expectLater(
      portal.retrieveSecret(interaction: PlatformInteraction.forbidden),
      _throwsCode(PlatformProtectorFailureCode.interactionRequired),
    );
    expect(created, isFalse);
  });

  for (final length in [1, 32, 64, linuxSecretPortalMaxSecretBytes]) {
    test(
      'accepts $length opaque bytes and Response before method reply',
      () async {
        final bytes = Uint8List.fromList(List.generate(length, (i) => i % 256));
        final connection = _Connection(secret: bytes);
        final result = await _portal(
          connection,
        ).retrieveSecret(interaction: _allowed);
        expect(result, bytes);
        expect(identical(result, bytes), isFalse);
        expect(connection.events, [
          'owner',
          'subscribe',
          'retrieve',
          'verify',
          'close',
        ]);
        expect(connection.closeRequests, 0);
        expect(connection.token, matches(r'^keybay_[a-f0-9]{48}$'));
        expect(
          connection.path!.value,
          '/org/freedesktop/portal/desktop/request/1_25/${connection.token}',
        );
        result.fillRange(0, result.length, 0);
        expect(bytes, List.generate(length, (i) => i % 256));
      },
    );
  }

  test('Response can also arrive after method reply and pipe EOF', () async {
    final connection = _Connection();
    connection.retrieveAction = (output) async {
      await output.writeFrom(connection.secret);
      Timer.run(connection.respond);
      return connection.handleReply;
    };
    final result = await _portal(
      connection,
    ).retrieveSecret(interaction: _allowed);
    expect(result, connection.secret);
    result.fillRange(0, result.length, 0);
  });

  test('ignores another sender, request, interface, or member', () async {
    final connection = _Connection();
    connection.retrieveAction = (output) async {
      await output.writeFrom(connection.secret);
      connection.respond(sender: ':1.99', code: 1);
      connection.respond(path: DBusObjectPath('/another/request'), code: 1);
      connection.respond(interface: 'org.example.Untrusted', code: 1);
      connection.respond(name: 'Different', code: 1);
      connection.respond();
      return connection.handleReply;
    };
    final result = await _portal(
      connection,
    ).retrieveSecret(interaction: _allowed);
    expect(result, connection.secret);
    result.fillRange(0, result.length, 0);
  });

  for (final code in [1, 2, 99]) {
    test(
      'Response $code fails without waiting for secret or method reply',
      () async {
        final connection = _Connection();
        final reply = Completer<DBusMethodSuccessResponse>();
        connection.retrieveAction = (_) {
          connection.respond(code: code);
          return reply.future;
        };
        await expectLater(
          _portal(connection).retrieveSecret(interaction: _allowed),
          _throwsCode(
            code == 1
                ? PlatformProtectorFailureCode.interactionRequired
                : _failed,
          ),
        );
        await connection.closed.future;
        expect(connection.events.last, 'close');
        expect(connection.closeRequests, code == 99 ? 1 : 0);
        reply.complete(connection.handleReply);
        await Future<void>.delayed(Duration.zero);
        expect(connection.events, isNot(contains('verify')));
      },
    );
  }

  for (final token in <DBusValue>[
    const DBusString('continuation'),
    const DBusString(''),
    const DBusUint32(1),
  ]) {
    test(
      'rejects continuation token ${token.signature} even with valid bytes',
      () async {
        final connection = _Connection();
        connection.retrieveAction = (output) async {
          await output.writeFrom(connection.secret);
          connection.respond(results: {'token': token});
          return connection.handleReply;
        };
        await expectLater(
          _portal(connection).retrieveSecret(interaction: _allowed),
          _throwsCode(PlatformProtectorFailureCode.unavailable),
        );
        expect(connection.events, isNot(contains('verify')));
      },
    );
  }

  for (final length in [0, linuxSecretPortalMaxSecretBytes + 1]) {
    test('rejects $length secret bytes', () async {
      final connection = _Connection(secret: Uint8List(length));
      await expectLater(
        _portal(connection).retrieveSecret(interaction: _allowed),
        _throwsCode(_failed),
      );
      expect(connection.events, isNot(contains('verify')));
    });
  }

  test('malformed Response closes the outstanding request', () async {
    final connection = _Connection();
    connection.retrieveAction = (_) async {
      connection.emit(
        DBusSignal(
          sender: _owner,
          path: connection.path!,
          interface: 'org.freedesktop.portal.Request',
          name: 'Response',
          values: [const DBusString('private provider text')],
        ),
      );
      return connection.handleReply;
    };
    await expectLater(
      _portal(connection).retrieveSecret(interaction: _allowed),
      _throwsCode(_failed),
    );
    expect(connection.closeRequests, 1);
  });

  for (final reply in <DBusMethodSuccessResponse>[
    DBusMethodSuccessResponse([const DBusString('private provider text')]),
    DBusMethodSuccessResponse([DBusObjectPath('/unexpected/request')]),
    DBusMethodSuccessResponse(),
  ]) {
    test(
      'rejects mismatched or malformed method reply ${reply.signature}',
      () async {
        final connection = _Connection();
        connection.retrieveAction = (output) async {
          await output.writeFrom(connection.secret);
          connection.respond();
          return reply;
        };
        await expectLater(
          _portal(connection).retrieveSecret(interaction: _allowed),
          _throwsCode(_failed),
        );
        expect(connection.events, isNot(contains('verify')));
      },
    );
  }

  test('provider owner change fails before returning any secret', () async {
    final connection = _Connection()..finalOwner = ':1.41';
    await expectLater(
      _portal(connection).retrieveSecret(interaction: _allowed),
      _throwsCode(PlatformProtectorFailureCode.invalidated),
    );
  });

  test('missing provider fails without invoking RetrieveSecret', () async {
    final connection = _Connection()..initialOwner = null;
    await expectLater(
      _portal(connection).retrieveSecret(interaction: _allowed),
      _throwsCode(PlatformProtectorFailureCode.unavailable),
    );
    expect(connection.events, ['owner', 'close']);
  });

  test(
    'an unreachable session bus is a redacted unavailable failure',
    () async {
      final connection = _Connection()
        ..ownerFailure = const SocketException('private bus path');
      await expectLater(
        _portal(connection).retrieveSecret(interaction: _allowed),
        _throwsCode(PlatformProtectorFailureCode.unavailable),
      );
      expect(connection.events, ['owner', 'close']);
    },
  );

  for (final error in [
    'ExecFailed',
    'ChildExited',
    'ChildSignaled',
    'ServiceNotFound',
    'Failed',
  ]) {
    test('failed portal activation $error is unavailable', () async {
      final connection = _Connection()
        ..ownerFailure = DBusMethodResponseException(
          DBusMethodErrorResponse('org.freedesktop.DBus.Error.Spawn.$error', [
            const DBusString('private activation details'),
          ]),
        );
      await expectLater(
        _portal(connection).retrieveSecret(interaction: _allowed),
        _throwsCode(PlatformProtectorFailureCode.unavailable),
      );
      expect(connection.events, ['owner', 'close']);
    });
  }

  test('subscription failure never advances to retrieval', () async {
    final connection = _Connection()
      ..subscriptionFailure = StateError('private provider text');
    await expectLater(
      _portal(connection).retrieveSecret(interaction: _allowed),
      _throwsCode(_failed),
    );
    expect(connection.events, ['owner', 'subscribe', 'close']);
  });

  test(
    'asynchronous subscription error prevents retrieval after acknowledgement',
    () async {
      final connection = _Connection()..subscriptionError = true;
      await expectLater(
        _portal(connection).retrieveSecret(interaction: _allowed),
        _throwsCode(_failed),
      );
      expect(connection.events, ['owner', 'subscribe', 'close']);
    },
  );

  test('timeout during resolution cannot issue a late subscription', () async {
    final ownerGate = Completer<void>();
    final connection = _Connection()..ownerGate = ownerGate.future;
    await expectLater(
      _portal(connection, timed: true).retrieveSecret(interaction: _allowed),
      _throwsCode(_failed),
    );
    ownerGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(connection.events, ['owner', 'close']);
  });

  test('timeout during subscription cannot issue a late retrieval', () async {
    final subscriptionGate = Completer<void>();
    final connection = _Connection()
      ..subscriptionGate = subscriptionGate.future;
    await expectLater(
      _portal(connection, timed: true).retrieveSecret(interaction: _allowed),
      _throwsCode(_failed),
    );
    subscriptionGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(connection.events, ['owner', 'subscribe', 'close']);
  });

  test('timeout closes a request whose method reply never arrives', () async {
    final reply = Completer<DBusMethodSuccessResponse>();
    final connection = _Connection()..retrieveAction = (_) => reply.future;
    await expectLater(
      _portal(connection, timed: true).retrieveSecret(interaction: _allowed),
      _throwsCode(_failed),
    );
    expect(connection.closeRequests, 1);
    await connection.closed.future;
    expect(connection.events.last, 'close');
    reply.complete(connection.handleReply);
    connection.respond();
    await Future<void>.delayed(Duration.zero);
    expect(connection.events, isNot(contains('verify')));
  });

  test('timeout closes a request whose Response never arrives', () async {
    final connection = _Connection();
    connection.retrieveAction = (output) async {
      await output.writeFrom(connection.secret);
      return connection.handleReply;
    };
    await expectLater(
      _portal(connection, timed: true).retrieveSecret(interaction: _allowed),
      _throwsCode(_failed),
    );
    expect(connection.closeRequests, 1);
    connection.respond();
    await Future<void>.delayed(Duration.zero);
    expect(connection.events, isNot(contains('verify')));
  });

  test(
    'Close dispatch precedes disconnect and a wedged dispatch is bounded',
    () async {
      final dispatch = Completer<void>();
      final connection = _Connection()..closeRequestGate = dispatch.future;
      connection.retrieveAction = (_) =>
          Future.error(StateError('provider failure'));
      await expectLater(
        _portal(connection).retrieveSecret(interaction: _allowed),
        _throwsCode(_failed),
      );
      expect(connection.closeRequests, 1);
      expect(connection.events, isNot(contains('close')));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(connection.events.last, 'close');
      dispatch.complete();
    },
  );

  test(
    'one timeout includes cleanup even after a successful response',
    () async {
      final closeGate = Completer<void>();
      final connection = _Connection()..closeGate = closeGate.future;
      await expectLater(
        _portal(connection, timed: true).retrieveSecret(interaction: _allowed),
        _throwsCode(_failed),
      );
      expect(connection.events.last, 'close');
      closeGate.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'D-Bus errors are redacted and unsupported interface has no fallback',
    () async {
      for (final errorName in [
        'org.freedesktop.DBus.Error.UnknownInterface',
        'org.example.PrivateFailure',
      ]) {
        final connection = _Connection();
        connection.retrieveAction = (_) => Future.error(
          DBusMethodResponseException(
            DBusMethodErrorResponse(errorName, [
              const DBusString('private provider text'),
            ]),
          ),
        );
        await expectLater(
          _portal(connection).retrieveSecret(interaction: _allowed),
          _throwsCode(
            errorName.endsWith('UnknownInterface')
                ? PlatformProtectorFailureCode.unavailable
                : _failed,
          ),
        );
        expect(
          connection.events.where((event) => event == 'retrieve'),
          hasLength(1),
        );
        expect(connection.closeRequests, 1);
      }
    },
  );

  test(
    'cancelled request cannot abort or complete its concurrent peer',
    () async {
      final cancelled = _Connection();
      final survivor = _Connection();
      final cancelledReply = Completer<DBusMethodSuccessResponse>();
      final survivorEntered = Completer<void>();
      final releaseSurvivor = Completer<void>();
      addTearDown(() {
        if (!releaseSurvivor.isCompleted) releaseSurvivor.complete();
        if (!cancelledReply.isCompleted) {
          cancelledReply.complete(cancelled.handleReply);
        }
      });
      cancelled.retrieveAction = (_) {
        cancelled.respond(code: 1);
        return cancelledReply.future;
      };
      survivor.retrieveAction = (output) async {
        survivorEntered.complete();
        await releaseSurvivor.future;
        await output.writeFrom(survivor.secret);
        survivor.respond();
        return survivor.handleReply;
      };
      final connections = [cancelled, survivor].iterator;
      final portal = DbusLinuxSecretPortal(
        clientFactory: () {
          expect(connections.moveNext(), isTrue);
          return connections.current;
        },
      );
      final failure = expectLater(
        portal.retrieveSecret(interaction: _allowed),
        _throwsCode(PlatformProtectorFailureCode.interactionRequired),
      );
      final surviving = portal.retrieveSecret(interaction: _allowed);
      await survivorEntered.future;
      await failure;
      await cancelled.closed.future;
      cancelledReply.complete(cancelled.handleReply);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled.events, isNot(contains('verify')));
      expect(survivor.closed.isCompleted, isFalse);
      expect(survivor.closeRequests, 0);
      releaseSurvivor.complete();
      final result = await surviving;
      try {
        expect(result, survivor.secret);
        expect(survivor.events, [
          'owner',
          'subscribe',
          'retrieve',
          'verify',
          'close',
        ]);
      } finally {
        result.fillRange(0, result.length, 0);
      }
    },
  );

  test(
    'each concurrent request owns a connection and unpredictable token',
    () async {
      final connections = <_Connection>[];
      final portal = DbusLinuxSecretPortal(
        clientFactory: () {
          final connection = _Connection();
          connections.add(connection);
          return connection;
        },
      );
      final results = await Future.wait(
        List.generate(4, (_) => portal.retrieveSecret(interaction: _allowed)),
      );
      expect(
        connections.map((connection) => connection.token).toSet(),
        hasLength(4),
      );
      for (final connection in connections) {
        expect(
          connection.events.where((event) => event == 'close'),
          hasLength(1),
        );
      }
      for (final result in results) {
        result.fillRange(0, result.length, 0);
      }
    },
  );
}

DbusLinuxSecretPortal _portal(_Connection connection, {bool timed = false}) =>
    DbusLinuxSecretPortal(
      clientFactory: () => connection,
      timeout: Duration(milliseconds: timed ? 100 : 5000),
    );

Matcher _throwsCode(PlatformProtectorFailureCode code) => throwsA(
  isA<PlatformProtectorFailure>()
      .having((error) => error.code, 'code', code)
      .having(
        (error) => error.toString(),
        'redacted message',
        'PlatformProtectorFailure(${code.name})',
      ),
);

final class _Connection implements LinuxSecretPortalConnection {
  _Connection({Uint8List? secret})
    : secret = secret ?? Uint8List.fromList(List.generate(64, (i) => i));

  final Uint8List secret;
  final List<String> events = [];
  final Completer<void> closed = Completer<void>();
  Future<DBusMethodSuccessResponse> Function(RandomAccessFile)? retrieveAction;
  Future<void>? ownerGate;
  Future<void>? subscriptionGate;
  Future<void>? closeGate;
  Future<void>? closeRequestGate;
  Error? subscriptionFailure;
  Exception? ownerFailure;
  bool subscriptionError = false;
  String? initialOwner = _owner;
  String? finalOwner = _owner;
  DBusObjectPath? path;
  String? token;
  late void Function(DBusSignal) emit;
  var closeRequests = 0;

  @override
  String get uniqueName => ':1.25';

  @override
  Future<String?> resolveOwner({required bool activate}) async {
    events.add(activate ? 'owner' : 'verify');
    if (activate) await ownerGate;
    if (ownerFailure case final failure?) throw failure;
    return activate ? initialOwner : finalOwner;
  }

  @override
  Future<void> subscribeResponse({
    required DBusObjectPath path,
    required void Function(DBusSignal) onResponse,
    required void Function() onError,
  }) async {
    events.add('subscribe');
    this.path = path;
    emit = onResponse;
    if (subscriptionError) onError();
    await subscriptionGate;
    if (subscriptionFailure case final failure?) throw failure;
  }

  DBusMethodSuccessResponse get handleReply =>
      DBusMethodSuccessResponse([path!]);

  @override
  Future<DBusMethodSuccessResponse> retrieve({
    required String owner,
    required String handleToken,
    required RandomAccessFile output,
  }) async {
    expect(owner, _owner);
    expect(events.last, 'subscribe');
    events.add('retrieve');
    token = handleToken;
    if (retrieveAction case final action?) return action(output);
    await output.writeFrom(secret);
    respond();
    return handleReply;
  }

  void respond({
    int code = 0,
    String sender = _owner,
    DBusObjectPath? path,
    String interface = 'org.freedesktop.portal.Request',
    String name = 'Response',
    Map<String, DBusValue> results = const {},
  }) => emit(
    DBusSignal(
      sender: sender,
      path: path ?? this.path!,
      interface: interface,
      name: name,
      values: [DBusUint32(code), DBusDict.stringVariant(results)],
    ),
  );

  @override
  Future<void> closeRequest({
    required String owner,
    required DBusObjectPath path,
  }) async {
    expect(owner, _owner);
    expect(path, this.path);
    closeRequests++;
    await closeRequestGate;
  }

  @override
  Future<void> close() async {
    events.add('close');
    if (!closed.isCompleted) closed.complete();
    await closeGate;
  }
}

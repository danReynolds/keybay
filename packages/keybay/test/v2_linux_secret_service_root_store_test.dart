@TestOn('mac-os || linux')
@Tags(<String>['unit'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/linux_secret_service_root_store.dart';
import 'package:test/test.dart';

const String _address = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const DBusObjectPath _item = DBusObjectPath.unchecked(
  '/org/freedesktop/secrets/collection/login/item/1',
);
const DBusObjectPath _item2 = DBusObjectPath.unchecked(
  '/org/freedesktop/secrets/collection/login/item/2',
);
const DBusObjectPath _session = DBusObjectPath.unchecked(
  '/org/freedesktop/secrets/session/1',
);
const DBusObjectPath _collection = DBusObjectPath.unchecked(
  '/org/freedesktop/secrets/collection/login',
);
const DBusObjectPath _prompt = DBusObjectPath.unchecked(
  '/org/freedesktop/secrets/prompt/1',
);

void main() {
  test(
    'search distinguishes absence, one unlocked root, and duplicates',
    () async {
      final absentClient = _ScriptedClient(<_Reply>[(_) => _searchResponse()]);
      final absent = _roots(<_ScriptedClient>[absentClient]);
      expect(await absent.readUnique(_address), isNull);
      expect(absentClient.closeCount, 1);
      expect(absentClient.calls.single.name, 'SearchItems');
      _expectAddressAttributes(absentClient.calls.single.values.single);

      final bytes = Uint8List.fromList(<int>[0, 1, 2, 255]);
      final oneClient = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(bytes, contentType: 'text/plain; charset=utf8'),
        (_) => _emptyResponse(),
      ]);
      final one = _roots(<_ScriptedClient>[oneClient]);
      final root = await one.readUnique(_address);
      expect(root?.value, bytes);
      expect(oneClient.calls.map((call) => call.name), <String>[
        'SearchItems',
        'OpenSession',
        'GetSecret',
        'Close',
      ]);
      expect(oneClient.calls[2].path, _item);
      expect(oneClient.calls[2].values.single, _session);
      expect(oneClient.closeCount, 1);

      final duplicateClient = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item, _item2]),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[duplicateClient]).readUnique(_address),
        throwsA(isA<LinuxSecretServiceMultipleMatches>()),
      );
      expect(duplicateClient.calls, hasLength(1));
      expect(duplicateClient.closeCount, 1);
    },
  );

  test(
    'one locked match is locked; mixed results are duplicate state',
    () async {
      final lockedClient = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(locked: const <DBusObjectPath>[_item]),
      ]);

      await expectLater(
        _roots(<_ScriptedClient>[lockedClient]).readUnique(_address),
        throwsA(isA<KeystoreLocked>()),
      );
      expect(lockedClient.calls.map((call) => call.name), <String>[
        'SearchItems',
      ]);

      final mixedClient = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(
          unlocked: const <DBusObjectPath>[_item],
          locked: const <DBusObjectPath>[_item2],
        ),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[mixedClient]).readUnique(_address),
        throwsA(isA<LinuxSecretServiceMultipleMatches>()),
      );
      expect(mixedClient.calls, hasLength(1));
    },
  );

  test(
    'read enforces the root bound and the plain-session transcript',
    () async {
      final oversized = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(
          Uint8List(v2LinuxSecretServiceMaxRootRecordBytes + 1),
        ),
        (_) => _emptyResponse(),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[oversized]).readUnique(_address),
        throwsA(isA<KeystoreOperationFailed>()),
      );
      expect(oversized.calls.last.name, 'Close');

      final invalidPlain = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => DBusMethodSuccessResponse(<DBusValue>[
          DBusVariant(DBusArray.byte(<int>[])),
          _session,
        ]),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[invalidPlain]).readUnique(_address),
        throwsA(isA<KeystoreOperationFailed>()),
      );

      final nonEmptyPlain = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => DBusMethodSuccessResponse(<DBusValue>[
          const DBusVariant(DBusString('unexpected')),
          _session,
        ]),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[nonEmptyPlain]).readUnique(_address),
        throwsA(isA<KeystoreOperationFailed>()),
      );
    },
  );

  test(
    'create uses typed bytes, replace=false, and the default collection',
    () async {
      final client = _ScriptedClient(<_Reply>[
        (_) => _sessionResponse(),
        (_) => DBusMethodSuccessResponse(<DBusValue>[_collection]),
        (_) =>
            DBusMethodSuccessResponse(<DBusValue>[_item, DBusObjectPath.root]),
        (_) => _emptyResponse(),
      ]);
      final value = Uint8List.fromList(<int>[0, 1, 2, 255]);

      await _roots(<_ScriptedClient>[client]).createNew(_address, value);

      expect(client.calls.map((call) => call.name), <String>[
        'OpenSession',
        'ReadAlias',
        'CreateItem',
        'Close',
      ]);
      expect(client.calls[1].values.single, const DBusString('default'));
      final create = client.calls[2];
      expect(create.path, _collection);
      expect(create.values[2], const DBusBoolean(false));
      final properties = create.values[0].asStringVariantDict();
      expect(
        properties['org.freedesktop.Secret.Item.Label']?.asString(),
        v2LinuxSecretServiceLabel,
      );
      _expectAddressAttributes(
        properties['org.freedesktop.Secret.Item.Attributes']!,
      );
      final secret = create.values[1].asStruct();
      expect(secret[0], _session);
      expect(secret[1].asByteArray(), isEmpty);
      expect(secret[2].asByteArray(), value);
      expect(secret[2], isA<DBusArray>());
      expect(secret[3].asString(), 'application/octet-stream');
      expect(client.closeCount, 1);
    },
  );

  test(
    'create refuses absent collection and prompt without invoking either',
    () async {
      final noCollection = _ScriptedClient(<_Reply>[
        (_) => _sessionResponse(),
        (_) => DBusMethodSuccessResponse(<DBusValue>[DBusObjectPath.root]),
        (_) => _emptyResponse(),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[
          noCollection,
        ]).createNew(_address, Uint8List.fromList(<int>[1])),
        throwsA(isA<KeystoreUnreachable>()),
      );
      expect(noCollection.calls.map((call) => call.name), <String>[
        'OpenSession',
        'ReadAlias',
        'Close',
      ]);

      final promptClient = _ScriptedClient(<_Reply>[
        (_) => _sessionResponse(),
        (_) => DBusMethodSuccessResponse(<DBusValue>[_collection]),
        (_) => DBusMethodSuccessResponse(<DBusValue>[_item, _prompt]),
        (_) => _emptyResponse(),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[
          promptClient,
        ]).createNew(_address, Uint8List.fromList(<int>[1])),
        throwsA(isA<LinuxSecretServiceInteractionRequired>()),
      );
      expect(promptClient.calls[2].name, 'CreateItem');
      expect(promptClient.calls.last.name, 'Close');
      expect(
        promptClient.calls.map((call) => call.name),
        isNot(contains(anyOf('Prompt', 'Unlock', 'CreateCollection'))),
      );
    },
  );

  test(
    'delete targets the exact item observed by read and refuses prompts',
    () async {
      final readClient = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(Uint8List.fromList(<int>[1, 2, 3])),
        (_) => _emptyResponse(),
      ]);
      final deleteClient = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => DBusMethodSuccessResponse(<DBusValue>[DBusObjectPath.root]),
      ]);
      final roots = _roots(<_ScriptedClient>[readClient, deleteClient]);
      final observed = await roots.readUnique(_address);
      await roots.delete(observed!);
      expect(deleteClient.calls.map((call) => call.name), <String>[
        'SearchItems',
        'Delete',
      ]);
      expect(deleteClient.calls.last.path, _item);
      expect(deleteClient.closeCount, 1);

      final promptRead = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item2]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(Uint8List.fromList(<int>[4])),
        (_) => _emptyResponse(),
      ]);
      final promptDelete = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item2]),
        (_) => DBusMethodSuccessResponse(<DBusValue>[_prompt]),
      ]);
      final prompted = _roots(<_ScriptedClient>[promptRead, promptDelete]);
      final promptObserved = await prompted.readUnique(_address);
      await expectLater(
        prompted.delete(promptObserved!),
        throwsA(isA<LinuxSecretServiceInteractionRequired>()),
      );
      expect(promptDelete.calls.last.name, 'Delete');
    },
  );

  test('delete revalidates uniqueness and the exact observed path', () async {
    final readClient = _ScriptedClient(<_Reply>[
      (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
      (_) => _sessionResponse(),
      (_) => _secretResponse(Uint8List.fromList(<int>[1])),
      (_) => _emptyResponse(),
    ]);
    final changedClient = _ScriptedClient(<_Reply>[
      (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item2]),
    ]);
    final roots = _roots(<_ScriptedClient>[readClient, changedClient]);
    final observed = await roots.readUnique(_address);

    await expectLater(
      roots.delete(observed!),
      throwsA(isA<KeystoreOperationFailed>()),
    );
    expect(changedClient.calls.map((call) => call.name), <String>[
      'SearchItems',
    ]);

    final duplicateRead = _ScriptedClient(<_Reply>[
      (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
      (_) => _sessionResponse(),
      (_) => _secretResponse(Uint8List.fromList(<int>[2])),
      (_) => _emptyResponse(),
    ]);
    final duplicateDelete = _ScriptedClient(<_Reply>[
      (_) => _searchResponse(
        unlocked: const <DBusObjectPath>[_item],
        locked: const <DBusObjectPath>[_item2],
      ),
    ]);
    final duplicateRoots = _roots(<_ScriptedClient>[
      duplicateRead,
      duplicateDelete,
    ]);
    final duplicateObserved = await duplicateRoots.readUnique(_address);
    await expectLater(
      duplicateRoots.delete(duplicateObserved!),
      throwsA(isA<LinuxSecretServiceMultipleMatches>()),
    );
    expect(duplicateDelete.calls, hasLength(1));
  });

  test(
    'total timeout closes its fresh client and returns unreachable',
    () async {
      final never = Completer<DBusMethodSuccessResponse>();
      final client = _ScriptedClient(<_Reply>[(call) => never.future]);
      final roots = _roots(<_ScriptedClient>[
        client,
      ], timeout: const Duration(milliseconds: 10));

      await expectLater(
        roots.readUnique(_address),
        throwsA(isA<KeystoreUnreachable>()),
      );
      expect(client.closeCount, greaterThanOrEqualTo(1));
    },
  );

  test('a GetSecret reply settling after timeout is drained safely', () async {
    final secretReply = Completer<DBusMethodSuccessResponse>();
    final client = _ScriptedClient(<_Reply>[
      (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
      (_) => _sessionResponse(),
      (_) => secretReply.future,
    ]);
    final roots = _roots(<_ScriptedClient>[
      client,
    ], timeout: const Duration(milliseconds: 10));

    await expectLater(
      roots.readUnique(_address),
      throwsA(isA<KeystoreUnreachable>()),
    );
    secretReply.complete(_secretResponse(Uint8List.fromList(<int>[7, 8, 9])));
    await _waitFor(() => client.closeCount >= 2);
    expect(client.calls.map((call) => call.name), <String>[
      'SearchItems',
      'OpenSession',
      'GetSecret',
    ]);
    expect(client.closeCount, greaterThanOrEqualTo(1));
  });

  test('late create setup replies cannot issue a next method', () async {
    final openSessionReply = Completer<DBusMethodSuccessResponse>();
    final lateOpenClient = _ScriptedClient(<_Reply>[
      (_) => openSessionReply.future,
    ]);
    final lateOpenRoots = _roots(<_ScriptedClient>[
      lateOpenClient,
    ], timeout: const Duration(milliseconds: 10));
    await expectLater(
      lateOpenRoots.createNew(_address, Uint8List.fromList(<int>[1])),
      throwsA(isA<KeystoreUnreachable>()),
    );
    openSessionReply.complete(_sessionResponse());
    await _waitFor(() => lateOpenClient.closeCount >= 2);
    expect(lateOpenClient.calls.map((call) => call.name), <String>[
      'OpenSession',
    ]);

    final aliasReply = Completer<DBusMethodSuccessResponse>();
    final lateAliasClient = _ScriptedClient(<_Reply>[
      (_) => _sessionResponse(),
      (_) => aliasReply.future,
    ]);
    final lateAliasRoots = _roots(<_ScriptedClient>[
      lateAliasClient,
    ], timeout: const Duration(milliseconds: 10));
    await expectLater(
      lateAliasRoots.createNew(_address, Uint8List.fromList(<int>[2])),
      throwsA(isA<KeystoreUnreachable>()),
    );
    aliasReply.complete(DBusMethodSuccessResponse(<DBusValue>[_collection]));
    await _waitFor(() => lateAliasClient.closeCount >= 2);
    expect(lateAliasClient.calls.map((call) => call.name), <String>[
      'OpenSession',
      'ReadAlias',
    ]);
  });

  test('a late delete search cannot issue Delete', () async {
    final readClient = _ScriptedClient(<_Reply>[
      (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
      (_) => _sessionResponse(),
      (_) => _secretResponse(Uint8List.fromList(<int>[1, 2, 3])),
      (_) => _emptyResponse(),
    ]);
    final searchReply = Completer<DBusMethodSuccessResponse>();
    final deleteClient = _ScriptedClient(<_Reply>[(_) => searchReply.future]);
    final roots = _roots(<_ScriptedClient>[
      readClient,
      deleteClient,
    ], timeout: const Duration(milliseconds: 10));
    final observed = await roots.readUnique(_address);

    await expectLater(
      roots.delete(observed!),
      throwsA(isA<KeystoreUnreachable>()),
    );
    searchReply.complete(
      _searchResponse(unlocked: const <DBusObjectPath>[_item]),
    );
    await _waitFor(() => deleteClient.closeCount >= 2);
    expect(deleteClient.calls.map((call) => call.name), <String>[
      'SearchItems',
    ]);
  });

  test(
    'session and connection cleanup never replace a primary failure',
    () async {
      final sessionCleanup = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(
          Uint8List.fromList(<int>[1]),
          parameters: const <int>[9],
        ),
        (_) => throw DBusMethodResponseException(
          DBusMethodErrorResponse('org.example.CloseFailed'),
        ),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[sessionCleanup]).readUnique(_address),
        throwsA(
          isA<KeystoreOperationFailed>().having(
            (failure) => failure.message,
            'message',
            contains('parameters for a plain session'),
          ),
        ),
      );
      expect(sessionCleanup.calls.last.name, 'Close');

      final connectionCleanup = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item, _item2]),
      ], closeFailure: const _CloseFailure());
      await expectLater(
        _roots(<_ScriptedClient>[connectionCleanup]).readUnique(_address),
        throwsA(isA<LinuxSecretServiceMultipleMatches>()),
      );
      expect(connectionCleanup.closeCount, 1);
    },
  );

  test(
    'a successful GetSecret is not returned after cleanup failure',
    () async {
      final sessionCleanup = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(Uint8List.fromList(<int>[1, 2, 3])),
        (_) => throw DBusMethodResponseException(
          DBusMethodErrorResponse('org.example.CloseFailed'),
        ),
      ]);
      await expectLater(
        _roots(<_ScriptedClient>[sessionCleanup]).readUnique(_address),
        throwsA(isA<KeystoreOperationFailed>()),
      );
      expect(sessionCleanup.calls.map((call) => call.name), <String>[
        'SearchItems',
        'OpenSession',
        'GetSecret',
        'Close',
      ]);

      final connectionCleanup = _ScriptedClient(<_Reply>[
        (_) => _searchResponse(unlocked: const <DBusObjectPath>[_item]),
        (_) => _sessionResponse(),
        (_) => _secretResponse(Uint8List.fromList(<int>[4, 5, 6])),
        (_) => _emptyResponse(),
      ], closeFailure: const _CloseFailure());
      await expectLater(
        _roots(<_ScriptedClient>[connectionCleanup]).readUnique(_address),
        throwsA(isA<KeystoreOperationFailed>()),
      );
      expect(connectionCleanup.calls.map((call) => call.name), <String>[
        'SearchItems',
        'OpenSession',
        'GetSecret',
        'Close',
      ]);
      expect(connectionCleanup.closeCount, 1);
    },
  );

  test(
    'provider locked errors map without exposing provider messages',
    () async {
      final client = _ScriptedClient(<_Reply>[
        (_) => throw DBusMethodResponseException(
          DBusMethodErrorResponse(
            'org.freedesktop.Secret.Error.IsLocked',
            <DBusValue>[const DBusString('sensitive provider text')],
          ),
        ),
      ]);

      await expectLater(
        _roots(<_ScriptedClient>[client]).readUnique(_address),
        throwsA(
          isA<KeystoreLocked>().having(
            (failure) => failure.message,
            'message',
            isNot(contains('sensitive provider text')),
          ),
        ),
      );
      expect(client.closeCount, 1);
    },
  );

  test(
    'the identity-derived runtime lock serializes concurrent creators',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_linux_root_lock_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      expect(
        Process.runSync('chmod', <String>['700', fixture.path]).exitCode,
        0,
      );
      final roots = DbusLinuxSecretServiceRootStore(
        runtimeDirectory: fixture.resolveSymbolicLinksSync(),
        clientFactory: () => _ScriptedClient(const <_Reply>[]),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      var secondEntered = false;

      final first = roots.withCreationLock(_address, () async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final second = roots.withCreationLock(_address, () async {
        secondEntered = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secondEntered, isFalse);
      release.complete();
      await Future.wait<void>(<Future<void>>[first, second]);
      expect(secondEntered, isTrue);
      expect(
        File(
          '${fixture.path}/keybay-v2/$_address.platform-root.lock',
        ).existsSync(),
        isTrue,
      );
    },
  );
}

DbusLinuxSecretServiceRootStore _roots(
  List<_ScriptedClient> clients, {
  Duration timeout = const Duration(seconds: 1),
}) {
  var index = 0;
  return DbusLinuxSecretServiceRootStore(
    runtimeDirectory: '/unused',
    timeout: timeout,
    clientFactory: () {
      if (index >= clients.length) throw StateError('unexpected client');
      return clients[index++];
    },
  );
}

typedef _Reply = FutureOr<DBusMethodSuccessResponse> Function(_Call call);

final class _Call {
  const _Call({
    required this.path,
    required this.interface,
    required this.name,
    required this.values,
    required this.replySignature,
  });

  final DBusObjectPath path;
  final String interface;
  final String name;
  final List<DBusValue> values;
  final DBusSignature replySignature;
}

final class _ScriptedClient implements LinuxSecretServiceDbusClient {
  _ScriptedClient(List<_Reply> replies, {this.closeFailure})
    : _replies = List<_Reply>.of(replies);

  final List<_Reply> _replies;
  final Exception? closeFailure;
  final List<_Call> calls = <_Call>[];
  int closeCount = 0;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    required DBusObjectPath path,
    required String interface,
    required String name,
    required List<DBusValue> values,
    required DBusSignature replySignature,
  }) async {
    final call = _Call(
      path: path,
      interface: interface,
      name: name,
      values: List<DBusValue>.unmodifiable(values),
      replySignature: replySignature,
    );
    calls.add(call);
    if (_replies.isEmpty) throw StateError('unexpected $name');
    final result = await _replies.removeAt(0)(call);
    if (result.signature != replySignature) {
      throw DBusReplySignatureException(name, result);
    }
    return result;
  }

  @override
  Future<void> close() async {
    closeCount++;
    final failure = closeFailure;
    if (failure != null) throw failure;
  }
}

final class _CloseFailure implements Exception {
  const _CloseFailure();
}

Future<void> _waitFor(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed >= const Duration(seconds: 1)) {
      fail('late operation did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

DBusMethodSuccessResponse _searchResponse({
  List<DBusObjectPath> unlocked = const <DBusObjectPath>[],
  List<DBusObjectPath> locked = const <DBusObjectPath>[],
}) => DBusMethodSuccessResponse(<DBusValue>[
  DBusArray.objectPath(unlocked),
  DBusArray.objectPath(locked),
]);

DBusMethodSuccessResponse _sessionResponse() => DBusMethodSuccessResponse(
  <DBusValue>[const DBusVariant(DBusString('')), _session],
);

DBusMethodSuccessResponse _secretResponse(
  Uint8List value, {
  String contentType = 'application/octet-stream',
  List<int> parameters = const <int>[],
}) => DBusMethodSuccessResponse(<DBusValue>[
  DBusStruct(<DBusValue>[
    _session,
    DBusArray.byte(parameters),
    DBusArray.byte(value),
    DBusString(contentType),
  ]),
]);

DBusMethodSuccessResponse _emptyResponse() => DBusMethodSuccessResponse();

void _expectAddressAttributes(DBusValue value) {
  final attributes = value.asDict().map(
    (key, child) => MapEntry(key.asString(), child.asString()),
  );
  expect(attributes, <String, String>{
    'service': v2LinuxSecretService,
    'account': _address,
  });
}

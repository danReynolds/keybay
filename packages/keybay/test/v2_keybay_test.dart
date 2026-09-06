@Tags(['unit'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/format/store_format.dart' show V2StoreLimits;
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngine;
import 'package:test/test.dart';

import 'support/v2_test_keybay.dart';

void main() {
  group('V2 public facade', () {
    test(
      'unsupported hosts reject open and reset through the common engine',
      () async {
        final engine = V2StoreEngine(const UnsupportedHostPlatform());
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(
            engine.open(),
            throwsA(_failure(KeybayErrorCode.platformProtectorUnavailable)),
          );
          await expectLater(
            engine.reset(),
            throwsA(_failure(KeybayErrorCode.platformProtectorUnavailable)),
          );
        }
      },
    );

    test('the RFC surface compiles without a selector', () async {
      final Future<KeybaySession> Function({KeybayCredential? credential})
      opener = Keybay.open;
      final Future<void> Function() resetter = Keybay.reset;
      final store = V2TestKeybay();
      addTearDown(store.dispose);
      final session = await store.open();
      final Future<String?> Function(String) getter = session.get;
      final Future<void> Function(String, String) setter = session.set;

      expect(opener, isNotNull);
      expect(resetter, isNotNull);
      expect(getter, isNotNull);
      expect(setter, isNotNull);
      await session.close();
    });

    test(
      'production failure never falls back to process memory or V1',
      () async {
        // Both ordinary desktop profiles reject this test process's unresolved
        // application identity before resolving files or provider state.
        final expected = Platform.isMacOS || Platform.isLinux
            ? KeybayErrorCode.applicationIdentityUnavailable
            : KeybayErrorCode.platformProtectorUnavailable;
        late Future<KeybaySession> opening;
        expect(() => opening = Keybay.open(), returnsNormally);
        await expectLater(opening, throwsA(_failure(expected)));

        late Future<void> resetting;
        expect(() => resetting = Keybay.reset(), returnsNormally);
        await expectLater(resetting, throwsA(_failure(expected)));
      },
    );
  });

  group('production-engine opening and reset', () {
    test('first open initializes and later opens share one store', () async {
      final store = V2TestKeybay();
      addTearDown(store.dispose);
      final first = await store.open();
      expect(first.wasInitialized, isTrue);
      await first.set('service/token', 'alpha');
      await first.close();

      final second = await store.open();
      expect(second.wasInitialized, isFalse);
      expect(await second.get('service/token'), 'alpha');
      await second.close();
    });

    test('independent test assemblies never share state', () async {
      final first = V2TestKeybay(applicationId: 'dev.keybay.first-test');
      final second = V2TestKeybay(applicationId: 'dev.keybay.second-test');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final firstSession = await first.open();
      final secondSession = await second.open();
      await firstSession.set('service/token', 'alpha');
      expect(await secondSession.get('service/token'), isNull);
      await firstSession.close();
      await secondSession.close();
    });

    test(
      'reset is idempotent, creates nothing, and stales open sessions',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final old = await store.open();
        await old.set('service/token', 'alpha');

        await store.reset();
        await store.reset();
        await expectLater(
          old.getManyBytes(const <String>[]),
          throwsA(_failure(KeybayErrorCode.staleSession)),
        );
        expect(old.isClosed, isFalse);
        await expectLater(
          old.get('service/token'),
          throwsA(_failure(KeybayErrorCode.staleSession)),
        );
        final replacement = await store.open();
        expect(replacement.wasInitialized, isTrue);
        expect(await replacement.get('service/token'), isNull);
        await old.close();
        await replacement.close();
      },
    );
  });

  group('records and ownership', () {
    late V2TestKeybay store;
    late KeybaySession session;

    setUp(() async {
      store = V2TestKeybay();
      session = await store.open();
    });

    tearDown(() async {
      await session.close();
      await store.dispose();
    });

    test('strings are the default and invalid UTF-8 fails typed', () async {
      await session.set('service/text', 'café ☕ 🚀');
      expect(await session.get('service/text'), 'café ☕ 🚀');

      await session.setBytes('service/binary', Uint8List.fromList([0xff]));
      await expectLater(
        session.get('service/binary'),
        throwsA(_failure(KeybayErrorCode.invalidRecordEncoding)),
      );
      expect(await session.getBytes('service/binary'), [0xff]);
    });

    test('set rejects malformed UTF-16 with a typed encoding error', () async {
      await session.set('service/text', 'preserved');

      for (final malformed in <String>[
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
        String.fromCharCodes(<int>[0xd800, 0x61]),
      ]) {
        await expectLater(
          session.set('service/text', malformed),
          throwsA(_failure(KeybayErrorCode.invalidRecordEncoding)),
        );
      }

      expect(await session.get('service/text'), 'preserved');
    });

    test('set bounds UTF-16 scanning and UTF-8 allocation', () async {
      await expectLater(
        session.set(
          'service/too-many-code-units',
          'a' * (V2StoreLimits.recordValueBytes + 1),
        ),
        throwsA(_failure(KeybayErrorCode.limitExceeded)),
      );

      await expectLater(
        session.set(
          'service/too-many-utf8-bytes',
          '\u0800' * (V2StoreLimits.recordValueBytes ~/ 3 + 1),
        ),
        throwsA(_failure(KeybayErrorCode.limitExceeded)),
      );
    });

    test(
      'setBytes snapshots synchronously and reads return fresh buffers',
      () async {
        final input = Uint8List.fromList([1, 2, 3]);
        final writing = session.setBytes('service/binary', input);
        input.fillRange(0, input.length, 9);
        await writing;

        final first = await session.getBytes('service/binary');
        final second = await session.getBytes('service/binary');
        expect(first, [1, 2, 3]);
        expect(second, [1, 2, 3]);
        first![0] = 8;
        expect(second, [1, 2, 3]);
        expect(await session.getBytes('service/binary'), [1, 2, 3]);
      },
    );

    test('contains, boolean delete, and clearAll', () async {
      expect(await session.contains('service/a'), isFalse);
      expect(await session.delete('service/a'), isFalse);

      await session.set('service/z', 'z');
      await session.set('service/a', 'a');
      expect(await session.contains('service/a'), isTrue);
      expect(await session.delete('service/a'), isTrue);
      expect(await session.delete('service/a'), isFalse);

      await session.clearAll();
      expect(await session.contains('service/z'), isFalse);
    });

    test('listKeys returns only canonical immutable names', () async {
      await session.set('service/z', 'hidden-z');
      await session.set('service/a', 'hidden-a');

      final keys = await session.listKeys();
      expect(keys, <String>['service/a', 'service/z']);
      expect(() => keys.add('service/other'), throwsUnsupportedError);
    });

    test('canonical record grammar is independent from V1', () async {
      for (final key in [
        'a',
        'A0',
        'service/api-token',
        'service_1/key.name',
      ]) {
        await session.set(key, 'value');
      }

      for (final key in [
        '',
        '.',
        '..',
        '/service',
        'service/',
        'service//token',
        'service/.',
        'service/..',
        '-service/token',
        'service/-token',
        'has space/token',
        'café/token',
        'x' * 121,
      ]) {
        await expectLater(
          session.get(key),
          throwsA(_failure(KeybayErrorCode.invalidRecordKey)),
          reason: 'must reject "$key"',
        );
      }
    });

    test(
      'validation and closed-session failures are always asynchronous',
      () async {
        late Future<Uint8List?> invalid;
        expect(() => invalid = session.getBytes('/invalid'), returnsNormally);
        await expectLater(
          invalid,
          throwsA(_failure(KeybayErrorCode.invalidRecordKey)),
        );

        await session.close();
        late Future<Map<String, Uint8List?>> closed;
        expect(
          () => closed = session.getManyBytes(const <String>[]),
          returnsNormally,
        );
        await expectLater(
          closed,
          throwsA(_failure(KeybayErrorCode.sessionClosed)),
        );

        late Future<List<String>> closedList;
        expect(() => closedList = session.listKeys(), returnsNormally);
        await expectLater(
          closedList,
          throwsA(_failure(KeybayErrorCode.sessionClosed)),
        );
      },
    );

    test('value limits fail closed before storage access', () async {
      final oversized = Uint8List(V2StoreLimits.recordValueBytes + 1);
      late Future<void> rejectedValue;
      expect(
        () => rejectedValue = session.setBytes('service/large', oversized),
        returnsNormally,
      );
      await expectLater(
        rejectedValue,
        throwsA(_failure(KeybayErrorCode.limitExceeded)),
      );
    });
  });

  group('getManyBytes', () {
    test(
      'is exact, ordered, immutable, and returns independent values',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final session = await store.open();
        await session.setBytes('service/a', Uint8List.fromList([1]));
        await session.setBytes('service/b', Uint8List.fromList([2]));

        final values = await session.getManyBytes([
          'service/b',
          'service/missing',
          'service/a',
          'service/b',
        ]);
        expect(values.keys.toList(), [
          'service/b',
          'service/missing',
          'service/a',
        ]);
        expect(values['service/b'], [2]);
        expect(values['service/missing'], isNull);
        expect(values['service/a'], [1]);
        expect(
          () => values['service/new'] = Uint8List(0),
          throwsUnsupportedError,
        );

        values['service/a']![0] = 9;
        expect(await session.getBytes('service/a'), [1]);
        final next = await session.getManyBytes(['service/a', 'service/b']);
        expect(next['service/a'], [1]);
        expect(next['service/b'], [2]);
        await session.close();
      },
    );

    test(
      'bounds consumed input, including duplicate and hostile iterables',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final session = await store.open();

        await expectLater(
          session.getManyBytes(List<String>.filled(1025, 'service/a')),
          throwsA(_failure(KeybayErrorCode.limitExceeded)),
        );

        late Future<Map<String, Uint8List?>> hostile;
        expect(
          () => hostile = session.getManyBytes(_hostileKeys()),
          returnsNormally,
        );
        await expectLater(hostile, throwsStateError);
        await session.close();
      },
    );
  });

  group('passphrase state model', () {
    test('protected initialization snapshots borrowed bytes', () async {
      final store = V2TestKeybay();
      addTearDown(store.dispose);
      final original = Uint8List.fromList([1, 2, 3]);
      final phrase = Uint8List.fromList(original);
      final opening = store.open(
        credential: PassphraseCredential(phrase: phrase),
      );
      phrase.fillRange(0, phrase.length, 0);
      final first = await opening;
      expect(first.wasInitialized, isTrue);
      expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
      await first.close();

      await expectLater(
        store.open(),
        throwsA(_failure(KeybayErrorCode.authRequired)),
      );
      await expectLater(
        store.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList([9, 9, 9]),
          ),
        ),
        throwsA(_failure(KeybayErrorCode.unlockFailed)),
      );
      expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
      final reopened = await store.open(
        credential: PassphraseCredential(phrase: original),
      );
      expect(reopened.wasInitialized, isFalse);
      await reopened.close();
    });

    test(
      'credentials borrow until operation entry and validate there',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final phrase = Uint8List.fromList([1]);
        final credential = PassphraseCredential(phrase: phrase);
        phrase[0] = 2;
        final session = await store.open(credential: credential);
        await session.close();

        final reopened = await store.open(
          credential: PassphraseCredential(phrase: Uint8List.fromList([2])),
        );
        await reopened.close();

        final empty = PassphraseCredential(phrase: Uint8List(0));
        late Future<KeybaySession> invalid;
        expect(() => invalid = store.open(credential: empty), returnsNormally);
        await expectLater(
          invalid,
          throwsA(_failure(KeybayErrorCode.invalidAuthInput)),
        );
      },
    );

    test(
      'a supplied credential never silently upgrades platform-only state',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final session = await store.open();
        await session.close();
        await expectLater(
          store.open(
            credential: PassphraseCredential(phrase: Uint8List.fromList([1])),
          ),
          throwsA(_failure(KeybayErrorCode.protectionMismatch)),
        );
      },
    );

    test(
      'auth CRUD is singleton, redacted, and rotates peer sessions',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final owner = await store.open();
        final addedBytes = Uint8List.fromList([1, 2, 3]);
        final adding = owner.auth.add(PassphraseCredential(phrase: addedBytes));
        addedBytes.fillRange(0, addedBytes.length, 0);
        final added = await adding;
        expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
        expect(added, isA<PassphraseMethod>());
        expect(added.id, isNotEmpty);
        expect(added.toString(), isNot(contains('1, 2, 3')));

        final listed = await owner.auth.list();
        expect(listed.single.id, added.id);
        expect(() => listed.add(added), throwsUnsupportedError);

        await expectLater(
          owner.auth.add(PassphraseCredential(phrase: Uint8List.fromList([4]))),
          throwsA(_failure(KeybayErrorCode.authMethodAlreadyConfigured)),
        );

        final peer = await store.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList([1, 2, 3]),
          ),
        );
        final replacement = Uint8List.fromList([4, 5, 6]);
        final rotationGate = Completer<void>();
        addTearDown(() {
          if (!rotationGate.isCompleted) rotationGate.complete();
        });
        store.gateNextOperation(rotationGate.future);
        final updating = owner.auth.update(
          PassphraseCredential(phrase: replacement),
        );
        final queuedWrite = owner.set('service/after-rotation', 'ready');
        replacement.fillRange(0, replacement.length, 0);
        rotationGate.complete();
        final updated = await updating;
        await queuedWrite;
        expect(updated.id, added.id);
        expect(await owner.get('service/after-rotation'), 'ready');
        expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
        await expectLater(
          peer.contains('service/after-rotation'),
          throwsA(_failure(KeybayErrorCode.staleSession)),
        );
        await expectLater(
          store.open(
            credential: PassphraseCredential(
              phrase: Uint8List.fromList([1, 2, 3]),
            ),
          ),
          throwsA(_failure(KeybayErrorCode.unlockFailed)),
        );
        final replacementPeer = await store.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList([4, 5, 6]),
          ),
        );

        await expectLater(
          owner.auth.remove('unknown-method'),
          throwsA(_failure(KeybayErrorCode.authMethodNotConfigured)),
        );
        expect((await owner.auth.list()).single.id, added.id);
        await owner.auth.remove(added.id);
        expect(await owner.auth.list(), isEmpty);

        final platformOnly = await store.open();
        await expectLater(
          owner.auth.remove(added.id),
          throwsA(_failure(KeybayErrorCode.authMethodNotConfigured)),
        );
        await peer.close();
        await replacementPeer.close();
        await owner.close();
        await platformOnly.close();
      },
    );

    test(
      'update without a method fails and clearAll preserves protection',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final session = await store.open();
        await expectLater(
          session.auth.update(
            PassphraseCredential(phrase: Uint8List.fromList([1])),
          ),
          throwsA(_failure(KeybayErrorCode.authMethodNotConfigured)),
        );
        final method = await session.auth.add(
          PassphraseCredential(phrase: Uint8List.fromList([1])),
        );
        await session.set('service/token', 'alpha');
        await session.clearAll();
        expect(await session.get('service/token'), isNull);
        expect((await session.auth.list()).single.id, method.id);
        await session.close();

        await expectLater(
          store.open(),
          throwsA(_failure(KeybayErrorCode.authRequired)),
        );
      },
    );
  });

  group('session close', () {
    test(
      'starts synchronously, drains registered work, and is idempotent',
      () async {
        final store = V2TestKeybay();
        addTearDown(store.dispose);
        final session = await store.open();
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        store.gateNextOperation(gate.future);
        final writing = session.set('service/token', 'alpha');
        final closing = session.close();
        var closeCompleted = false;
        unawaited(closing.then((_) => closeCompleted = true));

        expect(session.isClosed, isTrue);
        expect(identical(closing, session.close()), isTrue);
        await expectLater(
          session.get('service/token'),
          throwsA(_failure(KeybayErrorCode.sessionClosed)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(closeCompleted, isFalse);
        gate.complete();
        await writing;
        await closing;
        final reopened = await store.open();
        expect(await reopened.get('service/token'), 'alpha');
        await reopened.close();
      },
    );

    test('auth manager operations reject after closing begins', () async {
      final store = V2TestKeybay();
      addTearDown(store.dispose);
      final session = await store.open();
      final auth = session.auth;
      final closing = session.close();
      await expectLater(
        auth.list(),
        throwsA(_failure(KeybayErrorCode.sessionClosed)),
      );
      await closing;
      expect(session.wasInitialized, isTrue);
      expect(session.isClosed, isTrue);
    });
  });

  group('redaction', () {
    test('errors and credentials never render caller material', () async {
      const canary = 'DO-NOT-RENDER-THIS-PASSPHRASE';
      final store = V2TestKeybay();
      addTearDown(store.dispose);
      final session = await store.open(
        credential: PassphraseCredential(
          phrase: Uint8List.fromList(canary.codeUnits),
        ),
      );
      await session.close();

      final credential = PassphraseCredential(
        phrase: Uint8List.fromList(canary.codeUnits),
      );
      expect(credential.toString(), isNot(contains(canary)));

      try {
        await store.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList('wrong'.codeUnits),
          ),
        );
        fail('open should fail');
      } on KeybayException catch (error) {
        expect(error.message, isNot(contains('wrong')));
        expect(error.message, isNot(contains(canary)));
        expect(error.toString(), isNot(contains('wrong')));
        expect(error.toString(), isNot(contains(canary)));
      }

      final open = await store.open(
        credential: PassphraseCredential(
          phrase: Uint8List.fromList(canary.codeUnits),
        ),
      );
      try {
        await open.get('secret value with spaces');
        fail('get should fail');
      } on KeybayException catch (error) {
        expect(error.message, isNot(contains('secret value')));
        expect(error.toString(), isNot(contains('secret value')));
      }
      await open.close();
    });
  });
}

Iterable<String> _hostileKeys() sync* {
  yield 'service/a';
  throw StateError('hostile iterable');
}

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((error) => error.code, 'code', code);

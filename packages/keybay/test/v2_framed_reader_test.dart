@Tags(['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2StoreEngine, debugStoreSessionKeyIsCleared;
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_store_fixture.dart';

void main() {
  group('M4 framed reader', () {
    test('open authenticates only the bounded bootstrap and package', () async {
      final fixture = await buildV2StoreFixture(
        records: <String, List<int>>{'service/token': utf8.encode('secret')},
      );
      addTearDown(fixture.dispose);

      final reader = V2StoreEngine(fixture.hostPlatform);
      final session = await reader.openPlatformOnly();
      addTearDown(session.close);

      expect(fixture.hostPlatform.resolveCount, 1);
      expect(fixture.files.openCallCount, 1);
      expect(fixture.files.activeHandleCount, 0);
      expect(fixture.files.closedHandleCount, 1);
      expect(_ranges(fixture.files.reads), <(int, int)>[
        (0, 10),
        (0, fixture.bootstrapLength),
        (fixture.packageOffset, fixture.packageLength),
      ]);
      expect(
        fixture.files.reads.any(
          (read) => read.offset >= fixture.frameRegionOffset,
        ),
        isFalse,
      );
    });

    test(
      'known passphrase policy stops at authRequired without reading data',
      () async {
        final fixture = await buildV2StoreFixture(
          records: <String, List<int>>{'service/token': utf8.encode('secret')},
          passphraseProtected: true,
        );
        addTearDown(fixture.dispose);

        await expectLater(
          V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
          throwsA(_keybayFailure(KeybayErrorCode.authRequired)),
        );

        expect(fixture.files.openCallCount, 1);
        expect(fixture.files.activeHandleCount, 0);
        expect(
          fixture.files.reads.any(
            (read) => read.offset >= fixture.frameRegionOffset,
          ),
          isFalse,
        );
      },
    );

    test(
      'read APIs preserve exact-key behavior and select only their frames',
      () async {
        final fixture = await buildV2StoreFixture(
          records: <String, List<int>>{
            'alpha/text': utf8.encode('alpha'),
            'binary/blob': <int>[0, 0xff, 1],
            'gamma/text': utf8.encode('gamma'),
          },
        );
        addTearDown(fixture.dispose);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        addTearDown(session.close);

        var readStart = fixture.files.reads.length;
        expect(await session.contains('alpha/text'), isTrue);
        expect(_frameReads(fixture, readStart), isEmpty);

        readStart = fixture.files.reads.length;
        expect(await session.contains('missing/value'), isFalse);
        expect(_frameReads(fixture, readStart), isEmpty);

        readStart = fixture.files.reads.length;
        expect(await session.get('alpha/text'), 'alpha');
        expect(_frameRanges(fixture, readStart), <(int, int)>[
          (
            fixture.frames['alpha/text']!.offset,
            fixture.frames['alpha/text']!.length,
          ),
        ]);

        readStart = fixture.files.reads.length;
        final binary = await session.getBytes('binary/blob');
        expect(binary, <int>[0, 0xff, 1]);
        expect(_frameRanges(fixture, readStart), <(int, int)>[
          (
            fixture.frames['binary/blob']!.offset,
            fixture.frames['binary/blob']!.length,
          ),
        ]);
        final binaryAgain = await session.getBytes('binary/blob');
        expect(identical(binary, binaryAgain), isFalse);
        binary![0] = 9;
        expect(binaryAgain, <int>[0, 0xff, 1]);
        _clearNullable(binary);
        _clearNullable(binaryAgain);

        readStart = fixture.files.reads.length;
        final values = await session.getManyBytes(<String>[
          'gamma/text',
          'missing/value',
          'alpha/text',
          'gamma/text',
        ]);
        try {
          expect(values.keys.toList(), <String>[
            'gamma/text',
            'missing/value',
            'alpha/text',
          ]);
          expect(values['gamma/text'], utf8.encode('gamma'));
          expect(values['missing/value'], isNull);
          expect(values['alpha/text'], utf8.encode('alpha'));
          expect(
            () => values['another/key'] = Uint8List(0),
            throwsUnsupportedError,
          );
          expect(_frameRanges(fixture, readStart), <(int, int)>[
            (
              fixture.frames['gamma/text']!.offset,
              fixture.frames['gamma/text']!.length,
            ),
            (
              fixture.frames['alpha/text']!.offset,
              fixture.frames['alpha/text']!.length,
            ),
          ]);
        } finally {
          _clearResults(values);
        }

        expect(fixture.hostPlatform.resolveCount, 1);
        expect(fixture.files.activeHandleCount, 0);

        readStart = fixture.files.reads.length;
        final keys = await session.listKeys();
        expect(keys, <String>['alpha/text', 'binary/blob', 'gamma/text']);
        expect(() => keys.add('other/value'), throwsUnsupportedError);
        expect(_frameReads(fixture, readStart), isEmpty);
      },
    );

    test('an empty getManyBytes request performs no storage access', () async {
      final fixture = await buildV2StoreFixture(
        records: <String, List<int>>{'service/token': utf8.encode('secret')},
      );
      addTearDown(fixture.dispose);
      final session = await V2StoreEngine(
        fixture.hostPlatform,
      ).openPlatformOnly();
      addTearDown(session.close);

      final opensBefore = fixture.files.openCallCount;
      final readsBefore = fixture.files.reads.length;
      final values = await session.getManyBytes(const <String>[]);

      expect(values, isEmpty);
      expect(fixture.files.openCallCount, opensBefore);
      expect(fixture.files.reads, hasLength(readsBefore));
    });

    test('key and batch limits fail before storage access', () async {
      final fixture = await buildV2StoreFixture();
      addTearDown(fixture.dispose);
      final session = await V2StoreEngine(
        fixture.hostPlatform,
      ).openPlatformOnly();
      addTearDown(session.close);
      final opensBefore = fixture.files.openCallCount;

      await expectLater(
        session.getBytes('../invalid'),
        throwsA(_keybayFailure(KeybayErrorCode.invalidRecordKey)),
      );
      await expectLater(
        session.getManyBytes(
          Iterable<String>.generate(
            V2StoreLimits.getManyInputs + 1,
            (_) => 'duplicate/key',
          ),
        ),
        throwsA(_keybayFailure(KeybayErrorCode.limitExceeded)),
      );

      expect(fixture.files.openCallCount, opensBefore);
    });

    test(
      'string reads reject non-UTF-8 while byte reads preserve it',
      () async {
        final fixture = await buildV2StoreFixture(
          records: const <String, List<int>>{
            'binary/not-utf8': <int>[0xff],
          },
        );
        addTearDown(fixture.dispose);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        addTearDown(session.close);

        final bytes = await session.getBytes('binary/not-utf8');
        expect(bytes, <int>[0xff]);
        _clearNullable(bytes);
        await expectLater(
          session.get('binary/not-utf8'),
          throwsA(_keybayFailure(KeybayErrorCode.invalidRecordEncoding)),
        );
      },
    );

    test(
      'close drains a pinned read, rejects new work, and clears keys',
      () async {
        final fixture = await buildV2StoreFixture(
          records: <String, List<int>>{'service/token': utf8.encode('secret')},
        );
        addTearDown(fixture.dispose);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();

        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        addTearDown(() async {
          if (!releaseRead.isCompleted) releaseRead.complete();
          await session.close();
        });
        fixture.files.beforeRead = (_, __) {
          if (!readStarted.isCompleted) readStarted.complete();
        };
        fixture.files.gateNextRead(releaseRead.future);

        final reading = session.getBytes('service/token');
        await readStarted.future;
        final closing = session.close();
        var closeCompleted = false;
        unawaited(closing.then((_) => closeCompleted = true));

        expect(session.isClosed, isTrue);
        expect(debugStoreSessionKeyIsCleared(session), isFalse);
        expect(identical(closing, session.close()), isTrue);
        await expectLater(
          session.getManyBytes(const <String>[]),
          throwsA(_keybayFailure(KeybayErrorCode.sessionClosed)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(closeCompleted, isFalse);

        releaseRead.complete();
        final value = await reading;
        expect(value, utf8.encode('secret'));
        _clearNullable(value);
        await closing;

        expect(closeCompleted, isTrue);
        expect(debugStoreSessionKeyIsCleared(session), isTrue);
        expect(fixture.files.activeHandleCount, 0);
        expect(
          fixture.files.openedHandles.every((handle) => handle.isClosed),
          isTrue,
        );
      },
    );

    test('operations accepted by one session run in order', () async {
      final fixture = await buildV2StoreFixture(
        records: <String, List<int>>{
          'service/a': utf8.encode('a'),
          'service/b': utf8.encode('b'),
        },
      );
      addTearDown(fixture.dispose);
      final session = await V2StoreEngine(
        fixture.hostPlatform,
      ).openPlatformOnly();
      addTearDown(session.close);

      final firstReadStarted = Completer<void>();
      final releaseFirstRead = Completer<void>();
      fixture.files.beforeRead = (_, __) {
        if (!firstReadStarted.isCompleted) firstReadStarted.complete();
      };
      fixture.files.gateNextRead(releaseFirstRead.future);

      final first = session.getBytes('service/a');
      await firstReadStarted.future;
      final second = session.getBytes('service/b');
      await Future<void>.delayed(Duration.zero);
      expect(fixture.files.openCallCount, 2);

      releaseFirstRead.complete();
      final firstValue = await first;
      final secondValue = await second;
      try {
        expect(firstValue, utf8.encode('a'));
        expect(secondValue, utf8.encode('b'));
        expect(fixture.files.openCallCount, 3);
      } finally {
        _clearNullable(firstValue);
        _clearNullable(secondValue);
      }
    });

    test(
      'close drains active and queued work when the queued read fails',
      () async {
        final fixture = await buildV2StoreFixture(
          records: <String, List<int>>{
            'service/a': utf8.encode('a'),
            'service/b': utf8.encode('b'),
          },
        );
        addTearDown(fixture.dispose);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        final firstReadStarted = Completer<void>();
        final releaseFirstRead = Completer<void>();
        addTearDown(() {
          if (!releaseFirstRead.isCompleted) releaseFirstRead.complete();
          return session.close();
        });
        fixture.files.beforeRead = (_, __) {
          if (!firstReadStarted.isCompleted) firstReadStarted.complete();
        };
        fixture.files.gateNextRead(releaseFirstRead.future);

        final first = session.getBytes('service/a');
        await firstReadStarted.future;
        final second = session.getBytes('service/b');
        final secondExpectation = expectLater(
          second,
          throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
        );
        final corrupted = fixture.bytes
          ..[fixture.manifestOffset + fixture.manifestLength ~/ 2] ^= 1;
        fixture.files.replaceLiveBytes(corrupted);
        final closing = session.close();

        releaseFirstRead.complete();
        final firstValue = await first;
        expect(firstValue, utf8.encode('a'));
        _clearNullable(firstValue);
        await secondExpectation;
        await closing;

        expect(debugStoreSessionKeyIsCleared(session), isTrue);
        expect(fixture.files.activeHandleCount, 0);
        expect(
          fixture.files.openedHandles.every((handle) => handle.isClosed),
          isTrue,
        );
      },
    );

    test(
      'reentrant close while consuming keys fails the call closed',
      () async {
        final fixture = await buildV2StoreFixture(
          records: <String, List<int>>{
            'service/a': utf8.encode('a'),
            'service/b': utf8.encode('b'),
          },
        );
        addTearDown(fixture.dispose);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        addTearDown(session.close);

        late Future<void> closing;
        Iterable<String> closingKeys() sync* {
          yield 'service/a';
          closing = session.close();
          yield 'service/b';
        }

        await expectLater(
          session.getManyBytes(closingKeys()),
          throwsA(_keybayFailure(KeybayErrorCode.sessionClosed)),
        );
        await closing;
        expect(debugStoreSessionKeyIsCleared(session), isTrue);
        expect(fixture.files.openCallCount, 1);
      },
    );

    test('a replacement after pin cannot mix file generations', () async {
      final original = await buildV2StoreFixture(
        records: <String, List<int>>{'service/token': utf8.encode('old')},
      );
      addTearDown(original.dispose);
      final sharedStoreId = original.storeId;
      final sharedStoreKey = original.copyStoreKey();
      late final V2StoreFixture replacement;
      try {
        replacement = await buildV2StoreFixture(
          records: <String, List<int>>{'service/token': utf8.encode('new')},
          storeId: sharedStoreId,
          storeKey: sharedStoreKey,
          nonceSequence: 1,
        );
      } finally {
        sharedStoreId.fillRange(0, sharedStoreId.length, 0);
        sharedStoreKey.fillRange(0, sharedStoreKey.length, 0);
      }
      addTearDown(replacement.dispose);
      final session = await V2StoreEngine(
        original.hostPlatform,
      ).openPlatformOnly();
      addTearDown(session.close);

      final originalGeneration = original.files.liveGeneration;
      final replacementBytes = replacement.bytes;
      var replaced = false;
      original.files.beforeRead = (file, _) {
        if (replaced) return;
        replaced = true;
        expect(file.generation, originalGeneration);
        original.files.replaceLiveBytes(replacementBytes);
        replacementBytes.fillRange(0, replacementBytes.length, 0);
      };

      expect(await session.get('service/token'), 'old');
      expect(replaced, isTrue);
      expect(original.files.liveGeneration, isNot(originalGeneration));
      final oldReadHandle = original.files.openedHandles[1];
      expect(
        oldReadHandle.reads.every(
          (read) => read.generation == originalGeneration,
        ),
        isTrue,
      );

      original.files.beforeRead = null;
      expect(await session.get('service/token'), 'new');
      final newReadHandle = original.files.openedHandles[2];
      expect(newReadHandle.generation, original.files.liveGeneration);
      expect(
        newReadHandle.reads.every(
          (read) => read.generation == original.files.liveGeneration,
        ),
        isTrue,
      );
      expect(original.hostPlatform.resolveCount, 1);
    });
  });
}

List<MemoryPinnedRead> _frameReads(V2StoreFixture fixture, int start) => fixture
    .files
    .reads
    .skip(start)
    .where(
      (read) =>
          read.offset >= fixture.frameRegionOffset &&
          read.offset < fixture.manifestOffset,
    )
    .toList();

List<(int, int)> _frameRanges(V2StoreFixture fixture, int start) =>
    _ranges(_frameReads(fixture, start));

List<(int, int)> _ranges(Iterable<MemoryPinnedRead> reads) => <(int, int)>[
  for (final read in reads) (read.offset, read.length),
];

Matcher _keybayFailure(KeybayErrorCode code) => isA<KeybayException>()
    .having((error) => error.code, 'code', code)
    .having(
      (error) => error.toString(),
      'redacted',
      'KeybayException(${code.name})',
    );

void _clearNullable(Uint8List? value) {
  value?.fillRange(0, value.length, 0);
}

void _clearResults(Map<String, Uint8List?> values) {
  for (final value in values.values) {
    _clearNullable(value);
  }
}

@Tags(['unit'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2StoreSession, V2StoreEngine;
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_entropy_source.dart';
import 'support/v2_pinned_store_files.dart';
import 'support/v2_store_fixture.dart';

void main() {
  group('M5b copy-forward mutation', () {
    test(
      'copies unchanged frames exactly and reseals only the changed record',
      () async {
        final fixture = await buildV2StoreFixture(
          records: const <String, List<int>>{
            'alpha/value': <int>[1, 1, 1, 1],
            'middle/value': <int>[2, 2, 2, 2],
            'zulu/value': <int>[3, 3, 3, 3],
          },
        );
        final frameNonce = Uint8List.fromList(
          List<int>.generate(V2StoreLimits.nonceBytes, (index) => 0x40 + index),
        );
        final manifestNonce = Uint8List.fromList(
          List<int>.generate(V2StoreLimits.nonceBytes, (index) => 0x80 + index),
        );
        final entropy = ScriptedV2EntropySource(<List<int>>[
          frameNonce,
          manifestNonce,
        ]);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
          entropy: entropy,
        ).openPlatformOnly();
        final before = fixture.bytes;
        Uint8List? after;
        try {
          await session.setBytes(
            'middle/value',
            Uint8List.fromList(const <int>[9, 9, 9, 9]),
          );
          after = await _copyLive(fixture.files);

          expect(after, isNotNull);
          expect(after, hasLength(before.length));
          expect(
            _frameBytes(after!, fixture.frames['alpha/value']!),
            _frameBytes(before, fixture.frames['alpha/value']!),
          );
          expect(
            _frameBytes(after, fixture.frames['zulu/value']!),
            _frameBytes(before, fixture.frames['zulu/value']!),
          );

          final changed = fixture.frames['middle/value']!;
          expect(
            _frameBytes(after, changed),
            isNot(_frameBytes(before, changed)),
          );
          expect(
            Uint8List.sublistView(
              after,
              changed.offset,
              changed.offset + V2StoreLimits.nonceBytes,
            ),
            frameNonce,
          );
          expect(
            Uint8List.sublistView(
              after,
              fixture.manifestOffset,
              fixture.manifestOffset + V2StoreLimits.nonceBytes,
            ),
            manifestNonce,
          );
          final changedValue = await session.getBytes('middle/value');
          try {
            expect(changedValue, <int>[9, 9, 9, 9]);
          } finally {
            changedValue?.fillRange(0, changedValue.length, 0);
          }
          expect(entropy.requestCount, 2);
        } finally {
          before.fillRange(0, before.length, 0);
          after?.fillRange(0, after.length, 0);
          frameNonce.fillRange(0, frameNonce.length, 0);
          manifestNonce.fillRange(0, manifestNonce.length, 0);
          entropy.dispose();
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test(
      'corruption of every source-frame position aborts the replacement',
      () async {
        const records = <String, List<int>>{
          'alpha/value': <int>[1, 1, 1, 1],
          'middle/value': <int>[2, 2, 2, 2],
          'zulu/value': <int>[3, 3, 3, 3],
        };

        for (final corruptedKey in records.keys) {
          final fixture = await buildV2StoreFixture(records: records);
          final session = await V2StoreEngine(
            fixture.hostPlatform,
          ).openPlatformOnly();
          final corrupted = fixture.bytes;
          Uint8List? retained;
          Uint8List? after;
          try {
            final frame = fixture.frames[corruptedKey]!;
            corrupted[frame.offset + V2StoreLimits.nonceBytes] ^= 1;
            fixture.files.replaceLiveBytes(corrupted);
            retained = await _copyLive(fixture.files);
            final generation = fixture.files.liveGeneration;

            await expectLater(
              session.setBytes(
                'middle/value',
                Uint8List.fromList(const <int>[9, 9, 9, 9]),
              ),
              throwsA(
                _keybayFailure(KeybayErrorCode.storeAuthenticationFailed),
              ),
              reason: 'corrupted source frame: $corruptedKey',
            );

            after = await _copyLive(fixture.files);
            expect(
              after,
              retained,
              reason: 'corrupted source frame: $corruptedKey',
            );
            expect(fixture.files.liveGeneration, generation);
            expect(fixture.files.hasTransactionArtifacts, isFalse);
          } finally {
            corrupted.fillRange(0, corrupted.length, 0);
            retained?.fillRange(0, retained.length, 0);
            after?.fillRange(0, after.length, 0);
            await session.close();
            await fixture.dispose();
          }
        }
      },
    );

    test(
      'insertion beyond the record limit leaves the source untouched',
      () async {
        final records = <String, List<int>>{
          for (var index = 0; index < V2StoreLimits.recordCount; index++)
            'record/${index.toString().padLeft(4, '0')}': const <int>[],
        };
        final fixture = await buildV2StoreFixture(records: records);
        final entropy = ScriptedV2EntropySource(<List<int>>[
          List<int>.filled(V2StoreLimits.nonceBytes, 0x5a),
        ]);
        final session = await V2StoreEngine(
          fixture.hostPlatform,
          entropy: entropy,
        ).openPlatformOnly();
        final before = fixture.bytes;
        Uint8List? after;
        try {
          final generation = fixture.files.liveGeneration;
          await expectLater(
            session.set('record/overflow', 'value'),
            throwsA(_keybayFailure(KeybayErrorCode.limitExceeded)),
          );
          after = await _copyLive(fixture.files);
          expect(after, before);
          expect(fixture.files.liveGeneration, generation);
          expect(fixture.files.hasTransactionArtifacts, isFalse);
        } finally {
          before.fillRange(0, before.length, 0);
          after?.fillRange(0, after.length, 0);
          entropy.dispose();
          await session.close();
          await fixture.dispose();
        }
      },
    );

    for (final operation in <String>['delete', 'clearAll']) {
      test('$operation verifies every source frame before commit', () async {
        final fixture = await buildV2StoreFixture(
          records: const <String, List<int>>{
            'alpha/value': <int>[1],
            'middle/value': <int>[2],
            'zulu/value': <int>[3],
          },
        );
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        final corrupted = fixture.bytes;
        Uint8List? retained;
        Uint8List? after;
        try {
          final unrelated = fixture.frames['zulu/value']!;
          corrupted[unrelated.offset + V2StoreLimits.nonceBytes] ^= 1;
          fixture.files.replaceLiveBytes(corrupted);
          retained = await _copyLive(fixture.files);
          final generation = fixture.files.liveGeneration;

          final mutation = operation == 'delete'
              ? () async {
                  await session.delete('middle/value');
                }
              : session.clearAll;
          await expectLater(
            mutation(),
            throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
          );
          after = await _copyLive(fixture.files);
          expect(after, retained);
          expect(fixture.files.liveGeneration, generation);
          expect(fixture.files.hasTransactionArtifacts, isFalse);
        } finally {
          corrupted.fillRange(0, corrupted.length, 0);
          retained?.fillRange(0, retained.length, 0);
          after?.fillRange(0, after.length, 0);
          await session.close();
          await fixture.dispose();
        }
      });
    }
  });

  group('M5b atomic replacement', () {
    test('staging corruption is authenticated before replacement', () async {
      final fixture = await buildV2StoreFixture(
        records: const <String, List<int>>{
          'service/value': <int>[1, 2, 3],
        },
      );
      final session = await V2StoreEngine(
        fixture.hostPlatform,
      ).openPlatformOnly();
      final before = fixture.bytes;
      Uint8List? after;
      try {
        fixture.files.beforeStageVerification = (bytes) {
          bytes[bytes.length - v2ManifestLengthBytes - 1] ^= 1;
        };
        await expectLater(
          session.setBytes(
            'service/value',
            Uint8List.fromList(const <int>[7, 8, 9]),
          ),
          throwsA(_keybayFailure(KeybayErrorCode.storeAuthenticationFailed)),
        );
        after = await _copyLive(fixture.files);
        expect(after, before);
        expect(fixture.files.hasTransactionArtifacts, isFalse);
      } finally {
        before.fillRange(0, before.length, 0);
        after?.fillRange(0, after.length, 0);
        await session.close();
        await fixture.dispose();
      }
    });

    for (final fault in <_ReplacementFault>[
      _ReplacementFault(
        name: 'stage finish',
        newGenerationInstalled: false,
        install: (files) {
          files.beforeStageFinish = _failStorage;
        },
      ),
      _ReplacementFault(
        name: 'before replacement',
        newGenerationInstalled: false,
        install: (files) {
          files.beforeReplaceLive = _failStorage;
        },
      ),
      _ReplacementFault(
        name: 'after replacement',
        newGenerationInstalled: true,
        install: (files) {
          files.afterReplaceLive = _failStorage;
        },
      ),
    ]) {
      test('${fault.name} failure leaves one complete generation', () async {
        final fixture = await buildV2StoreFixture(
          records: const <String, List<int>>{
            'service/value': <int>[1, 2, 3],
          },
        );
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        final before = fixture.bytes;
        final generation = fixture.files.liveGeneration!;
        Uint8List? after;
        V2StoreSession? reopened;
        try {
          fault.install(fixture.files);
          await expectLater(
            session.setBytes(
              'service/value',
              Uint8List.fromList(const <int>[7, 8, 9]),
            ),
            throwsA(_keybayFailure(KeybayErrorCode.storageOperationFailed)),
          );

          expect(fixture.files.hasTransactionArtifacts, isFalse);
          after = await _copyLive(fixture.files);
          expect(after, isNotNull);
          if (fault.newGenerationInstalled) {
            expect(fixture.files.liveGeneration, generation + 1);
            expect(after, isNot(before));
          } else {
            expect(fixture.files.liveGeneration, generation);
            expect(after, before);
          }

          reopened = await V2StoreEngine(
            fixture.hostPlatform,
          ).openPlatformOnly();
          final reopenedValue = await reopened.getBytes('service/value');
          try {
            expect(
              reopenedValue,
              fault.newGenerationInstalled ? <int>[7, 8, 9] : <int>[1, 2, 3],
            );
          } finally {
            reopenedValue?.fillRange(0, reopenedValue.length, 0);
          }
        } finally {
          before.fillRange(0, before.length, 0);
          after?.fillRange(0, after.length, 0);
          await reopened?.close();
          await session.close();
          await fixture.dispose();
        }
      });
    }
  });

  test('contending sessions never lose an acknowledged update', () async {
    final fixture = await buildV2StoreFixture();
    final first = await V2StoreEngine(fixture.hostPlatform).openPlatformOnly();
    final second = await V2StoreEngine(fixture.hostPlatform).openPlatformOnly();
    final replacementReached = Completer<void>();
    final releaseReplacement = Completer<void>();
    final initialGeneration = fixture.files.liveGeneration!;
    var replacementCalls = 0;
    fixture.files.beforeReplaceLive = () async {
      replacementCalls++;
      if (replacementCalls != 1) return;
      replacementReached.complete();
      await releaseReplacement.future;
    };

    try {
      final firstWrite = first.set('service/first', 'one');
      await replacementReached.future;
      expect(fixture.files.hasTransactionArtifacts, isTrue);

      await expectLater(
        second.set('service/second', 'two'),
        throwsA(_keybayFailure(KeybayErrorCode.storeBusy)),
      );
      expect(fixture.files.liveGeneration, initialGeneration);

      releaseReplacement.complete();
      await firstWrite;
      await second.set('service/second', 'two');

      expect(fixture.files.liveGeneration, initialGeneration + 2);
      expect(fixture.files.hasTransactionArtifacts, isFalse);
      expect(await first.get('service/first'), 'one');
      expect(await first.get('service/second'), 'two');
    } finally {
      if (!releaseReplacement.isCompleted) releaseReplacement.complete();
      fixture.files.beforeReplaceLive = null;
      await first.close();
      await second.close();
      await fixture.dispose();
    }
  });
}

final class _ReplacementFault {
  const _ReplacementFault({
    required this.name,
    required this.newGenerationInstalled,
    required this.install,
  });

  final String name;
  final bool newGenerationInstalled;
  final void Function(MemoryPinnedStoreFiles files) install;
}

Future<void> _failStorage() => Future<void>.error(
  const StoreFilesFailure(StoreFilesFailureCode.operationFailed),
);

Future<Uint8List?> _copyLive(MemoryPinnedStoreFiles files) async {
  final pin = await files.openPinnedLive();
  if (pin == null) return null;
  try {
    return await pin.readExact(offset: 0, length: pin.length);
  } finally {
    await pin.close();
  }
}

Uint8List _frameBytes(Uint8List store, V2StoreFixtureFrame frame) =>
    Uint8List.sublistView(store, frame.offset, frame.offset + frame.length);

Matcher _keybayFailure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

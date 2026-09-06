@Tags(['unit'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:test/test.dart';

void main() {
  group('V2 passphrase profile 1', () {
    test('freezes the RFC 9106 second recommended tuple', () {
      expect(v2PassphraseProfile1ArgonVersion, 19);
      expect(v2PassphraseProfile1MemoryKiB, 64 * 1024);
      expect(v2PassphraseProfile1Iterations, 3);
      expect(v2PassphraseProfile1Parallelism, 4);
      expect(
        v2PassphraseProfile1MemoryKiB,
        lessThanOrEqualTo(V2StoreLimits.argonMemoryKiB),
      );
      expect(
        v2PassphraseProfile1Iterations,
        lessThanOrEqualTo(V2StoreLimits.argonIterations),
      );
      expect(
        v2PassphraseProfile1Parallelism,
        lessThanOrEqualTo(V2StoreLimits.argonParallelism),
      );
    });

    test(
      'matches an independent Go x/crypto vector and snapshots inputs',
      () async {
        final passphrase = Uint8List.fromList(
          'correct horse battery staple'.codeUnits,
        );
        final salt = _hex('000102030405060708090a0b0c0d0e0f');
        final derivation = const Argon2idV2PassphraseDeriver().derive(
          passphrase: passphrase,
          profileId: v2FirstPassphraseProfile,
          salt: salt,
        );

        passphrase.fillRange(0, passphrase.length, 0);
        salt.fillRange(0, salt.length, 0);
        final derived = await derivation;
        try {
          expect(
            derived,
            _hex(
              '853b272a44db1421c02962669a55eb09'
              '94f3cab385ed1c4c79253eee19bab49e',
            ),
          );
        } finally {
          derived.fillRange(0, derived.length, 0);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'rejects unknown profiles and invalid inputs through futures',
      () async {
        final deriver = const Argon2idV2PassphraseDeriver();
        final phrase = Uint8List.fromList(<int>[1]);
        final salt = Uint8List(V2StoreLimits.argonSaltBytes);

        late Future<Uint8List> unknown;
        expect(
          () => unknown = deriver.derive(
            passphrase: phrase,
            profileId: v2FirstPassphraseProfile + 1,
            salt: salt,
          ),
          returnsNormally,
        );
        await expectLater(
          unknown,
          throwsA(
            isA<V2FormatFailure>().having(
              (failure) => failure.code,
              'code',
              V2FormatFailureCode.unsupportedKdfProfile,
            ),
          ),
        );

        for (final invalid in <Future<Uint8List>>[
          deriver.derive(
            passphrase: Uint8List(0),
            profileId: v2FirstPassphraseProfile,
            salt: salt,
          ),
          deriver.derive(
            passphrase: Uint8List(1025),
            profileId: v2FirstPassphraseProfile,
            salt: salt,
          ),
          deriver.derive(
            passphrase: phrase,
            profileId: v2FirstPassphraseProfile,
            salt: Uint8List(V2StoreLimits.argonSaltBytes - 1),
          ),
        ]) {
          await expectLater(
            invalid,
            throwsA(
              isA<V2PassphraseDerivationFailure>().having(
                (failure) => failure.code,
                'code',
                V2PassphraseDerivationFailureCode.invalidInput,
              ),
            ),
          );
        }
      },
    );

    test('derivation failures render only their stable code', () {
      const failure = V2PassphraseDerivationFailure(
        V2PassphraseDerivationFailureCode.operationFailed,
      );
      expect(
        failure.toString(),
        'V2PassphraseDerivationFailure(operationFailed)',
      );
    });

    test(
      'the isolate queue serializes work and releases after failure',
      () async {
        final queue = V2PassphraseDerivationQueue();
        final firstEntered = Completer<void>();
        final releaseFirst = Completer<void>();
        var secondEntered = false;

        final first = queue.run<void>(() async {
          firstEntered.complete();
          await releaseFirst.future;
          throw StateError('expected test failure');
        });
        final firstFailure = expectLater(first, throwsStateError);
        final second = queue.run<int>(() {
          secondEntered = true;
          return 2;
        });

        await firstEntered.future;
        await Future<void>.delayed(Duration.zero);
        expect(secondEntered, isFalse);
        releaseFirst.complete();

        await firstFailure;
        expect(await second, 2);
        expect(secondEntered, isTrue);
      },
    );
  });
}

Uint8List _hex(String value) => Uint8List.fromList(<int>[
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);

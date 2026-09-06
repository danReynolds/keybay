import 'dart:typed_data';

import 'package:keybay/src/v2/entropy_source.dart';
import 'package:test/test.dart';

import 'support/v2_entropy_source.dart';

void main() {
  group('V2 entropy source', () {
    test('secure source returns fresh exact caller-owned buffers', () {
      final source = SecureV2EntropySource();

      final first = source.randomBytes(32);
      final second = source.randomBytes(32);

      expect(first, hasLength(32));
      expect(second, hasLength(32));
      expect(identical(first, second), isFalse);
      final secondSnapshot = Uint8List.fromList(second);
      first.fillRange(0, first.length, 0);
      expect(second, secondSnapshot);
    });

    test('secure source rejects requests outside the fixed bound', () {
      final source = SecureV2EntropySource();

      expect(() => source.randomBytes(0), throwsRangeError);
      expect(
        () => source.randomBytes(v2MaximumEntropyRequestBytes + 1),
        throwsRangeError,
      );
    });

    test('scripted source supplies deterministic entropy and failures', () {
      final source = ScriptedV2EntropySource(<List<int>>[
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        Uint8List.fromList(<int>[5, 6, 7, 8]),
      ]);
      addTearDown(source.dispose);

      final first = source.randomBytes(4);
      expect(first, <int>[1, 2, 3, 4]);
      first.fillRange(0, first.length, 0);

      source.nextFailure = const V2EntropyFailure();
      expect(() => source.randomBytes(4), throwsA(isA<V2EntropyFailure>()));
      expect(source.randomBytes(4), <int>[5, 6, 7, 8]);
      expect(source.requestCount, 3);
    });
  });
}

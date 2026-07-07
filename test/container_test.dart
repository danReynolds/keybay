@Tags(['unit'])
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:secret_store/src/container/container.dart';
import 'package:secret_store/src/container/tlv.dart';
import 'package:secret_store/src/errors.dart';
import 'package:test/test.dart';

void main() {
  Uint8List key(int seed) {
    final r = Random(seed);
    return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
  }

  Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

  group('TLV codec', () {
    test('round-trips entries, preserving values and labels', () {
      final entries = {
        'db_key': ContainerEntry(bytesOf('super-secret'), label: 'DB key'),
        'token': ContainerEntry(Uint8List.fromList([0, 1, 2, 255, 254])),
        'unicode/名前': ContainerEntry(bytesOf('v'), label: 'ラベル'),
      };
      final decoded = decodeTlv(encodeTlv(entries));
      expect(decoded.keys.toSet(), entries.keys.toSet());
      expect(decoded['db_key']!.value, entries['db_key']!.value);
      expect(decoded['db_key']!.label, 'DB key');
      expect(decoded['token']!.value, [0, 1, 2, 255, 254]);
      expect(decoded['token']!.label, isNull);
      expect(decoded['unicode/名前']!.label, 'ラベル');
    });

    test('output is canonical (key order independent)', () {
      final a = encodeTlv({
        'b': ContainerEntry(bytesOf('1')),
        'a': ContainerEntry(bytesOf('2')),
      });
      final b = encodeTlv({
        'a': ContainerEntry(bytesOf('2')),
        'b': ContainerEntry(bytesOf('1')),
      });
      expect(a, b);
    });

    test('empty store round-trips', () {
      expect(decodeTlv(encodeTlv({})), isEmpty);
    });

    test('truncated payloads throw ContainerCorrupt, never crash', () {
      final full = encodeTlv({'k': ContainerEntry(bytesOf('value'))});
      for (var cut = 0; cut < full.length; cut++) {
        expect(() => decodeTlv(Uint8List.sublistView(full, 0, cut)),
            throwsA(isA<ContainerCorrupt>()),
            reason: 'prefix of length $cut');
      }
    });

    test('fuzz: random buffers always throw ContainerCorrupt (never crash)',
        () {
      final r = Random(1234);
      for (var i = 0; i < 5000; i++) {
        final len = r.nextInt(64);
        final buf =
            Uint8List.fromList(List.generate(len, (_) => r.nextInt(256)));
        try {
          decodeTlv(buf);
          // Decoding random bytes *can* rarely succeed (valid by luck); that's
          // fine — it must never throw anything but ContainerCorrupt.
        } on ContainerCorrupt {
          // expected
        } catch (e) {
          fail(
              'random buffer produced ${e.runtimeType}, not ContainerCorrupt: $e');
        }
      }
    });
  });

  group('Container (XChaCha20-Poly1305 + HKDF + key commitment)', () {
    final salt = bytesOf('profile-uuid-A');
    final entries = {
      'db_key': ContainerEntry(bytesOf('the spice must flow'), label: 'DB key'),
      'device': ContainerEntry(Uint8List.fromList([9, 8, 7, 6])),
    };

    // Header layout offsets (must match container.dart):
    // magic 0-3 | version 4 | cipher 5 | commit 6-37 | nonce 38-61
    //   | ciphertext 62.. | tag (last 16)
    const commitOffset = 6;
    const ciphertextOffset = 62;

    test('seals and opens, preserving all entries', () async {
      final c = Container(contextSalt: salt);
      final sealed = await c.seal(entries, key(1));
      final opened = await c.open(sealed, key(1));
      expect(opened['db_key']!.value, bytesOf('the spice must flow'));
      expect(opened['db_key']!.label, 'DB key');
      expect(opened['device']!.value, [9, 8, 7, 6]);
    });

    test('nonce is fresh per seal (no deterministic reuse)', () async {
      final c = Container(contextSalt: salt);
      final a = await c.seal(entries, key(1));
      final b = await c.seal(entries, key(1));
      expect(a, isNot(b),
          reason: 'same input must not produce identical bytes');
    });

    test('wrong store key -> WrongStoreKey (commitment, not a tag failure)',
        () async {
      final c = Container(contextSalt: salt);
      final sealed = await c.seal(entries, key(1));
      expect(() => c.open(sealed, key(2)), throwsA(isA<WrongStoreKey>()));
    });

    test('different profile salt -> WrongStoreKey (commit binds identity)',
        () async {
      final sealed = await Container(contextSalt: bytesOf('profile-A'))
          .seal(entries, key(1));
      expect(
        () => Container(contextSalt: bytesOf('profile-B')).open(sealed, key(1)),
        throwsA(isA<WrongStoreKey>()),
      );
    });

    test('tampered commit field -> WrongStoreKey', () async {
      final c = Container(contextSalt: salt);
      final sealed = await c.seal(entries, key(1));
      final tampered = Uint8List.fromList(sealed)..[commitOffset] ^= 0x01;
      expect(() => c.open(tampered, key(1)), throwsA(isA<WrongStoreKey>()));
    });

    test('single-bit ciphertext/tag flip -> AuthenticationFailed', () async {
      final c = Container(contextSalt: salt);
      final sealed = await c.seal(entries, key(1));
      for (final pos in [ciphertextOffset, sealed.length - 1]) {
        final tampered = Uint8List.fromList(sealed)..[pos] ^= 0x01;
        expect(() => c.open(tampered, key(1)),
            throwsA(isA<AuthenticationFailed>()),
            reason: 'flip at $pos');
      }
    });

    test('bad magic / version / cipher -> ContainerCorrupt', () async {
      final c = Container(contextSalt: salt);
      final sealed = await c.seal(entries, key(1));
      expect(() => c.open(Uint8List.fromList(sealed)..[0] ^= 0xFF, key(1)),
          throwsA(isA<ContainerCorrupt>()));
      expect(() => c.open(Uint8List.fromList(sealed)..[4] = 0x99, key(1)),
          throwsA(isA<ContainerCorrupt>()));
      expect(() => c.open(Uint8List.fromList(sealed)..[5] = 0x99, key(1)),
          throwsA(isA<ContainerCorrupt>()));
    });

    test('too-short input -> ContainerCorrupt', () async {
      final c = Container(contextSalt: salt);
      expect(
          () => c.open(Uint8List(3), key(1)), throwsA(isA<ContainerCorrupt>()));
      // One byte short of the minimum envelope (header 38 + nonce 24 + tag 16).
      expect(() => c.open(Uint8List(77), key(1)),
          throwsA(isA<ContainerCorrupt>()));
    });

    test('fuzz: random bytes always throw a typed SecretStoreException',
        () async {
      final c = Container(contextSalt: salt);
      final r = Random(99);
      for (var i = 0; i < 800; i++) {
        final len = r.nextInt(120);
        final buf =
            Uint8List.fromList(List.generate(len, (_) => r.nextInt(256)));
        try {
          await c.open(buf, key(1));
          fail(
              'random bytes decrypted successfully (impossible without the key)');
        } on SecretStoreException {
          // expected: ContainerCorrupt, WrongStoreKey, or AuthenticationFailed
        } catch (e) {
          fail('random bytes produced ${e.runtimeType}, not a typed error: $e');
        }
      }
    });
  });
}

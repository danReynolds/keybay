@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:test/test.dart';

void main() {
  group('multi-method package wire format', () {
    test('one passphrase has the frozen big-endian encoding', () {
      final package = V2MethodsPackage(
        storeId: List<int>.filled(16, 0x11),
        epoch: 7,
        methods: <V2AuthMethodEnvelope>[
          V2AuthMethodEnvelope(
            methodId: List<int>.filled(16, 0x22),
            kind: V2AuthMethodKind.passphrase,
            label: 'Main',
            salt: List<int>.filled(16, 0x33),
            profileId: 1,
            publicKey: List<int>.filled(32, 0x44),
            keyEnvelope: List<int>.filled(80, 0x55),
          ),
        ],
      );
      final expected = <String>[
        '11' * 16,
        '0000000000000007',
        '02',
        '00000001',
        '22' * 16,
        '01',
        '00000004',
        '4d61696e',
        '33' * 16,
        '01',
        '44' * 32,
        '55' * 80,
        '00000000',
      ].join();

      final encoded = encodeKeyPackage(package);
      expect(encoded, hasLength(187));
      expect(_hex(encoded), expected);
      final decoded = decodeKeyPackage(encoded) as V2MethodsPackage;
      expect(decoded.epoch, 7);
      expect(decoded.methods.single.label, 'Main');
      expect(decoded.methods.single.passkeyRecord, isEmpty);
      expect(encodeKeyPackage(decoded), encoded);
      package.clear();
      decoded.clear();
    });

    test('construction sorts all routes and preserves opaque record bytes', () {
      final record = utf8.encode('{ "version": 3, "unchanged": "é" }');
      final package = _package(<V2AuthMethodEnvelope>[
        _method(3, kind: V2AuthMethodKind.hardwarePasskey, record: record),
        _method(1, kind: V2AuthMethodKind.passphrase),
        _method(2, kind: V2AuthMethodKind.systemPasskey),
      ]);
      final encoded = encodeKeyPackage(package);
      final decoded = decodeKeyPackage(encoded) as V2MethodsPackage;
      expect(decoded.methods.map((method) => method.methodId.first), [1, 2, 3]);
      expect(decoded.methods.map((method) => method.kind), [
        V2AuthMethodKind.passphrase,
        V2AuthMethodKind.systemPasskey,
        V2AuthMethodKind.hardwarePasskey,
      ]);
      expect(decoded.methods.last.passkeyRecord, record);
      expect(encodeKeyPackage(decoded), encoded);
      package.clear();
      decoded.clear();
    });

    test('maximum directory fits the exact plaintext bound', () {
      final record = utf8.encode('"${'a' * (v2MaxPasskeyRecordBytes - 2)}"');
      final package = _package(<V2AuthMethodEnvelope>[
        for (var index = 0; index < v2MaxMethods; index++)
          _method(index, label: 'x' * v2MaxMethodLabelBytes, record: record),
      ]);
      final encoded = encodeKeyPackage(package);
      expect(v2MethodsPackageMaxBytes, 101613);
      expect(encoded, hasLength(v2MethodsPackageMaxBytes));
      expect(encoded.length, lessThan(V2StoreLimits.sealedPackageBytes));
      final decoded = decodeKeyPackage(encoded) as V2MethodsPackage;
      expect(decoded.methods, hasLength(8));
      expect(encodeKeyPackage(decoded), encoded);
      package.clear();
      decoded.clear();
    });

    test('decoder refuses reordered or duplicate method IDs', () {
      final encoded = encodeKeyPackage(
        _package(<V2AuthMethodEnvelope>[_method(1), _method(2)]),
      );
      final one = encodeKeyPackage(
        _package(<V2AuthMethodEnvelope>[_method(1)]),
      );
      final entryLength = one.length - 29;
      final reordered = Uint8List.fromList(<int>[
        ...encoded.sublist(0, 29),
        ...encoded.sublist(29 + entryLength),
        ...encoded.sublist(29, 29 + entryLength),
      ]);
      expect(() => decodeKeyPackage(reordered), throwsA(_invalid));
      final duplicated = Uint8List.fromList(encoded);
      duplicated.setRange(29 + entryLength, 45 + entryLength, encoded, 29);
      expect(() => decodeKeyPackage(duplicated), throwsA(_invalid));
    });

    test('decoder refuses every truncated prefix and a suffix', () {
      final encoded = encodeKeyPackage(
        _package(<V2AuthMethodEnvelope>[_method(1)]),
      );
      for (var length = 0; length < encoded.length; length++) {
        expect(
          () => decodeKeyPackage(Uint8List.sublistView(encoded, 0, length)),
          throwsA(_invalid),
          reason: 'prefix length $length',
        );
      }
      expect(
        () => decodeKeyPackage(Uint8List.fromList(<int>[...encoded, 0])),
        throwsA(_invalid),
      );
    });

    test('decoder bounds count, label, and record before variable reads', () {
      final encoded = encodeKeyPackage(
        _package(<V2AuthMethodEnvelope>[_method(1, label: 'abc')]),
      );
      for (final (offset, value) in <(int, int)>[
        (25, 0),
        (25, 9),
        (25, 0xffffffff),
        (46, v2MaxMethodLabelBytes + 1),
        (46, 0xffffffff),
        (182, v2MaxPasskeyRecordBytes + 1),
        (182, 0xffffffff),
      ]) {
        final changed = Uint8List.fromList(encoded);
        ByteData.sublistView(changed).setUint32(offset, value);
        expect(
          () => decodeKeyPackage(changed),
          throwsA(_limit),
          reason: 'offset $offset, value $value',
        );
      }
      expect(
        () => decodeKeyPackage(
          Uint8List.fromList(<int>[
            ...encoded.sublist(0, 25),
            ...List<int>.filled(v2MethodsPackageMaxBytes, 0),
          ]),
        ),
        throwsA(_limit),
      );
    });

    test(
      'decoder rejects unknown kind, wrong profile, and malformed UTF-8',
      () {
        final encoded = encodeKeyPackage(
          _package(<V2AuthMethodEnvelope>[_method(1, label: 'abc')]),
        );
        for (final (offset, value) in <(int, int)>[
          (45, 0),
          (45, 4),
          (69, 1),
          (50, 0xff),
          (186, 0xff),
        ]) {
          final changed = Uint8List.fromList(encoded)..[offset] = value;
          expect(() => decodeKeyPackage(changed), throwsA(_invalid));
        }
        final badEpoch = Uint8List.fromList(encoded);
        ByteData.sublistView(badEpoch).setUint64(16, 0);
        expect(() => decodeKeyPackage(badEpoch), throwsA(_invalid));
      },
    );

    test(
      'decoder rejects a second passphrase and invalid passphrase profile',
      () {
        final first = encodeKeyPackage(
          _package(<V2AuthMethodEnvelope>[
            _method(1, kind: V2AuthMethodKind.passphrase),
          ]),
        );
        final second = encodeKeyPackage(
          _package(<V2AuthMethodEnvelope>[
            _method(2, kind: V2AuthMethodKind.passphrase),
          ]),
        );
        final two = Uint8List.fromList(<int>[...first, ...second.sublist(29)]);
        ByteData.sublistView(two).setUint32(25, 2);
        expect(() => decodeKeyPackage(two), throwsA(_invalid));
        // The default fixture label is empty, putting profileId at byte 66.
        final invalidProfile = Uint8List.fromList(first)..[66] = 0;
        expect(
          () => decodeKeyPackage(invalidProfile),
          throwsA(_failure(V2FormatFailureCode.unsupportedKdfProfile)),
        );
      },
    );
  });

  group('multi-method construction and ownership', () {
    test('constructor enforces count, uniqueness, and one passphrase', () {
      expect(() => _package(<V2AuthMethodEnvelope>[]), throwsA(_limit));
      expect(
        () => _package(<V2AuthMethodEnvelope>[
          for (var index = 0; index < 9; index++) _method(index),
        ]),
        throwsA(_limit),
      );
      final method = _method(1);
      expect(() => _package([method, method]), throwsA(_invalid));
      expect(method.methodId.first, 1);
      expect(
        () => _package([
          _method(1, kind: V2AuthMethodKind.passphrase),
          _method(2, kind: V2AuthMethodKind.passphrase),
        ]),
        throwsA(_invalid),
      );
    });

    test('constructor enforces route-specific profile and record presence', () {
      expect(() => _method(1, profileId: 1), throwsA(_invalid));
      expect(() => _method(1, record: <int>[]), throwsA(_invalid));
      expect(
        () => _method(
          1,
          kind: V2AuthMethodKind.passphrase,
          record: utf8.encode('{}'),
        ),
        throwsA(_invalid),
      );
      expect(
        () => _method(1, kind: V2AuthMethodKind.passphrase, profileId: 2),
        throwsA(_failure(V2FormatFailureCode.unsupportedKdfProfile)),
      );
    });

    test(
      'constructor counts label bytes and rejects lossy or malformed text',
      () {
        expect(_method(1, label: 'é' * 128).label, 'é' * 128);
        expect(() => _method(1, label: 'é' * 129), throwsA(_limit));
        expect(() => _method(1, label: '\uD800'), throwsA(_invalid));
        expect(() => _method(1, record: <int>[0xc0, 0x80]), throwsA(_invalid));
        expect(() => _method(1, record: <int>[256]), throwsA(_invalid));
        expect(
          () => _method(
            1,
            record: List<int>.filled(v2MaxPasskeyRecordBytes + 1, 0x61),
          ),
          throwsA(_limit),
        );
      },
    );

    test('constructor rejects wrong fixed widths and non-byte integers', () {
      for (final invalid in <List<int>>[<int>[], List<int>.filled(16, -1)]) {
        expect(() => _method(1, methodId: invalid), throwsA(_invalid));
        expect(() => _method(1, salt: invalid), throwsA(_invalid));
      }
      for (final invalid in <List<int>>[<int>[], List<int>.filled(32, 256)]) {
        expect(() => _method(1, publicKey: invalid), throwsA(_invalid));
      }
      for (final invalid in <List<int>>[<int>[], List<int>.filled(80, -1)]) {
        expect(() => _method(1, keyEnvelope: invalid), throwsA(_invalid));
      }
    });

    test('constructor inputs and returned byte buffers never alias', () {
      final id = Uint8List.fromList(List<int>.filled(16, 1));
      final salt = Uint8List.fromList(List<int>.filled(16, 2));
      final publicKey = Uint8List.fromList(List<int>.filled(32, 3));
      final envelope = Uint8List.fromList(List<int>.filled(80, 4));
      final record = Uint8List.fromList(utf8.encode('{}'));
      final method = _method(
        1,
        methodId: id,
        salt: salt,
        publicKey: publicKey,
        keyEnvelope: envelope,
        record: record,
      );
      final inputs = <Uint8List>[id, salt, publicKey, envelope, record];
      final expected = inputs.map(Uint8List.fromList).toList();
      for (final input in inputs) {
        input.fillRange(0, input.length, 0);
      }
      List<Uint8List> read() => <Uint8List>[
        method.methodId,
        method.salt,
        method.publicKey,
        method.keyEnvelope,
        method.passkeyRecord,
      ];
      expect(read(), expected);
      for (final output in read()) {
        output.fillRange(0, output.length, 0);
      }
      expect(read(), expected);
    });

    test('updates return independent envelopes and retain method identity', () {
      final original = _method(1);
      final replacement = List<int>.filled(80, 0x99);
      final updated = original
          .withKeyEnvelope(replacement)
          .withPasskeyRecord(utf8.encode('{"updated":true}'));
      replacement.fillRange(0, replacement.length, 0);
      expect(updated.methodId, original.methodId);
      expect(updated.salt, original.salt);
      expect(updated.publicKey, original.publicKey);
      expect(updated.keyEnvelope, everyElement(0x99));
      expect(original.keyEnvelope, everyElement(4));
      expect(utf8.decode(original.passkeyRecord), '{}');
      expect(utf8.decode(updated.passkeyRecord), '{"updated":true}');
      expect(() => original.withKeyEnvelope(<int>[]), throwsA(_invalid));
      expect(() => original.withPasskeyRecord(<int>[]), throwsA(_invalid));
    });

    test(
      'packages clone envelopes, reject list mutation, and clear locally',
      () {
        final source = _method(1);
        final sources = <V2AuthMethodEnvelope>[source];
        final first = _package(sources);
        final second = _package(first.methods);
        sources.clear();
        final retained = first.methods;
        expect(() => retained.add(source), throwsUnsupportedError);
        expect(identical(retained.single, source), isFalse);
        first.clear();
        first.clear();
        expect(() => first.methods, throwsStateError);
        expect(() => first.storeId, throwsStateError);
        expect(() => encodeKeyPackage(first), throwsStateError);
        expect(() => retained.single.methodId, throwsStateError);
        expect(() => retained.single.keyEnvelope, throwsStateError);
        expect(
          () => retained.single.withPasskeyRecord(utf8.encode('{}')),
          throwsStateError,
        );
        expect(source.methodId.first, 1);
        expect(second.methods.single.methodId.first, 1);
        second.clear();
      },
    );

    test('decoding never retains mutable input buffers', () {
      final encoded = encodeKeyPackage(
        _package(<V2AuthMethodEnvelope>[_method(1)]),
      );
      final expected = Uint8List.fromList(encoded);
      final decoded = decodeKeyPackage(encoded) as V2MethodsPackage;
      encoded.fillRange(0, encoded.length, 0);
      expect(encodeKeyPackage(decoded), expected);
      decoded.clear();
    });
  });
}

V2MethodsPackage _package(List<V2AuthMethodEnvelope> methods) =>
    V2MethodsPackage(
      storeId: List<int>.filled(16, 0x11),
      epoch: 1,
      methods: methods,
    );

V2AuthMethodEnvelope _method(
  int id, {
  V2AuthMethodKind kind = V2AuthMethodKind.systemPasskey,
  String label = '',
  List<int>? methodId,
  List<int>? salt,
  int? profileId,
  List<int>? publicKey,
  List<int>? keyEnvelope,
  List<int>? record,
}) => V2AuthMethodEnvelope(
  methodId: methodId ?? List<int>.filled(16, id),
  kind: kind,
  label: label,
  salt: salt ?? List<int>.filled(16, 2),
  profileId: profileId ?? (kind == V2AuthMethodKind.passphrase ? 1 : 0),
  publicKey: publicKey ?? List<int>.filled(32, 3),
  keyEnvelope: keyEnvelope ?? List<int>.filled(80, 4),
  passkeyRecord:
      record ??
      (kind == V2AuthMethodKind.passphrase ? <int>[] : utf8.encode('{}')),
);

Matcher get _invalid => _failure(V2FormatFailureCode.invalidEncoding);
Matcher get _limit => _failure(V2FormatFailureCode.limitExceeded);

Matcher _failure(V2FormatFailureCode code) =>
    isA<V2FormatFailure>().having((failure) => failure.code, 'code', code);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

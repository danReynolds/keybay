@Tags(['unit'])
library;

// Structure-aware fuzz for the container's two parsing layers. The
// deterministic corpus in container_test.dart already exhausts single-byte
// flips and prefix truncations, and the random-buffer fuzz there covers
// unstructured noise; this file covers what neither can: *coherent lies* —
// length fields that disagree with their content, counts that overrun the
// buffer, truncation at exact field boundaries, and components spliced
// between two individually valid envelopes.
//
// Oracle: every mutation either decodes to a structurally valid result or
// throws a typed SecretStoreException. Nothing may escape as RangeError,
// FormatException, or a successful open under the wrong key/context.
//
// Reproducibility: cases derive from a fixed default seed. The weekly canary
// raises KEYBAY_FUZZ_ITERATIONS and randomizes KEYBAY_FUZZ_SEED; a failure
// prints both so the exact case can be replayed and then pinned into the
// deterministic corpus in container_test.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:keybay/src/container/container.dart';
import 'package:keybay/src/container/tlv.dart';
import 'package:keybay/src/errors.dart';
import 'package:test/test.dart';

final int _iterations =
    int.tryParse(Platform.environment['KEYBAY_FUZZ_ITERATIONS'] ?? '') ?? 200;
final int _seed =
    int.tryParse(Platform.environment['KEYBAY_FUZZ_SEED'] ?? '') ?? 20260817;

void main() {
  Uint8List keyOf(int seed) {
    final r = Random(seed);
    return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
  }

  Map<String, ContainerEntry> randomEntries(Random r) {
    final count = r.nextInt(6);
    final entries = <String, ContainerEntry>{};
    for (var i = 0; i < count; i++) {
      final key = 'k${r.nextInt(1 << 16)}-$i';
      final label = r.nextBool() ? 'label-${r.nextInt(1 << 8)}' : null;
      final value =
          Uint8List.fromList(List.generate(r.nextInt(64), (_) => r.nextInt(256)));
      entries[key] = ContainerEntry(value, label: label);
    }
    return entries;
  }

  /// Applies one structural mutation to a valid TLV payload. Every branch
  /// produces a payload whose *fields lie* about its shape.
  Uint8List mutateTlv(Uint8List valid, Random r) {
    final out = Uint8List.fromList(valid);
    final data = ByteData.sublistView(out);
    switch (r.nextInt(6)) {
      case 0: // entry count claims more entries than exist
        data.setUint32(0, data.getUint32(0) + 1 + r.nextInt(3));
        return out;
      case 1: // entry count claims a huge allocation
        data.setUint32(0, 0x40000000 + r.nextInt(1 << 20));
        return out;
      case 2: // first length field overruns the remaining buffer
        if (out.length >= 6) data.setUint16(4, 0xFFFF);
        return out;
      case 3: // truncate at a random interior field boundary
        final cut = out.length <= 4 ? 4 : 4 + r.nextInt(out.length - 4);
        return Uint8List.sublistView(out, 0, cut);
      case 4: // trailing garbage after a canonical payload
        return Uint8List.fromList([...out, ...List.filled(1 + r.nextInt(7), 0xAA)]);
      default: // invalid UTF-8 where a key's bytes begin
        if (out.length > 8) out[8] = 0xFF;
        return out;
    }
  }

  test('structural TLV lies decode typed or not at all (seed $_seed)', () {
    final r = Random(_seed);
    for (var i = 0; i < _iterations; i++) {
      final valid = encodeTlv(randomEntries(r));
      final mutated = mutateTlv(valid, r);
      try {
        decodeTlv(mutated);
        // A mutation can accidentally reconstruct a valid payload; validity,
        // not rejection, is the oracle.
      } on ContainerCorrupt {
        // The required typed refusal.
      } catch (error) {
        fail('case $i (seed $_seed): TLV mutation escaped as '
            '${error.runtimeType}: $error');
      }
    }
  });

  test('cross-envelope splices fail typed, never open (seed $_seed)', () async {
    final r = Random(_seed ^ 0x5EED);
    final saltA = utf8.encode('fuzz-context-A');
    for (var i = 0; i < _iterations ~/ 10 + 5; i++) {
      final containerA = Container(contextSalt: saltA);
      final containerB = Container(
          contextSalt: r.nextBool() ? saltA : utf8.encode('fuzz-context-B'));
      final keyA = keyOf(r.nextInt(1 << 30));
      final keyB = keyOf(r.nextInt(1 << 30));
      // A commit-field splice between same-key, same-salt envelopes is a
      // no-op; force distinct keys so every splice genuinely lies.
      var identicalKeys = keyA.length == keyB.length;
      for (var b = 0; identicalKeys && b < keyA.length; b++) {
        identicalKeys = keyA[b] == keyB[b];
      }
      if (identicalKeys) keyB[0] ^= 1;
      final sealedA = await containerA.seal(randomEntries(r), keyA);
      final sealedB = await containerB.seal(randomEntries(r), keyB);

      // Splice structurally meaningful regions of B into A: the key-commit
      // field, the nonce, and the trailing tag. Each splice preserves shape
      // while lying about provenance.
      const commitOffset = 6;
      const nonceOffset = commitOffset + 32;
      const bodyOffset = nonceOffset + 24;
      final spliced = Uint8List.fromList(sealedA);
      switch (r.nextInt(3)) {
        case 0:
          spliced.setRange(
              commitOffset, nonceOffset, sealedB, commitOffset);
        case 1:
          spliced.setRange(
              nonceOffset, bodyOffset, sealedB.sublist(nonceOffset, bodyOffset));
        default:
          spliced.setRange(spliced.length - 16, spliced.length,
              sealedB.sublist(sealedB.length - 16));
      }
      try {
        await containerA.open(spliced, keyA);
        fail('case $i (seed $_seed): spliced envelope opened under key A');
      } on SecretStoreException {
        // WrongStoreKey or AuthenticationFailed — both are correct; which one
        // depends on the spliced region, and both fail closed.
      } catch (error) {
        fail('case $i (seed $_seed): splice escaped as '
            '${error.runtimeType}: $error');
      }
    }
  });
}

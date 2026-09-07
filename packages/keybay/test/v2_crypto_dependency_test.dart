@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:test/test.dart';

// Keybay's AEAD cleanup depends on this pinned dependency using the supplied
// workspace. This checks that assumption at empty, key and maximum-record sizes;
// format vectors and SDK rejection tests exercise the surrounding construction.
void main() {
  test('Argon2 workspace is stable and writable until release', () async {
    final state = const DartArgon2id(
      parallelism: 4,
      memory: 64 * 1024,
      iterations: 3,
      hashLength: 32,
    ).newState();
    // ignore: invalid_use_of_protected_member
    final buffer = state.getByteBuffer();
    final memory = buffer.asUint64List();
    List<int>? result;
    try {
      result = await state.deriveKeyBytes(
        password: [1, 2, 3],
        nonce: Uint8List(16),
      );
      // ignore: invalid_use_of_protected_member
      expect(state.getByteBuffer(), same(buffer));
      expect(memory.lengthInBytes, 64 * 1024 * 1024);
      expect(memory.any((word) => word != 0), isTrue);
      memory.fillRange(0, memory.length, 0);
      expect(memory, everyElement(0));
    } finally {
      result?.fillRange(0, result.length, 0);
      memory.fillRange(0, memory.length, 0);
      state.tryReleaseMemory();
    }
    // No access to memory after release: the dependency may have freed it.
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final length in [0, 32, V2StoreLimits.recordValueBytes]) {
    for (final validTag in [true, false]) {
      test('AEAD workspace ownership: $length bytes, valid=$validTag', () async {
        final aead = DartXchacha20.poly1305Aead();
        final keyBytes = Uint8List(32)..fillRange(0, 32, 7);
        final key = SecretKeyData(keyBytes, overwriteWhenDestroyed: true);
        final plaintext = Uint8List(length)..fillRange(0, length, 19);
        Uint8List? workspace;
        try {
          final box = await aead.encrypt(
            plaintext,
            secretKey: key,
            nonce: Uint8List(24),
            aad: const [1, 2, 3],
          );
          workspace = Uint8List.fromList(box.cipherText);
          final tag = Uint8List.fromList(box.mac.bytes);
          if (!validTag) tag[0] ^= 1;
          final opening = aead.decrypt(
            SecretBox(workspace, nonce: box.nonce, mac: Mac(tag)),
            secretKey: key,
            aad: const [1, 2, 3],
            possibleBuffer: workspace,
            chunkSize: -1,
          );
          if (validTag) {
            final result = await opening;
            // Empty output contains no secret and may use a shared empty list.
            if (length != 0) expect(identical(result, workspace), isTrue);
            expect(result, plaintext);
          } else {
            await expectLater(
              opening,
              throwsA(isA<SecretBoxAuthenticationError>()),
            );
            // The primitive decrypts before checking the tag. Keybay must clear
            // this workspace on failure as well as on a successful copy-out.
            expect(workspace, plaintext);
          }
        } finally {
          workspace?.fillRange(0, workspace.length, 0);
          plaintext.fillRange(0, plaintext.length, 0);
          key.destroy();
        }
        expect(keyBytes, everyElement(0));
      });
    }
  }
}

@Tags(['unit'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/android_keystore_key_source.dart';
import 'package:keybay/src/app_paths.dart';
import 'package:keybay/src/errors.dart';
import 'package:keybay/src/ffi/posix_file.dart';
import 'package:test/test.dart';

// The JNI/Keystore choreography itself is covered by the emulator tier
// (example_flutter/); these are the pure parts — the wrapped-blob codec and
// the Context-free path derivation.
void main() {
  Uint8List bytes(List<int> v) => Uint8List.fromList(v);

  group('wrapped-key blob codec', () {
    final iv = bytes(List.generate(12, (i) => i + 1));
    final ct = bytes(List.generate(48, (i) => 255 - i)); // 32 key + 16 tag

    test('round-trips, preserving iv/ct', () {
      final encoded =
          encodeWrappedKeyBlob(WrappedKeyBlob(iv: iv, ciphertext: ct));
      final decoded = decodeWrappedKeyBlob(encoded);
      expect(decoded.iv, iv);
      expect(decoded.ciphertext, ct);
    });

    test('the reserved byte is ignored, not rejected', () {
      // A non-zero reserved byte (formerly the StrongBox flag) must still
      // decode — the field carries no meaning and older blobs may have set it.
      final full = encodeWrappedKeyBlob(WrappedKeyBlob(iv: iv, ciphertext: ct));
      final withReserved = Uint8List.fromList(full)..[4] = 0x01;
      final decoded = decodeWrappedKeyBlob(withReserved);
      expect(decoded.iv, iv);
      expect(decoded.ciphertext, ct);
    });

    test('every truncation throws KeyInvalidated (never crashes)', () {
      final full = encodeWrappedKeyBlob(WrappedKeyBlob(iv: iv, ciphertext: ct));
      for (var cut = 0; cut < full.length; cut++) {
        expect(() => decodeWrappedKeyBlob(Uint8List.sublistView(full, 0, cut)),
            throwsA(isA<KeyInvalidated>()),
            reason: 'prefix of length $cut');
      }
    });

    test('trailing garbage and bad magic throw KeyInvalidated', () {
      final full = encodeWrappedKeyBlob(WrappedKeyBlob(iv: iv, ciphertext: ct));
      expect(() => decodeWrappedKeyBlob(Uint8List.fromList([...full, 0])),
          throwsA(isA<KeyInvalidated>()),
          reason: 'trailing byte');
      expect(() => decodeWrappedKeyBlob(Uint8List.fromList(full)..[0] ^= 0xFF),
          throwsA(isA<KeyInvalidated>()),
          reason: 'bad magic');
    });

    test('encode rejects out-of-range lengths', () {
      expect(
          () => encodeWrappedKeyBlob(
              WrappedKeyBlob(iv: Uint8List(0), ciphertext: ct)),
          throwsArgumentError);
      expect(
          () => encodeWrappedKeyBlob(
              WrappedKeyBlob(iv: iv, ciphertext: Uint8List(0))),
          throwsArgumentError);
      expect(
          () => encodeWrappedKeyBlob(
              WrappedKeyBlob(iv: Uint8List(64), ciphertext: ct)),
          throwsArgumentError);
    });
  });

  group('Android path derivation (Context-free, strict)', () {
    test('derives dataDir from the framework tmpdir (cache) layout', () {
      expect(androidDataDirFromTmpdir('/data/user/0/com.example.app/cache'),
          '/data/user/0/com.example.app');
      expect(androidDataDirFromTmpdir('/data/user/0/com.example.app/cache/'),
          '/data/user/0/com.example.app');
      expect(
          androidContainerPathFor('com.example.app',
              tmpdir: '/data/user/0/com.example.app/cache'),
          '/data/user/0/com.example.app/no_backup/com.example.app/secrets.enc');
      expect(
          androidLegacyContainerPathFor('com.example.app',
              tmpdir: '/data/user/0/com.example.app/cache'),
          '/data/user/0/com.example.app/files/com.example.app/secrets.enc');
      expect(androidNoBackupDirFromTmpdir('/data/user/0/com.example.app/cache'),
          '/data/user/0/com.example.app/no_backup');
    });

    test('anything surprising fails closed instead of guessing', () {
      for (final bad in [
        '', // unset
        'cache', // relative
        '/cache', // empty dataDir
        '/tmp', // not a cache dir
        '/data/user/0/app/Cache', // wrong case
        '/data/user/0/app/cache/extra', // not the leaf
      ]) {
        expect(() => androidDataDirFromTmpdir(bad),
            throwsA(isA<KeystoreUnreachable>()),
            reason: '"$bad"');
      }
    });

    test('atomically migrates the complete legacy directory', () {
      final root = Directory.systemTemp.createTempSync('keybay-android-path-');
      const fs = SecureFileSystem();
      try {
        final tmpdir = '${root.path}/data/cache';
        Directory(tmpdir).createSync(recursive: true);
        final legacyContainer =
            androidLegacyContainerPathFor('com.example.app', tmpdir: tmpdir);
        final legacyDir = File(legacyContainer).parent.path;
        fs.ensurePrivateDirSync(legacyDir);
        fs.writeAtomicSync(legacyContainer, bytes([1, 2, 3]));
        fs.writeAtomicSync('$legacyDir/store-key.wrapped', bytes([4, 5, 6]));
        fs.writeAtomicSync('$legacyContainer.lock', Uint8List(0));

        migrateLegacyAndroidStore('com.example.app', tmpdir: tmpdir);

        final currentContainer =
            androidContainerPathFor('com.example.app', tmpdir: tmpdir);
        final currentDir = File(currentContainer).parent.path;
        expect(Directory(legacyDir).existsSync(), isFalse);
        expect(File(currentContainer).readAsBytesSync(), [1, 2, 3]);
        expect(
            File('$currentDir/store-key.wrapped').readAsBytesSync(), [4, 5, 6]);
        expect(File('$currentContainer.lock').existsSync(), isTrue);
        expect(fs.verifyPrivateDirSync(currentDir), isTrue);

        // Resolution is idempotent after the move.
        migrateLegacyAndroidStore('com.example.app', tmpdir: tmpdir);
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('two populated locations fail closed without changing either', () {
      final root = Directory.systemTemp.createTempSync('keybay-android-path-');
      const fs = SecureFileSystem();
      try {
        final tmpdir = '${root.path}/data/cache';
        Directory(tmpdir).createSync(recursive: true);
        final legacyContainer =
            androidLegacyContainerPathFor('com.example.app', tmpdir: tmpdir);
        final currentContainer =
            androidContainerPathFor('com.example.app', tmpdir: tmpdir);
        fs.ensurePrivateDirSync(File(legacyContainer).parent.path);
        fs.ensurePrivateDirSync(File(currentContainer).parent.path);
        fs.writeAtomicSync(legacyContainer, bytes([1]));
        fs.writeAtomicSync(currentContainer, bytes([2]));

        expect(
          () => migrateLegacyAndroidStore('com.example.app', tmpdir: tmpdir),
          throwsA(
            isA<StoreMigrationConflict>()
                .having((e) => e.legacyPath, 'legacyPath',
                    File(legacyContainer).parent.path)
                .having((e) => e.currentPath, 'currentPath',
                    File(currentContainer).parent.path),
          ),
        );
        expect(File(legacyContainer).readAsBytesSync(), [1]);
        expect(File(currentContainer).readAsBytesSync(), [2]);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}

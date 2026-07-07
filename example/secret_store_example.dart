// A tiny CLI demonstrating the front API.
//
//   dart run example/secret_store_example.dart
//
// You express intent; the library picks the strongest backing per platform.
import 'dart:convert';
import 'dart:io';

import 'package:secret_store/secret_store.dart';

Future<void> main() async {
  // --- The default: the platform's OS keystore, chosen for you --------------
  final store = SecretStorage(service: 'com.example.secret_store_demo');

  await store.writeString('api_token', 's3cr3t-value', label: 'Demo API token');
  stdout.writeln('read back: ${await store.readString('api_token')}');
  stdout.writeln('present?   ${await store.containsKey('api_token')}');
  await store.delete('api_token');
  stdout.writeln('after delete: ${await store.readString('api_token')}');

  // --- Encrypted file: one wrapped key + a container ------------------------
  // For headless deployments, one backup unit, or many secrets. In production
  // the key comes from `KeystoreKeySource` (OS keystore) or a TPM; this demo
  // uses an in-memory key so it stays self-contained and idempotent (nothing
  // persists past the process, nothing lands in your real keychain).
  final dir = Directory.systemTemp.createTempSync('secret_store_demo_');
  try {
    final fileStore = SecretStorage.encryptedFile(
      path: '${dir.path}/secrets.enc',
      keySource: InMemoryKeySource(),
      contextSalt: utf8.encode('demo-profile-uuid'),
    );
    await fileStore.writeString('db_key', 'the spice must flow');
    stdout.writeln('container read: ${await fileStore.readString('db_key')}');
    stdout.writeln('container file is ciphertext on disk at ${dir.path}');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

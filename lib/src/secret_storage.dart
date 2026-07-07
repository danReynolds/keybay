/// The front API (see doc/design.md): a bytes-first async key-value store.
///
/// Users express *intent*, not mechanism. `SecretStorage(service:)` gives the
/// most secure storage the platform offers, chosen by the library — the caller
/// never picks between "keystore items" and "encrypted file". The only cases
/// that take more than a service name are the ones that are genuinely a
/// decision: opting up to the macOS Data Protection keychain on an entitled
/// app (`api:`), and running headless where the encryption key needs an
/// explicit home ([SecretStorage.encryptedFile]).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'backend.dart';
import 'backends/encrypted_file_backend.dart';
import 'backends/keystore_backend.dart';
import 'errors.dart';
import 'ffi/keychain.dart';
import 'ffi/keystore_api.dart';
import 'ffi/secret_service.dart';
import 'identifiers.dart';
import 'key_source.dart';

/// Returns the platform's OS keystore binding — `MacKeychainApi` on macOS,
/// `SecretToolApi` on Linux. Throws [KeystoreUnreachable] elsewhere (fail-closed
/// — no silent fallback to weaker storage). Used to build a keystore-wrapped
/// container (model B) as well as by [SecretStorage.new].
KeystoreApi platformKeystore() {
  if (Platform.isMacOS) return MacKeychainApi();
  if (Platform.isLinux) return SecretToolApi();
  throw KeystoreUnreachable(
      'no OS keystore backend for ${Platform.operatingSystem}');
}

/// Stores named byte secrets.
final class SecretStorage {
  /// Injects a [SecretBackend] directly. Escape hatch for tests (a fake) and
  /// custom backends; normal callers use [SecretStorage.new] or
  /// [SecretStorage.encryptedFile].
  SecretStorage.withBackend(this.backend);

  /// The secure default: stores each secret in the platform's OS keystore
  /// (macOS Keychain, Linux Secret Service), the strongest storage available
  /// without extra setup. Fail-closed — throws [KeystoreUnreachable] where
  /// there is no usable keystore (e.g. a headless server), rather than falling
  /// back to something weaker; there, reach for [SecretStorage.encryptedFile]
  /// with a deliberate key source.
  ///
  /// [api] is an advanced override of the keystore binding for the platforms
  /// that use OS items. Its one intended use today is opting an **entitled
  /// macOS app** up to the Data Protection keychain + Secure Enclave:
  /// `SecretStorage(service: s, api: MacKeychainApi.dataProtection())`. Leave
  /// it null everywhere else.
  factory SecretStorage({required String service, KeystoreApi? api}) {
    validateIdentifier(service, 'service');
    return SecretStorage.withBackend(
        KeystoreBackend(service: service, api: api ?? platformKeystore()));
  }

  /// Stores all secrets in one authenticated encrypted file at [path], sealed
  /// by a key from [keySource]. Use this when there is no OS keystore (a
  /// headless server — pair with a TPM or, as an explicit insecure fallback,
  /// a file key source), when you want a single backup unit, or for many
  /// secrets. [contextSalt] optionally binds the container to a caller identity
  /// (e.g. a profile UUID) so it can't be opened in another context.
  factory SecretStorage.encryptedFile({
    required String path,
    required KeySource keySource,
    List<int> contextSalt = const [],
  }) {
    return SecretStorage.withBackend(EncryptedFileBackend(
      path: path,
      keySource: keySource,
      contextSalt: contextSalt,
    ));
  }

  /// The underlying backend. Read [SecretBackend.capabilities] to branch on
  /// optional operations, or `await backend.describe()` for a health snapshot
  /// (including which mechanism the library selected).
  final SecretBackend backend;

  /// Reads the raw bytes for [key], or null if absent.
  Future<Uint8List?> read(String key) {
    validateIdentifier(key, 'key');
    return backend.read(key);
  }

  /// Reads [key] as a UTF-8 string, or null if absent.
  Future<String?> readString(String key) async {
    final bytes = await read(key);
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// Whether [key] exists.
  Future<bool> containsKey(String key) {
    validateIdentifier(key, 'key');
    return backend.contains(key);
  }

  /// Stores [value] under [key], replacing any existing value. [label] is
  /// optional non-secret metadata shown in keystore UIs.
  Future<void> write(String key, Uint8List value, {String? label}) {
    validateIdentifier(key, 'key');
    validateLabel(label);
    return backend.write(key, value, label: label);
  }

  /// Stores [value] (encoded UTF-8) under [key].
  Future<void> writeString(String key, String value, {String? label}) =>
      write(key, Uint8List.fromList(utf8.encode(value)), label: label);

  /// Removes [key]. Idempotent.
  Future<void> delete(String key) {
    validateIdentifier(key, 'key');
    return backend.delete(key);
  }

  /// All entries. Throws [UnsupportedCapability] when the backend cannot
  /// enumerate (guard with `backend.capabilities.enumeration`). `async` so the
  /// capability failure surfaces as a rejected future, not a synchronous throw.
  Future<Map<String, Uint8List>> readAll() async {
    if (!backend.capabilities.enumeration) {
      throw const UnsupportedCapability('enumeration');
    }
    return backend.readAll();
  }

  /// Removes every entry. Requires enumeration.
  Future<void> deleteAll() async {
    final all = await readAll();
    for (final key in all.keys) {
      await backend.delete(key);
    }
  }
}

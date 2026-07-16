/// The backend seam (see doc/design.md).
///
/// A [SecretBackend] is bound to a single service at construction; its methods
/// take only a key. Adding a platform is one implementation + one line of
/// default resolution. Capabilities are reported honestly, so a future backend
/// that cannot enumerate stays honest at the seam instead of throwing after
/// the fact.
library;

import 'dart:typed_data';

/// Which of the two storage shapes the resolver chose. These are the whole
/// system: a secret is either a native Data Protection Keychain item, or an
/// entry in one authenticated encrypted file whose key is OS-protected.
///
/// This is the typed discriminator the library branches on (e.g. the macOS
/// scheme-migration guard); it replaces the earlier stringly-typed backend
/// `name`.
enum StorageScheme {
  /// Each secret is its own native item in Apple's Data Protection Keychain.
  /// No separate Keybay store key or file exists on this path.
  nativeItems,

  /// All secrets live in one authenticated encrypted file. Its 32-byte key is
  /// stored by a desktop credential service or wrapped by Android Keystore.
  encryptedFile,
}

/// An observed protection signal for backends that expose one Keybay can
/// inspect. Android reports the wrapping key's provider; desktop file-key
/// sources report login binding. Apple native items leave the level null rather
/// than infer hardware backing from an unrelated capability.
enum SecurityLevel {
  /// Android reported the wrapping key in TEE or StrongBox.
  hardwareBacked,

  /// Android's wrapping-key provider was not reported as TEE or StrongBox.
  softwareBacked,

  /// The key is protected by the OS login (login Keychain, Secret Service,
  /// DPAPI): safe from other local users; against a stolen disk, as strong as
  /// the login password.
  loginBound,
}

/// What a backend can and cannot do. Guard optional operations on these rather
/// than catching an [UnsupportedCapability] after the fact.
final class BackendCapabilities {
  const BackendCapabilities({
    required this.enumeration,
    required this.persistent,
  });

  /// Whether [SecretBackend.readAll] is supported.
  final bool enumeration;

  /// Whether secrets survive process exit (false only for in-memory backends).
  final bool persistent;
}

/// A point-in-time health snapshot for diagnostics UIs.
final class BackendInfo {
  const BackendInfo({
    required this.scheme,
    required this.available,
    required this.locked,
    required this.capabilities,
    this.level,
    this.detail,
  });

  /// Which storage shape the resolver chose (native items vs encrypted file).
  final StorageScheme scheme;

  /// Whether the backend can be reached at all.
  final bool available;

  /// Whether it is locked / needs interaction that can't be satisfied.
  final bool locked;

  final BackendCapabilities capabilities;

  /// The observed platform protection signal, when known. Android reads
  /// `KeyInfo.getSecurityLevel()`, so this is null before its first write when
  /// no wrapping key exists to inspect. Apple native-item paths also leave it
  /// null because their hardware backing is not attested. Custom/test backends
  /// may omit it too. Null-check before use.
  final SecurityLevel? level;

  /// Free-form extra detail (e.g. a path or provider name). Never a secret.
  final String? detail;
}

/// Storage of named byte secrets for one service.
abstract interface class SecretBackend {
  /// Static description of what this backend supports.
  BackendCapabilities get capabilities;

  /// The value for [key], or null if absent.
  Future<Uint8List?> read(String key);

  /// Whether [key] exists. The native-item backend answers this with an
  /// attributes-only keystore query, so it never fetches the value. The
  /// encrypted-file backend must still read
  /// and decrypt the whole container, which is a single sealed blob.
  Future<bool> contains(String key);

  /// Stores [value] under [key], replacing any existing value. [label] is
  /// optional non-secret metadata for keystore UIs.
  Future<void> write(String key, Uint8List value, {String? label});

  /// Removes [key]. Idempotent.
  Future<void> delete(String key);

  /// All entries. Throws [UnsupportedCapability] when
  /// [BackendCapabilities.enumeration] is false.
  Future<Map<String, Uint8List>> readAll();

  /// Health snapshot for diagnostics.
  Future<BackendInfo> describe();
}

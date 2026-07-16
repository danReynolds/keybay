# Changelog

## 0.1.0

First release. A bytes-first, async secret store for Dart — no Flutter, no
platform channels, no native build step — that applies one documented,
OS-backed storage policy for the current runtime and fails closed when that
policy cannot be upheld.

Ships as `keybay`: the package was developed under the working name
`secret_store` and renamed before this first publish (nothing was ever
released under the old name). The container's wire-format constants that
happen to carry the old name — the HKDF info strings `secret_store:v1:*` —
are frozen protocol constants, deliberately not rebranded (doc/design.md §7).

### API

- One production entry point: `SecretStorage(appId:)`. The library resolves the
  scheme per platform; the caller never picks a mechanism, a path, or a key
  home. `SecretStorage.withBackend(...)` is the test hatch.
- Bytes-first (`Uint8List`) with `readString`/`writeString` convenience; an
  optional non-secret `label:` for keystore UIs; `readAll`/`deleteAll` guarded
  by a `capabilities.enumeration` flag; and a `describe()` diagnostics call for
  the resolved scheme, observed protection signal, and reachable/locked state.
- `appId` and `key` are validated identifiers — `appId` is traversal-proof by
  grammar, since it names the data directory and the keystore service. A sealed
  `SecretStoreException` taxonomy carries stable codes and key *names*, never
  values and never raw subprocess output.

### Platforms — genuine paths exercised with native and simulator harnesses

- **macOS** — native Data Protection Keychain items for an entitled app, chosen
  by a once-per-process probe; `errSecMissingEntitlement` (the normal CLI
  result) selects the authenticated encrypted-file scheme with its key in the
  login Keychain; any other Data Protection Keychain failure throws rather than
  downgrade. Keybay does not claim or report hardware backing for these items.
- **iOS** — native Data Protection Keychain items with a fixed, device-bound
  policy (`…AfterFirstUnlockThisDeviceOnly`, `synchronizable=false`); hardware
  backing is not attested.
- **Linux** — the encrypted file with its key in the Secret Service (GNOME
  Keyring / KWallet) via `secret-tool`; secrets travel on stdin, never argv.
- **Android (12 / API 31+)** — the encrypted file with its key wrapped by an
  AES-256-GCM Android Keystore KEK. StrongBox is requested; when unavailable,
  the normal provider is retried and may be TEE-backed or software-backed. The
  hand-rolled `dart:ffi` JNI shim needs no plugin, platform channel, or
  `package:jni`, so Flutter-less programs can still depend on it. A write-time
  wrap/unwrap self-test refuses a broken Keystore without a plaintext store-key
  fallback.
- Windows is unsupported and resolves to typed `KeystoreUnreachable`. Headless
  operation has no dedicated backend or supported availability contract; an
  absent or locked desktop credential service fails typed.
- Security level is **measured, not assumed** (`describe().level`): Android reads
  the KEK's `KeyInfo`; desktop file-key paths report login binding. Apple native
  items leave the value null rather than infer hardware backing.

### Cryptographic container

- XChaCha20-Poly1305 (AEAD) over a binary TLV payload — secret values stay
  `Uint8List` end to end, never interned `String`s, and no general-purpose
  parser runs on decrypted bytes.
- An HKDF-SHA256 **key-commitment** header field, checked in constant time
  before decryption, so a wrong key or context is a typed `WrongStoreKey`,
  distinct from tamper's `AuthenticationFailed`, and multi-key ciphertext games
  fail closed. HKDF domain separation keeps the raw keystore key off the AEAD
  path.
- Crypto runs through concrete `Dart*` implementations constructed directly, not
  the swappable `Cryptography.instance` locator a host app could repoint, and is
  exercised against RFC 8439 / RFC 5869 / draft-arciszewski test vectors plus
  fuzz and edge cases.
- `Random.secure()` only. Native staging buffers that held key or secret bytes
  are zeroed before they are freed (managed-heap copies cannot be reliably
  scrubbed — the Dart heap, and on Android the intermediate Java arrays key
  material transits — and the package does not claim otherwise).

### At rest and on disk

- The encrypted file is 0600-from-birth via a small POSIX FFI shim
  (`O_CREAT|O_EXCL`, `fsync`, atomic rename, parent-directory fsync) — none of
  which `dart:io` can express. Reads refuse a group/other-accessible container,
  key file, or store directory (the OpenSSH stance) and refuse non-regular
  files.
- Writers are serialized on two layers: a per-path, isolate-local FIFO mutex,
  and an exclusive advisory `flock` around every mutating read-modify-write that
  additionally excludes other isolates *and* other processes — so a lost update,
  or two first-writers minting rival store keys, cannot happen (a contended lock
  fails typed as `StoreBusy`, never hangs). Reads stay lock-free, since an atomic
  replace is never torn. No rollback protection — AEAD is not anti-rollback.

### Supply chain

- Exactly one third-party runtime dependency (`cryptography`), exact-pinned, its
  transitive closure entirely dart-lang official — enforced by a
  dependency-closure firewall test. A CI canary fails the build when a newer
  `cryptography` is published, so the pin moves only by a reviewed decision. CI
  actions are pinned by commit SHA and the workflow token is read-only by
  default.

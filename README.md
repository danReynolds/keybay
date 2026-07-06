# secret_store

Platform-keystore secret storage for Dart **without Flutter** — macOS Keychain
and Linux Secret Service, plus an authenticated encrypted-file container, behind
one small async API.

`flutter_secure_storage` is a Flutter plugin, so a CLI or server can't use it.
Python, Go, and Rust each have a `keyring` library; this is Dart's. Pure Dart +
FFI, no platform channels — it runs in CLIs, servers, and Flutter apps alike.

```dart
import 'package:secret_store/secret_store.dart';

final store = SecretStorage(service: 'com.example.myapp');

await store.writeString('api_token', 's3cr3t', label: 'API token');
final token = await store.readString('api_token');   // 's3cr3t'
await store.delete('api_token');
```

`read`/`write` are bytes-first (`Uint8List`); `readString`/`writeString` are the
convenience tier. Values never become `String`s internally (a `String` interns
and can't be overwritten).

## Backends

`SecretStorage(service:)` resolves the platform OS keystore and stores each
secret as its own item — the `flutter_secure_storage` model. Resolution is
**fail-closed**: on a platform without a supported keystore it throws rather than
silently falling back to weaker storage.

| Platform | Backing | Notes |
|---|---|---|
| macOS | Keychain via `SecItem` FFI | classic login keychain; never synchronized to iCloud; secrets move as `CFData`. |
| Linux | Secret Service via `secret-tool` | secret crosses on stdin (never argv); every call has a hard timeout so a locked keyring can't hang an SSH session. |

### Encrypted-file container (many secrets, or headless)

For an app with many secrets, one backup unit, or a **headless** deployment (a
server has no unlocked keyring), wrap a single keystore-held key around an
encrypted container: the key lives in the keystore, the AEAD-encrypted secrets
live in a file.

```dart
final store = SecretStorage.withBackend(
  EncryptedFileBackend(
    path: '$stateDir/secrets.enc',
    keySource: KeystoreKeySource(service: 'myapp/$profileId', api: platformKeystore()),
    contextSalt: utf8.encode(profileId),   // binds the container to this profile
  ),
);
```

`FileKeySource` is available as an explicit fallback (the key on disk beside the
container, `0600`) for environments with no keystore at all — gate it behind a
deliberate opt-in in your app.

## Threat model

**Protects against** plaintext key material on disk (backup / Time-Machine /
dotfile-sync leaks), offline disk theft without full-disk encryption, other local
users, and casual disclosure (scrollback, `ps` argv).

**Does not protect against** same-user malware while the keystore is unlocked;
process-memory disclosure (including swap and core dumps — Dart cannot zero
buffers); rollback to an older genuine container; timing side-channels in
pure-Dart crypto; root. There is **no key escrow** — losing the keystore item
loses the store.

The bar is ssh-agent / aws-vault, not an HSM. Full derivation and the crypto/FFI
engineering practices are in [doc/design.md](doc/design.md).

## Requirements

- Dart SDK ≥ 3.6, macOS or Linux.
- Linux: `secret-tool` (Debian/Ubuntu: `libsecret-tools`) and a Secret Service
  provider (GNOME Keyring or KWallet ≥ 5.97).
- One third-party runtime dependency, exact-pinned: `cryptography`. The full
  runtime closure is `{cryptography, ffi, collection, crypto, meta, typed_data}`
  — everything but `cryptography` is dart-lang official, and a test fails CI if
  the tree changes.

## Cryptography

XChaCha20-Poly1305 (AEAD) container, HKDF-SHA256 key derivation, `Random.secure()`
only — all via `package:cryptography`, exercised against RFC 8439 / RFC 5869 /
draft-arciszewski vectors in this package's own suite so a buggy or compromised
dependency update cannot pass silently.

## Testing

```sh
dart test                                             # hermetic unit tier
SECRET_STORE_INTEGRATION=1 dart test -t integration   # hits the real OS keystore
```

The unit tier (crypto vectors, container/fuzz, POSIX permissions on the real
filesystem, backend logic over fakes, dependency-closure firewall) needs no
keystore. Integration tests exercise the real macOS Keychain / Linux Secret
Service and are opt-in.

## Status

Pre-1.0 and not yet published to pub.dev; the API and on-disk container format
may still change before 1.0. Report vulnerabilities per [SECURITY.md](SECURITY.md);
the design rationale is in [doc/design.md](doc/design.md).

## License

MIT.

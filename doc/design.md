# secret_store — design

The canonical design document for `secret_store`. It reflects the package as it
is, with the reasoning behind the choices that aren't obvious. (It originated as
RFC 0005 in the dune_cli repo — the pathfinding consumer — and moved here when
the package was extracted.)

---

## 1. Motivation

Storing credential material from a Dart program means handing it to the OS
keystore — macOS Keychain, Linux Secret Service — or, failing that, to an
encrypted file. The community answer, `flutter_secure_storage`, is a Flutter
plugin (platform channels): unusable from a CLI or a server. Python, Go, and
Rust each have a `keyring` library; Dart did not.

`secret_store` fills that gap: pure Dart + FFI, no platform channels, so it runs
in CLIs, servers, and Flutter apps alike. It targets macOS and Linux in v1.

### Why build rather than adopt (surveyed 2026-07-05)

| Candidate | Verdict |
|---|---|
| `flutter_secure_storage` + kin | Flutter plugins — platform channels; unusable off Flutter. |
| `dbus_secrets` | The only pure-Dart Secret Service client: 2 likes, ~141 downloads, unmaintained, plaintext bus session. A useful reference, not infrastructure for DB keys. |
| `keyring` (pub) | Days-old Rust-FFI umbrella, no releases/CI, unspecified native-binary distribution. On the watch-list. |
| macOS Keychain from pure Dart | Nothing exists. |

The gap is real; the build is thin glue over vetted infrastructure
(`package:cryptography`, libc, the OS keystores), not a new subsystem.

## 2. Goals / non-goals

**Goals** — `flutter_secure_storage`-class storage without Flutter (macOS +
Linux); usable from CLIs, servers, and Flutter apps; backends as the extension
seam with honest capability reporting; zero native build artifacts (subprocess +
system-framework FFI only, no toolchain); a minimal, fully-enumerated dependency
and API surface.

**Non-goals (v1)** — Windows/Android/iOS backends (§9 sketches the path);
biometric prompts; change listeners; web; our own crypto primitives;
cross-process write coordination (consumers bring their own lock); rollback
protection (§8).

## 3. Architecture

```
SecretStorage            bytes-first async KV; validation; capability guard
     │
SecretBackend  (seam)    KeystoreBackend | EncryptedFileBackend
     │                        │                    │
KeystoreApi (seam)            │              Container (AEAD+TLV)
  MacKeychainApi (SecItem FFI)│              KeySource:
  SecretToolApi (secret-tool) │                KeystoreKeySource (wraps key in keystore)
                              │                FileKeySource (insecure fallback)
                              └── SecureFileSystem (POSIX FFI: 0600, fsync, atomic)
```

Two seams keep it testable and portable: `SecretBackend` (what storage looks
like to the app) and `KeystoreApi` (what the OS keystore looks like to a
backend). Both have fakes; the real bindings are covered by integration tests.
The core is `dart:io`-free except the file backend and the subprocess runner, so
it can run wherever Dart runs.

## 4. Public API

The `flutter_secure_storage` silhouette (async KV, nullable read, familiar) with
its known warts corrected: **bytes-first** (`Uint8List`, not `String` — values
are key material, and `String` interns and can't be overwritten), configuration
at **construction, never per call**, write **metadata** (`label:`) for keystore
UIs, and first-class **diagnostics** (`describe()`).

```dart
final store = SecretStorage(service: 'myapp');   // resolves the platform keystore

await store.write('token', bytes, label: 'API token');
final Uint8List? v = await store.read('token');
await store.writeString('note', 'hello');        // String convenience tier
await store.delete('token');
await store.containsKey('token');

if (store.backend.capabilities.enumeration) {
  await store.readAll(); await store.deleteAll();
}
final info = await store.backend.describe();      // reachable? locked? capabilities
```

**Input contract.** `service` and `key` are validated against
`[A-Za-z0-9._/-]{1,120}`; labels allow printable text with spaces but reject
control characters. One identifier grammar across backends beats per-backend
escaping — and it keeps the Linux argv path safe by construction.

**Error hygiene.** Typed `SecretStoreException`s carry key *names* and stable
codes — **never values**, and never raw subprocess output. Names/labels are
non-secret (they appear in keystore UIs); values never leave the container, the
keystore, or process memory.

**Enumeration is a capability, not a promise.** Every backend here supports it,
but the interface treats it as optional so a future direct-items backend that
can't enumerate stays honest rather than throwing after the fact.

## 5. Backends

```dart
abstract interface class SecretBackend {
  BackendCapabilities get capabilities;
  Future<Uint8List?> read(String key);
  Future<bool> contains(String key);
  Future<void> write(String key, Uint8List value, {String? label});
  Future<void> delete(String key);
  Future<Map<String, Uint8List>> readAll();   // if capabilities.enumeration
  Future<BackendInfo> describe();
}
```

| Backend | Platform | Mechanism |
|---|---|---|
| `KeystoreBackend` (macOS) | macOS | `MacKeychainApi` — direct `SecItem` CoreFoundation FFI. Classic login keychain (`kSecUseDataProtectionKeychain: false`), `kSecAttrSynchronizable: false` (a synchronizable item would escrow the key to iCloud). Secrets move as `CFData` — no text protocol on this path. Enumeration via `SecItemCopyMatching`. |
| `KeystoreBackend` (Linux) | Linux | `SecretToolApi` — `secret-tool` over an injectable, timeout-guarded `ProcessRunner`. Secret crosses on **stdin** (never argv), base64-encoded so binary/newlines survive. |
| `EncryptedFileBackend` | anywhere | An authenticated container (§7) sealed by a `KeySource`. |

**The keystore seam is async.** A keystore is an IO boundary: the macOS binding
resolves immediately (synchronous FFI wrapped in a future), the Linux binding
spawns a subprocess with a timeout. One generic `KeystoreApi` /
`KeystoreBackend` / `KeystoreKeySource` serves both platforms.

**macOS FFI discipline.** CoreFoundation is manually reference-counted — the one
place *we* can write a memory-safety bug. Contained by a tiny scope
(add/copy/update/delete + CF helpers), strict `*Create*`/`CFRelease` pairing (a
tracked ref list freed in `finally`), and a leak-checked integration pass.
`OSStatus` maps to the typed taxonomy (`errSecItemNotFound`,
`errSecInteractionNotAllowed` → locked, `errSecDuplicateItem` → upsert, …).
Writes are add-then-update on duplicate (covers the delete/add race).

**Linux subprocess hygiene.** Every op has a hard timeout (default 15 s):
`secret-tool` has no no-prompt flag and a locked collection spawns a GUI
prompter — over SSH that would hang forever, so on timeout we kill and surface a
typed `KeystoreLocked`. Subprocess stdout/stderr is parsed into the taxonomy and
**discarded** — never attached to an error (a failed `store` echoes its stdin,
i.e. the base64 value). Launch failure → `KeystoreUnreachable`.

**Default resolution** (`SecretStorage(service:)`): macOS → Keychain; Linux with
a reachable Secret Service → that; otherwise **throw with guidance** — never
silently degrade to weaker storage. Consumers opt into fallbacks explicitly.

## 6. Two composition models

**A — direct items.** Each secret is its own keystore item. The
`flutter_secure_storage` shape and the default for `SecretStorage(service:)`.
Right for an app with a handful of tokens.

**B — wrapped key + container.** One keystore item holds a random 32-byte store
key; the secrets live in an `EncryptedFileBackend` container sealed by that key.

```dart
final store = SecretStorage.withBackend(
  EncryptedFileBackend(
    path: '$dir/secrets.enc',
    keySource: KeystoreKeySource(service: 'myapp/$profileId', api: platformKeystore()),
    contextSalt: utf8.encode(profileId),
  ),
);
```

**When to prefer B.** Model A is strictly the smaller surface — no crypto, no
parser, one keystore round-trip per secret, hardware-backed where available.
Reach for B when you have many secrets (Model A's per-item keychain prompts recur
per binary-identity change, e.g. once per SDK upgrade under `dart run`), when you
want one backup unit, or — decisively — when you must run **headless**: a server
has no unlocked keyring, so its store key needs a file/TPM `KeySource` and its
secrets need the container. Swapping the `KeySource` is the only difference
between the desktop and headless configurations. (dune uses B for exactly these
reasons — 9 secrets and a headless `serve` node.)

## 7. Container format (`EncryptedFileBackend`)

Whole-store blob, rewritten atomically per mutation:

```
magic "DSS1" | version u8 | cipher u8 | nonce(24) | ciphertext | tag(16)
  cipher v1 = XChaCha20-Poly1305
  AEAD key  = HKDF-SHA256(storeKey, salt: contextSalt,
                          info: "secret_store:v1:container" ‖ cipherId)
  AAD       = magic ‖ version ‖ cipher ‖ contextSalt
  plaintext = binary TLV:
      entryCount u32 | per entry: keyLen u16 · keyUtf8 · labelLen u16 · labelUtf8
                                  · valueLen u32 · valueBytes
```

- **Binary TLV, not JSON.** JSON would route every secret value through
  `jsonDecode` into interned, unzeroable `String`s (defeating the whole
  memory-hygiene stance) and run a general parser on decrypted bytes. TLV keeps
  values as `Uint8List` views end-to-end and is a fixed-layout, bounds-checked
  reader — the direct target of the fuzz test.
- **HKDF domain separation.** The raw keystore key is never used directly as the
  AEAD key, so it could later serve other purposes (rotation, per-file keys via
  salt) without cross-protocol reuse.
- **AAD binds identity.** A container moved between profiles (contexts) fails
  authentication even under a hypothetically shared key.
- **RNG:** `Random.secure()` (OS CSPRNG) exclusively — nonces and store keys.
- **Atomic, 0600-from-birth.** An exclusive-created (`O_EXCL`) temp file in the
  same directory, `0600` before any content, `fsync`, then `rename`; the temp is
  unlinked on any failure. The parent dir must grant no group/other access
  (created `0700` if absent). Durability guarantee: **never torn** — a crash
  yields the complete previous or the complete new store (Dart can't fsync a
  directory, so the rename's persistence across a power cut isn't guaranteed,
  but the file is never a mix).
- **Read hardening.** Reads are size-capped (16 MiB) and the parser is total:
  arbitrary or truncated bytes always produce a typed `ContainerCorrupt` /
  `AuthenticationFailed`, never a crash (fuzzed).

**Failure matrix** (each a distinct typed error, so a diagnostics UI can explain
recovery):

| Container | Store key | State | Surfaces as |
|---|---|---|---|
| absent | absent | fresh install | create on first write |
| absent | present | container lost/moved | `ContainerMissing` (recoverable if restored) |
| present | absent | key lost | `StoreKeyMissing` (unrecoverable without a key backup) |
| present | wrong / tampered / malformed | swap, tamper, corruption | `AuthenticationFailed` / `ContainerCorrupt` |

## 8. Threat model

**Protects against:** plaintext key material on disk (backup / Time-Machine /
dotfile-sync leaks); offline disk theft without full-disk encryption; other local
*users*; casual disclosure (scrollback; `ps` argv — hence stdin transport).

**Does not protect against:** same-user malware while the keystore is unlocked
(macOS prompts per binary; Linux Secret Service hands secrets to any same-user
process); process-memory disclosure, including **swap** (encrypted by default on
macOS, often not on Linux) and **core dumps** (Dart can neither suppress them nor
zero buffers); **rollback** to an older genuine container (AEAD can't detect a
backup being restored — a keystore-anchored generation counter is the fix, a
recorded follow-up); timing side-channels in pure-Dart crypto (there is no remote
oracle — a local-timing attacker is already same-user); root.

**No key escrow, by design.** Losing the keystore item loses the store; recovery,
if needed, belongs a layer up. Secrets never touch environment variables or argv.

The bar is ssh-agent / aws-vault, not an HSM. The `KeySource` seam is where a
TPM / Secure Enclave attaches later without redesign.

## 9. Platform expansion path

iOS reuses the macOS `SecItem` C API almost verbatim. Windows is DPAPI/wincred
(clean FFI). Android is the hard one — Keystore has no NDK C API, so the
no-Flutter route is `package:jni`/`jnigen`. Because this is pure Dart + FFI with
no plugin registration, it also runs inside Flutter apps — the long-term option
to retire `flutter_secure_storage` and share one audited store across surfaces.

## 10. Supply chain & security engineering

- **One third-party runtime dependency**, exact-pinned: `cryptography` (verified
  publisher, ~423k weekly downloads), plus `ffi` (dart-lang official, for the
  POSIX shim). The entire runtime closure is `{cryptography, ffi, collection,
  crypto, meta, typed_data}` — everything but `cryptography` is dart-lang
  official. A `dart pub deps --json` snapshot test fails CI if the tree changes;
  CI also runs OSV advisory scanning.
- **Vector firewall.** The pinned crypto is checked against published standard
  vectors (XChaCha20-Poly1305 draft-arciszewski A.3.1, HKDF-SHA256 RFC 5869) in
  our own suite, so a silently-buggy or compromised dependency update can't pass.
- **Narrowed crypto contract.** We call the AEAD with a caller-supplied key
  (HKDF output) and caller-supplied nonce (`Random.secure()`); the dependency's
  own keygen/RNG paths are unused. Contingency: if maintenance decays, vendor the
  XChaCha20-Poly1305 implementation under the same vector suite.
- **FFI is the safest category** — fixed-arity libc / Security.framework calls
  over ints and byte buffers, behind seams with fakes. Guard clauses in FFI use
  braces unconditionally (the "goto fail" bug class is a braceless `if` in
  security C).
- **`dart analyze --fatal-infos` clean**, `strict-casts`/`strict-inference`/
  `strict-raw-types`.

## 11. Implementation notes

Non-obvious things the build settled:

- **HKDF comes from `cryptography`, not hand-rolled** — no home-grown crypto,
  and `crypto` stays a purely transitive dependency.
- **A POSIX file shim is unavoidable.** `dart:io` cannot create a file with
  restrictive permissions (it yields `0644`), cannot `fsync`, and cannot
  exclusive-create — so `SecureFileSystem` binds libc `open`/`write`/`fsync`/
  `close`/`mkdir` directly. Trap: `open` is variadic and on **Apple arm64**
  variadic args pass on the stack, so a fixed-arity binding silently produced
  mode-`000` files; the mode must be bound via `VarArgs`. A perms test on the
  real filesystem guards this permanently.
- **macOS enumeration quirk.** `kSecMatchLimitAll` + `kSecReturnData` together
  returns `errSecParam` on the legacy keychain; `getAll` enumerates
  *attributes only* for the account names, then fetches each value singly.
- **Directory ownership.** The parent-dir check enforces `mode & 0o077 == 0`
  (portable); the strict "owned by the current euid" check needs per-platform
  `struct stat` offsets and is a recorded follow-up (a 0700 dir owned by another
  uid is unusable to us anyway — EACCES).

## 12. Decision log

- Standalone package (name `secret_store`; `lockbox` was the runner-up).
- macOS = direct `SecItem` FFI (an earlier `security`-CLI sketch was dropped: its
  stdin protocol was injectable and its stderr echoed values — both classes
  vanish with the direct API; ecosystem precedent — git/docker credential
  helpers, aws-vault — is unanimously direct-API).
- Linux = `secret-tool` for v1 (its transport is already stdin); a native D-Bus
  client with the encrypted `dh-ietf1024` session is a recorded follow-up.
- Container: XChaCha20-Poly1305, versioned header, HKDF domain separation,
  profile-bound AAD, binary TLV, `Random.secure()` only, fail-closed resolution.
- Pure Dart, not native: native crypto doesn't compose on an all-Dart secret
  lifecycle and would re-add a toolchain + a second FFI seam. Swap/core-dump
  belong at the OS level in the consuming process (`setrlimit`, encrypted swap).

## 13. Follow-ups (recorded, non-blocking)

Native D-Bus Secret Service client · dir-fsync via FFI · strict euid dir-owner
check · keystore-anchored rollback counter · `rotateStoreKey()` · a TPM
`KeySource` (`systemd-creds`) for headless nodes · Windows/iOS/Android backends ·
Linux `secret-tool` integration test under `dbus-run-session` · pub publication.

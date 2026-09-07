# RFC 0001: Cross-platform per-application stores

- **Status:** Accepted
- **Date:** 2026-08-28
- **Accepted:** 2026-08-31
- **Target:** Keybay V2
- **Scope:** SDK storage architecture and platform security policy
- **Companion:** [RFC 0002: Keybay V2 CLI and foreground UI](0002-cli-tui.md)

> This RFC defines the accepted Keybay V2 target. It does not describe the API,
> file format, or security guarantees of any currently shipped Keybay release.

## Summary

Keybay V2 presents exactly **one encrypted store per host application**. A
random store key derives separate keys for a sealed manifest and independently
authenticated record frames. A stable random platform wrapping root—or a
non-exportable equivalent—lives at an identity-derived location and protects
the store's changing key package. The package, frames, and sealed manifest live
in one atomically replaced file. The file remains encrypted for its entire
lifetime; opening Keybay recovers only the store key and minimal session
metadata, not record names or values.

Platform protection is mandatory on every supported path. Applications may add
one or more explicit unlock methods. Once any are configured, recovering the
store key requires platform protection **and any one configured unlock method**.
V2 ships passphrase support first; the policy is intentionally extensible to
multiple hardware credentials without pretending that alternative unlock
methods are multi-factor authentication.

The ordinary SDK entry point has no application or store selector:

```dart
final session = await Keybay.open();
```

Keybay derives application identity from the operating system when the OS can
authenticate it. An arbitrary Dart executable declares a fallback identity in
its `pubspec.yaml`. Keybay reads that declaration only from qualified owning
metadata, or build integration embeds it when raw AOT output retains no such
metadata. That fallback is a namespace, not an authorization boundary, and
documentation must say so.

The returned session is the only public record-access handle. It is explicitly
closed when the caller is finished so Keybay can clear its in-memory store key
and temporary plaintext. Process termination also releases that memory, but a
long-lived forgotten session unnecessarily extends the key's exposure window.

This model deliberately does not expose a `vault` concept or named/selectable
stores. A host app cannot ask Keybay to open another application's store through
the public API. Libraries imported by an application share the host
application's store.

## Decision

Keybay V2 adopts these rules:

1. One host application has one Keybay store, exposed through `Keybay.open()`.
2. Every record is an independent authenticated-encryption frame. A sealed tail
   manifest maps canonical record keys to frame lengths and SHA-256 digests of
   the exact serialized frames; offsets are derived from physical order rather
   than persisted.
3. Every store has an independent, random 256-bit store key (`Kstore`).
4. Ordinary mutations verify and copy unchanged frames as ciphertext, seal only
   changed frames with fresh nonces, and atomically replace the complete file.
   `Kstore` rotation and any future incompatible-format rewrite re-encrypt every
   frame.
5. The platform's preferred credential mechanism supplies one stable
   per-application wrapping root or sealing capability. That root protects the
   changing key package stored inside the encrypted store file. There is no
   passphrase-only or plaintext-key fallback.
6. With no configured unlock methods, platform protection alone opens the
   store. With one or more configured methods, platform access **and any one**
   method are needed to recover `Kstore`.
7. Passphrase unlock has cardinality `0..1`. Future hardware unlock methods may
   have cardinality `0..N`. Platform protection is not a removable method.
8. OS-authenticated application identity is derived, never supplied by an SDK
   call. Where no such identity exists, Keybay uses a verified pubspec
   declaration retained with the owning launch mode or embedded by controlled
   build integration, and reports `namespaceOnly` assurance.
9. The resolved application identity selects the file and platform-root
   locations. Persisted bootstrap fields cannot select an application,
   provider, filesystem path, destruction target, or unrestricted credential
   item. Bounded provider state is consumed only by the already-selected,
   caller-bound provider and remains untrusted until the key package
   authenticates.
10. A missing, invalidated, or inaccessible platform root fails closed. It never
   creates a replacement store while encrypted state remains.
11. Keybay internally classifies identity, file isolation, key isolation, and
    measured hardware protection separately. A later public capability API is
    optional and does not block the core V2 storage API.
12. `session.clearAll()` removes records while preserving protection;
    selector-free `Keybay.reset()` removes the encrypted store, staging, and
    qualified deletable provider state for the resolved application. It retains
    nonsecret coordination locks and creates no replacement store.

## Motivation

Operating systems disagree about what a secure local store is. iOS and Android
give installed apps meaningful application principals and private data
containers. A Flatpak portal can authenticate its sandboxed caller, but the
Secret portal may invoke trusted provider UI when obtaining its reusable
application secret. Ordinary Linux Secret Service clients generally select items
using attributes; an application ID in those attributes does not prove which
process is asking. An unentitled Dart CLI has another problem: source paths,
executable names, and working directories are mutable and are not durable
application identities.

Pretending these mechanisms have identical isolation would make a simple API
misleading. Making a passphrase compulsory everywhere would impose an
interactive password-manager workflow on applications that already have
OS-enforced isolation and on development tools that intentionally rely on the
login session.

The proposal keeps the common storage and cryptographic model small while
exposing the material differences. The encrypted file gives all platforms one
bounded framed format and one atomic update path for both records and unlock
policy. Platform-specific code is limited to establishing identity, choosing a
private data location, and providing one stable wrapping root or sealing
capability.

## Goals

- Give every host application one predictable local secret store.
- Keep the common SDK workflow to `open`, key-oriented operations, and `close`.
- Encrypt record names and values at rest, authenticate the complete manifest,
  and independently authenticate every record frame.
- Decrypt only explicitly requested record values during ordinary reads and
  copy unchanged frames without decrypting them during ordinary mutations.
- Use the strongest appropriate built-in key protection available on each
  supported platform without claiming hardware backing that was not measured.
- Make every configured unlock method meaningfully additive to platform
  protection while stating clearly that methods are alternatives to one
  another.
- Minimize accidental cross-application namespace collisions without presenting
  a declared namespace as an authorization boundary.
- State clearly when the OS enforces application identity and when Keybay only
  has a developer-declared namespace.
- Keep platform key stores small: normally one stable wrapping-root item per
  application, and one Android Keystore key per installed host application.
- Fail closed through key loss, partial writes, conflicting generations, and
  unknown file versions.
- Retain qualification evidence for identity, file isolation, key isolation,
  and measured hardware protection so documentation and first-party guidance
  can report platform limitations without blocking the core SDK.

## Non-goals

- Multiple named stores inside one application.
- A public runtime `appId` or arbitrary store selector.
- Cloud synchronization, sharing, export, backup, or account recovery.
- Protecting plaintext while a compromised host process is using it.
- Protecting against kernel/root compromise, process injection, screen capture,
  a keylogger, or a malicious Keybay binary.
- Preventing deletion by an actor that can modify both the platform root
  and the application's files.
- Guaranteed rollback detection without a separately protected monotonic state.
- Web support, a plaintext fallback, or a special headless mode that bypasses
  the platform protector. A platform-only store may still be used unattended
  when its qualified platform protector is actually available.
- YubiKey, biometric, recovery-key, or multi-factor policy APIs in the first V2
  implementation. The key package is versioned for future unlock methods, but
  this RFC standardizes only platform protection and an optional passphrase.
- In-place frame mutation, an append-only log, journals, tombstones, free lists,
  compaction, Merkle trees, or a general encrypted database.
- Hiding which ciphertext frames remain unchanged across successive snapshots.
  Record names and values remain confidential, but a snapshot observer may
  correlate stable ciphertext and approximate changed-frame sizes.

## Terminology

- **Host application:** The installed app or executable in whose process the
  Keybay SDK runs. A Dart package imported by that process is not a separate
  host application.
- **Application identity:** The stable identity from which Keybay derives the
  store location and platform-root location.
- **OS-enforced identity:** An identity authenticated by code signing, an app
  sandbox, a package/UID boundary, or a portal that identifies its caller.
- **Declared identity:** An identifier embedded from application metadata. It
  avoids collisions and gives storage continuity, but another same-user program
  may declare the same value on a platform that does not authenticate it.
- **Store:** The host application's one encrypted record collection.
- **Session:** A process-local, explicitly closable handle holding the recovered
  `Kstore` and only the minimal metadata needed for key-oriented operations.
- **Unlock method:** An application-configured way to recover `Kstore` after the
  mandatory platform protector succeeds. Configured methods are alternatives
  unless a future explicit multi-factor policy says otherwise.
- **`Kstore`:** A random 256-bit master key, unique to the store. Domain-separated
  manifest and record-frame keys are derived from it; it is not used directly
  as an AEAD key.
- **Record frame:** One canonical record value independently sealed with
  authenticated context binding it to this store, key epoch, format, and exact
  record key.
- **Manifest:** The bounded, encrypted and authenticated tail index listing
  records in physical order with each canonical key, serialized-frame length,
  and ciphertext digest. Frame offsets are derived by prefix sums.
- **File generation:** One complete immutable store-file instance selected by a
  pinned handle. This is a concurrency term, not a persisted counter; V2 stores
  no data-generation field.
- **Key package:** The small, versioned object from which `Kstore` can be
  recovered. It contains the authoritative unlock policy and a sealed route for
  each configured method, or a platform-only route when none are configured.
  The package is sealed by the platform root and stored in the encrypted store
  file.
- **Platform root:** A stable per-application wrapping key or sealing capability
  protected by Keychain, Keystore, Secret Service, or a future qualified
  provider. It protects the key package but is never used directly for bulk
  record encryption. It may be non-exportable.
- **Bootstrap header:** The small public portion of the store file needed before
  the key package can be authenticated. Its fields are bounded and untrusted.
  They describe only the format, sealed-package length, and any
  provider-required opaque continuation token. They never select a provider,
  application, unrestricted credential item, filesystem path, or destruction
  target. Any continuation state is only a hint within the already-selected,
  caller-bound provider.

## One store per host application

The production SDK exposes a session for the host application's store, not a
store registry:

```dart
final session = await Keybay.open();

try {
  await session.set('github/api-token', token);
  final saved = await session.get('github/api-token');
} finally {
  await session.close();
}
```

There is no `Keybay.open(id: ...)`, `SecretStorage(appId: ...)`, or equivalent
production escape hatch. Allowing a caller to change an identifier at runtime
would turn an application identity into a storage selector and imply an
isolation guarantee that ordinary Linux cannot provide.

An application can use slash-separated record keys for organization. Those
names are not separate security, lifecycle, or authentication domains. If a
future use case genuinely needs independently protected collections, that is a
new architecture decision rather than a hidden reintroduction of multi-store.

Tests use an injected in-memory or temporary backend. Testability must not
require production code to accept another application's identity.

### Public SDK surface

The normative V2 API shape is:

```dart
import 'dart:typed_data';

abstract final class Keybay {
  external static Future<KeybaySession> open({
    KeybayCredential? credential,
  });

  // Removes encrypted store/staging and qualified deletable provider state.
  // Retains nonsecret coordination locks; creates no replacement store.
  external static Future<void> reset();
}

sealed class KeybayCredential {
  const KeybayCredential();
}

final class PassphraseCredential extends KeybayCredential {
  PassphraseCredential({required Uint8List phrase}) : _phrase = phrase;

  final Uint8List _phrase;
}

enum KeybayErrorCode {
  applicationIdentityUnavailable,
  platformProtectorUnavailable,
  platformProtectorLocked,
  platformInteractionRequired,
  platformOperationFailed,
  platformKeyInvalidated,
  storageOperationFailed,
  entropyUnavailable,
  authRequired,
  protectionMismatch,
  unlockFailed,
  authMethodAlreadyConfigured,
  authMethodNotConfigured,
  resetIncomplete,
  storeAuthenticationFailed,
  unsupportedStoreVersion,
  storeStateConflict,
  storeBusy,
  staleSession,
  sessionClosed,
  invalidRecordKey,
  invalidRecordEncoding,
  limitExceeded,
  invalidAuthInput,
}

final class KeybayException implements Exception {
  KeybayException._();

  external KeybayErrorCode get code;
  external String get message;

  @override
  String toString() => 'KeybayException(${code.name})';
}

sealed class AuthMethod {
  const AuthMethod._(this.id);

  // Opaque, stable, and non-secret. Callers receive it from add() or list().
  final String id;
}

final class PassphraseMethod extends AuthMethod {
  const PassphraseMethod._(String id) : super._(id);
}

abstract final class KeybayLimits {
  static const int recordValueBytes = 1024 * 1024;
}

abstract interface class KeybaySession {
  bool get wasInitialized;
  bool get isClosed;
  KeybayAuthManager get auth;

  Future<String?> get(String key);
  Future<void> set(String key, String value);

  Future<Uint8List?> getBytes(String key);
  Future<Map<String, Uint8List?>> getManyBytes(Iterable<String> keys);
  Future<List<String>> listKeys();
  Future<void> setBytes(String key, Uint8List value);

  Future<bool> contains(String key);
  Future<bool> delete(String key);

  Future<void> clearAll();
  Future<void> close();
}

abstract interface class KeybayAuthManager {
  Future<List<AuthMethod>> list();
  Future<AuthMethod> add(KeybayCredential credential);
  Future<AuthMethod> update(KeybayCredential replacement);
  Future<void> remove(String id);
}
```

`external` is used above only to omit the facade method bodies from the RFC; it
does not require an FFI or native-external public implementation.

These declarations are the V2 implementation target. The session, record,
authentication, lifecycle, error, and reset surfaces are the core path. A
richer capability-reporting or non-mutating inspection API may ship afterward
under a separate API review. Any public-shape change must not reintroduce a
store selector, callback-only access, named passphrase methods, or ambient
process-global authorization. SDK-returned method objects and lists are
immutable snapshots.

SDK operation failures use `KeybayException` with a stable
`KeybayErrorCode`. Its `message` is a redacted human diagnostic, not a stable
parsing surface, and `toString()` includes only the enum code. Raw provider
exceptions and causal subprocess output never cross this boundary. Programming
errors wholly outside a Keybay operation may still use Dart's standard argument
or state errors; every failure condition named by this RFC uses the public
Keybay error shape.

Every public method that returns a `Future` reports validation, lifecycle, and
input-snapshot failures through that future rather than throwing synchronously
after argument evaluation. This makes the documented call-then-clear-then-await
pattern safe for borrowed byte inputs. `PassphraseCredential` construction only
stores the borrowed reference; validation occurs at the receiving operation
boundary.

`get` and `set` use strict UTF-8 strings because textual secrets are the common
SDK case. Dart strings are immutable and cannot be reliably zeroized; callers
that need mutable plaintext use `getBytes` and `setBytes`. `getBytes` returns a
fresh, caller-owned `Uint8List?`; it never aliases a frame, session buffer, or
another result. `setBytes` does not take ownership of its value. It
synchronously snapshots the bounded input before returning its future, and the
SDK clears that internal copy when the operation settles. Missing keys return
`null`, `delete` returns whether a key existed, and `contains` never returns a
record value. Ordinary reads decrypt the sealed manifest and only explicitly
requested frames.

`getManyBytes` is a bounded exact-key operation, not `readAll()`. It first enforces
the normal session lifecycle check, so an empty request cannot succeed on a
closing or closed session. It then synchronously snapshots and validates the
input iterable before beginning storage access, collapses duplicate keys, and
returns an unmodifiable map containing every distinct requested key; a missing
key maps to `null`. Output iteration follows the first occurrence of each key in
the input. An empty request on a live session returns an empty map without
decrypting the manifest or any frame. The maximum number of requested keys is a
published resource limit; the bound applies to consumed input elements as well
as distinct keys, so duplicates or an unbounded iterable cannot bypass it.
Iteration stops and the call fails before decryption as soon as the bound is
exceeded.

All non-null results are independent, caller-owned `Uint8List` values. If a
selected frame fails authentication or the operation otherwise fails, Keybay
clears every result buffer it has already produced and returns no partial map.
The operation decrypts one sealed manifest from one pinned store generation,
then authenticates and decrypts only the requested frames. While processing, it
sums selected plaintext lengths with checked arithmetic and rejects an aggregate
above the published `getManyBytes` byte limit with `LimitExceeded`. Separate
manifest, frame, and total-store limits bound every allocation. The operation
cannot mix values across concurrent commits and never decrypts unrelated record
values. `getBytes(key)` may use the same primitive for one key. No eager
unbounded value-enumeration API is provided.

`listKeys` decrypts and authenticates the manifest from one pinned generation,
but opens no record frame. It returns names in canonical order as an
immutable list of caller-owned strings. It exists for bounded management
surfaces such as the CLI's `list` command; it is not a value-enumeration API.
`KeybayLimits.recordValueBytes` is the only initially public resource constant
because callers such as the CLI must cap plaintext input before buffering it.
Storage-format and provider limits remain internal.

`delete` removes the record from the live generation but does not rotate
`Kstore` per record or claim erasure from copied generations, filesystem
snapshots, backups, swap, or flash remanence.

Returned bytes belong to the caller. A caller with a narrow plaintext lifetime
can overwrite its `Uint8List` with zeros in `finally`, but this is optional,
best-effort hygiene rather than a security guarantee: Dart, native APIs, or the
caller may already have made copies. Keybay does not impose a custom disposable
byte type on every integration. Keybay's directly owned `Kstore`, derived-key
snapshots, passphrase copies, decrypted manifests, selected-frame scratch, and
input snapshots use mutable buffers and are cleared on every success and failure
path. Dependency-owned buffers have a separate limitation: cryptography 2.9.0's
HKDF returns a `SecretKeyData` without overwrite-on-destroy enabled, and its
immutable byte view prevents Keybay from clearing that backing allocation.
Destroying that wrapper only discards its reference. Internal cipher/KDF state,
immutable provider data and VM copies are not covered by a zeroization guarantee.
A successful
read's transferred result buffer is no longer SDK-owned. AEAD opening uses a
single Keybay-owned ciphertext workspace for in-place decryption, copies out
only an authenticated result, and clears that workspace even when tag
verification fails. Public ciphertext, nonces, salts, digests, AAD, and
bootstrap/provider routing metadata have no zeroization contract.

`PassphraseCredential` borrows the caller's `Uint8List`; construction makes no
secret copy. `open`, `auth.add`, or `auth.update` synchronously validates and snapshots
the current bytes before returning its future. The operation owns and clears
that internal snapshot on success or failure. After the operation call returns,
the caller may independently clear its original input. There is no `String`
passphrase constructor in the security core.

`session.clearAll()` is authenticated record management: it verifies the source
manifest and every source-frame digest, then atomically commits an empty manifest
and no frames while preserving the platform root, `Kstore`, unlock policy, and
open session. It decrypts no record value and makes no forensic-erasure claim.

`Keybay.reset()` is the deliberately broader recovery operation. It removes the
live encrypted file—including its key package and unlock policy—plus transaction
artifacts and qualified deletable provider state for the one resolved application.
It retains fixed nonsecret coordination locks and their directories, creates no
replacement store, and does not require the store to be openable. Its
provider-qualified contract is defined under failure behavior below.

### Opening and first use

`Keybay.open()` both opens and, on total first-use absence, initializes the one
application store. There is no separate public `create()` or `configure()`.
Initialization is permitted only when both the live encrypted file and
Keybay-managed platform-root state are absent. Under the interprocess lock,
Keybay creates an owned root with create-only semantics, or obtains the
qualified profile's ambient application root, then builds and verifies a
complete encrypted empty staging file, durably replaces the live path, verifies
the committed file, and only then returns a session. Root-only, file-only, and
stage-only states fail closed rather than becoming or resuming a store. Because
initialization contains no acknowledged records until `open()` returns,
deliberate reset is the recovery path; V2 does not need a general automatic
initialization-resume protocol. A portal-owned reusable secret is not orphaned
Keybay-managed state: its existence without a file is normal first use for the
Flatpak profile, including after reset. An existing encrypted file must still
authenticate under the returned root; provider failure never initializes over it.

There is one narrower cleanup rule for an acknowledged live generation beside
the fixed staging artifact left by an interrupted write. `open()` holds one
exclusive transaction lock, pins and authenticates the live bootstrap and key
package through the normal provider and credential path, then durably removes
only the staging artifact before continuing. It never reads, authenticates,
adopts, or promotes staging. Failed live authentication leaves staging
untouched; failed staging cleanup or directory durability fails the open. No
diagnostic or existing-session operation performs this recovery.

The state machine is normative:

| Existing state | `Keybay.open()` | `Keybay.open(credential: PassphraseCredential(...))` |
|---|---|---|
| Totally absent | Atomically initialize platform-only and open | Atomically initialize passphrase-protected and open |
| Platform-only | Open | Throw `ProtectionMismatch` without mutation |
| Passphrase-protected | Throw `AuthRequired` | Authenticate and open |
| Live file plus fixed staging artifact | Apply the matching live-store row; only after bootstrap and key-package authentication succeeds, durably discard staging under the same lock and open. Otherwise fail closed without cleanup. | Apply the matching live-store row; only after bootstrap and key-package authentication succeeds, durably discard staging under the same lock and open. Otherwise fail closed without cleanup. |
| Partial or migrating state, invalidated root, malformed bootstrap, or unauthenticated key package | Fail closed | Fail closed |

`open()` deliberately does not decrypt the sealed manifest or record frames, so
it cannot certify those regions. Manifest corruption fails on the first record
operation. A selected frame is authenticated when read, and every source-frame
digest is verified before a mutation commits. This bounded detection is not
misreported as complete-file verification during open.

`session.wasInitialized` is true only for successful initialization rows.
Supplying `PassphraseCredential` is therefore both an unlock attempt and a
caller-held requirement that an existing store use that method. It never
silently adds a passphrase to a platform-only store; protection changes occur
only through an already authorized session.

An interactive application confirms a new passphrase before calling
`Keybay.open(credential: ...)`. Keybay owns no passphrase confirmation, terminal,
Flutter route, biometric, or hardware UI. It receives authentication material
from its host and performs derivation, verification, and storage transactions.

`PassphraseCredential` borrows the caller's mutable bytes without copying them.
Passing it to `open`, `auth.add`, or `auth.update` synchronously snapshots the
current bytes before the method returns its future. The authentication operation
clears that internal snapshot on success or failure and never retains the
passphrase after derivation. The caller retains ownership of the original input
bytes and may clear them as soon as the operation call returns. Reusing a
credential object simply snapshots its then-current caller-owned bytes; it is
not a stored credential handle.
There is no `String` passphrase constructor in the security core. UI adapters
that begin with an immutable string must acknowledge that runtime limitation
and clear their own controls best-effort.

The core accepts 1 to 1024 passphrase bytes with no text normalization or
encoding interpretation. Empty and oversized inputs throw `InvalidAuthInput`
before KDF work. Text-based adapters, including the CLI, define a stable mapping
into those bytes and may choose an equal or narrower bound.

### Session walkthrough and lifetime

A protected store uses the same session API:

```dart
final phrase = await readPassphraseBytes();
final opening = Keybay.open(
  credential: PassphraseCredential(phrase: phrase),
);
phrase.fillRange(0, phrase.length, 0);

final session = await opening;

try {
  final password = await session.get('accounts/github/password');
  if (password != null) {
    await usePassword(password);
  }
} finally {
  await session.close();
}
```

Opening recovers `Kstore`, authenticates minimal header and policy metadata, and
retains only what subsequent operations need. It does not decrypt or cache the
manifest, record names, or values. Each key operation decrypts the bounded
manifest and only the requested frames, then clears SDK-owned temporary
plaintext when the operation settles.

Applications that need a coherent configuration snapshot request its exact
keys together:

```dart
final values = await session.getManyBytes({
  'service/client-id',
  'service/client-secret',
});

try {
  final clientId = values['service/client-id'];
  final clientSecret = values['service/client-secret'];
  // Use the two values from one authenticated store generation.
} finally {
  for (final value in values.values) {
    value?.fillRange(0, value.length, 0); // Optional caller hygiene.
  }
}
```

Closing the session clears `Kstore`; it cannot clear plaintext buffers already
returned to the caller. The inner `finally` illustrates an optional short-lived
consumer policy, not a required Keybay disposal contract.

`session.auth.list()` is the authenticated public view of configured additional
unlock methods. A successful auth-method mutation updates that view before its
future completes; the unexposed internal key epoch advances at the same commit.
The `auth` manager remains obtainable after closing, but each of its operations
returns a failed future with `SessionClosed`; `isClosed` and `wasInitialized`
remain readable for lifecycle diagnostics.

`close()` is idempotent. It first marks the session closing and rejects new
operations, then waits for every operation already registered with that session
to settle. Those operations may complete before `close()` returns. Keybay then
releases locks and provider handles, clears `Kstore` and any session-owned
plaintext scratch buffers best-effort, and marks the session closed.
Because the public API has no separate `isClosing` state, `isClosed` becomes
true as soon as closing starts; it means that the session accepts no new work,
not that asynchronous cleanup has necessarily finished. Await `close()` for the
cleanup boundary.
Passphrase-derived keys are operation-lived and have already been cleared when
their auth operation settled. After `close()` completes, no Keybay operation
remains in flight and later calls throw `SessionClosed`. A future that settled
with caller-owned bytes before `close()` returned may still be awaited and
observed afterward; closing cannot revoke or erase that result.

`close()` attempts every cleanup step even if waiting on an operation or
releasing a provider/lock resource reports an error; zeroization is always in a
`finally` path. It does not rethrow errors already delivered by operations and
completes normally so a `finally { await session.close(); }` cannot mask the
caller's primary failure. Cleanup failures may be sent to a redacted diagnostic
hook, but never prevent the remaining cleanup steps.

The encrypted file is always ciphertext, including staged transaction files.
Closing does not re-encrypt the store because it was never decrypted in place.
If the process exits without closing, the OS reclaims its address space, but
explicit close still matters in a long-lived process: it bounds how long
`Kstore` is exposed to memory disclosure, crash dumps, swap, or a later defect
in the host. A finalizer may provide best-effort fallback cleanup but is never a
lifecycle guarantee.

### Managing unlock methods

Unlock methods are changed only through an authorized session. The current
session proves authority, so changing a passphrase does not redundantly accept
the current passphrase:

```dart
final newPhrase = await readNewPassphraseBytes();
final adding = session.auth.add(
  PassphraseCredential(phrase: newPhrase),
);
newPhrase.fillRange(0, newPhrase.length, 0);
final passphrase = await adding;

final replacement = await readReplacementPassphraseBytes();
final updating = session.auth.update(
  PassphraseCredential(phrase: replacement),
);
replacement.fillRange(0, replacement.length, 0);
final updated = await updating;

assert(updated.id == passphrase.id);
await session.auth.remove(passphrase.id);
```

Passphrase auth has cardinality `0..1`. `add(PassphraseCredential(...))` throws
`AuthMethodAlreadyConfigured` if one exists. It returns a redacted
`PassphraseMethod` with a fresh opaque ID. `update(PassphraseCredential(...))`
throws `AuthMethodNotConfigured` if none exists, atomically replaces the
credential, and returns the updated method with the same ID. It must never be
implemented as remove followed by add.

`list()` returns redacted `AuthMethod` values, never credentials, passphrases,
verifiers, derived keys, or provider secrets. `remove(id)` accepts only an ID
previously returned by `add()` or `list()`; an unknown or stale ID throws
`AuthMethodNotConfigured` without mutation. IDs are stable, opaque,
collision-resistant, and non-secret. They select configured methods but do not
authorize an operation. The authenticated session supplies authority. A host
UI confirms removal of the final additional method when that reduction to
platform-only protection needs explicit human acknowledgement; the SDK does
not embed UI policy in `remove()`.

Future multi-instance hardware methods may receive fresh IDs from `add()` and
be removed through the same API. Their credential and update shapes require a
separate API and cryptographic review; V2 does not reserve public parameters
for an unimplemented design.

V2 implements platform-only and singleton passphrase states. Its generic auth
manager reserves the clean CRUD shape, while persistence for multiple
simultaneous alternative methods requires a follow-up cryptographic design.
Rotating `Kstore` while preserving other routes without presenting their
credentials is not solved by simply sealing the same key independently to each
method. No YubiKey or multi-route implementation may ship until that rekey and
revocation model has its own review and test vectors.

The intended future policy remains:

```text
no configured methods:
  platform protection

one or more configured methods:
  platform protection AND
    (passphrase OR YubiKey A OR YubiKey B ...)
```

These are **unlock methods**, not implicit MFA factors. Adding a second method
broadens the set of acceptable unlock routes. A future AND policy must be an
explicit policy API and may not be inferred from `auth.add`.

### Record key grammar

V2 record keys use a single canonical ASCII grammar across the SDK and storage
format: 1 to 120 characters, composed of slash-separated segments matching
`[A-Za-z0-9][A-Za-z0-9._-]*`. Empty segments, leading or trailing slashes,
`.`/`..` segments, percent decoding, Unicode normalization, query strings, and
fragments do not exist in the key model.

The CLI may require a narrower organizational subset, such as at least two
segments, because one CLI store serves many projects. A `kb://` reference uses
the exact characters after the prefix as the record key; it is not a general
URI and performs no decoding. These rules keep names safe to render and ensure
that every layer selects the same record.

### Libraries inside an application

An arbitrary Dart library cannot establish an application principal. A library
that needs Keybay storage operates within the importing host application's
store and should use a stable package-specific key prefix to avoid collisions.
It must not ship its own fallback application identity.

## Application identity

Identity resolution returns both a value and its assurance:

```text
ApplicationIdentity
  stableValue
  source             // operating system, pubspec, build embedding...
  assurance          // osEnforced | namespaceOnly
  diagnostics
```

The stable value is normalized and domain-separated where it enters a
filesystem path or platform-root location. No unchecked identifier becomes a
path component or provider selector. Provider aliases, services, and lookup
attributes are derived from this value plus fixed Keybay constants, never from
persisted store metadata.

Resolution follows this order:

1. Use an OS-authenticated host identity when the platform exposes one.
2. Otherwise use the application's Keybay pubspec declaration from a qualified
   owning launch mode or controlled build embedding.
3. If none is available, throw `ApplicationIdentityUnavailable` with build
   guidance. Do not guess from the current working directory, executable path,
   executable filename, or a mutable environment variable.

### Arbitrary Dart executables

An arbitrary Dart executable declares its stable namespace as application
metadata:

```yaml
name: acme_tool

keybay:
  application_id: dev.acme.tool
```

The identifier grammar is the case-sensitive ASCII expression
`[A-Za-z0-9][A-Za-z0-9._-]{0,119}`. The declaration uses exactly the unquoted,
two-space-indented form above. Keybay's deliberately narrow parser accepts no
quoted key or value, inline map, alias, block scalar, tab indentation, trailing
comment on the value, or duplicate `keybay`/`application_id` key. It reads
strict UTF-8 and rejects a pubspec larger than 64 KiB. This is a parser for one
namespaced declaration, not a second general YAML implementation.

The `pubspec.yaml` file is not reliably present beside arbitrary compiled
output. Keybay's narrow `keybay_compile` integration therefore validates the
entrypoint-owning declaration and passes it to `dart compile exe` (or
`dart compile aot-snapshot` with the helper's `--aot-snapshot` flag) as the
compile-time `keybay.application_id` declaration without invoking a shell or
accepting a runtime selector. Raw AOT output without that embedded declaration
fails closed. A separate ELF or Mach-O AOT module is recognized by its native
image header when the process executable is the Dart AOT runtime. The header
is only a launch-format check; it confers no authenticated identity or authority.
The module still requires its build-embedded declaration. This supports native
macOS module loading with hardened runtime and library validation intact.

Source execution resolves the nearest pubspec above the canonical source
entrypoint and never searches the current working directory. Legacy
`dart pub global activate` execution accepts only a snapshot beneath the
package root's verified `.dart_tool/pub/bin` directory and reads that root's
pubspec. A source or activated launch carrying an embedded declaration must
match its pubspec.

`dart install` AOT-compiles each executable into an application bundle that
retains the source package's `pubspec.yaml` and generated `pubspec.lock` above
`bundle/bin/<executable>`. Keybay canonicalizes the resolved executable, accepts
only the exact documented local, hosted, or Git app-bundle shapes beneath an
`app-bundles` directory, requires both metadata files to be regular files, and
reads the same bounded declaration from that pubspec. The executable path only
locates owning metadata; no path component becomes the application identity.
An embedded declaration, when present, must match. Missing, malformed, or
unrecognized metadata fails closed. Because this Dart bundle layout is not a
language-level compatibility guarantee, every maintained SDK with
`dart install` must pass an integration fixture; layout drift becomes an
unsupported launch rather than an identity fallback.

The `package:test` runner executes a temporary bootstrap outside the host
package, and compile-time declarations are not reliably forwarded to its test
isolates. Production identity resolution therefore fails closed in that mode;
SDK tests assemble the production V2 engine with disposable file and protector
boundary fakes. There is no alternate behavioral store implementation. This
exclusion is an explicit launch-mode limit, not an identity fallback.

The declaration is intentionally absent from Dart business logic. Application
code remains `Keybay.open()` on every platform. On an OS-enforced platform,
the authenticated OS principal is authoritative. Any declared value is
diagnostic metadata only and cannot override the principal.

The declaration gives an ordinary Dart/Linux process a stable namespace, **not
proof of caller identity**. Another program can compile the same declaration.
Keybay must classify that case internally as `namespaceOnly` and describe it
honestly in user-facing documentation.

### Identity changes

Changing an application ID is equivalent to changing the store's address. It is
not a rename. Signed entitlement, access-group, package-name, and sandbox-ID
changes have the same effect. V2 does not discover or import state from another
identity during normal `Keybay.open()`; applications must keep their identity
stable. A future identity-transfer tool would require an explicit design that
proves access to both identities and copies records transactionally.

## Internal platform boundary

Platform variation ends at one closed internal boundary. The resolver returns a
complete, immutable host binding before any store metadata is trusted:

```text
HostPlatform.resolve()
  -> ResolvedHost(
       application identity,
       application-owned StoreFiles,
       PlatformProtector,
       fixed qualified profile,
     )
  -> common StoreEngine
```

The binding is selected as one qualified profile, not assembled dynamically
from independent capability flags. The Flatpak profile carries its
portal-authenticated identity, sandbox-private files, and
protector together. The active ordinary Linux profile carries its declared
namespace, XDG files, and Secret Service protector together. The common engine
contains no platform checks, provider registry, or fallback selection.

`StoreFiles` owns the identity-derived live, staging, lock, and reset targets;
pinned snapshot reads; the exclusive transaction lock; durable ciphertext
staging; and atomic replacement. It accepts no public path or filename. The
common engine owns the state machine, framing, manifest validation, record
operations, key rotation, and transaction ordering.

A Keybay runtime is one loaded SDK instance in one Dart isolate. It does not
gain process-wide authority over sessions in other isolates. The common engine
creates one production session owner for each successful open. That owner holds
`Kstore`, store ID, epoch, operation ordering, invalidation, and close state.
Framed reads and transactions remain operations beneath it; they do not retain
a second session, key copy, queue, or lifecycle.

`ResolvedHost` also fixes one `ResolvedApplicationBinding` before provider
access. The resolver gives that exact binding object to both `StoreFiles` and
`PlatformProtector`; independently resolved adapters cannot be combined. Its
storage-domain value is a SHA-256 commitment over a versioned,
length-delimited encoding of the canonical application identity, identity
assurance, qualified profile, and the profile's stable storage location.
Path-bound profiles use the canonical file-root URI with the existing
`keybay:v2:storage-domain` label. iOS uses the fixed container-relative URI
`Library/Application%20Support/keybay-v2/` with the separate
`keybay:v2:container-storage-domain` label. Both encodings append NUL after the
label, then the length-prefixed identity, assurance byte, profile, and location
URI. The binding also retains the actual canonical physical root; file adapters
must match it independently of the cryptographic domain. Identity evidence
source is excluded so the same declared namespace does not move when execution
changes from source metadata to the identical AOT-embedded declaration.
Assurance uses frozen one-byte wire codes rather than Dart enum names:
`osEnforced = 1` and `namespaceOnly = 2`. Domain and provider-address encodings
have fixed vectors.

For one stable identity, assurance, and profile, the provider address is
separately derived from those three values and deliberately excludes the file
root. Profiles whose file root can vary independently of their provider
namespace—most notably ordinary Linux under different `XDG_DATA_HOME` values—
must coordinate first-use root creation outside the candidate data directory
and bind the resulting provider state to the selected storage domain. A later
mismatch is `StoreStateConflict`, never total absence and never permission to
initialize a second valid store. A profile that cannot prove this one-binding
property is not qualified. The exact canonicalization, provider commitment, and
cross-root lock primitive are owned by M2 and the relevant M7 profile.

An OS-managed iOS container can move during an application update while its
Library contents survive. Its absolute UUID path is therefore a physical access
location, not durable cryptographic identity. Only the fixed iOS resolver may
select this container-relative binding; it still resolves and validates the
physical root through Foundation on each launch. This does not add a caller-
selected location or permit initialization when an owned provider root survives
without its complete store. See [Apple TN2285](https://developer.apple.com/library/archive/technotes/tn2285/_index.html).

`PlatformProtector` is a package-sealing boundary rather than a raw-key API. It
supports create-only initialization, opening existing provider state, and the
provider's qualified two-phase reset operation. A profile may instead obtain
an ambient, reusable platform root that it does not own or delete. This is a
narrow internal lifecycle distinction, not a public provider selector.
Create returns an operation-scoped
package sealer, its final immutable bounded provider state before the engine
constructs bootstrap AAD, and an internal disposition distinguishing a newly
created root, a concurrently adopted root, or a reused portal-owned root.
Open accepts the bounded
persisted state and must return that identical state or fail invalidated; it
never silently rotates or replaces it. The sealer authenticates
caller-supplied AAD. Exportable Keychain and Secret Service roots use an
internal software-sealing helper and clear root bytes before releasing the
operation. Android and future non-exportable providers implement the same
contract without exporting their root key. Provider calls also receive the
operation's internal interaction permission; they cannot infer permission from
the file or broaden a noninteractive request.

Reset preparation is non-mutating. It completes every provider qualification,
state, and interaction check and returns an operation-scoped capability fixed to
the identity-derived provider target. The implementation either holds that target
stable or revalidates it before mutation. Only after the file adapter has made
the authoritative live target unavailable may the engine commit the prepared
provider reset. Flatpak owns no provider deletion target, so its reset
preparation and commit make no portal call. Closing an uncommitted preparation
changes nothing; every commit
failure is `ResetIncomplete` because file revocation has already begun.

Successful package sealing returns a fresh caller-owned mutable buffer and
retains no alias. The common engine rejects an empty result or one larger than
the fixed opaque-package bound before constructing the bootstrap. The opaque
sealed package is public ciphertext and does not require zeroization.

The opaque provider state is passed only to the already-selected protector. It
cannot choose a profile, provider, application, credential item, path, or reset
target. The protector either opens the requested state under the resolved host
binding or fails; it never asks the engine to try another provider.

Measured identity, file-isolation, key-isolation, and hardware facts remain
qualification evidence in V2 rather than a generic runtime capability object.
They support tests, packaging decisions, documentation, and conservative
first-party UI guidance but do not require a public capability or inspection
API. Each profile must pass the same provider conformance suite before it is
advertised.

Existing Keychain, Android Keystore, Secret Service, secure-file, and locking
bindings may be reused. The record-oriented `SecretBackend` and raw-byte
`KeySource` interfaces are not the V2 boundary: they cannot represent the
single common framed engine and a non-exportable package-sealing capability
without leaking platform differences back into the core.

## Storage and key hierarchy

Every platform uses the same logical hierarchy:

```text
sealed manifest                    independently sealed record frames
       ▲                                      ▲
       │ Kmanifest                            │ Kframe
       └─────────── domain-separated KDF ──────────┘
                              ▲
                              │
                           Kstore
              (random, unique to this application store)
                              ▲
                              │ platform-only route, or one configured
                              │ additional unlock route
                 platform-sealed key package
                              ▲
                              │ fixed identity-derived provider location
                              │
            stable mandatory platform root or sealing capability
```

The arrows are unlock dependencies. With no configured unlock method, opening
the platform-sealed package yields `Kstore`. With passphrase protection,
platform access yields only the passphrase envelope; the passphrase is also
needed to recover `Kstore`. Future multiple-route packages must preserve the
same outer platform requirement. The stable platform root does not change
during ordinary record or unlock-policy mutations. `Kmanifest` and `Kframe`
are derived from `Kstore` with fixed format-versioned domain labels. `Kstore`
is never used directly as an AEAD key.

### Encrypted record file

The store is one versioned, atomically replaced file:

```text
bootstrap core + sealed-package length + opaque platform-sealed key package
serialized record frame 1
...
serialized record frame N
sealed tail manifest
sealed-manifest length
```

Suite 1 uses one strict binary encoding. Integers are unsigned big-endian;
lengths and counts are 32-bit, the key epoch is 64-bit, and tags or policy
values are 8-bit. Decoders require exact component lengths and reject unknown
values or trailing bytes. There are no optional fields, ignored extensions, or
alternative encodings within a suite.

The epoch is encoded as `u64` but its canonical semantic range is
`1..0x7fffffffffffffff`. Zero and values with the high bit set are rejected, so
the value has identical exact integer behavior across maintained Dart and
independent implementations.

```text
bootstrapCore = "KBV2" | suite:u16 | providerStateLength:u32 | providerState
bootstrap     = bootstrapCore | sealedPackageLength:u32
file          = bootstrap | opaqueSealedPackage | recordFrames...
                | sealedManifest | sealedManifestLength:u32
```

The common format deliberately treats `opaqueSealedPackage` as provider-owned
bytes. A software-root provider may encode it as `nonce || ciphertext || tag`;
a non-exportable platform provider may use another qualified encoding. Every
provider must authenticate and consume the exact bounded blob passed to
`openPackage`; ignored suffixes are forbidden.

After provider opening, the package plaintext has one of two exact forms:

```text
common       = storeId:16 | epoch:u64 | policy:u8
platformOnly = common(policy=0) | Kstore:32                         # 57 bytes
passphrase   = common(policy=1) | methodId:16 | profileId:u8
               | salt:16 | innerEnvelope:72                       # 130 bytes
innerEnvelope = nonce:24 | encryptedKstore:32 | tag:16
```

The raw method ID is 16 random bytes. Its SDK-visible opaque form is exactly 32
lowercase hexadecimal characters; uppercase and alternative encodings are not
accepted.

Each serialized frame is `nonce || ciphertext || authentication tag` under
XChaCha20-Poly1305 and `Kframe`: a 24-byte nonce, zero to 1 MiB of ciphertext,
and a 16-byte tag. It has no public key or length header. Its canonically
encoded AAD binds the suite, store UUID, key epoch, frame type, and exact
canonical record-key bytes. It deliberately does **not** bind physical offset,
ordinal, or any manifest-specific value, so an unchanged authenticated frame
may move within a replacement file without being re-encrypted. Copying
identical sealed bytes is not a new encryption operation and therefore is not
nonce reuse. Every new or changed frame receives a fresh CSPRNG nonce;
resealing different plaintext under an existing nonce is forbidden.

The tail manifest is independently sealed under `Kmanifest` with a fresh nonce.
Its canonical plaintext contains one entry per record in physical frame order:

```text
entryCount:u32
repeated entryCount times:
  keyLength:u32 | canonical ASCII key | frameLength:u32
  | SHA-256(serialized frame):32
```

The digest is an exact-frame copy-forward commitment protected by the sealed
manifest; it does not replace the frame's AEAD authentication tag. Entries use
unique keys in ascending canonical byte order. Offsets are never persisted:
readers derive them by checked prefix sums from the authenticated lengths and
require those lengths to consume the frame region exactly. Gaps, overlaps,
trailing frames, duplicate keys, out-of-range lengths, noncanonical encodings,
and arithmetic overflow fail before any record plaintext is released. The
fixed-width public manifest length is only a bounded, untrusted locator; it
cannot select another file, provider, key, or allocation beyond published
limits.

Manifest decoding keeps record names as mutable ASCII byte buffers. Key-oriented
operations encode the caller's requested name and compare bytes; rotation and
any future incompatible-format rewrite use those same bytes for frame AAD.
SDK-owned manifest name buffers are cleared after every operation.

The manifest plaintext authenticated by AEAD binds the complete ordered frame
layout above. Its AAD contains only context available before decryption: a fixed
domain label, the resolved storage-domain commitment, the exact full bootstrap
bytes, and the exact opaque sealed-package bytes. The authenticated
entry lengths must consume the actual frame region exactly, so its total length
is not duplicated in AAD. This binding prevents an already-open session from
accepting or copying forward a modified format version, package length, provider
state, or any sealed-package byte. The manifest nonce is already an AEAD
input and is not redundantly copied into AAD. Record names are encrypted inside
the manifest and never appear as filenames, public-header fields, frame headers,
or credential-store attributes. The outer filesystem still reveals that the
application has a Keybay store, total file size, update timing, and—to
an observer retaining successive snapshots—which sealed frame byte strings
remained unchanged and their approximate sizes.

`open()` bounds-checks the bootstrap, resolves the provider independently,
authenticates the selected key package in its identity and bootstrap context,
and recovers `Kstore`; it does not decrypt the manifest or any frame. `contains`
decrypts only the bounded manifest. `get`, `getBytes`, and
`getManyBytes` pin one file generation, decrypt its manifest, locate selected
frames from authenticated lengths, compare each exact serialized-frame digest,
and then authenticate and decrypt only the requested values. No unrelated
record value enters plaintext memory. `getManyBytes` returns requested values
from one generation and enforces a separate aggregate return limit. SDK-owned
manifest, selected plaintext, and temporary result-construction buffers are
cleared on every path. Successful result buffers become caller-owned; if the
operation fails, any results already constructed are cleared before the error
is returned.

An operation opens and pins the then-current complete file before interpreting
its manifest and never reopens the live path to fetch a frame. If key rotation
committed before the pin, it releases no plaintext and fails with `StaleSession`
or another fail-closed authentication/state error. If the pin happened first
and authentication succeeds, the operation may finish from that prior
generation after a concurrent replacement commits. It never combines a
manifest from one generation with frames from another, and no result is released
before every selected frame authenticates.

`set` and `delete` take the interprocess lock, pin the latest complete source
file, and authenticate its manifest against the exact bootstrap and sealed
package without reopening the platform provider. They then create a
ciphertext-only staging file. Keybay streams every source frame through SHA-256
and compares the result with the authenticated source-manifest digest. It copies
unchanged frame bytes directly, omits deleted frames, and writes each new or
changed value as a freshly sealed frame. The implementation builds the new
ordered manifest while streaming, seals it at the tail with a fresh nonce,
appends the bounded fixed-width length, validates the complete staging layout,
and then durably replaces the live file atomically. An integrity mismatch aborts
without committing; no unrelated record is decrypted.
No plaintext store, journal, backup, recovery file, tombstone, free list, or
compaction state is written.

The same copy-forward transaction is used by `clearAll`, except its new manifest
is empty. `Kstore` rotation or a future incompatible frame/AAD rewrite cannot
copy old frames because `Kframe` or its authenticated context changes; it
streams through every value one at a time. Before AEAD-open, it hashes the exact
old serialized frame and compares that digest with the authenticated source
manifest; this prevents a valid older frame for the same record and key epoch
from being promoted during rotation. It then authenticates and decrypts the
frame, reseals it under the new epoch or format, and clears each plaintext
before continuing.

The wire encoding, XChaCha20-Poly1305 and SHA-256 suite, domain-separated KDF
labels, AAD encodings, nonce rules, parser limits, and exact-frame digests
require a dedicated format review and fixed independent test vectors before
persistent implementation. Keybay does not add a custom cipher, commitment
primitive, or KDF.

### Suite 1 keys and authenticated transcripts

Suite 1 pins the pure-Dart `DartXchacha20`, `DartHkdf` with HMAC-SHA-256,
`DartSha256`, and `DartArgon2id` implementations from the exact-pinned
`cryptography` dependency. It does not resolve primitives through the mutable
global `Cryptography.instance` service locator.

The two bulk keys use HKDF-SHA-256 with `Kstore` as input keying material and
the 16-byte store ID as salt:

```text
Kmanifest = HKDF-SHA256(Kstore, storeId, "keybay:v2:s1:key:manifest")
Kframe    = HKDF-SHA256(Kstore, storeId, "keybay:v2:s1:key:record-frame")
```

Every AAD transcript has one encoding: the exact ASCII label, one zero byte,
then each field as `length:u32 || bytes`. Suite 1 fixes these labels and fields:

| Purpose | Label | Ordered fields |
|---|---|---|
| Platform package | `keybay:v2:s1:aad:platform-package` | storage-domain commitment, exact `bootstrapCore` |
| Manifest | `keybay:v2:s1:aad:manifest` | storage-domain commitment, exact full `bootstrap`, exact opaque sealed package |
| Passphrase envelope | `keybay:v2:s1:aad:passphrase-envelope` | store ID, encoded epoch, method ID, profile ID byte, salt |
| Record frame | `keybay:v2:s1:aad:record-frame` | store ID, encoded epoch, frame-type byte `1`, exact canonical record-key bytes |

The storage-domain commitment is the 32-byte binding over resolved identity,
assurance, qualified profile, and its stable storage location as defined above.
The package
length cannot be package AAD because it does not exist until the provider has
sealed the package. Instead, the provider must consume the exact package blob;
the resulting length and bytes are then both bound by manifest AAD. This avoids
a circular encoding without granting a public field routing authority.

Suite 1 has these pre-allocation limits:

| Resource | Limit |
|---|---:|
| Complete store file | 16 MiB |
| Provider continuation state | 64 bytes |
| Opaque sealed package | 4 KiB |
| Records | 4,096 |
| Canonical record key | 1–120 ASCII bytes |
| Record value | 0–1 MiB |
| Serialized record frame | 1 MiB + 40 bytes |
| Manifest plaintext | 655,364 bytes |
| Sealed manifest | 655,404 bytes |
| `getManyBytes` consumed inputs | 1,024 |
| `getManyBytes` aggregate result | 16 MiB |

The trailer accepts only a complete sealed manifest—at least the encrypted
four-byte empty-manifest count plus nonce and tag. Prefix-sum layout arithmetic
must also fit the complete-file limit and consume the frame region exactly.

Mutations use a per-store interprocess lock and a durable atomic replace. A write
is not acknowledged until the complete authenticated file and required metadata
have been flushed according to the platform contract. A crash leaves either the
old complete live file or the new complete live file. An uncommitted staging
file is never authoritative.

An already-open session reads only the live file and does not inspect staging.
A read concurrent with a lock-holding mutation may therefore complete from the
old live generation. Open, initialization, mutation, and reset classify
transaction artifacts only while holding the transaction lock; once that lock
is acquired, remaining staging has no active owner and is abandoned state. Only
`open()` may preserve the live generation while removing that staging, and only
after authenticating the live bootstrap and key package under the same lock.
Existing-session mutations continue to fail closed; reset follows its separate
live-revocation protocol.

One session serializes its accepted operations. Under the
interprocess lock, a mutation rereads the authoritative manifest before applying
its change, so a concurrent record write cannot be silently overwritten. An
ordinary record change does not require platform access or reauthentication: a
session holding the current `Kstore` can authenticate the latest file and
proceed.

An unlock-method change rotates `Kstore`, advances the key epoch, and replaces
the key package, every record frame, and the manifest in that same atomic file
transaction. The stable platform root is obtained, with trusted provider UI
permitted, before
mutation and does not change. The committing session advances to the new key
only after the durable replacement succeeds. Other sessions registered with
the same Keybay runtime are invalidated. Sessions in another isolate or process
fail closed when their old `Kstore` cannot authenticate the new file, but retain
key or plaintext already in memory until their own lifecycle clears it. Keybay
does not reacquire the platform root to classify this failure. Cross-runtime
rotation, tamper, and wholesale replacement can therefore produce the same
`storeAuthenticationFailed` error. The caller closes the old session and makes
a fresh authenticated `open()`; a failed reopen is not permission to reset.
`staleSession` remains the result of known invalidation within the runtime.

An operation already pinned to the prior generation may settle after rotation
if that generation authenticates successfully; it is ordered before the commit.
Rotation cannot revoke an operation already linearized at the pin. Tests cover
both orderings.

The lock implementation, timeout, and owner-failure behavior are platform
adapters behind one contract. Failing to acquire it returns `StoreBusy`; Keybay
does not break an apparently live lock or continue without serialization.
Initialization, record mutation, auth rotation, recovery, and any future
incompatible-format rewrite all use the same lock domain.

File permissions such as `0700` directories and `0600` files are defense in
depth. They isolate OS users; they do not isolate two unrestricted processes
running as the same user.

### Bootstrap header, platform root, and key package

The identity resolver and positively observed runtime capabilities select the
platform provider. The provider-root location is then fixed or derived from the
resolved identity and a domain-separated Keybay purpose. On an OS that already
namespaces aliases by application, Keybay uses one fixed V2 alias. On
`namespaceOnly` systems it uses a fixed schema/service plus a normalized identity
digest. The digest prevents unsafe path construction and accidental collision;
it is not an ACL and does not make the declared identity unspoofable.

The persisted file never supplies an arbitrary provider, credential-item
locator, application ID, filesystem path, command, URI, or destruction target.
A provider-required opaque continuation token may be passed only to the
already-selected provider in the resolved application context. It is a bounded,
untrusted hint: the returned root must authenticate the key package, alteration
cannot trigger fallback or initialization, and a future provider change remains
an explicit operation requiring access to both protection paths.

The bounded bootstrap contains only what is needed before `Kstore` is
available. Its core is fixed magic, suite number, and any bounded opaque
continuation state required by the already-selected platform provider. That
exact core authenticates as package AAD. The provider then produces an opaque
sealed package, whose length is appended to form the full bootstrap. The length
cannot authenticate the operation that creates it; instead, package opening
must authenticate and consume the exact blob, and the full bootstrap plus blob
authenticate as manifest AAD. Before then, continuation state and lengths are
only bounded hints whose authority comes from the caller-bound provider and
subsequent authentication. The bootstrap contains no provider identifier,
store UUID, key epoch, record layout, frame locator, or manifest routing
authority.

The fixed-width manifest length at the tail is a separate untrusted parsing hint.
It is bounds-checked against the actual pinned file before allocation; the
manifest's AEAD and exact frame-region consumption establish authority. This
split lets an ordinary record mutation retain the sealed package byte-for-byte
while replacing frames and the manifest. `open()` must not claim to authenticate
the manifest contents or layout before a later record operation opens it.

Every public field is untrusted before the corresponding authentication step.
Before authentication it is constrained to a fixed value or published
byte/allocation limit and cannot broaden what resource Keybay accesses. Package
AAD binds a fixed domain label, the resolved storage-domain commitment, and the
exact bootstrap core. Once the package authenticates, the suite in that core
and the store UUID, key epoch, unlock policy, passphrase profile, and salt inside
the package are authoritative. The manifest subsequently binds the full
bootstrap and exact opaque package. None is duplicated merely for confirmation.
Secret record names, values, `Kstore`, the platform root, and the passphrase
never live in the public header.

Providers establish the stable platform root differently:

- Keychain and Secret Service store random wrapping-root bytes at the one
  identity-derived item.
- Flatpak obtains the portal-owned application secret and derives a
  Keybay-specific wrapping root; it does not create a Keybay provider item.
- Android Keystore holds one non-exportable app-root key that seals and opens
  the file's key package.
- A qualified Windows provider may supply an implicit sealing capability rather
  than exportable root bytes.

The Flatpak profile uses XDG Secret Portal v1 `RetrieveSecret` only when the
operation permits trusted provider interaction. The transport accepts 1–4096
opaque bytes, but the protector requires 32–4096 bytes. This is a supported
subset of the portal's variable-length contract. The 32-byte minimum is a
necessary input shape for the 256-bit root, not proof of entropy: HKDF cannot
create entropy, and qualification must review the backend's random-secret
generation. No content-based entropy heuristic is used.

HKDF-SHA256 derives 32 wrapping bytes using the resolved storage-domain bytes as
salt and the UTF-8 info label `keybay:v2:linux-flatpak:portal-root:v1`.
Keybay-owned raw and derived root snapshots are cleared after the operation;
the dependency-owned HKDF result has the memory-clearing limitation described
above. This separates Keybay's use from another use of the same
application secret without inventing a provider item lifecycle.

The initial profile supports no continuation state. It rejects a response
containing a continuation token and any nonempty persisted provider state,
including an empty-string token response. It never ignores a token and then
pretends later calls can retrieve the same secret. Timeout, cancellation,
malformed response, unavailable portal, and unsupported continuation fail
closed; none selects ordinary Secret Service.

An identity-derived Secret Service lookup must return exactly one root item.
Zero matches means absence, one means an existing root, and multiple matches are
`StoreStateConflict`. Initialization re-queries after create and never chooses,
overwrites, or deletes an arbitrary duplicate.

These are internal variations. The key package remains in the store file and
the record format and `Kstore` semantics do not change.

`Keybay.open()` (including initialization), `session.auth.add/update/remove`,
and `Keybay.reset()` may invoke trusted OS or provider UI. Calling one of these
operations permits that interaction; the public API adds no interaction option.
Hosts must invoke these lifecycle operations from a context that can accommodate
provider interaction and handle typed cancellation, timeout, locked, or
unavailable failures. Existing profiles may remain noninteractive even when
interaction is permitted.

`get`, `getBytes`, `getManyBytes`, `set`, `setBytes`, `contains`, `listKeys`,
`delete`, `clearAll`, and `auth.list` never prompt. They use the session's store
key and never acquire the platform provider, including on failure. There is
no provider-based stale-session diagnostic. Cross-runtime authentication changes
retain `storeAuthenticationFailed` rather than inferring the reason for failure.
An unclassified authentication failure remains a failure, never permission to
show UI or return plaintext. Keybay itself never obtains a passphrase through
provider UI: callers supply the credential explicitly. A future biometric,
hardware-token, or OS-presence credential still needs its own unlock-method
contract; provider UI is not silently treated as an additional method.

Device lock and platform user-presence policies therefore gate operations that
must reacquire the platform root; they do not retroactively revoke `Kstore`
from an already-open session. Such a session continues until it is closed,
becomes stale, or its process ends. Callers that need a shorter exposure window
must close the session at their own lifecycle boundary.

## Additional unlock methods

V2 implements one optional passphrase unlock method. It is additive to the
mandatory platform protector:

```text
Kpass = Argon2id-v19(passphrase, random 16-byte salt, allowlisted profile)
inner = AEAD-Seal(Kpass, Kstore, authenticated store/method context)
package = PlatformSeal(Kplatform, inner + authoritative policy)
Kmanifest, Kframe = DomainSeparatedKDF(Kstore)
file = bootstrap + package + record frames + sealed tail manifest
```

`Kplatform` names the stable platform root conceptually; an adapter may instead
offer a non-exportable seal/open capability. Without a passphrase, the
platform-sealed package contains `Kstore` and the authoritative `platformOnly`
policy. There is never a mode where the passphrase replaces platform
protection.

On open, Keybay obtains the platform root or sealing capability and authenticates
the on-file key package. If its policy requires a passphrase, Keybay derives
`Kpass`, authenticates the inner envelope, and only then retains `Kstore` in the
returned session. Exportable platform-root material, the input passphrase,
`Kpass`, decrypted package, and provider scratch buffers are cleared before
`open()` returns. `Kstore` remains only until the session closes or becomes
stale. None is persisted in plaintext. Documentation acknowledges that Dart's
runtime, immutable strings, swap, and crash capture prevent a promise of perfect
memory zeroization.

The file stores a one-byte Argon2id profile ID and a 16-byte random salt, not
attacker-selected memory, iteration, or parallelism values. Each known profile
maps immutably to a library-defined Argon2id v19 tuple and 32-byte output;
unknown IDs fail before allocation or KDF work. Profile 1 is RFC 9106's second
recommended profile: 64 MiB, three iterations, parallelism four, and a 32-byte
output. Every future allowlisted profile remains within absolute limits of
256 MiB, 10 iterations, and parallelism 4.

M6 serializes derivations within each Dart isolate to avoid accidental memory
amplification inside one Keybay runtime. There is deliberately no process-wide
arbiter: runtimes in other isolates cannot share session authority, and a host
that creates several isolates can multiply the KDF's memory cost just as it can
allocate memory directly. Each M7 profile must pass AOT latency and memory
qualification on its maintained device classes before production activation.
Optional Argon secret and associated-data inputs are empty in the shipping
passphrase flow.

The exact-pinned `cryptography` package supplies a pure-Dart `DartArgon2id`, so
the primitive is available anywhere maintained Dart runs; qualification still
depends on measured memory and latency, not mere availability. The dependency
passes RFC 9106 section 5.3's Argon2id vector in Keybay's suite. On native hosts
the production profile uses a 64 MiB native workspace and four helper isolates.
Keybay captures the workspace before deriving, overwrites it before releasing
it, and attempts release even if cleanup fails. Its use of the dependency's
protected workspace accessor is pinned and covered by an ownership regression.
Cleanup does not allocate another workspace after allocation failure. The
single-isolate queue bounds callers' concurrent derivations, not the dependency's
helper count. Dependency-internal hash state, Dart heap copies, swap and crash
capture remain residual risks; this is not a whole-process erasure guarantee.

### What a passphrase adds

On ordinary Linux, a same-user program may be able to retrieve another
application's Secret Service root item if it knows or discovers the attributes.
The root opens the outer on-file package. With a passphrase enabled, that still
yields only the passphrase-wrapped store key. The attacker must then guess the
passphrase through Argon2id before it can decrypt the manifest or frames. The same
protection applies when an unentitled CLI's platform root is exposed or when its
credential-store data and encrypted file are copied for offline attack.

This is strong, useful additional confidentiality when the passphrase has
adequate entropy and is not observed. It does not prevent:

- keylogging, process injection, or memory inspection during an operation;
- offline guessing against a copied envelope;
- deletion of the encrypted file or platform root;
- replacement of every same-user-writable store artifact with a new store; or
- replay of a complete older store generation without a protected monotonic
  counter.

In particular, a passphrase does not turn a declared application namespace into
an OS application ACL. While the genuine protected envelope survives, an
attacker cannot decrypt or forge it without the passphrase. If unrestricted
same-user code can replace both the platform root and the file, Keybay has no
external trust anchor from which to prove that wholesale substitution occurred.

The concrete downgrade attack is important: an attacker on a `namespaceOnly`
platform can delete a protected store, install a new platform-only store under
the same declared identity with an attacker-known key, and wait for the genuine
application to store a new value. Unless the caller independently requires a
passphrase, the replacement is indistinguishable from valid new state and the
new value is recoverable by the attacker. A passphrase protects the genuine
store's contents; it cannot preserve its own policy after every local anchor is
replaced. CLI warnings make this visible but are not cryptographic prevention.

### Unlock-method changes

`session.auth.add`, `update`, and `remove` rotate `Kstore` and re-encrypt every
record frame and the manifest. Merely rewrapping the same `Kstore` would let a
copied old unlock envelope open all future versions of the file. Rotation limits
an old envelope to the old encrypted generation it accompanied.

The stable platform root is opened with trusted provider interaction permitted
before mutation but is not
changed. Keybay generates a fresh `Kstore`, builds a complete staging file with
the replacement package, policy, epoch, re-encrypted frames, and new manifest;
verifies it; flushes it; atomically replaces the live file; and flushes the
containing directory. A crash before atomic replacement leaves the old complete policy and
data. After acknowledged durable completion, the new complete policy and data
are authoritative. A crash during an unacknowledged rename or directory flush
may leave either complete version, never a partially authenticated version;
the next open resolves only a valid live generation or fails closed. Successful
completion removes the old unlock route from the live store without a
cross-provider transaction or silent `platformOnly` fallback.

Rotation cannot revoke plaintext or older complete snapshots already captured
before the protection change. Full rollback resistance remains a stated
non-goal until Keybay has a qualified monotonic anchor.

There is no implicit recovery path. Losing the passphrase, losing a mandatory
platform root, or invalidating the provider capability makes the store
unrecoverable unless a future explicit recovery design says otherwise.

## Platform policy

The table describes the proposed V2 resolution. It is not a claim that every
listed path has been implemented or physically qualified.

| Platform / host context | Identity and assurance | Encrypted record location | Stable platform root protecting the on-file key package | Honest guarantee and passphrase guidance |
|---|---|---|---|---|
| **iOS app** | Build-expanded `KeybayApplicationIdentifier=$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` read from the signed, nonlocalized processed Info.plist and cross-checked against the bundle identifier; the exact-group Keychain operation supplies the `osEnforced` check | App-private Application Support file with backup exclusion set and verified | One stable random root in a Data Protection Keychain item in the app's signed application-identifier group, never an arbitrary shared group; `kSecAttrSynchronizable=false` and `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | A normal peer app outside the signed group cannot read the root or app-private file. Another same-team app can be explicitly authorized into an access group, so this is signed-group isolation rather than absolute privacy. The baseline requires device unlock but not fresh biometric presence for each operation. Keychain storage is not claimed to be Secure Enclave-backed. A passphrase is optional defense in depth, not a default requirement. |
| **Android 12+ app (proposed API 31+ V2 floor)** | Installed package and UID derived through the host integration; `osEnforced` | `noBackupFilesDir` beneath the application sandbox | One non-exportable app-root AES-GCM key in Android Keystore seals the independent key package stored in the file | Package sandboxing isolates ordinary peer apps. The qualification harness reads `KeyInfo.getSecurityLevel()` from the generated key to distinguish StrongBox, TEE, and software status; the austere V2 SDK exposes no generic capability API. A passphrase is optional defense in depth. Root-key loss is `PlatformKeyInvalidated`, not a new store. |
| **macOS signed + entitled app** | Signed application-identifier identity derived from the code signature and entitlements; key access is `osEnforced` | App container when sandboxed, otherwise derived Application Support directory | One stable random root item with `kSecUseDataProtectionKeychain=true` in the app's signed application-identifier group, never an arbitrary shared group; non-synchronizing with an explicit `ThisDeviceOnly` accessibility class | The entitlement protects root access from processes outside the signed group; explicitly entitled same-team apps may share a group. File isolation is reported separately because entitlement and App Sandbox are different properties. No Secure Enclave or per-operation user-presence claim is made for a generic keychain item. Passphrase is optional; it is more valuable for an unsandboxed app whose ciphertext can be deleted or replaced by same-user code. |
| **macOS unentitled app or CLI** | Verified pubspec or build-embedded declaration; `namespaceOnly`. A stable code signature/Keychain ACL may add key-access protection, but does not upgrade the declared namespace itself | One identity-derived leaf at `Library/Application Support/<application-id>-<full identity/profile digest>.keybay-v2/` beneath the effective OS account's canonical home. The existing Application Support directory is the durable anchor; Keybay never creates missing ancestors. The leaf is `0700`, files are `0600`, extended ACLs are absent, and path traversal is descriptor-relative with symlinks refused | One stable random root in an identity-derived item in the explicit `Library/Keychains/login.keychain-db` opened from that same OS-account home. Adds use `kSecUseKeychain`; reads and deletes use a one-entry `kSecMatchSearchList`. The mutable default and ambient search list are never consulted | Keychain ACL behavior, unsigned/ad-hoc builds, `dart run`, and binary replacement do not form one portable application sandbox. Another process may also invoke a trusted CLI as a deputy. Strong passphrase recommendation for human credentials or protection from same-user programs; optional for developer injection workflows. Missing or inaccessible fixed login-Keychain state fails closed; there is no fallback to another Keychain. |
| **Linux Flatpak candidate** | `[Application] name` in the running sandbox's `/.flatpak-info`; portal-authenticated caller, `osEnforced` | Fixed `<instance-path>/data/keybay-v2` beneath the sandbox's private application data directory | Portal-owned reusable application secret, domain-separated into the Keybay wrapping root | Trusted provider UI is permitted for open and authentication changes. Record operations never call an interactive portal. Reset retains the portal secret, so an old complete encrypted store can restore access. Qualified isolation requires Linux evidence with two installed application IDs under verified Flatpak confinement. No raw Secret Service fallback. |
| **Linux strict Snap** | Deferred beyond initial V2 | Deferred | Deferred | No Snap profile is advertised until confinement identity, persistent location, provider binding, upgrade continuity, and reset behavior pass a separate qualification. Environment variables alone do not establish identity. |
| **Ordinary Linux desktop** | Verified pubspec or build-embedded declaration; `namespaceOnly` | `${XDG_DATA_HOME}`-derived application directory, `0700` directory and `0600` store files | One identity-derived Secret Service item containing stable random root material | Protects against other OS users and casual offline access according to the provider, but does not promise same-user application isolation. Another unlocked-keyring client may read, replace, or delete the root; same-user code may modify files. A passphrase is **strongly recommended** for passwords and high-value credentials, but is not mandatory. |
| **Windows packaged/unpackaged app** | Planned: package/AppContainer identity where authenticated; verified pubspec or build-embedded declaration otherwise | Planned app-private or Local App Data location | Planned stable DPAPI/CNG/AppContainer-aware wrapping root or sealing capability for the on-file package | **Not a shipped V2 commitment until implemented and qualified.** User-scoped DPAPI alone must not be described as application isolation. The exact provider, packaged-app split, and hardware reporting remain open; passphrase guidance follows the measured identity/key-isolation capabilities. |

App Sandbox status changes the entitled macOS file root and its measured file
isolation, but not the provider profile or Keychain address. If that status—or
another host fact—changes the canonical file root for the same signed
application identifier, the retained root's domain commitment makes the next
open fail `StoreStateConflict`; Keybay does not initialize a second store.

On iOS and entitled macOS, Keychain state may survive an uninstall even though
the application file container does not, but Keybay does not depend on that
behavior. An owned provider root without its complete store is
`StoreStateConflict`, including after an iOS reinstall at a new physical path.
A retained root committed to a different domain also fails closed. An explicit
`Keybay.reset()` under that same resolved
identity and profile may remove the fixed root and allow a new first-use
initialization; Keybay never auto-adopts it or creates a second store.

The unentitled macOS profile is intentionally stricter because its declared
namespace is not authority to delete another file domain's valid login-Keychain
root. `Keybay.reset()` from a conflicting candidate root returns
`StoreStateConflict` and preserves that root. An application must reset while
running from the old resolved root, or perform separately scoped external
cleanup; the new candidate path cannot authorize cross-root deletion.

### Provider selection and fallback

Keybay selects a provider deterministically from positively observed runtime
capabilities. Packaging intent, environment variables, and library availability
alone do not establish confinement or caller identity.

A detected Flatpak selects only its portal profile. Invalid sandbox identity,
an unsupported data layout, or portal failure is an error. Keybay does **not**
create a raw Secret Service store under weaker assumptions. An ordinary
unsandboxed launch is a different runtime context: it may select Secret Service
with `namespaceOnly` assurance and the declared application namespace, but
Keybay does not describe that as a downgraded Flatpak store.

The Flatpak profile `linux.flatpak.secret-portal-file.v1` reads only the fixed
`/.flatpak-info`, bounded to 64 KiB, and requires an unambiguous valid
`[Application] name` and normalized absolute `[Instance] instance-path`.
Runtime-only metadata, duplicates, malformed identity, and unsupported paths
fail before store/provider access. `FLATPAK_ID`, `HOME`, and `XDG_DATA_HOME` do
not supply identity or storage authority. The file root is the fixed
`<instance-path>/data/keybay-v2`; descriptor-relative no-follow traversal and
private leaf permissions apply. Positive `xdg-data/keybay-v2` filesystem grants
and grants below that subtree are rejected because they can remount host data
over Keybay's private target. The isolation claim assumes default confinement;
broader filesystem or host privileges can weaken it and are not normalized into
a generic permissions model. Changing application ID is a new identity, not an
automatic migration.

The selected provider, root location, identity source, and assurance derive from
trusted runtime facts and fixed Keybay constants. Persisted metadata may match or
conflict with that decision but never overrides it. Once any store state exists,
`open()` uses that identity-derived root or fails; it never follows an on-file
locator, falls through to another provider, creates a second store, or downgrades
its qualified assurance because the preferred service is temporarily missing.
Changing provider is outside initial V2. A future provider-change operation must
prove access to both old and new protection paths.

That continuity guarantee is scoped to a stable resolved identity, assurance,
and provider profile. On macOS, gaining or losing the Data Protection Keychain
entitlement, or changing the signed application identifier, selects a different
identity or profile. Initial V2 does not infer a relationship, scan the other
provider, or migrate state. A clean new profile may therefore initialize while
old-profile state remains unreachable. An application that needs continuity
must reset through the old profile before shipping the transition; otherwise it
is deliberately starting a new application store. Preventing or migrating such
a transition would require durable cross-profile authority and is outside V2.

### Stable platform-root count and compromise boundary

Keybay creates or obtains one long-lived platform root per host application and
keeps records, salts, KDF parameters, nonces, and sealed key-package bytes in the
application's store file. On Android this means one Keystore key and one
independent `Kstore`, not one Keystore object per record. Exportable root bytes
from Keychain or Secret Service are operation-lived and are not retained by an
open session.

Keeping `Kstore` separate from the app-root key preserves a common container
format, permits content-key rotation, and avoids using a provider key directly
for bulk data. It is not compartmentalization against compromise of the same
application: an attacker who can use or copy the platform root and read the file
can recover that application's platform-only store. A configured passphrase
remains additionally required. Because the root is long-lived, a copied
exportable root remains useful against future platform-only files until a future
provider-change or root-rotation operation replaces it.

### Linux guidance without a compulsory passphrase

Keybay must not silently imply that `application_id` attributes in Secret
Service are ACLs. On an ordinary unlocked desktop session, unrestricted code
running as the same user may be able to query or alter those items. Restrictive
file permissions do not separate processes with the same UID.

V2 nevertheless keeps passphrases optional. Developer tools often need
unattended process injection and intentionally accept the login session as their
trust boundary; established desktop secret libraries offer a similar baseline.
Keybay should not make those workflows interactive by policy.

Instead:

- the CLI gives conservative additional-protection guidance during setup and
  every platform-only store access, without requiring a public platform
  inspection API;
- SDK documentation places the limitation next to store creation and reads;
- password-manager and human-credential examples enable a passphrase; and
- Keybay never markets ordinary Secret Service storage as application-private.

This is a conscious ergonomics/security choice, not an assertion that the
platform limitation is harmless.

## Internal platform classification

Security remains multi-dimensional: identity assurance, file isolation, key
isolation, measured hardware protection, and per-access user presence are
separate facts. Each platform adapter must qualify those dimensions internally
and use them for warnings, documentation, and support claims. It must never
collapse them into one `secure` boolean.

Authenticated callers use `session.auth.list()` to learn the configured
additional methods. V2 exposes no public inspection or general capability
surface. First use is reported by `session.wasInitialized`; provider and state
failures use typed errors; platform-specific security guidance is documented
and qualified independently.

Qualification and any future richer capability API follow these rules:

- a hardware-protection claim requires a platform API that reports the actual
  generated key's security level; a provider brand is not evidence;
- `osEnforced` requires a trusted platform observation, not a user-controlled
  environment variable;
- file isolation and key isolation remain separate facts;
- a per-access user-presence claim requires a provider policy that gates every
  unwrap; a device lock, login session, or possible prompt is not enough;
- a passphrase policy is not proof of passphrase strength or live human
  presence; and
- unknown remains unknown rather than being upgraded to the hoped-for result.

If structured capability reporting is later exposed, it requires a separate API
review and must preserve the evidence-backed dimensions above. The V2 API's
atomic caller-held protection assertion remains
`Keybay.open(credential: ...)`: it refuses an existing platform-only store
rather than silently ignoring the supplied credential. Keybay does not impose a
universal Linux passphrase requirement.

## Failure behavior

The following conditions are distinct `KeybayErrorCode` values. The descriptive
PascalCase labels below map directly to the normative lower-camel enum members,
for example `AuthRequired` is `KeybayErrorCode.authRequired`:

- `ApplicationIdentityUnavailable`: no authenticated identity or embedded
  declaration can be resolved.
- `PlatformProtectorUnavailable`: the required platform provider is absent.
- `PlatformProtectorLocked`: the provider exists but will not currently open.
- `PlatformInteractionRequired`: the provider could continue only by presenting
  UI that this operation did not explicitly authorize.
- `PlatformOperationFailed`: the selected provider failed an operation for a
  reason not represented by a narrower platform error; no raw provider cause is
  exposed.
- `PlatformKeyInvalidated`: encrypted state exists but its required stable
  platform root or sealing capability is missing or unusable.
- `StorageOperationFailed`: a common encrypted-store operation, including KDF,
  file, lock, flush, or atomic replacement work, failed for a reason not
  represented by a narrower error. Callers may retry; raw causes remain hidden.
- `EntropyUnavailable`: the cryptographically secure random source failed; no
  initialization or mutation is committed.
- `AuthRequired`: the authenticated policy requires an unlock method but none
  was supplied.
- `ProtectionMismatch`: the caller supplied or required an unlock method that
  the existing store does not use.
- `UnlockFailed`: passphrase verification, key-package authentication, or a
  protection-context check failed without leaking secret material.
- `AuthMethodAlreadyConfigured`: `add` targeted a singleton method already
  present.
- `AuthMethodNotConfigured`: `update` or `remove` targeted a method not present.
- `ResetIncomplete`: reset began but one or more identity-derived store
  artifacts could not be removed; no replacement state was initialized and the
  caller may retry `Keybay.reset()`.
- `StoreAuthenticationFailed`: the key package, sealed manifest, exact-frame
  digest, or selected frame AEAD did not authenticate.
- `UnsupportedStoreVersion`: a newer or unknown format was found.
- `StoreStateConflict`: multiple or conflicting generations cannot be reconciled
  safely.
- `StoreBusy`: the interprocess lock could not be acquired under the bounded
  platform policy.
- `StaleSession`: the session no longer matches the current key epoch and must
  clear its key material.
- `SessionClosed`: an operation was attempted after closing began.
- `InvalidRecordKey`: a caller-supplied key violated the canonical grammar.
- `InvalidRecordEncoding`: `get` found bytes that are not strict UTF-8.
- `LimitExceeded`: a bounded input or decoded structure exceeded a published
  limit.
- `InvalidAuthInput`: authentication input was empty, oversized, or otherwise
  invalid before derivation.

Errors never contain a passphrase, key, record value, decrypted provider output,
or raw subprocess output. A caller may receive the record name it supplied, but
diagnostics should avoid exposing names from an unauthenticated container.

If a store file exists and its platform root is missing, Keybay does not
generate a replacement root. If a root exists and the live file is missing,
Keybay does not silently initialize a new empty store. Explicit recovery or
deletion is required in either direction. An
initialization staging file is never authoritative and is not resumed
automatically. Root-only, file-only, and stage-only states fail closed until
deliberately reset. The sole non-destructive cleanup is `open()` removing the
fixed staging artifact beside a live file after authenticating that live file's
bootstrap and key package. A malformed or unauthenticated live-plus-stage state
fails closed without cleanup, and no diagnostic or existing-session mutation
performs this recovery.

`Keybay.open()` may initialize a store only on total Keybay-state absence. Once
the session exists, reads and deletion do not perform further initialization.
On a `namespaceOnly` platform, complete deletion of both file and platform root
can be indistinguishable from a first installation without an external anchor.
Keybay must not claim that it can detect that form of denial of service.

### Clearing records and resetting

An authenticated session can remove every record without removing the store:

```dart
await session.clearAll();
```

`clearAll()` takes the interprocess lock, authenticates the latest manifest,
verifies every source frame's exact ciphertext digest without decrypting record
values, and atomically commits a zero-frame snapshot with a canonical empty
manifest. It preserves `Kstore`, the stable platform root, every configured
unlock method, and the session. A stale session fails before mutation. Like
individual deletion, it does not claim erasure from copied generations,
backups, snapshots, swap, or flash media.

Complete local removal is deliberately separate:

```dart
await Keybay.reset();
```

`reset()` resolves the current application identity itself and accepts no
application, path, provider, or store selector. Under the same interprocess lock
it first prepares the qualified provider reset without mutation. The file adapter
then makes that identity's authoritative live target unavailable as its first
managed-file mutation, before removing staging or recovery artifacts. Once that
revocation point is reached, Keybay attempts both remaining file cleanup and the
prepared provider commit even if either is incomplete. Provider commit may delete
or invalidate the identity-derived platform root. Targets are derived from
trusted runtime identity and fixed Keybay constants, never public file metadata
or provider continuation state. The operation initializes nothing; calling it
again after complete removal succeeds without initializing a store. The POSIX
adapter retains its fixed nonsecret coordination lock and containing directory;
unlinking a lock while another process holds it could split mutual exclusion
across different inodes.

Every connected provider must establish a safe reset-and-reinitialize contract
during qualification. A provider that cannot do so is not an available Keybay
profile. Flatpak intentionally retains its portal-owned application secret:
the portal exposes no deletion API. Reset removes the encrypted store and staging
while retaining nonsecret coordination locks. The next successful open generates
a fresh random `Kstore`. Restoring
an older complete encrypted store under the same identity, profile, file domain,
and portal secret can restore access, with its old passphrase still required
when configured. This is the documented rollback limit, not root revocation or
forensic erasure.

Reset does not require a session or unlock credential. This is intentional: it
is the recovery path for a forgotten passphrase, invalidated root, corrupt file,
or partial initialization. It authorizes denial of service, not disclosure.
Code executing as the host application is already inside Keybay's trust
boundary, while a `namespaceOnly` same-user attacker who can reach both storage
locations can already delete them directly. The method name is the SDK's
compile-site warning; a confirmation enum would not add authentication or a
security boundary. Interactive hosts, including the Keybay CLI, must provide
their own deliberate human confirmation before calling it.

Reset invalidates sessions registered with the same Keybay runtime. It cannot
erase `Kstore` from another isolate or process that already opened the store. An
operation that pinned the old live generation before the file-revocation point
may finish from that pin; an operation that attempts to pin afterward fails
closed. The other runtime retains any key or plaintext already in memory until
its own lifecycle clears it.

File and deletable platform-provider state cannot be one atomic transaction.
Provider preparation performs its runtime checks before mutation and may invoke
trusted provider UI. Cancellation or failure there leaves managed state
unchanged. Flatpak needs no portal call to prepare or commit its file-only reset.
A file failure before the live-revocation point changes no managed
artifact and does not commit the prepared provider operation. Once revocation
begins, every incomplete result is `ResetIncomplete`; the live target is no
longer authoritative, Keybay attempts the remaining fixed cleanup steps,
initializes nothing, and retrying reset is safe. Neither `clearAll()` nor
`reset()` promises forensic erasure or universal platform-root rotation.

## Future format and provider changes

Because Keybay V2 is pre-launch, the implementation has no prior-version
compatibility milestone. Normal `Keybay.open()` considers only V2 state for the
resolved application.

An incompatible future format change, platform-provider change, or application
identity transfer requires a separate reviewed design with explicit authority
over both sides and an atomic encrypted rewrite. None is part of initial V2.
Changing unlock policy uses the single-file rotation transaction described
above.

## Threat model

### Defended when the platform capability supports it

- Offline inspection of a copied store file without its platform root or sealing
  capability.
- Modification of the sealed manifest or any selected record frame without
  detection. Mutations additionally verify every source frame's exact
  ciphertext digest before committing a replacement snapshot.
- Access by a different OS user under normal filesystem and credential-store
  permissions.
- Access by a peer mobile or sandboxed application where the OS or portal
  authenticates application identity and isolates both key and file.
- Disclosure of an exportable platform root to same-user code when a strong,
  unobserved passphrase remains required.
- Path traversal and malformed storage selectors through validated identity and
  record-key derivation.
- Reduced accidental namespace collision through stable declared IDs; this is
  not protection from a deliberate duplicate declaration.

### Not defended, or defended only partially

- Malicious code running inside the host application.
- Unrestricted root/kernel/administrator access.
- Same-user host malware on `namespaceOnly` platforms when no passphrase is
  enabled.
- Same-user keylogging or memory inspection while a passphrase-protected command
  is active.
- Disclosure of all record names from the transient decrypted manifest while a
  key operation is active. Unrelated record values are not decrypted.
- Correlation of unchanged frame ciphertext and approximate changed-frame sizes
  by an observer retaining successive complete store snapshots.
- Deletion and denial of service where the attacker can modify the relevant
  credential store or filesystem.
- Complete store substitution or rollback where every available trust anchor is
  same-user writable.
- Deliberate namespace aliasing by a second program that embeds the same
  declared ID on a `namespaceOnly` platform.
- Weak passphrase guessing after an attacker captures the KDF envelope.
- Continued use of a copied exportable platform root against later
  platform-only files until a future root-rotation or provider-change operation
  replaces it. Current passphrase-protected files still require their current
  passphrase.
- Secrets deliberately printed, exported, placed in an environment, or handed
  to a child process by the application or CLI.

The [companion CLI RFC](0002-cli-tui.md) narrows plaintext lifetime by
requiring the passphrase on each store-accessing command and by keeping
interactive browsing in one foreground TUI. That improves exposure windows but
does not change these platform boundaries.

## Alternatives considered

### Runtime `appId`

Rejected for the production SDK. It is convenient but makes cross-application
selection look supported and confuses a namespace with authenticated identity.
Build metadata is the fallback for arbitrary Dart executables.

### Multiple named stores

Rejected for V2. Most applications need one protection and lifecycle domain;
names add management commands, collision rules, key-store entries, and choices
without creating additional OS principals. Key prefixes cover organization.

### Store records directly in each native credential store

Rejected for the V2 common model. It creates materially different enumeration,
format-evolution, passphrase, and record-update behavior per platform and can
require a credential-store item per secret. One encrypted container lets the
platform protect the small thing it handles best: one wrapping root.

### Store the changing key package directly in the platform provider

Rejected for V2. It makes every passphrase add, update, or removal a transaction
across both the credential provider and encrypted file. A stable platform root
provides the same outer platform protection while allowing the changing package,
policy, key epoch, and records to commit in one atomic file replacement.

### One whole-store authenticated-encryption payload

Rejected for V2. It has the smallest codec, but every key-oriented read places
all record values in plaintext memory and every mutation decrypts them together.
The selected framed snapshot adds one sealed manifest and independently sealed
record messages while preserving the same one-file lock, staging, flush, and
atomic-replace transaction. It does not add an encrypted database, in-place
updates, a journal, or compaction. A whole-payload rewrite would also hide which
ciphertext remained unchanged across snapshots; V2 accepts that longitudinal
metadata leak in exchange for selective plaintext and authenticated
copy-forward.

### Passphrase-derived content key

Rejected. It would make platform protection optional, tie every passphrase
change to the primary content key by definition, and encourage weak passwords
to become the only at-rest secret. `Kstore` is random; Argon2id wraps it inside
the mandatory platform layer.

### Mandatory passphrase on ordinary Linux

Rejected. It would improve one threat boundary but break legitimate unattended
developer workflows and create a false appearance of protecting an actively
compromised session. Keybay instead reports the missing application isolation,
strongly recommends a passphrase for human secrets, and lets an application
assert that policy by consistently opening with `PassphraseCredential`.

### Executable path, filename, or hash as identity

Rejected. Paths and filenames change under installation and relocation; hashes
change on every update. All create surprising empty stores and none proves a
stable application principal.

## Security references

- [Apple keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
  describe the code-signing-enforced application-identifier and access-group
  rules used by iOS and Data Protection Keychain apps.
- [Apple's macOS keychain note](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)
  distinguishes access-group-protected Data Protection items from legacy
  file-keychain ACLs. [`SecKeychainOpen`](https://developer.apple.com/documentation/security/seckeychainopen%28_%3A_%3A%29?language=objc),
  [`kSecUseKeychain`](https://developer.apple.com/documentation/security/ksecusekeychain),
  and [`kSecMatchSearchList`](https://developer.apple.com/documentation/security/ksecmatchsearchlist)
  provide the explicit file-Keychain targeting used by the unentitled profile;
  it never relies on the user-configurable default Keychain.
- [Android app-specific storage](https://developer.android.com/training/data-storage/app-specific)
  and [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
  define the private file and non-exportable-key primitives used by the Android
  row; actual key level comes from
  [`KeyInfo.getSecurityLevel()`](https://developer.android.com/reference/android/security/keystore/KeyInfo#getSecurityLevel()).
- The [Secret Service specification](https://specifications.freedesktop.org/secret-service/latest-single/)
  defines login-session collections and explicitly permits provider-dependent
  client unlock behavior; attributes are lookup metadata, not Keybay app ACLs.
- The [XDG Secret portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html)
  returns a stable per-application secret to a sandboxed caller and may return
  an identifier that must be supplied on the next call; version 1 defines no
  atomic transaction with an application's local file. Its shared
  [Request contract](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Request.html)
  permits user interaction and cancellation; it has no noninteractive retrieval
  option or secret deletion method. Keybay therefore limits portal retrieval to
  interaction-permitted operations and retains the secret after reset.
- [Flatpak metadata](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-metadata)
  describes the running sandbox's identity and instance storage facts.
  [Filesystem permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
  describe grants that can expose host data or remount XDG subdirectories.
- [Snap confinement](https://snapcraft.io/docs/explanation/security/snap-confinement/)
  distinguishes strict confinement from classic and development modes.
- [Windows DPAPI](https://learn.microsoft.com/en-us/windows/win32/seccrypto/example-c-program-using-cryptprotectdata)
  is user-and-machine scoped by default, which is why it is not treated as an
  ordinary Win32 application ACL.
- [RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.html) specifies Argon2id and
  its versioned password-KDF inputs.
- [OWASP Cryptographic Storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)
  recommends authenticated encryption, CSPRNG-generated keys and nonces,
  separation of data-encryption and key-encryption keys, and the simpler
  re-encryption path when rotating keys where feasible.
- [restic's pack format](https://github.com/restic/restic/blob/master/doc/design.rst)
  uses independently encrypted and authenticated blobs plus an encrypted tail
  header, explicitly permitting ciphertext reorganization without decryption.
- [Apache Parquet modular encryption](https://github.com/apache/parquet-format/blob/master/Encryption.md)
  uses encrypted footer metadata, independently authenticated modules, and
  module-specific AAD to support selective decryption without ciphertext
  substitution.
- [libsodium's XChaCha20-Poly1305 guidance](https://doc.libsodium.org/secret-key_cryptography/aead/chacha20-poly1305/xchacha20-poly1305_construction)
  supports safely generated random nonces for independent messages; Keybay's
  copied frames reuse bytes, never a nonce for a new encryption operation.
- Dart permits namespaced custom
  [pubspec fields](https://dart.dev/tools/pub/pubspec), while
  [`dart compile exe`](https://dart.dev/tools/dart-compile) accepts the
  compile-time environment declarations used by Keybay's controlled build
  helper. [`dart install`](https://dart.dev/tools/dart-install) retains the
  source pubspec and lockfile in its AOT application bundle.

## Implementation milestones

Milestones are ordered security gates, not release dates. Work on later fakes,
terminal adapters, or provider bindings may proceed in parallel, but no platform
profile may persist V2 user state until the common gates through M6 and that
profile's M7 qualification gate have passed.

### M0 — Contract freeze

Reconcile this RFC and RFC 0002 with the normative public API, the internal
platform boundary, the one-store model, and the initial platform matrix.

Exit gate: the examples type-check as API fixtures; no stale public API remains;
every unresolved item below has an owning milestone or is explicitly deferred.

### M1 — SDK state model

Implement the public facade, typed errors, session lifecycle, string and byte
record APIs, exact-key `getManyBytes`, auth CRUD semantics, and injected
in-memory test storage. A non-production harness exercises the real public
session, exception, credential, and redacted method types without making their
constructors or backend selection part of the production API. This milestone
writes no persistent V2 data.

Exit gate: lifecycle, synchronous input snapshotting, byte ownership, UTF-8,
auth cardinality, opaque method IDs, close, and error-redaction tests pass.

### M2 — Host identity and platform boundary

Implement `ResolvedHost`, `StoreFiles`, `PlatformProtector`, software test
protectors, the provider conformance harness, and build-embedded identity for
supported Dart run modes. Resolve each host binding once; the store engine must
contain no platform selection or fallback.

Exit gate: tests prove identity, path, protector, and reset targets cannot be
mixed or redirected by persisted bytes; the same program resolves the same
declared identity under supported Dart source, legacy activation,
`dart install`, and controlled AOT modes. Package-test and unrecognized AOT
runners prove their documented fail-closed behavior. Signed and packaged
profiles instead prove their platform identity in their qualified build modes.
Provider state is final before package AAD is
built, cannot rotate during open, and reports the creation disposition needed by
the shared state machine. Launches with different candidate file roots but the
same provider identity must resolve the same committed storage domain or fail
with `StoreStateConflict`; tests must prove they cannot initialize two valid
stores. iOS additionally proves that relocating a complete application container
preserves record and passphrase access, while a relocated empty container with
retained provider state still refuses initialization.

### M3 — Format and KDF freeze

Freeze the bootstrap, platform-sealed package, record frame, tail manifest, and
trailer encodings; domain labels; AAD; nonces; frame commitments; parser limits;
passphrase-package representation; and KDF parameter bounds.

Exit gate: a new V2 magic/version, fixed cross-language vectors, adversarial
fixtures, dependency review, and independent cryptographic format review are
complete. No production V2 writer exists before this gate.

The M3 implementation receipt is the two internal, I/O-free modules
`format/store_format.dart` and `format/store_crypto.dart`, plus
`test/vectors/v2_suite1.json`. The fixture was reproduced independently with
Go's `x/crypto/chacha20poly1305`, `crypto/hmac`, and `crypto/sha256`; the
retained reference is `tool/v2_suite1_reference_go`. The published RFC 9106
vector separately anchors Argon2id. These modules accept no entropy source,
path, provider selector, lock, or persistence dependency.

### M4 — Framed reader

Implement bounded bootstrap/package parsing, package opening through the test
protector, manifest authentication, `contains`, `get`, `getBytes`, and
`getManyBytes` against pinned file generations.

Exit gate: only selected values decrypt; every malformed length, digest,
encoding, limit, generation mix, and authentication failure returns no partial
plaintext and performs no unbounded allocation.

The M4 read-path receipt now lives in the internal `V2StoreEngine`, the minimal
`PinnedStoreFile` capability, and the disposable framed-store fixtures.
`openPlatformOnly()` authenticates only the bounded bootstrap and exact sealed
key package. Each later operation pins one immutable generation, authenticates
its manifest, and reads only selected frames; operations accepted by one
session are serialized and `close()` drains them before clearing `Kstore`.
Baseline and adversarial suites cover selective reads, byte ownership, strict
UTF-8, bounds, authenticated corruption, no partial result, cleanup, and both
sides of live-file replacement. Cleanup-failure injection proves that partial
plaintext is erased and withheld, every acquired resource is closed, and a
primary operation failure keeps precedence. At the M4 gate the engine remained
internal and read-only: it used the transaction lock only to classify artifacts
and pin the initial generation. M5b subsequently evolves that same owner rather
than wrapping it.

### M5a — Transaction boundary

Freeze the lock-scoped `StoreFiles` transaction capability, live/staging
classification, provider seal-output contract, prepared reset failure phases, and
injected CSPRNG boundary. Record—but do not yet implement—the sole production
session owner and isolate-local invalidation constraints for M5b. Add the common
secure entropy adapter, disposable contract fakes and lifecycle tests, and
lock-scoped M4 open classification.

Exit gate: tests prove fixed identity-derived targets, exclusive transaction
ownership, create-only bounded staging, live-only reads during active staging,
pre-existing staging is never adopted, conforming provider seal outputs are
independently backed and within the fixed bound, and entropy failure is
deterministic. Cleanup tests prove automatic stage abortion, capability expiry,
verification-pin cleanup, lock release, and primary-error precedence.

The M5a implementation receipt is the internal `StoreTransaction`,
`StagedStoreFile`, and `V2EntropySource` contracts plus disposable tests. It
creates, stages, replaces, mutates, or resets no production state and leaves
`Keybay.open()` unavailable. The existing M4 session is the lifecycle that M5b
evolves; M5b may not wrap it in another production session.

### M5b — Persistent mutation

Implement create-only initialization, copy-forward `set`/`setBytes`, deletion,
`clearAll`, interprocess locking, ciphertext staging, flush, durable atomic
replacement, and the qualified reset state machine.

Exit gate: fault injection proves old-or-new complete state, no plaintext
staging, no lost concurrent update, authenticated live-plus-stage cleanup during
`open()`, and fail-closed root-only, file-only, stage-only, malformed
live-plus-stage, and partial-reset behavior.

The M5b implementation receipt is the internal `V2StoreEngine` and
`V2StoreSession`, the operation-local framed writer, and the prepared file-first
reset protocol. First use creates and verifies a complete encrypted empty
snapshot before returning. Mutations authenticate the latest manifest under the
interprocess transaction, hash every exact source frame, copy unchanged
ciphertext byte-for-byte, verify the complete stage, replace atomically, and
verify the committed generation. Reset prepares its fixed provider target
without mutation, makes the live file unavailable first, marks same-runtime
sessions invalid, then commits provider removal and drains those sessions after
releasing the transaction lock.

Disposable engine and adversarial suites cover first-use state conflicts,
initialization failure points, copy-forward identity, every source-frame digest,
record limits, staging corruption, pre/post-replacement faults, contention,
reset failure phases, retry, and pinned-read/queued-write linearization. These
tests qualify common-engine ordering and old-or-new handling; actual filesystem
locking, flush, atomic replacement, directory durability, and provider behavior
remain per-profile M7 gates. At this milestone the public `Keybay` runtime
remained unavailable.

### M6 — Passphrase credentials and rotation

Implement passphrase open, add, update, remove, Argon2id, full `Kstore` rotation,
method-ID continuity, and stale-session behavior.

Exit gate: every auth change is one atomic complete-file replacement; every
record is resealed under the new epoch; an old envelope cannot open a future
generation; peer sessions fail closed; secrets and errors satisfy the memory
and redaction contract.

The M6 implementation receipt is the injectable, isolate-serialized
`V2PassphraseDeriver`, Argon2id profile 1, strict protected-open state machine,
and operation-local framed rotation used by `V2StoreSession`. Auth add, update,
and removal each create a fresh `Kstore`, advance the epoch, verify every source
frame, decrypt and reseal one value at a time, authenticate the complete staged
snapshot, atomically replace it, and only then advance the owning session.
Verified post-replacement failures adopt the committed key; indeterminate
outcomes immediately invalidate affected sessions.

Disposable lifecycle and fault suites cover the open matrix, method-ID
continuity, wrong and superseded passphrases, early credential release, full
frame resealing, same-runtime and separate-engine stale sessions, opens racing
rotation, pre-replacement rollback, verified post-replacement adoption,
indeterminate replacement, and credential-free reset. The production runtime
remained unavailable through M6.

### M7 — Platform profiles

Connect and qualify one complete profile at a time through the common
conformance suite. Recommended order is macOS unentitled/CLI, Android, ordinary
Linux Secret Service, iOS, and entitled macOS. Android appears early to prove
the boundary with a non-exportable root.

Exit gate per profile: signed or packaged identity evidence, fixed
identity-derived targets, provider create/open/reset behavior, operation-specific
interaction and failure classification, invalidation, concurrency, durable replacement, and
platform-only plus passphrase integration tests all pass. The fixed Argon2id
profile also passes AOT latency and peak-memory measurements on that profile's
maintained device classes. Profiles whose file location can vary independently
of provider identity also prove the
M2 one-binding invariant against their real provider. Flatpak, strict Snap, and
Windows remain unadvertised as qualified until their profiles qualify. The
Flatpak candidate follows the interaction contract above, retains the portal
secret after reset, and never falls back to raw Secret Service. Its hermetic
tests cover token rejection, bounded responses, timeout, cancellation, reset,
passphrase changes, concurrency, and prompt-free record operations.

The macOS unentitled/CLI candidate is the first M7 implementation slice. It now
has a descriptor-relative production file adapter rooted at one leaf beneath a
pre-existing durable parent, effective-account home resolution that ignores
process environment routing, an explicit login-Keychain adapter, one immutable
host binding shared by both sides, and opt-in end-to-end tests through the real
login Keychain and framed file. Provider
records commit the file-domain digest, use create-only/read-back semantics, and
are read with a fixed Dart-allocation bound. Reset prepares and revalidates the
fixed record before deletion. Classic file Keychains do not enforce the
Data Protection Keychain's per-call UI-failure option, so all root acquisitions
and prepared resets require interaction permission before native access. No
process-global UI setting is changed. They also expose no atomic
compare-and-delete, so an already-authorized same-user process can still
race that final provider mutation as denial of service. This does not create a
new confidentiality boundary and is part of the profile's stated same-user
tampering limit.

The ordinary Linux candidate is now connected through the same common engine.
It derives one canonical XDG data root, securely creates only a known missing
directory suffix with descriptor-relative no-follow operations, and binds that
root to one identity-derived Secret Service record. Its exact-pinned raw D-Bus
adapter uses typed byte arrays and only the fixed `SearchItems`, plain
`OpenSession`, `GetSecret`, `ReadAlias`, `CreateItem(replace=false)`, exact-item
`Delete`, and `Session.Close` calls. It never invokes protocol prompts, unlocks,
or collection creation. Zero, one, locked, and duplicate search results remain
distinct; root reads are bounded to 4096 bytes; create adopts only an exact
readback. An absent default collection is unavailable; only an actual returned
non-root prompt path is interaction-required. Each operation owns a fresh
connection and one total timeout. Its lifetime guard prevents a late method
reply from authorizing a subsequent `CreateItem` or `Delete`; a method already
sent when the deadline fires remains indeterminate. First creation uses a
fixed-name, descriptor-relative lock beneath private `XDG_RUNTIME_DIR`, with a
10-second bounded acquisition and ABI-correct no-follow/close-on-exec flags.
Contention maps to public `StoreBusy`.

Reset re-searches for one unlocked match at the exact observed object path
before `Delete` and verifies absence afterwards. Secret Service has no atomic
compare-and-delete, so an already-authorized same-user actor may still replace
that object between the final validation and deletion. This can cause or win a
denial-of-service race under the profile's already-stated same-user tampering
limit; it does not weaken record or store confidentiality. Hermetic transcript
tests retain these method, signature, cleanup, locked, duplicate, and race
rules. Opt-in gnome-keyring tests exercise raw root create/read/delete and the
public `Keybay.open`/reopen/passphrase/reset path with production identity and
XDG resolution, including clean-account directory creation, encrypted
persistence across processes, a conflicting second XDG root, and proof that
pre-V2 state is neither adopted nor removed.

By explicit cutover authorization on 2026-09-02, the public production runtime
now selects connected V2 profiles on Android, iOS, macOS, and ordinary Linux.
Entitled macOS uses one provider profile across sandboxed and unsandboxed file
locations, so a sandbox-mode path transition conflicts with the existing
domain rather than creating another platform root.
The 2026-09-04 contract revision permits trusted provider interaction during
open, authentication changes, and reset, and authorizes the Flatpak candidate
with an ambient portal root. This supersedes the earlier noninteractive-only
restriction and Flatpak deferral. Qualification remains separate from connection.
Snap and unsupported platforms remain unavailable. Every runtime arm reads only
V2 state: it does not enumerate,
adopt, migrate, or fall back to V1, and it never substitutes process memory.

Activation is not a claim that release qualification is complete. Before a V2
release, retain the signed/unsigned ACL and update-continuity matrix, supported
macOS-version login-Keychain-path checks, locked/interaction classification,
real multiprocess and crash-boundary evidence, and the maintained-device AOT
Argon2id latency and peak-memory matrix.

An initial non-gating AOT observation on 2026-09-01 used the profile-1 KDF on
one arm64 macOS 26.2 host: 215 ms derivation time, 178,339,840 bytes maximum
resident set size, and 168,707,904 bytes reported peak memory footprint. Those
whole-process figures include the Dart runtime. They establish feasibility on
this host only; they do not replace the maintained-device qualification matrix.

### M8 — CLI and release integration

Complete RFC 1's SDK packaging, identity, adversarial format, real-provider,
device evidence, and independent security review before resuming RFC 0002's
remaining CLI work and Fleury TUI. Existing CLI behavior still needs its own
contract and release validation; it is not evidence that the SDK is qualified.

Exit gate: every shipped claim maps to retained evidence, and release
documentation changes only when V2 is actually qualified and cut.

Because Keybay is pre-launch, M8 removes the pre-V2 SDK and CLI compatibility
surface before release. It implements no persisted-state transfer path.

CLI/TUI implementation is deferred while the SDK gates are completed. A richer
public capability surface, additional hardware
methods, rollback anchors, and platform-root rotation are not prerequisites.

### Current execution scope

The common engine, SDK, ordinary profiles, and Flatpak candidate implementation
are authorized. Flatpak follows the revised lifecycle contract above. CLI/TUI
work remains deferred while the SDK and RFC 1 release evidence are completed.
Implementation, a passing local suite, and a configured CI lane do not by
themselves establish a qualified release or authorize broader platform claims.

## Milestone-owned and deferred decisions

The following details remain intentionally unresolved until their owning gate:

- **M2:** fixed identity-derived file/provider locations for each future real
  profile and completion of the generic cross-root initialization proof. The
  interface, application-ID grammar, narrow pubspec parser, supported Dart
  launch matrix, controlled AOT embedding, binding commitment, and provider
  scope are fixed above.
- **M5b:** root-only, file-only, first-use, partial-reset, provider-reset, lock,
  flush, rename, and directory-durability contracts.
- **M7:** each qualified provider's sealing lifecycle and aliases; unentitled
  macOS Keychain ACL continuity across source, ad-hoc, signed, update, and
  binary-replacement modes; minimum iOS and macOS versions; confirmation or
  revision of Android's API 31 floor; and AOT latency and peak-memory
  qualification of the fixed Argon2id profile on each maintained device class.

The following are explicitly deferred beyond the initial V2 implementation:

- platform-root rotation;
- rollback detection using platform monotonic anchors;
- multiple simultaneous alternative unlock methods and hardware credentials;
- Strict Snap qualification; and
- packaged and unpackaged Windows profiles.

Deferral does not permit a plaintext key fallback, runtime store selector,
implicit provider downgrade, or claim stronger than measured platform evidence.

## Persistent implementation completion criteria

The session API and in-memory scaffolding may begin under the milestones above.
A persistent production backend is not complete or eligible for
an accepted security claim until:

- the canonical bootstrap-header, sealed key-package, record-frame, tail
  manifest, and trailer formats have independent cryptographic review and fixed
  vectors for every derived key and authenticated context;
- nonce tests prove a fresh nonce or IV for every newly sealed package,
  manifest, and changed frame under a long-lived key, reject reuse in
  deterministic fixtures, distinguish byte-for-byte frame copying from a new
  encryption operation, and fail without committing when secure entropy is
  unavailable;
- identity resolution has fixtures for every maintained run/package mode;
- every cell in the `Keybay.open()` first-use matrix has tests, and initialization
  uses create-only semantics for Keybay-managed roots, verifies its encrypted
  staging file before commit, refuses every unsupported root-only, file-only,
  stage-only, or conflicting pre-existing state, and recovers only an authenticated live
  bootstrap and key package beside the fixed staging artifact by durably
  discarding that artifact under the same exclusive lock;
- `open()` decrypts no manifest or record frame and retains only `Kstore` plus
  minimal authenticated session metadata;
- `session.auth.list()` reflects the authenticated additional-method set,
  updates atomically after successful session-owned policy changes, and is
  rejected with a failed `SessionClosed` future after closing begins;
- `close()` is asynchronous and idempotent, rejects new operations, settles
  in-flight work, clears session-owned key/plaintext buffers best-effort, and
  leaves no operation running after it completes; tests acknowledge that a
  previously settled caller-owned result may be awaited afterward;
- values returned by `getBytes` and `getManyBytes` are fresh, independent,
  caller-owned buffers; Keybay retains no aliases, imposes no disposal contract,
  and string operations do not claim zeroization;
- every named failure maps to its stable `KeybayErrorCode`, while exception
  messages and `toString()` remain redacted and raw provider causes never cross
  the public boundary;
- byte-ownership tests cover `setBytes` and `PassphraseCredential` synchronous
  snapshots, caller mutation after operation entry, construction and
  abandonment of `PassphraseCredential` without a Keybay-owned secret copy,
  independent read results, and mandatory clearing of every SDK-owned plaintext
  and key buffer on success and failure;
- Future-entry tests prove validation, lifecycle, and snapshot errors do not
  escape synchronously after argument evaluation, so callers can clear borrowed
  byte inputs immediately after receiving the future;
- key API tests cover canonical grammar rejection, missing-key results,
  delete's boolean result, strict UTF-8 decoding failure, and authenticated
  immutable `listKeys` ordering without opening any record frame;
- `getManyBytes` tests cover synchronous input snapshotting, validation, duplicate
  collapse, first-occurrence order, missing and empty results, and distinct-key
  plus consumed-element and aggregate-plaintext limits; they prove a closed
  session rejects even an empty request, an empty request opens no manifest or
  frame, only requested frames enter AEAD-open, no unrelated record value is
  decrypted, every result comes from one pinned generation during concurrent
  writes or rotation, both sides of the rotation linearization point behave as
  specified, and any failure clears produced buffers without returning a partial
  map;
- `clearAll()` tests prove it authenticates the latest manifest, verifies every
  source-frame digest without decrypting a record value, atomically commits a
  zero-frame snapshot, preserves `Kstore`, unlock methods, and the open session,
  and rejects a stale session before mutation;
- reset tests cover absent, healthy, forgotten-passphrase, invalidated,
  corrupt, and partial states; prove the operation is idempotent, initializes
  no replacement store, accepts no selector, and invalidates same-runtime sessions; and
  prove another isolate or process holding `Kstore` cannot release a result
  from an operation that attempts to pin after live-file revocation, while an
  already-pinned operation may settle from its prior generation;
- provider reset tests prove every connected provider has a qualified safe
  reset-and-reinitialize path, preparation is non-mutating, provider commit
  occurs only after live-file revocation, and a successful reset can be followed
  by first-use initialization;
- fault injection at every reset step proves only the resolved application's
  identity-derived file and platform-root artifacts are targeted, no public
  header or provider continuation state can redirect deletion, partial deletion
  returns `ResetIncomplete` and can be retried, and provider cancellation obeys
  the pre/post-mutation contract;
- the file, staging, recovery, and rotation paths never write plaintext
  artifacts; ordinary mutations verify the SHA-256 digest of every exact source
  frame, copy every unchanged frame byte-for-byte, decrypt no unrelated record
  value, and clear all SDK-owned plaintext buffers;
- format-adversarial tests cover manifest mutation; frame substitution,
  duplication, reordering, truncation, and trailing bytes; nonce, ciphertext,
  and tag mutation; digest mismatch; hostile trailer lengths; cumulative-length
  overflow; and a correctly digested but AEAD-invalid frame proving that the
  manifest digest never substitutes for frame authentication;
- frame-layout tests prove manifest entries are canonical and unique, persisted
  offsets do not exist, checked prefix sums consume the frame region exactly,
  manifest AAD binds the resolved storage domain, exact full bootstrap, and
  exact opaque sealed package, and mutation of any retained bootstrap field or
  package byte is not copied forward by an open session; common package tests
  prove package AAD binds the resolved storage domain and exact bootstrap core,
  every provider authenticates and consumes its exact blob without ignored
  suffixes, package sealing returns independent caller-owned output within the
  fixed `1..4096`-byte bound, and provider-specific tests freeze that provider's
  own serialization;
  frame AAD binds store UUID, key epoch, suite, type, and exact record key, and
  frame AAD excludes manifest-specific values, ordinal, and physical offset;
- interprocess concurrency tests prove initialization races, serialized writes,
  no lost updates, old-or-new complete file durability across power-loss fault
  points, bounded lock failure, and stale-session behavior after key rotation;
- cross-root tests launch the same resolved provider identity with different
  candidate file roots and prove one committed storage-domain binding,
  `StoreStateConflict` on mismatch, and no path that initializes two
  independently valid stores;
- each platform path has integration tests proving identity-derived root
  location, root loss/replacement, tamper, lock, collision, and partial-write
  behavior;
- the Android qualification harness reports the generated key's actual provider
  level and is exercised on maintained emulators plus retained physical-device
  evidence for hardware claims; the V2 SDK does not retain a dormant capability
  API solely for this evidence;
- Apple entitlement/access-group resolution is exercised in a signed harness;
- unentitled macOS Keychain tests cover development and signed-release creation,
  upgrade continuity, replacement, interaction-required failure, and the
  approved continuity and recovery design before that path is advertised;
- Linux tests qualify ordinary Secret Service separately from the Flatpak
  candidate and prove Snap, unsupported providers, and portal failure cannot
  fall back to raw Secret Service;
- Secret Service tests treat zero, one, and multiple attribute matches as
  absence, one root, and `StoreStateConflict` respectively, and re-query after
  create without selecting or deleting an arbitrary duplicate; they also vary
  `XDG_DATA_HOME` while retaining the same Secret Service identity and prove the
  cross-root invariant above;
- Flatpak qualification runs two installed application IDs against the real
  portal frontend and Secret backend on Linux, proves stable distinct portal
  secrets and private files, and covers restart, reset, passphrase, concurrent
  access, and failure without fallback. Nested Docker is acceptable when the
  inner Flatpak retains its own namespaces, syscall filter, and unprivileged
  identity; ordinary Secret Service or portal-only container tests do not
  establish that boundary. Evidence records the actual kernel, architecture,
  provider versions, and container configuration. Qualification also reviews the selected backend's
  random-secret generation: length and distinct outputs alone do not prove
  entropy. Raw secrets and derived challenge responses are not retained in logs
  or artifacts;
- provider tests prove record operations and `auth.list` never prompt, including
  stale-session classification; open, auth changes, and reset permit only trusted
  OS/provider UI and preserve typed cancellation and failure. Provider open
  decrypts no manifest or frame, and an existing store never changes provider;
- `session.auth.add/update/remove/list` tests prove passphrase cardinality,
  redacted `AuthMethod` values, stable opaque IDs, removal of the final
  additional method, and absence of an old unlock route; fault injection proves
  the platform root remains unchanged,
  pre-replacement failure leaves old auth, post-replacement success leaves new
  auth, every old exact-frame digest is verified against the authenticated
  source manifest before AEAD-open, a spliced older valid frame is rejected,
  every frame is decrypted and resealed one at a time under the new `Kstore`, no
  old frame is copied, and peer sessions become stale;
- `PassphraseCredential` ownership tests prove construction makes no secret copy,
  each receiving operation snapshots caller-owned bytes synchronously, every
  operation-owned copy is cleared on every success/failure path, and
  authentication material is never included in errors or `toString()` output;
- resource-limit tests reject oversized bootstrap metadata, manifests, frames,
  cumulative frame regions, values, returned-value aggregates, trailer lengths,
  provider tokens, and unknown KDF profile IDs before unbounded allocation or
  work; measured profile tuples remain within the absolute M3 caps;
- namespace-only substitution tests prove that a caller-held passphrase
  requirement rejects an attacker-created platform-only replacement, while the
  no-requirement path is documented as unable to distinguish total replacement;
- any later structured capability output matches observed isolation rather than
  packaging intent; and
- release documentation changes only after V2 qualification is complete.

# Keybay security design

This is the concise security model for the V2 implementation. The complete
normative decisions, format ownership rules, failure semantics, and milestone
gates are in [RFC 0001](rfcs/0001-per-application-stores.md).

## Security objective

Keybay protects local application secrets at rest without inventing a Keybay
account or service. Each host application gets one encrypted store. Platform
protection is always required, and an optional passphrase can make possession
of platform-accessible artifacts insufficient to recover the store key.

The design is intentionally one-way:

```text
authenticated or declared host identity
              |
              v
fixed host profile -> fixed file root + fixed platform-root location
              |
              v
platform root -> authenticated key package -> random store key
              |
              v
encrypted manifest + independently encrypted record frames
```

No public call selects an identity, path, provider, backend, or alternate
store. No failure reaches plaintext, process-memory storage, another provider,
or pre-V2 data.

## Threat model

Keybay is designed to resist:

- disclosure from copied encrypted files, backups, or dotfile repositories;
- other OS users lacking the application's platform/file authority;
- accidental cross-application namespace collisions;
- corruption, wrong keys, frame substitution, truncation, and malformed input;
- lost updates and split initialization across processes; and
- recovery of a passphrase-protected store from platform artifacts alone.

It does not claim to resist:

- root/kernel compromise or an attacker injected into the host process;
- a keylogger, screen capture, terminal compromise, or a malicious Keybay
  binary;
- plaintext disclosure after the application explicitly reads a value;
- deletion by an actor able to modify both provider state and application
  files;
- rollback to an older complete authentic snapshot; or
- reliable zeroing of every Dart VM, OS, or immutable-string copy.

Ordinary unsandboxed Linux and unentitled macOS have a further limit. Their
declared application namespace is not an authorization boundary. A same-user
program may claim it and may reach the login credential store and files. A
Keybay passphrase prevents those artifacts alone from yielding the store key;
it cannot prevent denial of service by an actor with the authority to delete or
replace them.

## Security guarantees

These invariants are claims only where the named platform configuration has
matching executable or retained qualification evidence.

| Invariant | Guarantee |
|---|---|
| `KB-INV-001` | Keybay-managed persistent data artifacts do not contain plaintext record values or passphrases. |
| `KB-INV-002` | Copying the encrypted store without its separately platform-protected root is insufficient to recover records; configured passphrase protection additionally requires that passphrase. |
| `KB-INV-003` | Missing identity/key material, unsupported versions, corruption, and authentication failure fail closed without returning plaintext or silently creating replacement state. |
| `KB-INV-004` | Process, lock, reboot, reinstall, backup, transfer, and restore behavior matches the documented policy for the qualified platform configuration. |
| `KB-INV-005` | Keybay reports only protection properties established by the running platform and never infers hardware backing from an API or provider name. |
| `KB-INV-006` | Identity, provider, entitlement, confinement, and storage transitions never select a weaker fallback or present abandoned state as a fresh empty store. |
| `KB-INV-007` | Concurrency, interruption, malformed input, and native-boundary stress preserve confidentiality, integrity, bounded resource use, and typed failure behavior. |
| `KB-INV-008` | Backup, synchronization, and cross-device transfer behavior matches the documented nonmigration policy on the reference host configuration. |

## Cryptographic construction

Each store has a random 256-bit `Kstore`. Domain-separated HKDF-SHA256 outputs
are used for the manifest, record frames, commitments, and authenticated
contexts; `Kstore` is not used directly as an AEAD key.

The file is one bounded framed snapshot:

```text
bootstrap | platform-sealed key package | record frame... | sealed manifest
```

The bootstrap contains only version and bounded-length/provider-continuation
fields needed before authentication. It cannot choose an application, path,
provider, credential item, or destruction target.

The manifest is XChaCha20-Poly1305 authenticated ciphertext. Its plaintext lists
canonical record names, serialized-frame lengths, and SHA-256 digests in
physical order. Offsets are derived rather than persisted. Each value is a
separate XChaCha20-Poly1305 frame whose authenticated data binds the file
format, storage domain, key epoch, and exact record name.

An ordinary read authenticates the manifest and decrypts only requested record
frames. An ordinary write authenticates the source, copies unchanged frames as
ciphertext, encrypts changed frames under fresh nonces, writes a complete stage
file, fsyncs it, and atomically renames it. Store-key rotation re-encrypts every
frame. V2 deliberately has no journal, append log, tombstones, free list,
compaction, Merkle tree, or in-place mutation.

All lengths and counts are bounded before allocation. Current top-level limits
include a 16 MiB file, 4,096 records, 120-byte record names, and 1 MiB record
values.

## Key package and passphrases

The platform root seals the authoritative key package. With no additional
method, that package has one platform-only route to `Kstore`. Adding a
passphrase transactionally replaces it with a package that requires both the
platform root and the passphrase-derived key.

V2 passphrase profile 1 uses Argon2id v1.3 with 64 MiB, three iterations, four
lanes, a random 16-byte salt, and a 32-byte result. Derivations are serialized
per isolate so concurrent opens cannot multiply the 64 MiB working set there.
The package format allows only zero or one passphrase method. A future hardware
method may allow multiple instances, but methods are alternatives unless a
future policy explicitly introduces multi-factor authentication.

Credential APIs accept mutable bytes. Keybay snapshots caller input
synchronously and clears its owned copy after the operation. Sessions clear
their owned store key and temporary plaintext on close. These are useful
best-effort reductions in lifetime, not a claim that a garbage-collected Dart
process can prove complete memory erasure.

## Identity and provider binding

Application identity, host-profile code, assurance class, and the profile's
stable storage location are committed into one storage domain. Ordinary
path-bound profiles use the canonical file root. iOS uses its fixed location
relative to the OS-managed application container, whose absolute path can change
on update. The binding retains the actual canonical root independently for
filesystem validation. The provider address is derived
from qualified identity/profile facts, not read from the file. Provider state
inside the bootstrap is a short untrusted continuation value meaningful only
to that already-selected provider; authentication of the key package decides
whether it belongs to the store.

iOS, Android, and entitled macOS obtain OS-bound application identity. Ordinary
Dart executables on Linux and unentitled macOS use the declaration in their
owning pubspec or an AOT value embedded by the Keybay compile wrapper. Source
paths, working directories, executable names, and environment variables are
not durable application identity.

## Platform policy

| Host profile | File | Platform root | Important boundary |
|---|---|---|---|
| iOS | app-private Application Support; backup exclusion verified | exact signed Data Protection Keychain group; non-syncing, `WhenUnlockedThisDeviceOnly` | signed-group isolation; no Secure Enclave claim |
| Android 12+ | app-private `noBackupFilesDir` | one non-exportable AES-GCM Android Keystore key | package/UID sandbox; StrongBox requested, actual level measured only in qualification |
| entitled macOS | app container when sandboxed, otherwise derived Application Support | exact signed Data Protection Keychain group | entitlement isolates the root; App Sandbox separately determines file isolation |
| unentitled macOS | derived restrictive Application Support directory | one item in the explicit login Keychain | declared namespace and Keychain ACL/login session, not a portable app sandbox |
| ordinary Linux | derived restrictive XDG data directory | one Secret Service item; private runtime lock for first creation | declared namespace; authorized same-user clients may reach the item |

Provider selection is direct and fallback-free. A missing, locked, invalidated,
or mismatched root is an error while encrypted state exists. Create is
insert-only/adopt-the-winner where the provider permits it. Reset prepares an
exact provider cleanup, revokes the live file generation under lock, commits
that cleanup, and reports partial failure rather than claiming success.

The Flatpak candidate uses `/.flatpak-info` identity, the fixed private
`<instance-path>/data/keybay-v2` directory, and a domain-separated XDG Secret
Portal root. It rejects continuation tokens and never falls back to raw Secret
Service. Reset removes the encrypted store and staging, retaining nonsecret
coordination locks and the portal-owned application secret; the next open
generates a fresh store key, but an old
complete encrypted backup can restore access. Native Linux evidence with two
installed application IDs is required before claiming qualified isolation.
Snap, Windows, and unsupported provider configurations fail closed.

## Native and filesystem boundaries

POSIX paths are opened descriptor-relative with no-follow checks. Keybay fixes
all mutable names below a canonical private root, validates file type and
permissions, uses advisory locks for mutation, writes private staging files,
fsyncs content and directory state, and atomically replaces the live name.
Readers retain an open descriptor to one immutable generation.

Apple Keychain operations use Security/CoreFoundation FFI and typed byte data.
Android uses the existing JNI FFI boundary because Android Keystore has no NDK
secret-storage API. Linux uses exact-pinned typed D-Bus calls to Secret Service
or the Secret Portal, never a shell/text protocol. Open, authentication changes,
and reset may invoke trusted OS/provider UI. Record operations and `auth.list`
never acquire a provider, including on authentication failure. Interaction policy
is passed internally to providers; it adds no public interaction option.

## Supply chain and evidence

Runtime dependencies are exact-pinned. CI freezes the resolved hosted closure,
runs crypto vectors and format/adversarial tests, exercises real provider APIs
where available, and separates simulator/emulator evidence from claims about
physical hardware. A platform/API name alone is not evidence of secure hardware
mediation.

The current physical and lifecycle qualification inventory is in
[device-security-suite.md](device-security-suite.md). The separate Claude review
and remediation follow-up have been accepted; see the
[review record](security-review.md). This is an AI model review, not a human
external audit. The [qualification report](qualification-status.md) records the
current SDK release scope and deferred evidence.

# Keybay V2 architecture

The accepted design is [RFC 0001](rfcs/0001-per-application-stores.md). This is
the short implementation map.

## One shape

Every supported host application has exactly one store:

```text
Keybay.open()
    |
    v
resolved application identity + qualified host profile
    |
    +-- one platform-protected wrapping root
    |
    `-- one atomically replaced encrypted file
          bootstrap | key package | record frames | sealed manifest
```

There are no named stores, runtime application IDs, backend selectors,
plaintext modes, V1 probes, migrations, or fallback providers.

The random 256-bit store key derives independent keys for the manifest and
record frames. The platform root seals the small changing key package, which
contains the authoritative unlock policy and routes to the store key.

`Keybay.open()` recovers the store key into an explicitly closable session. It
does not preload record names or values. Reads authenticate the manifest and
decrypt only requested frames. Writes authenticate the source snapshot, copy
unchanged frames as ciphertext, seal changed frames with fresh nonces, and
atomically replace the complete file. This keeps the format transactional
without adding an encrypted database, journal, free list, or compaction logic.

## Layers

```text
public API
  Keybay / KeybaySession / KeybayAuthManager

common engine
  framed reader + writer + protection rotation
  bounded binary format + XChaCha20-Poly1305 + HKDF-SHA256
  Argon2id passphrase derivation

host profile
  authenticated/declared application identity
  fixed file root
  fixed platform protector

platform boundaries
  POSIX descriptor-relative files and atomic replacement
  Apple Security/CoreFoundation FFI
  Android Keystore through the existing JNI FFI boundary
  Linux Secret Service and XDG Secret Portal through typed D-Bus
```

The common engine depends only on the `HostPlatform` contract. Platform code
cannot choose another application's identity or feed an arbitrary path or
provider into the public API.

## Stored file

The public bootstrap is deliberately powerless: it identifies the format and
bounds the sealed package/provider continuation lengths. It cannot select a
path, provider, application, credential item, or deletion target.

The authenticated manifest contains canonical record names, exact serialized
frame lengths, and SHA-256 digests. Offsets are derived from physical order.
Each record value is independently AEAD-sealed with context binding it to the
store domain, key epoch, format, and exact record key.

The format is a framed snapshot, not an in-place database. Ordinary reads are
selective; ordinary writes still stage and replace one whole file but do not
decrypt unchanged record values. Complete store-key rotation re-encrypts every
frame.

## Protection policy

Platform protection is mandatory. With no configured unlock method it is
sufficient to recover the store key. When methods exist, opening requires:

```text
platform protection AND (passphrase OR future hardware method A OR ...)
```

V2 implements zero or one passphrase. Methods are alternatives, not implicit
multi-factor authentication. Adding, updating, or removing a method is an
authenticated transaction that rewrites the key package and preserves the
record set.

Provider calls carry an internal interaction policy fixed by the operation.
Open, authentication changes, and reset may invoke trusted OS/provider UI;
record operations and authentication listing never acquire a provider. Their
failure paths do not recheck provider state to diagnose cross-process rotation.
The public API has no interaction option.

## Platform profiles

| Profile | Identity | File isolation | Root protection |
|---|---|---|---|
| iOS | signed application identifier | app-private container | exact Data Protection Keychain group |
| Android 12+ | installed package/UID | app-private no-backup directory | one non-exportable Keystore key |
| entitled macOS | signed application identifier | sandbox when present; otherwise same-user writable | exact Data Protection Keychain group |
| unentitled macOS | owning pubspec/build declaration | restrictive Application Support directory | explicit login-Keychain item |
| ordinary Linux | owning pubspec/build declaration | restrictive XDG data directory | Secret Service item plus private runtime creation lock |

The last two profiles are `namespaceOnly`: a same-user process can claim the
same declaration and may reach the platform item/file. A passphrase prevents
those artifacts alone from yielding the store key, but cannot prevent deletion
or modification by an actor with filesystem/keyring authority.

The Flatpak candidate binds the application identity from `/.flatpak-info` to
`<instance-path>/data/keybay-v2` and a domain-separated XDG Secret Portal root.
The portal owns the reusable application secret; Keybay owns no deletable
provider item in this profile. Qualification requires native Linux evidence
with two installed application IDs. Flatpak never falls back to Secret Service.
Snap, Windows, and unsupported provider configurations fail closed.

## Concurrency and reset

Readers pin one immutable file generation. Mutations serialize, take the
platform/file locks required by the profile, authenticate the source, stage a
complete replacement, fsync it, and rename it atomically. A session whose
generation lost a protection-changing race becomes stale.

`clearAll` commits an empty record snapshot without changing protection.
`Keybay.reset()` locks the store, revokes the live file, removes staging, and
deletes an exact provider item where the profile owns one. It retains the
nonsecret coordination lock and its directory to preserve mutual exclusion. Flatpak
retains its portal-owned secret. Reset initializes nothing; the next successful
open generates a fresh store key. An operation pinned before live-file
revocation may finish from that generation; later pins fail. Restoring an old
complete encrypted store can restore access under a retained portal secret.

## Deliberate limits

V2 does not provide rollback detection, sync, export, recovery, multiple
stores, background unlock agents, a capability/inspection API, or protection
against root, process injection, keyloggers, or a malicious Keybay binary.
Plaintext explicitly returned to the application is ordinary process data.

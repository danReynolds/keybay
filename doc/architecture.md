# Keybay V2 architecture

This page explains how a Keybay vault works: where each piece lives, how keys
nest, and what happens when you open, write, and change protection. [Security
levels](security-levels.md) states what that means per platform. The normative
design is [RFC 0001](rfcs/0001-per-application-stores.md), amended by
[RFC 0003](rfcs/0003-passkey-methods.md); the [review guide](external-review.md)
distinguishes current source from published artifacts.

## One vault per application

Every supported application has exactly one vault: one platform-protected root
key and one encrypted file. There are no named stores, runtime application IDs,
backend selectors, plaintext modes, migrations, or fallback providers.

```text
Keybay.open()
    |
    v
application identity + host profile   (fixed by the OS or the owning pubspec)
    |
    +-- platform root                  (Keychain, Keystore, Secret Service or portal)
    |
    `-- vault file                     (one file, replaced atomically)
          bootstrap | key package | record frames | manifest
```

## Where things live

| Piece | Location | Contents |
| --- | --- | --- |
| Platform root | The platform's key store, at a location derived from the application identity | A random 32-byte key (Keychain, Secret Service), a key derived from the portal's per-app secret (Flatpak), or a non-exportable Keystore key (Android). Nothing else. |
| Bootstrap | Start of the vault file, unencrypted | Format version, suite and lengths. It cannot select a path, provider or application. |
| Key package | Vault file, sealed by the platform root | The vault's protection policy and the routes to its store key. |
| Record frames | Vault file | Each value encrypted separately. |
| Manifest | End of the vault file, encrypted | Record names, frame lengths and digests. It also authenticates the bootstrap and the whole key package. |

The [platform guides](security-levels.md#platform-guides) give each profile's
exact provider and file paths.

## Key hierarchy

```text
platform root
  `-- seals the key package
        |
        |-- platform-only:  store key
        |
        `-- with methods:   sealed vault secret S      (under the store key)
                            method 1: public key, envelope, confirmation
                            method 2: public key, envelope, confirmation
                            ...                        (at most eight)

store key  (random, 32 bytes, replaced on every protection change)
  |-- manifest key   (HKDF)
  `-- frame key      (HKDF)  --> each record frame
```

- **Platform-only vault:** the key package holds the store key itself, so the
  platform root alone opens the vault.
- **Vault with methods:** each method's credential output (an Argon2id result
  for a passphrase, a verified PRF output for a passkey) derives an X25519 key
  pair. Only the public key is stored. The method's **envelope** is the store
  key encrypted to that public key with HPKE, so any one method can recover it.
- **Confirmation:** an HMAC over the vault secret `S`, keyed from the same
  credential output. Anyone holding a public key can encrypt to it, so an
  envelope opening proves only that it was addressed to you. The confirmation
  proves that a holder of your credential vouched for this vault's `S`, which
  only the store key reveals.

No passphrase, PRF output, private key or other credential-equivalent secret is
ever stored.

## Opening a vault

Without a credential (`Keybay.open()`):

1. Read the bootstrap and acquire the platform root. This is the only step that
   can show OS or provider UI.
2. Unseal the key package. A platform-only package yields the store key; a
   package with methods returns `authRequired` with the method list.
3. Authenticate the manifest with the store key, then return a session.

With a credential (`Keybay.open(credential: ...)`):

1. Read the bootstrap, acquire the platform root, and unseal the key package.
2. Select the method matching the credential. An ambiguous passkey match fails
   here, before any prompt.
3. Obtain the credential output: Argon2id over the passphrase, or a passkey
   ceremony. Derive the method's private key and check it against the stored
   public key.
4. Open the envelope to recover the store key.
5. Decrypt `S` with the store key and recompute the method's confirmation.
   A mismatch fails with `storeAuthenticationFailed`.
6. Authenticate the manifest, which binds the bootstrap and the entire key
   package, with the store key.
7. For a passkey, persist the authenticator's updated counter, comparing the
   exact on-disk prefix so a concurrent change cannot be overwritten.
8. Return a session holding only the store key.

Nothing is returned or written before steps 3 to 6 succeed. A credential-based
open never creates or enrolls a vault.

## Reading and writing

A read pins one immutable file generation, authenticates its manifest, and
decrypts only the requested frames. Each frame's authenticated data binds the
store ID, key epoch, frame type and exact record name, so frames cannot be
swapped between records, epochs or vaults.

A write authenticates the current generation, copies unchanged frames as
ciphertext, encrypts changed values under fresh random nonces, writes a complete
staging file, fsyncs it, and atomically renames it over the live file. Record
operations never acquire the platform root or prompt. V2 deliberately has no
journal, append log, free list, compaction or in-place mutation.

## Changing protection

`auth.add` and `auth.remove` are the only protection changes; there is no
update or replace. Each one:

1. re-authenticates the current generation with the session's store key and
   unseals its key package with the platform root;
2. for `add`, runs the new method's enrollment (passphrase entry or passkey
   creation) and computes its confirmation over `S`;
3. generates a fresh store key and epoch;
4. re-encrypts `S` and every record frame under the new store key, and wraps
   the new store key to each remaining method's public key;
5. commits the new file atomically, invalidating other open sessions.

Remaining methods are never asked for their credentials: their envelopes are
rebuilt from public keys, and their confirmations do not depend on the store key.

- The first `add` on a platform-only vault creates `S`. Removing the last
  method returns the vault to platform-only protection and discards `S`.
- A session opened platform-only refuses to change protection if a methods
  package has appeared under its own store key, since whoever holds the platform
  root also knows that key.
- Removing a method stops it from reading anything written afterwards, but it
  keeps `S`. To fully revoke a compromised credential on an account-level
  platform, remove every method and add back the trusted ones. See
  [Security levels](security-levels.md#after-a-credential-is-compromised).
- Changing a passphrase is a separate remove and add. Add a replacement passkey
  before removing an old one when the method limit allows.

## Code layers

```text
public API
  Keybay / KeybaySession / KeybayAuthManager

common engine
  framed reader + writer + protection rotation
  bounded binary format + XChaCha20-Poly1305 + HKDF-SHA256
  Argon2id passphrase derivation / verified Keypass PRF material
  method X25519 keys + HPKE envelopes + confirmations

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

The engine acquires platform protection through `HostPlatform` and passkey
material through Keypass. Keybay owns derivation, envelopes, confirmations,
record integrity and atomic storage. Keypass owns provider and device
interaction and hands each temporary result to Keybay, which disposes of it.
Platform code cannot feed a runtime identity, arbitrary path or alternate
provider into the public API. Provider calls carry an interaction policy fixed
by the operation; the public API has no interaction option.

## Platform profiles

| Profile | Identity | File isolation | Root protection |
|---|---|---|---|
| iOS | signed application identifier | app-private container | exact Data Protection Keychain group |
| Android 12+ | installed package/UID | app-private no-backup directory | one non-exportable Keystore key |
| entitled macOS | signed application identifier | sandbox when present; otherwise same-user readable | exact Data Protection Keychain group |
| unentitled macOS | owning pubspec/build declaration | restrictive Application Support directory | explicit login-Keychain item |
| ordinary Linux | owning pubspec/build declaration | restrictive XDG data directory | Secret Service item plus private runtime creation lock |

The last two profiles are `namespaceOnly`: a same-user process can claim the
same declaration and reach the platform item and file. The Flatpak candidate
binds identity from `/.flatpak-info` to `<instance-path>/data/keybay-v2` and a
domain-separated XDG Secret Portal root, and never falls back to Secret Service.
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

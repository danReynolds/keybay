# RFC 0003: Passkey methods

- Status: implemented on the integration branch; review and release gates apply
- Date: 2026-10-02
- Amends: [RFC 0001](0001-per-application-stores.md)
- Consumer contract: [SDK guide](../sdk.md#add-passkey-protection)

## Scope

Keybay consumes Keypass as a separate, Flutter-free Dart SDK. It accepts
`PasskeyCredential.system` and `PasskeyCredential.hardware` in the existing
`open(credential:)`, `auth.add`, and `auth.update` APIs. Keybay owns credential
records, key derivation, envelopes, and atomic persistence; applications never
handle the temporary Keypass secret. One explicit RP ID configures each
credential request, independently of Keybay's fixed application identity.

Platform protection remains mandatory. When methods exist, **any one** method
plus that platform protection unlocks the store. There is at most one
passphrase and at most eight total methods. Removing the last method explicitly
returns to platform-only protection. Record operations and `auth.list()` never
access Keypass or reacquire a platform root.

The system route uses Keypass's native provider with the consumer's required
app/domain association and native host setup. The hardware route uses its
physical FIDO backend and optional PIN, connection, and event handlers. Direct
hardware RP scoping does not authenticate the calling executable. A shared
RP ID does not make separately enrolled credentials interchangeable. This
integration adds neither a Keybay service nor a production browser bridge.

## Selection and ownership

`open(credential:)` only authenticates existing protection, for both passphrase
and passkey requests. A missing live file with no staging artifacts returns
`storeNotFound` before platform-root access, Argon derivation, or a Keypass
operation; it never enrolls, including after reset or with a retained root.
Incomplete staging state still fails as `storeStateConflict` first.
Credential-free `open()` may initialize fully absent platform-only state;
additional protection is enrolled explicitly through the session's `auth.add`.
Existing stores require their current policy; a missing credential, wrong RP,
wrong route, or absent method never enrolls, resets, tries another method, or
retries a PIN.

Passkey unlock can omit `methodId` only when exactly one method matches its RP
and route. Ambiguity returns `authMethodSelectionRequired` before a passkey
prompt. Updates require an existing passkey method ID and retain it while
explicitly enrolling a replacement; they may change its RP or route. Adds
reject a supplied method ID. Passphrase updates retain
the existing singleton API. `authMethods` error hints are authenticated only
by the platform package, not yet by the credential-dependent manifest; UI must
not treat them as authority to unlock or change policy.

Keypass results are disposed immediately after copying and deriving their
material, and on every failure. Keybay clears its owned PRF/Argon output,
derived private key, HPKE scratch, provisional store key, and rejected queued
credential buffers. The session owns only its current store key and nonsensitive
metadata. Caller copies, Dart VM temporaries, and internal X25519 temporary
copies cannot all be proven erased. Passphrase APIs remain byte based.

## Suite and encoding

The `KBV2` bootstrap retains its layout and gains suite 2. Frame/manifest
primitives and domain labels stay unchanged; the authenticated bootstrap binds
the suite. Suite 1 retains its 4096-byte sealed-package cap; suite 2 allows
128 KiB. Suite 1 retains its 16 MiB total-file cap. Suite 2 permits at most
16 MiB of non-package bytes, plus its separately bounded sealed package:
`fileLength - sealedPackageLength <= 16 MiB`. Its absolute physical cap is
16 MiB plus 128 KiB. Every reader and record writer enforces the suite's bound;
records cannot consume the space reserved for authentication metadata. This
admits every valid legacy snapshot's content during migration and lets a full
passkey vault persist growing verifier state. The aggregate plaintext read
cap remains 16 MiB. Policy 2 requires suite 2. Older suite-1-only readers reject
the new suite before using its package. No implicit downgrade occurs after
removal.

Policy 0 (platform-only) and legacy policy 1 (singleton passphrase) remain
readable. Policy 2 encodes, using unsigned big-endian integers:

```text
storeId:16 | epoch:u64 | policy:u8=2 | count:u32
repeat count times, in strictly increasing method-ID byte order:
  methodId:16 | kind:u8 | labelLength:u32 | label:UTF8
  salt:16 | profile:u8 | publicKey:32 | envelope:80
  recordLength:u32 | record:UTF8
```

Kinds are 1 passphrase, 2 system passkey, and 3 hardware passkey. Passphrases use
allowlisted Argon profile 1 and an empty record; passkeys use profile 0 and a
nonempty serialized opaque `PasskeyRecord`. The label is at most 256 UTF-8
bytes and the record at most 12 KiB. The maximum plaintext package is 101,613
bytes. Empty directories, duplicate/unsorted IDs, extra bytes, unknown kinds
or profiles, non-byte inputs, malformed UTF-8 and multiple passphrases fail
closed. The engine additionally validates every Keypass record, its route,
and uniqueness of its stable credential identity before method selection.

Mutable Keypass verification state lives inside the serialized record. It is
authenticated by the package and manifest but excluded from stable derivation
and HPKE contexts. A changed counter must not change the derived private key.

## Derivation and wrapping

Let `M` be the 32-byte Argon2id result or verified Keypass PRF output. The
passphrase KDF remains profile 1 (Argon2id v1.3, 64 MiB, three iterations, four
lanes, random 16-byte salt). Passkey material is already high entropy and does
not pass through Argon2. All methods use a random 16-byte salt.

Define `LP(fields)` as concatenating `length:u32 | field` for each field:

```text
stable = LP("keybay:v2:methods:1", storeId, methodId, kind:u8,
            salt, stableRecordId:ASCII)
private = HKDF-SHA256(M, salt,
                     "keybay:v2:methods1:key:private" || 0x00 || stable, 32)
public  = X25519(private)
context = stable || LP(epoch:u64, public)
info    = "keybay:v2:methods1:hpke:store-key" || 0x00 || context
```

`stableRecordId` is empty for passphrases. It is Keypass's stable record ID for
passkeys, not serialized mutable verification state. The private seed is used
with X25519's standard clamping. It is never persisted.

Each envelope uses RFC 9180 base mode 0, DHKEM(X25519, HKDF-SHA256) 0x0020,
HKDF-SHA256 0x0001, and ChaCha20Poly1305 0x0003. Its info is the value above,
its AEAD AAD is `context`, and its plaintext is the 32-byte `Kstore`. A fresh
random 32-byte IKM feeds RFC 9180 `DeriveKeyPair` for every envelope. The
single-shot sequence number is zero; no nonce is stored:

```text
envelope = enc:32 | ciphertext:32 | tag:16
```

All-zero DH results are rejected. Only the public recipient key and envelope
are stored; there is no credential-encrypted private-key field and no method
secret encrypted under `Kstore`. HPKE base mode authenticates no sender.
The existing manifest's AAD authenticates the exact bootstrap and complete
platform-sealed package, including the whole method directory. A recovered
`Kstore` is provisional until this check succeeds. No redundant directory MAC
is introduced. Rotation trusts recipient public keys only from a directory
already authenticated with the current session key.

This permits rotating to a fresh `Kstore` and resealing every surviving method
without requesting its credential. Possession of a removed credential, its
old envelope, and the old `Kstore` does not reveal surviving private keys or
decrypt future rotated records. Possession of an old complete snapshot still
permits opening that snapshot. An actor controlling an authenticated process
can change policy; this design does not claim to defeat that attacker.

## Transactions and migration

Protected open pins a generation before any credential ceremony, obtains a
candidate key, and authenticates its manifest. Before publishing a session it
takes the file lock and compares the current exact bootstrap and sealed
package with the original prefix, even if the passkey counter stayed zero.
Changed policy or verifier metadata fails with a conflict; no retry or second
ceremony occurs automatically. Ordinary record writes preserve that prefix:
the current manifest is authenticated and any updated record state is merged
into a complete replacement containing those latest records.

A successful passkey unlock persists the returned verification state before
returning the session. Failure or cancellation before commit yields no session.
Cancellation is checked before provider access and after cleanup. Cancellation
or I/O failure racing durable replacement cannot undo a completed transaction;
the caller must inspect state on a deliberate retry. Provider enrollment may
leave an unused passkey behind when subsequent local persistence fails.

A legacy suite-1 passphrase open first recovers its key and authenticates the
original manifest. While the verified Argon result is still owned, Keybay
derives the new private method key and seals the same store key under its public
key. Migration preserves method ID, salt, epoch, and encrypted record frames,
then atomically commits suite 2, policy 2, and a newly authenticated manifest.
Wrong credentials cannot migrate state. Failed or uncertain commits return no
session; whichever complete generation is live remains reopenable.

Auth changes authenticate and prepare outside the exclusive file transaction.
After any enrollment/prompt, a second transaction compares the exact prefix,
authenticates the latest records, and rotates all of them atomically to a fresh
key and epoch. The existing uncertain-rename classifier adopts a proven new
generation, retains a proven old one, or invalidates sessions when neither is
provable. Successful rotation invalidates peer sessions. Same-session work
remains queued; callbacks attempting Keybay operations fail with `storeBusy`
rather than waiting on their own auth operation. First creation remains an
exclusive initialization transaction to prevent rival stores.

As in the existing initialization model, failure after creating the platform
root but before committing the first file can leave root-only state. A later
credential-free open reports `storeStateConflict` (credential-based open reports
`storeNotFound` without acquiring that root); deliberate reset is required
before creating a new store. Keybay never treats partial initialization as
absence or deletes provider credentials automatically. Successful auth rotation
drains already accepted peer work before its Future settles; a peer waiting for
interactive authentication can delay settlement, even though the file lock is
released and the new generation is already committed.

## Evidence and release boundary

The HPKE implementation is tested against the published RFC 9180 vector and
independently generated Python fixtures, including every-byte tampering,
context separation, low-order inputs, cleanup, and survivor rotation.
Format, legacy migration, mixed-credential engine, transactional failure,
counter persistence, callback reentrancy, and cross-engine concurrency tests
exercise the production Keypass facade with a test backend.

These are implementation tests and engineering review, not an independent
cryptographic audit or physical-device Keybay qualification. Native Keypass
host artifacts must be integrated by the consumer. Previously recorded
Keypass iOS/Android/macOS experiments do not qualify this new vault format.
The current exact Git dependency is a development input; a hosted Keypass
release is required for a publishable Keybay package. No release gate is waived.

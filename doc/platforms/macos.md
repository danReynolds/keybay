# keybay on macOS

macOS has two schemes. The library picks one automatically — once per process,
deterministically, and never by silently degrading.

## How the choice is made

On first use the library derives the first authorized access group from the
signed process entitlements, then verifies it with a tiny explicitly scoped
write to the
[**Data Protection keychain**](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain):

- **Success** → the app is signed and carries the Keychain Sharing
  entitlement → [native items](#signed-apps-entitled).
- **`errSecMissingEntitlement` (−34018)** → the normal result for a plain CLI
  or `dart run` → the [encrypted file](#command-line-and-unentitled).
- **Any other error** → it throws. A misconfigured entitlement is surfaced
  loudly, never quietly downgraded.

Entitlements are baked into the code signature, so the outcome is fixed per
binary and cached for the process. The probe writes to a **dedicated internal
service** (outside the `appId` grammar) in that exact group, so it can never
collide with or delete a caller secret.

**Gaining the entitlement between versions moves the store.** Switching from a
CLI/unentitled build to an entitled one changes the resolved scheme from the
encrypted file to native items — physically different places. The encrypted
file leaves its own on-disk trace (the container), so rather than silently
present an empty store and strand those secrets, an entitled resolve that finds
a pre-existing `~/Library/Application Support/<appId>/secrets.enc` throws a
typed `MigrationRequired` (`from: encryptedFile, to: nativeItems`). Migrate the
secrets across, then remove that file (or the directory) to proceed.

**Losing or changing the entitlement is also loud.** Before the first native
mutation, Keybay records a private, non-secret `.scheme` marker beside the
possible file-store location. It contains only the native scheme and encoded
access-group identity. A later unentitled resolver throws `MigrationRequired`
instead of opening a fresh file store; a different access group throws
`KeychainAccessGroupChanged`. The marker is retained after deletion so a
signing change cannot silently revive an abandoned namespace. Removing it is
therefore an explicit migration/reset action, not automatic cleanup.

The marker protects native use observed by marker-aware Keybay versions. An
older entitled installation should run one marker-aware build before its
entitlement or access group changes; changing both at the upgrade boundary
leaves no information an unentitled process can use to discover the older
OS-walled items and requires an explicit application migration decision.

## Signed apps (entitled)

Each secret is a **native item in the Data Protection Keychain**. There is no
Keybay secret container or separate Keybay store key on this path; only the
non-secret scheme marker above. Every operation includes the one derived
[access group](https://developer.apple.com/documentation/security/ksecattraccessgroup)
explicitly. Items use
[`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)
and are non-synchronizing; updates reassert both attributes rather than
inheriting a colliding pre-existing item's policy.

**What this policy means.** The item does not migrate to a different device.
`AfterFirstUnlock` remains compatible with background work: after the first
unlock following a reboot, it remains accessible when the machine relocks.
Keybay does not add biometric or current-unlock gating.

`describe().scheme` reports `nativeItems`. `describe().level` is null: Keybay
applies the documented Data Protection Keychain policy but does not infer or
attest a hardware-backing level for the stored items.

**Validation.** The refusal path (−34018 → the file scheme, with nothing
written as a fallback) is CI-tested on every push. The success path needs a
signed, provisioned bundle CI can't produce; it is validated end-to-end by the
`example_flutter/` host app (Keychain Sharing + a development team → the
resolver picks native items and completes a round trip). That leg is local —
the repeatable recipe is [tool/dp_keychain_verification.md](../../tool/dp_keychain_verification.md).
Its security properties, lifecycle extensions, and retained evidence contract
are tracked as the [macOS device-suite scenarios](../device-security-suite.md#macos).

## Command-line and unentitled

Every secret lives in **one authenticated encrypted file** at
`~/Library/Application Support/<appId>/secrets.enc` (mode `0600`, written
atomically). The file is sealed with **XChaCha20-Poly1305** under an
HKDF-SHA256-derived key with a key-commitment header (a wrong key fails closed
*before* decryption, distinct from tampering). The 32-byte file key is stored
in the **login Keychain** via the `SecItem` API. Keybay writes no plaintext copy
of that key beside the container; the operating system owns how the credential
store persists it.

First creation is insert-only: Keybay uses atomic `SecItemAdd`, and a racing
writer adopts the already-created Keychain value instead of overwriting it.
This matters when the same `appId` is reached from sandboxed and unsandboxed
processes whose container roots differ; both containers remain sealed under
the one winning Keychain key.

**What this resists.** The file key sits in the login Keychain under a
login-password-derived key: safe from other local users and casual theft.
Against a stolen disk it is only as strong as the login password. The
authenticated container adds tamper detection and separates the portable data
file from its key; it does not turn a login-bound key into hardware protection.

**Validation.** Real login-Keychain round-trips run in CI on every push; the
file scheme is additionally exercised inside a real sandboxed `.app` by the
`example_flutter/` harness. Destructive and lifecycle qualification remains
separate in the [macOS device-suite scenarios](../device-security-suite.md#macos).

## Know your trust unit

Keychain ACLs bind to the **acting binary**. Under `dart run` that binary is
the shared Dart VM, so one "Always Allow" authorizes *every* Dart program you
run to read the item silently. For production, `dart compile exe` and sign with
a stable Developer ID — the ACL then binds to your app and survives upgrades. A
locked keychain (SSH, CI) surfaces as a typed error rather than hanging on a
GUI unlock prompt.

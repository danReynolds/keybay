# keybay on macOS

macOS has two schemes. The library picks one automatically — once per process,
deterministically, and never by silently degrading.

## How the choice is made

On first use the library attempts a tiny probe write to the **Data Protection
keychain** and reads the result:

- **Success** → the app is signed and carries the Keychain Sharing
  entitlement → [native items](#signed-apps-entitled).
- **`errSecMissingEntitlement` (−34018)** → the normal result for a plain CLI
  or `dart run` → the [encrypted file](#command-line-and-unentitled).
- **Any other error** → it throws. A misconfigured entitlement is surfaced
  loudly, never quietly downgraded.

Entitlements are baked into the code signature, so the outcome is fixed per
binary and cached for the process. The probe writes to a **dedicated internal
service** (outside the `appId` grammar), so it can never collide with — or
delete — one of your secrets. (The full rationale — why a probe rather than
reading the entitlement, and why this is *not* the unsafe kind of
auto-detection — is in [design.md](../design.md).)

**Gaining the entitlement between versions moves the store.** Switching from a
CLI/unentitled build to an entitled one changes the resolved scheme from the
encrypted file to native items — physically different places. The encrypted
file leaves its own on-disk trace (the container), so rather than silently
present an empty store and strand those secrets, an entitled resolve that finds
a pre-existing `~/Library/Application Support/<appId>/secrets.enc` throws a
typed `MigrationRequired` (`from: encryptedFile, to: nativeItems`). Migrate the
secrets across, then remove that file (or the directory) to proceed. (No
separate marker file is kept — the container's existence is the signal, so a
store that was only *opened* under the file scheme but never written never
false-fires. The reverse, a *lost* entitlement, isn't detectable from the
now-unentitled process — it cannot read the abandoned Data Protection items,
which the OS walls off rather than resurfaces.)

## Signed apps (entitled)

Each secret is a **native item in the Data Protection Keychain**. There is no
Keybay container or separate Keybay store key on this path. Items use
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and are non-synchronizing.

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

## Command-line and unentitled

Every secret lives in **one authenticated encrypted file** at
`~/Library/Application Support/<appId>/secrets.enc` (mode `0600`, written
atomically). The file is sealed with **XChaCha20-Poly1305** under an
HKDF-SHA256-derived key with a key-commitment header (a wrong key fails closed
*before* decryption, distinct from tampering). The 32-byte file key is stored
in the **login Keychain** via the `SecItem` API. Keybay writes no plaintext copy
of that key beside the container; the operating system owns how the credential
store persists it.

**What this resists.** The file key sits in the login Keychain under a
login-password-derived key: safe from other local users and casual theft.
Against a stolen disk it is only as strong as the login password. The
authenticated container adds tamper detection and separates the portable data
file from its key; it does not turn a login-bound key into hardware protection.

**Validation.** Real login-Keychain round-trips run in CI on every push; the
file scheme is additionally exercised inside a real sandboxed `.app` by the
`example_flutter/` harness.

## Know your trust unit

Keychain ACLs bind to the **acting binary**. Under `dart run` that binary is
the shared Dart VM, so one "Always Allow" authorizes *every* Dart program you
run to read the item silently. For production, `dart compile exe` and sign with
a stable Developer ID — the ACL then binds to your app and survives upgrades. A
locked keychain (SSH, CI) surfaces as a typed error rather than hanging on a
GUI unlock prompt.

# Keybay security

Keybay encrypts local application secrets. Platform protection is mandatory;
passphrases and passkeys optionally add another cryptographic requirement.

Use maintained, patched operating systems and providers. There has been no
independent human security audit. The [review guide](doc/external-review.md)
records exact source/release baselines, prior reviews and outstanding work.

## Storage model

Each application has one atomically replaced encrypted file. An encrypted,
authenticated manifest holds record names; values are separate
XChaCha20-Poly1305 frames. A random store key derives separate manifest/frame
keys and is wrapped by the platform-protected key package.

| Host | Platform protection | Application boundary |
| --- | --- | --- |
| iOS | Data Protection Keychain, exact signed group | Signed group and app-private files |
| Android 12+ | Non-exportable Android Keystore key | Package/UID sandbox and no-backup files |
| Entitled macOS | Data Protection Keychain, exact signed group | Root isolated by entitlement; file isolation depends on App Sandbox |
| Unentitled macOS / CLI | Explicit login-Keychain item | Declared namespace and restrictive files, not an app sandbox |
| Ordinary Linux desktop | Secret Service item | Declared namespace and restrictive files, not an app sandbox |

The [Flatpak candidate](doc/platforms/linux.md) uses sandbox identity and XDG
Secret Portal, never raw Secret Service. Snap, Windows and unsupported providers
fail closed. [Qualification](doc/qualification-status.md) is configuration-specific.

With enrolled methods, opening requires
`platform AND (passphrase OR passkey A OR passkey B ...)`.
A store supports one passphrase at most and eight methods total. Argon2id
passphrase output or verified Keypass PRF material derives a method-specific
X25519 recipient through HKDF. HPKE wraps the store key; the platform seals
the method package, which the manifest authenticates. See
[RFC 0003](doc/rfcs/0003-passkey-methods.md) for the construction.

On ordinary Linux and unentitled macOS, another same-user program may claim
the namespace and reach platform storage. For a platform-only CLI vault, it can
use `list` and secret-referencing `run` without a credential prompt. Enroll a
passphrase or hardware passkey to make platform/file access alone insufficient.
A pseudo-terminal or UI prompt is not an authorization boundary.

System passkeys need a supported app host and domain association. Direct
hardware RP namespaces do not authenticate the calling executable. Ordinary
passkey login or a biometric success boolean cannot replace verified PRF
material. Synced passkeys do not bypass the mandatory platform root.

## What Keybay protects

- Managed persistent files contain no plaintext record values.
- A file alone is insufficient without the platform root; enrolled methods
  additionally require one matching credential.
- Corruption, wrong keys and unsupported state fail before returning plaintext.
- Concurrent writers commit one complete authenticated generation.
- Stored data cannot redirect platform selection.

Record operations and `auth.list()` never prompt or acquire a provider, even
on failure. Open, auth changes and reset may invoke trusted provider UI.
The [design](doc/design.md) and [storage RFC](doc/rfcs/0001-per-application-stores.md)
define the invariants and threat model.

## What Keybay does not protect

Keybay does not defend against root/kernel compromise, injected or malicious
host code, keyloggers, terminal/screen capture, denial of service by actors able
to delete state, or rollback to an older authentic snapshot. Returned plaintext
is ordinary application data. An attacker controlling an unlocked session can
change its protection policy.

Auth changes rotate the current store key and re-encrypt records. They do not
revoke old snapshots, issuer tokens or provider credentials. Removing the last
method returns to platform-only protection. Passphrase replacement is separate
remove/add commits: if it was the last method, the weaker state persists until
adding succeeds. Credential-based open never enrolls or repairs state.

Reset deletes files and deletable provider state, retaining coordination locks.
Flatpak also retains its portal secret. The next open creates a fresh store key;
restoring an old complete snapshot can restore its former access policy.

Buffer clearing is best-effort, not proof of erasure of VM/OS/dependency copies.
Keybay wipes its native Argon2 workspace before freeing it. The pinned HKDF
wrapper discards its immutable backing bytes without overwriting them.
The CLI disables core files and becomes non-dumpable on Linux before opening;
SDK hosts must choose their own process-wide dump policy.

CLI `get` rejects captured/redirected output, but that disclosure guard is not
authorization. `run` gives referenced secrets to its child. Copy releases a
secret to the OS clipboard: macOS marks it current-host-only and
sensitive/transient; Linux currently supplies no sensitivity hint. Clipboard
managers may retain it, and clearing the clipboard cannot erase their history.

## Engineering and evidence

Runtime dependencies are exact-pinned. CI checks the hosted dependency closure,
formatting, analysis, adversarial tests and affected provider lanes. Simulators,
fakes and readiness probes do not establish physical secure-hardware behavior.

- [External review](doc/external-review.md): code/test map, advisory maintenance,
  qualification gaps and review procedure.
- [Security review record](doc/security-review.md): prior AI reviews and findings;
  these predate the complete passkey integration.
- [Release readiness](doc/release-readiness.md): published artifacts versus newer
  source. Current source rejects V1 and retired V2 singleton formats without
  migration; published 0.2.0 retains the latter conversion.

## Reporting

Use [private vulnerability reporting](https://github.com/danReynolds/keybay/security/advisories/new)
or **me@danreynolds.ca**. Do not disclose security bugs in public issues.
Critical and High findings block the next release.

Release tags are signed with the maintainer's SSH key:

```sh
git verify-tag v0.2.0             # SDK
git verify-tag keybay_cli-v0.2.0  # CLI
```

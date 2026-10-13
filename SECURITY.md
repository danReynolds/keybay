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

| Host | Platform protection | Level | Without a passphrase or passkey |
| --- | --- | --- | --- |
| iOS | Data Protection Keychain, exact signed group | App-bound | Other apps cannot read values |
| Android 12+ | Non-exportable Android Keystore key | App-bound | Other apps cannot read values |
| Entitled macOS | Data Protection Keychain, exact signed group | App-bound key | Other apps cannot read values; file isolation needs App Sandbox |
| Unentitled macOS / CLI | Explicit login-Keychain item | Account-level | Programs running as you can use the CLI to read every value |
| Ordinary Linux desktop | Secret Service item | Account-level | Programs running as you can read every value |

[Security levels by platform](doc/security-levels.md) gives the full exposure
matrix, including backups and the Flatpak candidate, and what a passphrase or
passkey changes. [Architecture](doc/architecture.md) walks through how the vault
works.

The [Flatpak candidate](doc/platforms/linux.md) uses sandbox identity and XDG
Secret Portal, never raw Secret Service. Snap, Windows and unsupported providers
fail closed. [Qualification](doc/qualification-status.md) is configuration-specific.

With enrolled methods, opening requires
`platform AND (passphrase OR passkey A OR passkey B ...)`.
A store supports one passphrase at most and eight methods total. Argon2id
passphrase output or verified Keypass PRF material derives a method-specific
X25519 recipient through HKDF. HPKE wraps the store key; the platform seals
the method package, which the manifest authenticates. Each method also stores
a credential-keyed confirmation over a vault secret sealed under the store key,
so holding the platform root is not enough to build a store that a genuine
credential accepts. See
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
change its protection policy. Removing a method does not change the vault
secret, so its former holder, with the platform root and file, could still
substitute a store that the remaining methods accept.

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

## Verifying releases

SDK (`v*`) and CLI (`keybay_cli-v*`) tags are signed with the maintainer's
release SSH key:

```text
me@danreynolds.ca ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtnuwBbMwdKZu2YlUnDdhW7t0bp7JlCjUZR8/JOQae6
SHA256:4ozSnfVaMzZ/qrzo51I8FPKawmZSIojAB5Ll+qhguFM
```

Cross-check it against GitHub's list of the maintainer's
[signing keys](https://api.github.com/users/danReynolds/ssh_signing_keys).
It is not one of the authentication keys at `github.com/danReynolds.keys`.
In a clone of this repository, save the first line above as
`keybay-allowed-signers`, then verify a tag (`v0.2.0` for the SDK):

```sh
git -c gpg.ssh.allowedSignersFile=keybay-allowed-signers verify-tag keybay_cli-v0.2.0
```

Since 0.1.1, a CLI tag's annotation records the SHA-256 of that release's
`release-manifest.json`, which lists every archive's SHA-256 and the Homebrew
formula's. The [SDK](.github/workflows/audit-release.yml) and
[CLI](.github/workflows/audit-cli-release.yml) release audits re-verify these
tags; the CLI audit also checks the manifest chain and re-checks the newest
release and published formula daily. The
[CLI guide](packages/keybay_cli/README.md#verify-a-release-download) covers
downloads.

# Keybay security

Keybay holds local secrets for applications and its CLI on macOS, iOS, Android,
and ordinary Linux desktop. It is austere on purpose: one store shape, no
weaker configuration mode, and no platform claim without matching evidence.

## Storage model

Every supported application has one atomically replaced encrypted file. Record
names live in an authenticated encrypted manifest; each value is an independent
XChaCha20-Poly1305 frame. One random store key derives separate manifest and
frame keys. A small key package routes from the platform protector to that
store key.

| Host | Platform protection | Application isolation |
|---|---|---|
| iOS | exact signed Data Protection Keychain group | signed group plus app-private file container |
| Android 12+ | one non-exportable Android Keystore key | installed package/UID sandbox plus no-backup file directory |
| entitled macOS | exact signed Data Protection Keychain group | root isolated by entitlement; file isolation depends separately on App Sandbox |
| unentitled macOS / CLI | one explicit login-Keychain item | declared namespace and restrictive files; not a portable app sandbox |
| ordinary Linux desktop | one Secret Service item | declared namespace and restrictive files; not an OS-enforced app boundary |

Platform protection is mandatory. Applications may add one passphrase, making
opening require platform access and the passphrase. Passphrases are especially
important for high-value records on ordinary Linux and unentitled macOS, where
another same-user process may claim the same declared namespace and reach
login-bound storage.

For the CLI this is concrete: without a passphrase, any program running as you
can read every value through `keybay list` and `keybay run`, with no terminal or
prompt. On macOS those requests do not meet the Keychain prompt that an
unrelated program reading the item directly would. A terminal check would not
change this, because a program can supply its own pseudo-terminal; only a
passphrase separates you from other programs running as you.

The Flatpak candidate uses authenticated sandbox identity and XDG Secret Portal
protection. Two installed application IDs passed isolation checks in the
recorded native Linux and nested Docker configurations. The [qualification
report](doc/qualification-status.md) names their sources, providers and limits;
hermetic transport tests alone do not establish sandbox identity.
Flatpak never falls back to raw Secret Service. Snap, Windows, and unsupported
provider configurations fail closed.

Opening, changing authentication, and resetting may invoke trusted OS/provider
UI. Record operations and authentication listing never prompt. The public API
has no interaction option.

Record operations do not acquire any platform provider, including on failure.
Cross-process rotation can therefore report `storeAuthenticationFailed` rather
than `staleSession`. Classic macOS Keychain and Linux Secret Service acquisitions
also reject forbidden interaction before provider calls; neither offers a
portable guarantee against provider-specific access-control UI per call.

## What Keybay protects

Keybay is designed so that:

- its managed persistent files contain no plaintext record values;
- an encrypted file is insufficient without its platform-protected root;
- configured passphrase protection remains necessary even with access to the
  root item and file;
- corruption, wrong keys, unsupported formats, and missing provider state fail
  before plaintext is returned;
- concurrent writers produce one authenticated complete generation; and
- platform selection cannot be redirected by fields in the encrypted file.

The full threat model and numbered evidence-linked invariants are in
[doc/design.md](doc/design.md). The accepted construction is
[RFC 0001](doc/rfcs/0001-per-application-stores.md).

## What Keybay does not protect

Plaintext explicitly returned to an application is ordinary process data.
Keybay does not defend against root/kernel compromise, code injected into the
host process, a malicious Keybay binary, keyloggers, screen capture, terminal
compromise, or rollback to an older complete authentic snapshot. Flatpak reset
removes the encrypted store and staging but retains nonsecret coordination
locks and the portal-owned application secret.
The next successful open creates a fresh store key; restoring an old complete
encrypted store can nevertheless restore access under its old protection.
Changing a passphrase rotates the current store key and re-encrypts every
record; it does not revoke older snapshots or credentials at their issuer.

The CLI disables its own core files, and on Linux makes itself non-dumpable,
because an open session's store key would otherwise persist in a crash dump.
SDK applications hold the same key while a session is open; whether to disable
crash dumps is a process-wide choice left to the host application.

A passphrase does not prevent denial of service by an actor that can delete or
replace both provider state and application files. Best-effort clearing narrows
the lifetime of Keybay-owned mutable buffers but cannot prove erasure of every
Dart VM, cryptographic dependency, or operating-system copy. In particular,
the pinned HKDF implementation returns an immutable key wrapper whose destruction
discards its reference without overwriting the dependency's backing bytes.
The Argon2 production workspace is native memory; Keybay overwrites its retained
workspace view before releasing it. This narrows one specific lifetime without
claiming erasure of dependency-internal hash state or every process copy.

For the CLI, `get` is a disclosure guard rather than an authorization boundary:
it refuses redirected/captured output before decrypting, but a foreground
terminal can display the selected value. `run` necessarily supplies referenced
values to its child process. Neither operation reveals unrelated records.

## Engineering and evidence

Runtime dependencies are exact-pinned and the resolved hosted closure is
checked in CI. Changes run formatting, analysis, unit/adversarial tests, and the
affected genuine provider lanes. Simulator and emulator runs prove API paths,
not physical secure-hardware mediation. Hardware claims are made only from
measured platform metadata and retained qualification.

The current device, lifecycle, and provider evidence is tracked in
[doc/device-security-suite.md](doc/device-security-suite.md). A separate Claude
review and follow-up accepted the five remediations; that review phase is
closed. Findings, retained evidence and remaining qualification gates are
recorded in the [review record](doc/security-review.md).
It is an AI model review, not a human external audit; Keybay has one maintainer.

The [September 21 engineering audit](doc/security-review.md#engineering-audit-2026-09-21)
found no new confirmed vulnerability in the reviewed SDK/CLI source and passed
fresh core, terminal and deterministic tamper checks. That result does not
replace ongoing advisory triage or qualify a signed native release. The
[release-readiness record](doc/release-readiness.md) separates the remaining
distribution gates from completed source checks and retained platform evidence.

The [September 22 pre-release assessment](doc/security-review.md#pre-release-assessment-2026-09-22)
was the first review of the CLI/TUI and the Fleury paths it reaches. It found
three Medium and six Low issues, including one pre-existing; each is resolved
or explicitly accepted in that record.

For SDK 0.2.0, remaining physical lock/reboot, auth-change interruption and
actual backup/restore/transfer work is deferred until devices are available.
Maintained-device Argon2 latency/memory acceptance is lower-priority follow-up.
These are unqualified properties, not release claims; the
[scoped qualification record](doc/qualification-status.md#sdk-020-release-scope)
names the observed configurations. The release adds no performance guarantee
or broader device/provider coverage through those deferrals.

## Reporting

Use GitHub [private vulnerability reporting](https://github.com/danReynolds/keybay/security/advisories/new)
or email **me@danreynolds.ca**. Do not open a public issue for an undisclosed
security bug. Critical and High findings block the next release.

Releases are signed with the maintainer-controlled SSH key. Verify a tag with:

```sh
git verify-tag v<version>
```

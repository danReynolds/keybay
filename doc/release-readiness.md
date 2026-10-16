# Keybay release readiness

SDK and CLI 0.3.0 are published from source `eab2908`. Version 0.3.1 is the
next release candidate: it documents the exported SDK API, declares the SDK's
platforms for pub.dev, and stops the TUI offering Reopen for a store it can
never open.

| Artifact | Publication evidence |
| --- | --- |
| [Keybay SDK 0.3.0](https://pub.dev/packages/keybay/versions/0.3.0) | Pub archive SHA-256 `370148cc0e93ca41edb91b281023eaae90fb6fd5c52ec2a3711977ccd7f95126`; tag `v0.3.0` is unsigned |
| [CLI 0.3.0](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.3.0) | Immutable GitHub release with its release manifest and Homebrew formula; tag `keybay_cli-v0.3.0` is unsigned |
| [Keypass 0.1.0-dev.2](https://pub.dev/packages/keypass/versions/0.1.0-dev.2) | Pinned SDK/CLI dependency; remains a prerelease |

The 0.3.0 tags were published without signatures, so the signed-tag checks in
[verifying releases](../SECURITY.md#verifying-releases) fail for them and the
release audits report it; 0.2.0 and earlier tags are signed. The
[SDK 0.2.0](reviews/2026-10-07-sdk-publication.md) and
[CLI 0.2.0](reviews/2026-10-11-cli-publication.md) publication records keep the
previous release's evidence.

**Upgrading:** V1 stores are preserved but not read or migrated. Keep the old
installation available to transfer required secrets before switching.

## What 0.3.0 changed

Version 0.3.0 removed retired V2 singleton-passphrase conversion and duplicate
release tooling, confirms the vault on every method unlock (methods policy 3),
and fixed underlined input borders in the CLI. The minor version marks both
format changes: 0.2.0 vaults with a passphrase or passkey fail closed and need
their methods removed before upgrading and added back after; platform-only
vaults are unaffected. Policy 3 has unit, adversarial and vector coverage; it
has no renewed device or hardware-key qualification. Keybay still pins published
Keypass 0.1.0-dev.2, not its newer main branch. Use the
[review guide](external-review.md) for published commit/archive baselines.

## Release status

RK bundling, native notices, Linux ABI baseline and publication are complete.
The [candidate record](reviews/2026-10-11-cli-release-candidate.md) preserves
installed Linux checks and attended macOS hardware evidence for 0.2.0, whose
publication records cover its served artifacts; 0.3.0 has no separate
publication record. These do not qualify untested devices or lifecycle
behavior.

SDK and CLI are separate release units; `release.toml` publishes the package
before its dependent CLI. Never replace an already published SDK version.

## Native macOS packaging change

RK owns production bundles and archives. macOS ships a signed AOT module,
matching dedicated `dartaotruntime`, launcher and Keypass hardware libraries.
The single-file hardened executable failed startup on the recorded host;
[macOS packaging](platforms/macos.md#hardened-aot-packaging) retains that evidence.

Preserve these properties in subsequent releases:

1. Preserve the validated `keybay.application_id` through RK's build integration.
2. Resolve companions from the installed layout, never PATH or the working directory.
3. Sign runtime, module and libraries with the intended team, hardened runtime
   and library validation; no JIT/unsigned-executable-memory exceptions.
4. Include every companion in notarization, archive validation, hashes and installation.
5. Test the final installed launcher and served download, including replacement.

The build/notarization troubleshooting chronology is retained in dated release
records. Linux retains its supported executable bundle format.

## Qualification inputs

Run `./tool/test_cli.sh all` for disposable source-level core, macOS and Linux
checks. Installed-release qualification additionally needs the exact packages,
macOS ARM64 with Apple signing/notarization access, and Linux ARM64/x64 provider
environments. Record containers/emulation explicitly. Test replacement while
preserving the store and signing identity.

## Security and scope

See [SECURITY.md](../SECURITY.md) for guarantees and the
[review guide](external-review.md#outstanding-work-at-handoff) for open
advisory/qualification work. Prior AI reviews are not independent human audits.

Deferred: physical lock/reboot, auth-change interruption, actual backup/restore/
transfer and retained-root reinstall procedures; maintained-device Argon2
latency/memory acceptance. Native Wayland clipboard also needs qualification.
Flatpak CLI packaging, Windows, Snap and mobile CLI distribution are outside
this release. None of these untested properties is a passing claim.

Pub/path CLI installations trust the shared Dart VM on macOS and remain
[development builds](../packages/keybay_cli/README.md#development-builds).
Use the signed distribution for production.

## Final publication checks

Run full manual CI on the final main commit; weekly fuzz alone is insufficient.
Keep source, dependency resolution, package bytes, signatures and hashes together.
[SDK release audit](../.github/workflows/audit-release.yml) verifies the signed
tag, exact-commit CI and served Pub archive. The
[CLI release audit](../.github/workflows/audit-cli-release.yml) verifies the
signed tag, release manifest, archives and published Homebrew formula, and
repeats this daily for the newest release. Installed-product checks remain
separate, as in the records above.

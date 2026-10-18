# Keybay release readiness

SDK and CLI 0.3.1 are published from source `ce5d631` with signed tags.
Version 0.3.2 is the next release candidate: it moves to Keypass 0.1.0-dev.3,
which builds desktop hardware support against OpenSSL 3 or 4.

| Artifact | Publication evidence |
| --- | --- |
| [Keybay SDK 0.3.1](https://pub.dev/packages/keybay/versions/0.3.1) | [Signed tag, exact-commit CI and served Pub archive](reviews/2026-10-16-0.3.1-publication.md#sdk) |
| [CLI 0.3.1](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.3.1) | [Signed tag and manifest, served archives matching the stage, Homebrew formula](reviews/2026-10-16-0.3.1-publication.md#cli) |
| [Keypass 0.1.0-dev.2](https://pub.dev/packages/keypass/versions/0.1.0-dev.2) | Pinned SDK/CLI dependency; remains a prerelease |

The 0.3.0 tags are the only ones published without signatures, so the
signed-tag checks in [verifying releases](../SECURITY.md#verifying-releases)
fail for them. The [SDK 0.2.0](reviews/2026-10-07-sdk-publication.md) and
[CLI 0.2.0](reviews/2026-10-11-cli-publication.md) publication records keep the
evidence from that release.

**Upgrading:** V1 stores are preserved but not read or migrated. Keep the old
installation available to transfer required secrets before switching.

## What 0.3.1 changed

Version 0.3.1 documents every exported SDK member, declares the SDK's platforms
for pub.dev, stops the TUI offering Reopen for a store it can never open, and
gives the Homebrew formula a real description. The macOS CLI bundles OpenSSL
3.5.9, which carries the September 29, 2026 advisory's fixes; 0.3.0 bundled
3.6.3. The vault format is unchanged.

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
installed Linux checks and attended macOS hardware evidence for 0.2.0. The
[0.3.1 publication record](reviews/2026-10-16-0.3.1-publication.md) covers that release's served artifacts;
0.3.0 has no separate publication record. These do not qualify untested
devices or lifecycle behavior.

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

# Keybay 0.2.0 release readiness

SDK and CLI 0.2.0 are published. Subsequent source cleanup is unreleased.

| Artifact | Publication evidence |
| --- | --- |
| [Keybay SDK 0.2.0](https://pub.dev/packages/keybay/versions/0.2.0) | [Signed tag, exact-commit CI and served Pub archive](reviews/2026-10-07-sdk-publication.md) |
| [CLI 0.2.0](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.2.0) | [Signed manifest, public downloads, Homebrew upgrade and RK installation](reviews/2026-10-11-cli-publication.md) |
| [Keypass 0.1.0-dev.2](https://pub.dev/packages/keypass/versions/0.1.0-dev.2) | Pinned SDK/CLI dependency; remains a prerelease |

**Upgrading:** V1 stores are preserved but not read or migrated. Keep the old
installation available to transfer required secrets before switching.

## Source after publication

Keypass removed prototype verifier/native-loading exceptions. Keybay removed
retired V2 singleton-passphrase conversion and duplicate release tooling.
Published 0.2.0 still has that V2 conversion; current methods-based and
platform-only encodings are unchanged. Keybay still pins published Keypass
0.1.0-dev.2, not its newer main branch.

Version fields have not advanced with this cleanup. Use the
[review guide](external-review.md) for exact commit/archive baselines.

## Release status

RK bundling, native notices, Linux ABI baseline and publication are complete.
The [candidate record](reviews/2026-10-11-cli-release-candidate.md) preserves
installed Linux checks and attended macOS hardware evidence; the publication
records above cover the served artifacts. These do not qualify untested devices
or lifecycle behavior.

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

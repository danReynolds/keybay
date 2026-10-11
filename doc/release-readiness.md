# Keybay 0.2.0 release readiness

Updated October 11, 2026. The [SDK 0.2.0](https://pub.dev/packages/keybay/versions/0.2.0)
and [Keypass 0.1.0-dev.2](https://pub.dev/packages/keypass/versions/0.1.0-dev.2)
are published. The [SDK publication record](reviews/2026-10-07-sdk-publication.md)
links its signed tag, exact-commit CI and served-archive audit.

[CLI 0.2.0](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.2.0)
is now published through GitHub and Homebrew. The
[CLI publication record](reviews/2026-10-11-cli-publication.md) links exact-commit
CI, the signed tag and manifest, verified public downloads, the actual Homebrew
upgrade, and RK's GitHub installation. The
[candidate record](reviews/2026-10-11-cli-release-candidate.md) preserves the
attended YubiKey and installed Linux evidence without widening its scope.

**Upgrade warning:** V2 neither reads nor automatically migrates V1 stores.
Keep access to the old installation and transfer required secrets before
switching. The installed-product checks confirmed preservation of V1 data,
not migration into the new vault.

The SDK supports system and hardware passkeys. The CLI uses hardware keys with
no website requirement. Keypass remains an explicitly pinned prerelease;
publication does not turn deferred device/lifecycle work into passing evidence.
Dated qualification records retain their original scope and limitations.

## Release status

| Status | Work | Completion evidence |
| --- | --- | --- |
| Complete | RK bundling, notices and Linux ABI baseline. | RK #118 and Keybay #96 merged; signed/notarized macOS and glibc 2.35 Linux artifacts staged. |
| Complete within recorded scope | Installed native candidate qualification. | [Candidate record](reviews/2026-10-11-cli-release-candidate.md): isolated Homebrew upgrade, Linux installed CLI/TUI/protected-store checks, macOS YubiKey unlock in two fresh processes. |
| Complete | Hosted dependencies and SDK publication. | Keypass 0.1.0-dev.2, Fleury 0.1.1 and Keybay SDK 0.2.0 are published; runtime dependencies remain pinned. |
| Complete, CLI | Publish CLI 0.2.0 and verify served artifacts. | [Publication record](reviews/2026-10-11-cli-publication.md): exact source CI, signed tag, served hashes, public Homebrew upgrade and RK installation. |

The SDK's release unit is independent of CLI packaging; `release.toml`
publishes its package before the dependent CLI. Already-published SDK versions
must not be replaced or republished.

## Native macOS packaging change

The original September builder used a single executable. Release-kit now
supports a signed Dart runtime/module bundle, and Keybay's local archive helper
includes its hardware libraries. The October 9 candidate carried those companions through RK staging, signing,
notarization and archive creation. The October 10 installed candidate passed
isolated Homebrew installation and upgrade using that generated formula, plus
post-signing launch and native loading. Public-channel verification subsequently passed; see the publication record.

On October 7, authenticated notarization access succeeded after the developer
agreement was renewed. CLI staging then failed on all three targets because
release-kit invokes `dart compile`, which rejects Keypass build hooks.
No CLI artifact was published. The October 9 follow-up resolved this build
failure while preserving the signed runtime/module and library-validation
contract below. It did not publish a CLI release.

A Developer ID signed, hardened single-file CLI passed signature verification
but was killed before `--version` on macOS 26.2 ARM64 / Dart 3.13.4. A separate
signed AOT module and matching signed runtime passed help/version checks. A
disposable signed CLI fixture also passed protected-store upgrade checks.
Those fixtures establish the candidate format, not a finished release package.

The release integration must preserve these locally implemented properties:

1. Compile the application as an AOT module while preserving the validated
   `keybay.application_id` declaration. The SDK's `keybay_compile --aot-snapshot`
   already embeds it; release-kit must preserve that identity through its build
   integration instead of invoking an unidentified raw compile.
2. Include a dedicated `dartaotruntime` from the matching Dart SDK and a small
   launcher that resolves only its installed companion files. It must preserve
   arguments and process replacement, work outside the repository, and handle
   the Homebrew symlink/layout without finding a runtime or module via PATH or
   the working directory. Linux can retain its supported single-file format.
3. Sign both native files with the intended Developer ID identity, hardened
   runtime, secure timestamps and library validation. Extend signature, digest,
   post-signing launch and stable-identity checks to the complete bundle; do not
   weaken signing with unsigned-executable-memory or JIT exceptions.
4. Carry every bundle file through notarization, staging receipts, archive
   allowlists, checksums and Homebrew installation. Update the archive guard so
   it accepts exactly the intended layout and still rejects traversal,
   unexpected files and unsafe links.
5. Test the final installed launcher and downloaded/notarized artifact, not
   just direct execution of the runtime with a module in a build directory.

This changes distribution plumbing, not the encrypted format or custody model.
The [macOS profile](platforms/macos.md#hardened-aot-packaging) describes the
retained native evidence. Detailed local September 20 receipts are in
`build/security-remediation-20260920/`; local evidence paths are not public
downloads.

## Qualification inputs

The existing SDK/CLI suites provide disposable provider stores, native terminal
and child-process checks, and macOS private-pasteboard / Linux X11 coverage.
`./tool/test_cli.sh all` runs source-level core, macOS and Docker Linux checks.
Release qualification must additionally target the exact package after
installation and replacement, preserving the same store and signing identity.

Required inputs are a macOS ARM64 host with Apple tooling and a Developer ID
identity, authenticated notarization access, Linux x64/ARM64 execution
environments with the required provider stack, and the built candidate packages.
GitHub CI supplies a native Linux x64 lane; local Docker has supplied Linux
ARM64 evidence. Record containers/emulation explicitly rather than claiming
unobserved native hardware. Recheck prerequisites when running the candidate.
The maintainer's tag-signing key is separately needed at publication time.

On September 21, Docker was recovered and fresh macOS CLI provider, Linux
CLI core/provider and Linux SDK provider checks passed. The
[desktop follow-up](cli-qualification-status.md#desktop-provider-follow-up-2026-09-21)
records exact scope. The October 11 candidate record supplies the later
installed-package and notarization evidence; the publication record adds the
later public-channel checks.

## Security and scope

The September 21 engineering audit found no new confirmed vulnerability or
runtime security fix required before release preparation. Fresh checks passed
505 SDK tests (three D-Bus skips), 211 CLI tests, native terminal regressions and
20,000 deterministic tamper mutations. See the [review record](security-review.md#engineering-audit-2026-09-21).
This was not an independent external audit or renewed physical qualification.
The September 22 pre-release assessment then covered the CLI/TUI. Its findings
and resolutions are in the [review record](security-review.md#pre-release-assessment-2026-09-22).
The CLI is not published to pub.dev because a Pub installation runs in the
Dart VM, where the macOS Keychain item would trust every Dart program rather
than the signed release binary (KB-SA-04).

Known limits remain: best-effort memory clearing, no complete-snapshot rollback
protection, and namespace-only isolation for ordinary desktop applications.
Passphrases are recommended for high-value desktop credentials. Changing a
passphrase does not revoke copies of older snapshots or credentials at their
issuer. See the [security policy](../SECURITY.md).

The [Go reference maintenance issue](https://github.com/danReynolds/keybay/issues/75)
and [Apple qualification refresh](https://github.com/danReynolds/keybay/issues/76)
remain tracked follow-ups. New applicable security findings can change release
priority; the reviewed signals do not currently establish a new runtime defect.

The agreed SDK 0.2.0 scope still defers the remaining physical lock/reboot,
auth-change interruption, backup/restore/transfer and retained-root reinstall
procedures, plus maintained-device Argon2 latency/memory acceptance. They are
not passing claims or newly added blockers. Native Wayland clipboard needs its
own evidence before it is advertised as qualified. Flatpak CLI packaging,
Windows, Snap and mobile CLI distribution remain outside this release.

## Final publication checks

Run full manual CI on the final main commit after release/dependency changes;
the weekly fuzz run alone does not satisfy release CI. Keep the tested source,
package bytes, signed native files and hashes together. SDK publication is
witnessed by `.github/workflows/audit-release.yml`, which verifies the signed
source tag, exact-commit CI and the archive served by Pub. That workflow does
not verify CLI native archives or Homebrew, which need their own final checks.

SDK publication and its verification are recorded in the
[October 7 publication record](reviews/2026-10-07-sdk-publication.md).
The [CLI installation guide](../packages/keybay_cli/README.md#install) and
homepage now link the published native release. Local path activation remains
a development option with a different macOS Keychain trust boundary, not the
recommended production installation.

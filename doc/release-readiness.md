# Keybay 0.2.0 release readiness

Updated October 7, 2026 after publication of the
[SDK 0.2.0](https://pub.dev/packages/keybay/versions/0.2.0), including passkey
protection. The [publication record](reviews/2026-10-07-sdk-publication.md)
links the signed tag, exact-main-commit CI and served-archive audit.
The CLI/TUI implementation is integrated but 0.2.0 native publication remains
blocked on release-kit companion packaging and installed-distribution
qualification. Keypass and Fleury resolve from exact hosted releases.
The SDK ships on pub.dev; the CLI ships only as native binaries through
Homebrew and GitHub releases. Dated qualification records retain the evidence
and limitations of their original runs.

The October 2 passkey integration adds an exact-pinned Keypass
dependency and a new authenticated methods format. Its engineering review and
regressions do not renew the older physical-device evidence. With explicit owner
approval, Keypass became public and `0.1.0-dev.2` was published on pub.dev on
October 6. The SDK and CLI now pin that hosted version and its reviewed archive.
The CLI hardware UI is implemented; demo passkey UI and end-to-end native
Keybay vault qualification remain separate work; the SDK accepts system and hardware credentials.

The October 4 hardware follow-up implements TUI enrollment/removal, hardware
unlock for ordinary commands, and local native dependency bundling. Local
signed split-runtime loading and extracted help/version checks pass. See
[hardware packaging](cli-hardware-packaging.md) for the exact evidence. The
SDK publication is complete; final CLI installed-distribution gates remain.
The current release-kit checkout already supports a signed Dart runtime/module
bundle; carrying the new hardware companions through its release stages remains
integration work. The older single-file description below records the original
September finding, not the current release-kit implementation.

## Remaining work, in order

| Priority | Work | Completion evidence |
| --- | --- | --- |
| P0, native macOS | Carry the locally qualified runtime/module and hardware library companions through release-kit staging, signing, archive and Homebrew publication. | Reproducible bundle from the release candidate, stable application/signing identity, and successful launch after signing. |
| P0, native CLI | Qualify the actual installed packages and upgrades on macOS ARM64, Linux x64 and Linux ARM64, as configured in `release.toml`. | Artifact hashes, observed OS/ABI, protected-store continuity, CLI/TUI/child-process checks, and macOS notarization/downloaded-launch evidence. A source build or ad-hoc archive is insufficient. |
| Complete, hosted dependencies | Pin Keypass `0.1.0-dev.2` and Fleury `0.1.1`; the latter includes the former separate widget catalog. Remove the development Git pins and override. | Content-hashed hosted archives and the runtime dependency-closure gate. Installed CLI checks remain in the native distribution gate above. |
| Complete, SDK | Reconcile documentation, assess security monitoring and publish SDK 0.2.0. | [Publication evidence](reviews/2026-10-07-sdk-publication.md): full CI on the tagged main commit, successful monitoring assessment, signed tag and verified Pub archive. |
| Release, CLI | Publish the dependent CLI after native qualification, then verify its distribution channels. | Signed CLI tag, native downloads and Homebrew installation/upgrade checks. |

The SDK's release unit is independent of CLI packaging; `release.toml`
publishes its package before the dependent CLI.

## Native macOS packaging change

The original September builder used a single executable. Release-kit now
supports a signed Dart runtime/module bundle, and Keybay's local archive helper
includes its hardware libraries. Those hardware companions still need to pass
through release-kit's staging, signing, notarization and Homebrew path. The
existing post-signing launch check must remain a gate.

On October 7, authenticated notarization access succeeded after the developer
agreement was renewed. CLI staging then failed on all three targets because
release-kit invokes `dart compile`, which rejects Keypass build hooks.
No CLI artifact was published. The builder must consume native assets while
preserving the signed runtime/module and library-validation contract below.

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
records exact scope. The final installed-package and notarization gates above
remain open.

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
After CLI publication, update its installation guide and homepage with the
actual native release and verification links. Until those artifacts exist,
local path activation and the identity-aware development build remain the
documented CLI dogfood paths.

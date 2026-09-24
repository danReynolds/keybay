# Keybay 0.2.0 release readiness

Reviewed September 21, 2026 against `7965a5ea02e848a4de7216b094563cba5a0c40ee`;
updated September 24 to ship the CLI only through Homebrew and GitHub releases.
The SDK and CLI/TUI implementation are integrated. The scoped SDK release is
prepared; CLI publication still needs native distribution qualification and
hosted Fleury dependencies. The SDK ships on pub.dev; the CLI ships only as
native binaries through Homebrew and GitHub releases. Neither 0.2.0 package has
been published in this closeout. This page tracks remaining work; dated
qualification records retain the evidence and limitations of their original
runs.

## Remaining work, in order

| Priority | Work | Completion evidence |
| --- | --- | --- |
| P0, native macOS | Build and package a dedicated signed Dart runtime, signed AOT module and launcher through release-kit. Update the archive contract and Homebrew installation together. | Reproducible bundle from the release candidate, stable application/signing identity, and successful launch after signing. |
| P0, native CLI | Qualify the actual installed packages and upgrades on macOS ARM64, Linux x64 and Linux ARM64, as configured in `release.toml`. | Artifact hashes, observed OS/ABI, protected-store continuity, CLI/TUI/child-process checks, and macOS notarization/downloaded-launch evidence. A source build or ad-hoc archive is insufficient. |
| P0, Fleury | Publish reviewed Fleury and fleury_widgets versions that include [danReynolds/fleury#269](https://github.com/danReynolds/fleury/pull/269) (`93816cde`), then replace the CLI's exact Git pins with them. rk refuses to release a unit built from Git dependencies (RK-DART-201), even when they are pinned to a commit. | Reviewed dependency closure and installed CLI checks. Fleury publication is a separate release action; it has not happened as part of this work. |
| P1 | Reconcile documentation, assess the latest security-monitoring results and validate the final candidate. | Current installation/release claims, no unresolved applicable blocking findings, full manual CI on the exact final main commit, and retained package/archive receipts. |
| Release | Publish the SDK before the dependent CLI, then verify the channels actually served to users. | Signed tags, SDK Pub archive audit, CLI native download and Homebrew installation checks. Publishing is a separate action after preparation. |

The hosted-dependency work can proceed alongside native packaging. The SDK's
release unit is independent of CLI packaging; `release.toml` publishes its
package before the dependent CLI.

## Native macOS packaging change

The current release-kit Dart builder uses `dart compile exe`, and its binary
pipeline represents one executable through signing, notarization, archiving
and Homebrew installation. Keybay's local archive helper likewise packages one
`keybay` file. The existing post-signing launch check must remain a gate.

A Developer ID signed, hardened single-file CLI passed signature verification
but was killed before `--version` on macOS 26.2 ARM64 / Dart 3.13.4. A separate
signed AOT module and matching signed runtime passed help/version checks. A
disposable signed CLI fixture also passed protected-store upgrade checks.
Those fixtures establish the candidate format, not a finished release package.

Implement the bundle through the existing build and release steps:

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

After publication, replace the prepared/unreleased statements in the package
changelogs, README, CLI installation guide and homepage with the actual release
and verification links. Until those artifacts exist, local path activation and
the identity-aware development build remain the documented dogfood paths.

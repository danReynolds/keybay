# External review guide

Prepared October 11, 2026; published baselines updated for 0.3.2 on
October 18, 2026. This handoff defines the source, threat model,
review surface and evidence gaps. It does not claim a completed human security
audit. Review the vault construction together with the resolved Keypass dependency.

## Source and published baseline

| Target | Identity |
| --- | --- |
| Implementation baseline | [`1fb82cbfc08d14f4d046b6bde8e32801e1121357`](https://github.com/danReynolds/keybay/tree/1fb82cbfc08d14f4d046b6bde8e32801e1121357), the published 0.3.2 source |
| Published SDK | [0.3.2](https://pub.dev/packages/keybay/versions/0.3.2), signed tag `v0.3.2`, source `1fb82cbfc08d14f4d046b6bde8e32801e1121357` |
| SDK Pub archive SHA-256 | `34930317e208be191246710a5f4da94a3eeb27dd415c2d87c0239913bdcb2b01` |
| Published CLI | [0.3.2](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.3.2), signed tag `keybay_cli-v0.3.2`, source `1fb82cbfc08d14f4d046b6bde8e32801e1121357` |
| Resolved Keypass dependency | Exact-pinned [0.1.0-dev.3](https://pub.dev/packages/keypass/versions/0.1.0-dev.3); archive SHA-256 `e11a551ba04bd9311bd76276d00828502999221f9be4cc408eaf83782c76d77d` |
| Keypass source for joint review | [`000988de96d736b5d8725de06426196b4a705582`](https://github.com/danReynolds/keypass/tree/000988de96d736b5d8725de06426196b4a705582), the published 0.1.0-dev.3 source |

The [0.3.2 publication record](reviews/2026-10-18-0.3.2-publication.md) gives
its source, CI, signed tags and artifact hashes, and how the Keypass archive was
verified against its source. The 0.3.0 tags are unsigned;
see [verifying releases](../SECURITY.md#verifying-releases). The
[SDK 0.2.0](reviews/2026-10-07-sdk-publication.md) and
[CLI 0.2.0](reviews/2026-10-11-cli-publication.md) publication records keep
that release's installation evidence. Versions 0.3.1 and 0.3.2 change
documentation, pub.dev metadata, the TUI failure view and the Keypass build
dependency, not the vault construction.
Version 0.3.0 removed retired V2 singleton-passphrase reading/migration and
duplicate release tooling, and writes methods policy 3, which adds a credential
confirmation; 0.2.0 policy-2 and old singleton packages fail without mutation.
The platform-only encoding is unchanged. There is no automatic conversion.
Version fields alone do not identify a checkout's contents.

Capture `git rev-parse HEAD`, `git status --short`, toolchain versions,
`pubspec.lock`, native library versions/hashes and the precise tested artifact.
`dart pub get --enforce-lockfile` preserves this repository's hosted resolution.
A consumer has its own lockfile. Checking out new Keypass main does not change
Keybay's dependency; any local override is a separate joint-test configuration
and must not be represented as the published integration.

## Read in this order

1. [Security policy](../SECURITY.md) and [design](design.md): threat model,
   platform identity, storage invariants and exclusions.
2. [SDK guide](sdk.md) and [CLI guide](../packages/keybay_cli/README.md): actual
   API behavior, disclosure paths, native setup and recovery.
3. [RFC 0003](rfcs/0003-passkey-methods.md): method selection, derivation, HPKE,
   authenticated directory, transaction and key-rotation rules. It supersedes
   authentication sections of the [original V2 RFC](rfcs/0001-per-application-stores.md).
4. [Keypass review guide](https://github.com/danReynolds/keypass/blob/main/doc/external-review.md):
   verifier, provider/CTAP trust, PRF association and native result ownership.
5. [Qualification](qualification-status.md), [CLI qualification](cli-qualification-status.md),
   [device suite](device-security-suite.md) and [release scope](release-readiness.md).
6. [Prior security reviews](security-review.md) and [watcher assessments](../watchers/reports/SUMMARY.md).

Dated reviews and RFC milestone notes retain their original scope. The September
reviews predate the completed passkey integration and do not audit its HPKE or
native passkey boundary. `doc/reviews/` contains plans as well as receipts; read
status/date/source before treating a document as current behavior. Local ignored
`build/qualification/` receipts mentioned in publication records are not all in
a fresh clone; obtain the named redacted artifacts from the maintainer when
required. Missing evidence must remain a gap in the report.

## Boundaries to review

| Boundary | Implementation entry points | Tests/evidence |
| --- | --- | --- |
| Open/enroll/remove and selection | [public facade](../packages/keybay/lib/keybay.dart), [engine](../packages/keybay/lib/src/v2/keybay_v2.dart), [methods](../packages/keybay/lib/src/v2/auth_methods.dart), [passkey input](../packages/keybay/lib/src/v2/passkey_credential.dart) | `v2_auth_api_test.dart`, `v2_passkey_engine_test.dart`, `v2_passphrase_engine_test.dart` |
| Method cryptography and bounded packages | [method crypto](../packages/keybay/lib/src/v2/format/method_crypto.dart), [package codec](../packages/keybay/lib/src/v2/format/auth_package.dart), [passphrase KDF](../packages/keybay/lib/src/v2/passphrase_kdf.dart) | `v2_method_crypto_test.dart`, `v2_auth_package_test.dart`, [independent vectors](../packages/keybay/test/vectors/method_crypto.md) |
| Manifest/frame authentication and transactional storage | [format](../packages/keybay/lib/src/v2/format/store_format.dart), [reader](../packages/keybay/lib/src/v2/framed_store_reader.dart), [writer](../packages/keybay/lib/src/v2/framed_store_writer.dart), [rotation](../packages/keybay/lib/src/v2/framed_store_rotation.dart), [auth metadata](../packages/keybay/lib/src/v2/auth_metadata_commit.dart) | Framed-reader/engine adversarial suites, process-crash and contention tests, `v2_auth_headroom_test.dart` |
| Identity, provider selection and native files | [host binding](../packages/keybay/lib/src/v2/host_binding.dart), [platform protector](../packages/keybay/lib/src/v2/platform_protector.dart), [POSIX files](../packages/keybay/lib/src/v2/posix_store_files.dart) and platform adapters in that directory | Platform contract tests, `v2_posix_store_files_test.dart`, [real-platform regression](platform-regression.md) |
| CLI/TUI disclosure and input | [CLI source](../packages/keybay_cli/lib/src/), [clipboard](../packages/keybay_cli/lib/src/tui/clipboard.dart) | CLI unit/PTY/prompt tests and [CLI qualification](cli-qualification-status.md) |
| Dependency, native bundle and artifact integrity | `pubspec.lock`, [release.toml](../release.toml), [CI](../.github/workflows/ci.yml), Keypass build hook | Dependency closure tests, [release audit](../.github/workflows/audit-release.yml), publication receipts |

Test filenames above are under `packages/keybay/test/` unless otherwise noted.

Prioritize whether an untrusted package/record can redirect platform identity,
select a different method, bypass the manifest, release a provisional key or
commit stale authentication metadata. Check HPKE context binding and low-order
inputs; rotation must trust only already-authenticated survivor public keys.
Verify cancellation, native result disposal and crash/concurrent-writer behavior
at every transition. Review bounds before Argon2, allocation or native ceremony.

The policy is `platform AND (passphrase OR passkey A OR ...)`, with at most one
passphrase and eight total methods. An authenticated session may change policy.
Removing the last method returns to platform-only protection. There is no atomic
passphrase replacement; remove/add are separate commits. Old complete snapshots
remain usable with their old credentials/platform material. Direct hardware RP
namespaces and ordinary desktop application IDs do not authenticate executables.
These are explicit design limits, not gaps to conceal in a support claim.

## Outstanding work at handoff

| Item | Classification and current evidence |
| --- | --- |
| [Go reference dependency #75](https://github.com/danReynolds/keybay/issues/75) | Non-shipping tool maintenance. Recorded import-level analysis found affected SSH/OpenPGP packages unused; no reachable shipped vulnerability established. Upgrade/recheck and retain vector agreement. |
| [Apple qualification #76](https://github.com/danReynolds/keybay/issues/76) | Refresh provider isolation, lock/unlock, missing-root and deletion/reset receipts on patched physical hosts. Existing OS advisories do not establish a Keybay bypass. |
| Linux clipboard | Current `wl-copy`/`xclip` calls do not mark content sensitive; clipboard history may retain disclosed values. Follow-up in the [prior assessment](security-review.md#pre-release-assessment-2026-09-22). macOS markers are conventions, not protection from a hostile reader. |
| Physical lifecycle and performance | Lock/reboot, auth-change interruption, actual backup/restore/transfer and maintained-device Argon2 acceptance remain deferred in the [SDK scope](qualification-status.md#sdk-020-release-scope). |
| Passkey coverage | Keypass has bounded macOS/provider and single-key USB/phone-NFC receipts. Android OS-provider, Windows runtime, other hardware/vendors and wider lifecycle/production packaging remain unqualified. Keypass Windows work cannot supply a Keybay Windows platform root. |
| Independent audit | Internal/AI-assisted reviews and test vectors are engineering evidence. No completed human audit of the combined construction is claimed. |

The latest retained assessed watcher run is [October 12](../watchers/reports/2026-10-12-38221007653-1/assessment.md).
It found no new established Keybay defect and retained #75/#76. A successful scan
job is not a zero-findings or full-reachability guarantee. Recheck current
advisories and open issues when beginning the audit.

## Reproduce and deliver findings

With the documented [native build prerequisites](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md):

```sh
dart pub get --enforce-lockfile
dart analyze --fatal-infos
./tool/test_core.sh
(cd packages/keybay_cli && dart test -x integration)
```

These are core checks, not physical qualification. [Platform regression](platform-regression.md)
describes Linux/macOS/native CI and separate attended device procedures. Review
both independent crypto references under `packages/keybay/test/vectors/` and
`tool/v2_suite1_reference_go/`; do not overwrite checked-in vectors as a substitute
for comparison. Reviewers should use disposable stores and keys. Do not run reset,
PIN administration or provider deletion against personal data.

Return a dated report with exact source/dependencies/artifacts, reviewed and
excluded surfaces, repeatable findings with severity/impact, platform-specific
observations and unresolved assumptions. Report undisclosed vulnerabilities via
[private reporting](../SECURITY.md#reporting), without secrets or personal vault
material. Record remediation and retest against a new exact commit. Completion
of review is separate from publication and supported-platform qualification.

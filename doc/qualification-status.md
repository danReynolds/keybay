# Latest platform qualification

Evidence reviewed **2026-09-07**. This is a dated, reviewed summary of retained
local evidence, not release certification or an automatically refreshed dashboard.
New regression runs write individual JSON reports; update this summary after
reviewing their results and source applicability. Times below are UTC.

## Claude review remediation

The separate [Claude review](reviews/2026-09-06-claude.md) has been received.
The [remediation record](security-review.md#remediation-of-the-claude-findings)
covers the macOS x64 ABI correction, provider-free record operations, Argon2
workspace clearing and documentation fixes. The reviewed immutable snapshot is
`88c9cb5e…`; remediation verification is recorded separately from its earlier
receipts. Follow-up review of the changes and physical lifecycle/release gates
remain open.

The corrected runtime is commit `48e2bb80…`, SHA-256
`57163d1f9714024acf5ad3d86ea9ef7874684703b6592e912dfeea29b46cd5cf`
(40 SDK Dart files, using the digest rule below). Commit `b4b198a…` adds only a
test-worker startup correction: its cold-compilation allowance is separate from
the unchanged SDK lock deadline. The initial Intel CI attempt exposed that
five-second fixture timeout; its failure is retained.

The [remediation CI run](https://github.com/danReynolds/keybay/actions/runs/34073634184)
passed all 14 normal jobs at exact clean source `b4b198a…`; the scheduled fuzz
canary was skipped as intended. Native Intel macOS passed 502 core tests
with three host-specific D-Bus skips, all seven real Keychain tests, and the
public facade. The actual `macos_x64` Dart ABI is recorded in its reports.
Native ARM64 macOS, Linux, two-app Flatpak, Android API 31/36 and the iOS
simulator passed. Minimum Dart, analysis, formatting, dependency/publish checks
and the existing repository checks passed too. The
[initial run](https://github.com/danReynolds/keybay/actions/runs/34073103276)
at `48e2bb80…` retains the Intel fixture-startup failure.

Local ARM64 passed 502 core tests and all seven native Keychain tests; the
repository tools passed 40 tests and analysis was clean. Local Rosetta x64
passed the complete core suite, but two native fixture attempts timed out in
passphrase preparation. A standalone JIT comparison also timed out on the
original reviewed runtime; this does not establish the timing cause or a
Rosetta native-lane pass. AOT KDF vectors matched in five fresh processes on
ARM64 and five under Rosetta. Measurements remain observations without accepted
device budgets; the before/after ARM64 comparison ran on a loaded host.

The [local follow-up pack](../build/qualification/claude-remediation-20260907/REVIEW_NEXT.md)
retains the diff, source identity, public reports and failed attempts. No physical
device or signed-app run was repeated for this remediation. Its changed reader,
KDF and POSIX boundaries must be considered before carrying earlier evidence
forward. The original Claude review pack remains unchanged and verifies.

The platform table and remaining sections below retain the **Sep 6 baseline**.
Their `current runtime` and `unchanged implementation` descriptions refer to the
baseline digest recorded there, not the corrected runtime above. Remaining
physical lifecycle, release-configuration, maintained-device Argon2 acceptance
and Claude follow-up review gates remain open.

## Platform coverage

| Platform / profile | Latest evidence | What passed | Remaining qualification |
| --- | --- | --- | --- |
| **Shared SDK** | **Pass**, Sep 6; current runtime | Latest local `core` lane: 493 passed, three real D-Bus cases skipped on macOS; Dart 3.13.3 analysis clean. Includes nine additional source-review regressions for native rotation contention, crypto workspace ownership and concurrent portal cancellation. Earlier Linux/Flatpak evidence passed the real D-Bus cases. | Independent external crypto/security review; maintained-device Argon2 acceptance budgets. |
| **macOS file Keychain** | **Pass**, Sep 6 16:37, native CI and local Dart 3.13.3 | Seven tests: bounded root access, exact provider lifecycle, private files, persistence, passphrase/reset, and locked-provider record operations. Current and stale sessions are prepared before locking; native locked status is verified, current operations succeed and stale access fails closed. Disposable Keychain deleted; user search list and default preserved. The public facade separately passed on the CI account. | Unlock/recovery after a provider lock is not covered by this fixture. The separate Developer ID row covers bounded genuine-account continuity. Other signing/runtime transitions remain open. |
| **macOS signed app** | **Pass**, Sep 5 20:02; unchanged platform/common implementation, native Apple Development signing | Signed SDK baseline; passphrase-protected store seeded by build 101 and reopened without initialization by build 102. Explicit phase results, distinct code hashes, Apple-trusted signatures, exact sole Keychain group and sandboxing verified. Provider root, store and staging file absent after reset; harness exited; signing configuration and Keychain settings preserved. | Developer ID distribution/release upgrades, entitlement transitions, physical lock/reboot and reinstall. This qualifies the recorded development-signed profile and unchanged Apple/common implementation, not distribution signing. |
| **macOS single-file Developer ID** | **Failed**, Sep 6; dedicated hardened AOT SDK fixture | Trusted signature, secure timestamp, hardened-runtime flag and empty entitlements verified. Actual launch was killed before fixture startup. A minimal program without Keybay reproduces the failure; signed control without hardened runtime runs. No test store created; user Keychain settings preserved. | Single-file product packaging remains deferred with CLI work. The native module form below clears the SDK continuity check; it does not repair the single-file executable. |
| **macOS Developer ID runtime/module** | **Pass**, Sep 6 13:37; current runtime, native host | Separately signed AOT builds 101/102 reopened the passphrase-protected store without initialization. Hardened runtime, empty entitlements, matching team/designated requirements and changed module hashes verified. Native exits passed; provider/store/stage/control absent; user Keychain settings preserved. An ad-hoc module was separately rejected. | Notarization, entitled-app distribution, runtime/toolchain upgrades and other native configurations. Both modules used the same SDK and signed runtime; no format or signing-team migration. |
| **Ordinary Linux** | **Pass**, Sep 6 16:37; current runtime, native Ubuntu x64 CI; arm64 Docker also passed | Six tests: POSIX flags, clean-account directories, raw Secret Service root lifecycle, second-data-root rejection, public SDK persistence/passphrase/reset, and locked-provider fail-closed behavior. Private disposable provider state. | Additional supported provider configurations. Namespace isolation is not OS-enforced application isolation here. |
| **Flatpak** | **Pass**, Sep 6 16:39; current runtime, native Ubuntu 24.04 x64 CI; nested arm64 Docker also passed | Two-app identity/secret/file isolation, concurrent first use, no fallback, lifecycle/reset and provider restart passed. Real GNOME prompts passed user cancellation, timeout and two overlapping cancellations; both stores reopened without provider restart. Fixed a pending blocking pipe read that previously kept cancelled processes alive. Native descriptor/process regression and cleanup passed. | Other provider configurations. Timeout recovery includes explicitly dismissing any remaining native dialog; it does not establish automatic dialog dismissal. This covers the recorded GNOME backend. |
| **Android** | **Physical pass**, Sep 6 15:47 crash recovery and 01:08 Profile/AOT upgrade; Sep 5 00:16 baseline and 20:56 process continuity; unchanged platform/common implementation, Pixel 6a / Android 16 / API 36. Native CI emulator baselines passed Sep 6 16:41–16:42 on API 31 and API 36. | Six substantive baseline tests plus source/nonce metadata: native hardware-key assertion, ciphertext/reopen/passphrase/reset, all 32 contended writes, tamper rejection, missing root and same-alias replacement. Process continuity passed separately. Upgrade from signed build 101 to distinct AOT build 102 preserved the app UID, signer and both records without initialization; missing/wrong passphrases rejected, correct passphrase accepted. Matching source/nonce/build receipts and two native self-exit/code-zero records verified. Control/store/stage removed; package absence verified across all profiles. Crash qualification then passed two exact SIGKILLs, native PID/UID/user/package exit checks and recovery in a third process. Passphrase policy, acknowledged records, bounded sequence recovery, subsequent writes and reset/package cleanup passed. | Physical auth-change interruption, reboot/relock, backup/restore/transfer, peer-app procedures and other maintained devices. Upgrade covers a debug-signed Profile/AOT app with the same SDK and store format in both builds, using clean exits. Hardware baseline establishes TEE **or** StrongBox, not StrongBox specifically. |
| **iOS** | **Physical pass**, Sep 6 14:38 upgrade and 14:39 crash recovery; Sep 5 baseline and process continuity; iPhone 16 / iOS 18.7.3. Simulator CI passed Sep 6 16:42. | Baseline ciphertext/private files/backup exclusion, passphrase/reset and all 32 contended writes. Signed Profile/AOT upgrade 101 to 102 preserved the passphrase store without initialization, with stable signing identity and distinct binaries. Crash qualification verified two exact native SIGKILLs after seed and during numbered writes; a third process preserved acknowledged records/auth policy, recovered the last acknowledged sequence or its successor, and wrote again. Native exits/process absence and control/store/stage/acknowledgment cleanup passed. | Lock/reboot, physical auth-change interruption, access-group transitions, actual backup/restore/transfer and other maintained devices. Both upgrade builds use the same SDK/format; crash signals are not placed within a specific syscall. |

Windows and Snap are deferred and have no qualification claim. Hardware
credentials, rollback anchors and root rotation are also outside this scope.

## Additional checks already recorded

- The [adversarial source review](security-review.md#adversarial-source-review-2026-09-06)
  found no additional confirmed SDK correctness or security defect in the reviewed
  paths. SR-004 corrects an overbroad HKDF memory-clearing claim. Runtime source,
  format, API and dependencies are unchanged; nine new regressions use the existing
  core lane. The local [review record](../build/qualification/sdk-adversarial-review-20260906/review.json)
  and [core log](../build/qualification/sdk-adversarial-review-20260906/core.log)
  record 493 passes and three host-specific skips; the run's dirty-source flag represents
  the new uncommitted tests against base `80873887…`, not a runtime change.
  The complete [follow-up CI run](https://github.com/danReynolds/keybay/actions/runs/34045994325)
  passed at `e179370b…` on Sep 6 16:43 UTC: all 13 normal jobs passed and the
  scheduled fuzz canary was skipped as intended. All nine retained SDK platform
  reports name that exact clean source. Native Linux/macOS core, minimum Dart,
  real desktop providers, two-app Flatpak, Android API 31/36 emulators and the
  iOS simulator passed. Analysis, formatting, dependency/publish checks and the
  existing repository checks passed too. This adds regression evidence for the
  unchanged runtime; it adds no physical-device qualification.

- The [security review handoff](security-review.md) records the fixed portal
  cancellation defect, native AOT identity correction and qualified macOS
  runtime/module form. External
  review awaits a selected reviewer. The [mobile failure procedures](mobile-failure-qualification.md)
  now have physical crash passes on both Android and iOS. Remaining
  lock/reboot/restore phases are pending.

- Upgrade qualification passed physically on Android and iOS using signed
  builds 101/102, with host orchestration/receipt rejection tests also passing. The fixture now binds mode,
  build and process ID into its receipt; the older physical continuity receipts
  remain evidence for their recorded source and unchanged mobile/common implementation.
- Eight native macOS process-crash cases passed Sep 6: writes and passphrase rotation
  killed during staging, before replacement, after durable replacement and
  after acknowledgment. Recovery, credential selection, retained records,
  staging cleanup and subsequent writes passed. The provider and KDF are test
  implementations; this does not qualify mobile crashes or sudden power loss.
- Standalone Dart 3.11 SDK: 482 passed, five skipped (three D-Bus tests and two
  workspace-only guards), with the current runtime and compile helper. Offline
  dependency resolution and standalone analysis passed. The latest Dart 3.12
  SDK run is recorded above.
- Independent Go implementation matched 11 format/crypto outputs; 20,000 reader
  mutations passed across eight mutation classes. These are engineering checks,
  not an independent third-party security review.
- Dependency advisory scan recorded no runtime dependency matches at the time
  of that scan. Publish dry run passed; nothing was uploaded.
- Pixel Profile/AOT Argon2 measurements: five reference checks passed; first
  derivation 3.468 s, subsequent derivations 0.465–0.532 s. Whole-app peak RSS was
  about 351.6 MiB. No accepted latency/memory budget has been defined, so these
  measurements do not clear a performance gate.
- Latest complete repository-tool validation recorded 40 passing tests, clean
  Dart analysis, ShellCheck and pinned workflow lint. The signed-macOS and
  mobile runner checks include rejection of stale app receipts,
  launcher-only success and leftover fixture files. CI uses the shared commands
  against the published snapshot. All SDK platform reports passed at
  `5c1b4dd1…`. Earlier failures exposed stale formatter/site/transcript checks
  and a disposable macOS Keychain unlock failure. The locked-session test now
  needs one verified lock and direct fixture deletion; cleanup cannot mask the
  primary test error. Linux CI now propagates nested-shell failures and gives
  its locked-provider fixture a private runtime directory. The full-cost Argon2
  vector test has a two-minute correctness deadline after exceeding 30 seconds
  on shared minimum-SDK CI; its parameters and expected output are unchanged.
  Device performance acceptance remains separate. The final full CI run passed
  at `e5b68a5c…`; no SDK runtime change was needed.

## Evidence and source applicability

The current `packages/keybay/lib/**/*.dart` runtime hash includes the Linux
portal cancellation fix and native AOT identity correction:

```text
4f88c9e5546a35a5e1827d8b12fcaa909c48a6370a966542584ae713535d1cf9
```

Digest rule: sorted repository-relative Dart path, NUL, file bytes, NUL. This
compares SDK runtime source, not every harness, binary or dependency. The prior
whole-runtime hash was `d9b088ab…`; the portal fix produced `c9eb1b75…`. The
subsequent native AOT correction changed only `application_identity.dart`. The
common storage engine, format, Apple/Android authenticated identity and provider
adapters are unchanged. Ordinary declared-identity resolution has new native
module coverage; existing source/activation/install modes passed regression.
Their retained receipts remain evidence for those unchanged implementations, not full-tree
hash matches to this latest source.

The older physical iOS and Sep 4 signed-macOS receipts use runtime hash `8ef27d64…`. Their
historical `matchesCurrent` fields refer to the time they were recorded. The
signed-macOS and physical-iOS runs use the prior `d9b088ab…` hash. The iOS baseline
used snapshot `d9edb345…`; final process continuity used `b2f26814…`. Between
them, only the lifecycle fixture's public receipt output, qualification tooling,
tests and documentation changed. The Apple/common implementation and baseline
scenarios match the current worktree.
Android process continuity used snapshot `2308c2ef…`, adding its host runner,
tests and documentation. It reused the shared mobile fixture unchanged.
Android upgrade used snapshot `93633673…`, adding build/mode-bound receipts,
passphrase checks and upgrade orchestration. Its Android/common implementation
is unchanged. The current harness/runners additionally implement crash mode;
host regressions preserve the earlier process and upgrade paths. The new crash
runners have now executed physically on both Android and iOS. Android crash
qualification used `7c8a0527…`, whose only changes after the passing CI code
revision are qualification documents. Both upgrade builds used the same SDK
and store format; no version migration is claimed.

The physical iOS upgrade/crash runs used published commit `387c0d97…`.
The [SDK platform CI run](https://github.com/danReynolds/keybay/actions/runs/34041891569)
used `5c1b4dd1…`: all nine SDK regression reports passed, while its overall
workflow failed the separate CLI quickstart transcript check. The follow-up
[full CI run](https://github.com/danReynolds/keybay/actions/runs/34042688334)
**passed** at `e5b68a5c…`: all thirteen required jobs and all nine SDK
regression reports passed; the scheduled fuzz canary was correctly skipped.
The SDK runtime, dependency locks and physical iOS harness
are byte-for-byte unchanged across these revisions; only tests, qualification
tooling and documentation changed. Failed runs remain retained as history.

These links resolve to retained **local build artifacts**, which are not
included in a fresh checkout:

- [Physical Android crash qualification](../build/qualification/android-crash-20260906T154620Z/observation.json),
  [native report](../build/qualification/android-crash-20260906T154620Z/crash/report.json),
  and [reproduction instructions](../build/qualification/android-crash-20260906T154620Z/REPRODUCE.md).
- [Physical iOS upgrade/crash follow-up](../build/qualification/ios-physical-followup-20260906/observation.json),
  [upgrade report](../build/qualification/ios-physical-followup-20260906/upgrade/report.json),
  [crash report](../build/qualification/ios-physical-followup-20260906/crash/report.json),
  and [reproduction instructions](../build/qualification/ios-physical-followup-20260906/REPRODUCE.md).
- [Public CI and iOS evidence addendum](../build/qualification/signing-followup-20260906/security-review/keybay-sdk-review-20260906-addendum.tar.gz).
- [CI follow-up and source applicability](../build/qualification/signing-followup-20260906/ci-qualification.json)
  and [native x64 Flatpak assertions](../build/qualification/signing-followup-20260906/ci-seventh-run/flatpak-x64/flatpak-qualification.json).
- [Qualification follow-up and source applicability](../build/qualification/signing-followup-20260906/observation.json)
  and [reproduction instructions](../build/qualification/signing-followup-20260906/REPRODUCE.md).
- [Latest clean-source macOS/Linux/Flatpak regression](../build/qualification/signing-followup-20260906/provider-regression/report.json)
  and [two-app Flatpak assertions](../build/qualification/signing-followup-20260906/provider-regression/flatpak.json).
- [Hardened runtime/module qualification](../build/qualification/signing-followup-20260906/macos-developer-id-2pkkrf2d/report.json),
  and [mobile crash runner preparation](../build/qualification/mobile-crash-preparation-20260906/preparation.json).
- [Latest failure-case qualification and source applicability](../build/qualification/failure-cases-20260906/observation.json),
  [real prompted Flatpak assertions](../build/qualification/failure-cases-20260906/flatpak-final/flatpak.json),
  and [standalone signing reproduction](../build/qualification/failure-cases-20260906/signing-probe/result.json).
- [Core and native macOS regression](../build/regression/run-uJg7PI/report.json).
  Its aggregate status is blocked because Docker was stopped; the core and
  macOS rows passed. Later Linux/Flatpak results supersede those blocked rows.
- [Linux and Flatpak regression](../build/regression/run-Yb6Q3w/report.json) and
  [detailed Flatpak assertions and provider versions](../build/regression/run-Yb6Q3w/flatpak.json).
- [Android emulator / iOS simulator regression](../build/regression/run-jXhPun/report.json).
- [Physical Android report](../build/qualification/20260904T231637Z/android-pixel6a-20260905T001537Z/report.json)
  and [hardware, source, test and cleanup observations](../build/qualification/20260904T231637Z/android-pixel6a-20260905T001537Z/observation.json).
- [Android Profile/AOT process continuity](../build/qualification/android-physical-20260905T205513Z/lifecycle/report.json),
  [source, artifact and cleanup observations](../build/qualification/android-physical-20260905T205513Z/observation.json),
  and [reproduction instructions](../build/qualification/android-physical-20260905T205513Z/REPRODUCE.md).
- [Android passphrase-protected upgrade](../build/qualification/android-upgrade-20260906T010717Z/upgrade/report.json),
  [source, artifacts and cleanup observations](../build/qualification/android-upgrade-20260906T010717Z/observation.json),
  and [reproduction instructions](../build/qualification/android-upgrade-20260906T010717Z/REPRODUCE.md).
- [Mobile upgrade preparation and native process-crash checks](../build/qualification/mobile-upgrade-preparation-20260905T235609Z/observation.json),
  [native crash test events](../build/qualification/mobile-upgrade-preparation-20260905T235609Z/crash-tests.jsonl),
  [runner test events](../build/qualification/mobile-upgrade-preparation-20260905T235609Z/runner-tests.jsonl),
  and [reproduction instructions](../build/qualification/mobile-upgrade-preparation-20260905T235609Z/REPRODUCE.md).
- [Current signed macOS qualification](../build/qualification/macos-signed-20260905T200022Z/observation.json),
  [phase receipts](../build/qualification/macos-signed-20260905T200022Z/regression/report.json),
  and [reproduction instructions](../build/qualification/macos-signed-20260905T200022Z/REPRODUCE.md).
  The [earlier blocked rerun](../build/qualification/20260904T231637Z/macos-final-signed-blocked.json)
  remains as historical evidence; its development-signing gaps are superseded.
- [Current physical iOS qualification](../build/qualification/ios-physical-20260905T201952Z/observation.json),
  [baseline scenarios](../build/qualification/ios-physical-20260905T201952Z/baseline/report.json),
  [Profile/AOT process continuity](../build/qualification/ios-physical-20260905T201952Z/lifecycle/report.json),
  and [reproduction instructions](../build/qualification/ios-physical-20260905T201952Z/REPRODUCE.md).
  The [historical physical baseline](../build/qualification/20260904T231637Z/ios-baseline.json)
  predates the iOS container-binding correction and is superseded.
- [Engineering evidence index](../build/qualification/20260904T231637Z/engineering-checks.json),
  [retained Docker source/environment evidence](../build/qualification/20260904T231637Z/flatpak-nested-docker/result.json),
  and [GNOME backend source review and its limits](../build/qualification/20260904T231637Z/flatpak-backend-review/source-review.md).

Use the [regression commands](platform-regression.md) for repeatable checks and
the [device security suite](device-security-suite.md) for the remaining
qualification procedures and release gates.

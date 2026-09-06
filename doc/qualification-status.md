# Latest platform qualification

Evidence reviewed **2026-09-06**. This is a dated, reviewed summary of retained
local evidence, not release certification or an automatically refreshed dashboard.
New regression runs write individual JSON reports; update this summary after
reviewing their results and source applicability. Times below are UTC.

## Platform coverage

| Platform / profile | Latest evidence | What passed | Remaining qualification |
| --- | --- | --- | --- |
| **Shared SDK** | **Pass**, Sep 6; current runtime | 484 SDK tests (11 opt-in/native skips): cryptography, framed storage, hostile inputs, transactions, passphrase and platform contracts. The Linux/Flatpak run separately passed 41 portal tests, including the three real D-Bus cases. | Independent external crypto/security review; maintained-device Argon2 acceptance budgets. |
| **macOS file Keychain** | **Pass**, Sep 6 14:05; current runtime, native host | Seven tests: bounded root access, exact provider lifecycle, private files, persistence, passphrase/reset, and locked-provider record operations. Disposable Keychain deleted; user search list and default preserved. | The separate Developer ID runtime/module row now covers bounded genuine-account continuity. Other signing/runtime transitions remain open. |
| **macOS signed app** | **Pass**, Sep 5 20:02; unchanged platform/common implementation, native Apple Development signing | Signed SDK baseline; passphrase-protected store seeded by build 101 and reopened without initialization by build 102. Explicit phase results, distinct code hashes, Apple-trusted signatures, exact sole Keychain group and sandboxing verified. Provider root, store and staging file absent after reset; harness exited; signing configuration and Keychain settings preserved. | Developer ID distribution/release upgrades, entitlement transitions, physical lock/reboot and reinstall. This qualifies the recorded development-signed profile and unchanged Apple/common implementation, not distribution signing. |
| **macOS single-file Developer ID** | **Failed**, Sep 6; dedicated hardened AOT SDK fixture | Trusted signature, secure timestamp, hardened-runtime flag and empty entitlements verified. Actual launch was killed before fixture startup. A minimal program without Keybay reproduces the failure; signed control without hardened runtime runs. No test store created; user Keychain settings preserved. | Single-file product packaging remains deferred with CLI work. The native module form below clears the SDK continuity check; it does not repair the single-file executable. |
| **macOS Developer ID runtime/module** | **Pass**, Sep 6 13:37; current runtime, native host | Separately signed AOT builds 101/102 reopened the passphrase-protected store without initialization. Hardened runtime, empty entitlements, matching team/designated requirements and changed module hashes verified. Native exits passed; provider/store/stage/control absent; user Keychain settings preserved. An ad-hoc module was separately rejected. | Notarization, entitled-app distribution, runtime/toolchain upgrades and other native configurations. Both modules used the same SDK and signed runtime; no format or signing-team migration. |
| **Ordinary Linux** | **Pass**, Sep 6 14:05; current runtime, Ubuntu 24.04 arm64 in Docker | Six tests: POSIX flags, clean-account directories, raw Secret Service root lifecycle, second-data-root rejection, public SDK persistence/passphrase/reset, and locked-provider fail-closed behavior. Private disposable provider state. | Native x64 CI evidence for this source; additional supported provider configurations. Namespace isolation is not OS-enforced application isolation here. |
| **Flatpak** | **Pass**, Sep 6 14:05; current runtime, real nested Flatpak in Docker | Two-app identity/secret/file isolation, concurrent first use, no fallback, lifecycle/reset and provider restart passed. Real GNOME prompts passed user cancellation, timeout and two overlapping cancellations; both stores reopened without provider restart. Fixed a pending blocking pipe read that previously kept cancelled processes alive. Native descriptor/process regression and cleanup passed. | Native x64 CI evidence and other provider configurations. Timeout recovery includes explicitly dismissing any remaining native dialog; it does not establish automatic dialog dismissal. This covers the recorded GNOME backend. |
| **Android** | **Physical pass**, Sep 6 01:08 Profile/AOT upgrade; Sep 5 00:16 baseline and 20:56 process continuity; unchanged platform/common implementation, Pixel 6a / Android 16 / API 36. Latest emulator attempt Sep 5 14:42: **blocked**, no ready emulator. | Six substantive baseline tests plus source/nonce metadata: native hardware-key assertion, ciphertext/reopen/passphrase/reset, all 32 contended writes, tamper rejection, missing root and same-alias replacement. Process continuity passed separately. Upgrade from signed build 101 to distinct AOT build 102 preserved the app UID, signer and both records without initialization; missing/wrong passphrases rejected, correct passphrase accepted. Matching source/nonce/build receipts and two native self-exit/code-zero records verified. Control/store/stage removed; package absence verified across all profiles. | Abrupt termination, reboot/relock, backup/restore/transfer, peer-app procedures and other maintained devices. Upgrade covers a debug-signed Profile/AOT app with the same SDK and store format in both builds, using clean exits. Hardware baseline establishes TEE **or** StrongBox, not StrongBox specifically. |
| **iOS** | **Physical pass**, Sep 5 20:23 baseline and 20:41 Profile/AOT continuity; unchanged platform/common implementation, iPhone 16 / iOS 18.7.3. Simulator also passed Sep 5 14:42. | Two substantive physical SDK scenarios: ciphertext, private files/backup exclusion, fresh-engine reopen, passphrase/reset and all 32 contended writes. Separately, the same signed AOT app seeded and reopened the existing store in distinct processes with native exit codes and matching source/nonce/phase receipts. Signed application identity verified; control, encrypted-store and staging files absent after reset. | Application-update continuity, lock/reboot, access-group transitions, backup/restore/transfer and other maintained devices. Separate-process continuity uses platform protection; the passphrase baseline remains in-process. |

Windows and Snap are deferred and have no qualification claim. Hardware
credentials, rollback anchors and root rotation are also outside this scope.

## Additional checks already recorded

- The [security review handoff](security-review.md) records the fixed portal
  cancellation defect, native AOT identity correction and qualified macOS
  runtime/module form. External
  review awaits a selected reviewer. The [mobile failure procedures](mobile-failure-qualification.md)
  now have compiled crash runners; physical execution and remaining lock/reboot/restore phases are pending.

- Upgrade qualification is now implemented for Android/iOS: signed builds
  101/102 compiled successfully, and host orchestration/receipt rejection tests
  passed. The physical Android upgrade passed Sep 6; the iOS upgrade remains
  pending. The fixture now binds mode,
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
  but has not been run against the prepared source snapshot.

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
host regressions preserve the earlier process and upgrade paths, but those
new runners have not yet executed physically. Both upgrade builds used the
same SDK and store format; no version migration is claimed.

These links resolve to retained **local build artifacts**, which are not
included in a fresh checkout:

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

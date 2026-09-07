# Keybay core SDK: follow-up review of the remediation

- **Date:** 2026-09-06 local (2026-09-07 UTC for the CI run and later lane timestamps).
- **Reviewer:** Claude Fable 5.1 (`claude-fable-5-1`) as Claude Code, at the maintainer's request. AI model review, not a human external audit. No other participant. No web access.
- **Reviewed base:** `88c9cb5e738847d9443cdf3f35933e71e745ebd0` (runtime digest `4f88c9e5…`, the immutable pack, whose verifier still passes: 536 files).
- **Remediation:** runtime commit `48e2bb80fe686be7bcde690903fb486d8b3ba924`; fixture commit `b4b198a855879b5990ce437c2cff40d276364a97` (CI subject); documentation commit `0042f6dab89f0b2671491773bbdd6a289866dbc6` (branch head). I confirmed the branch is pushed at `0042f6d` (`git ls-remote`), that the clean checkout `/private/tmp/keybay-signed-qualification-ex80ba8b` is at `0042f6d` with a clean tree, and that the workspace `/Users/dan/Coding/keybay` has byte-identical `packages/keybay/lib`, `packages/keybay/test` and `ci.yml` (its two extra empty directories `lib/src/backends` and `lib/src/container` are leftovers of preexisting uncommitted deletions, not source).
- **Corrected runtime digest:** `57163d1f9714024acf5ad3d86ea9ef7874684703b6592e912dfeea29b46cd5cf` over 40 files, recomputed locally from `0042f6d` with the pack's digest rule and matching `source.json`, `manifest.json` and the qualification report.
- **Retained evidence:** `build/qualification/claude-remediation-20260907/manifest.json` verifies (33 of 33 files, no mismatches, no unlisted files besides the documented `ci-watch.log` and `ci-reports/`); `remediation.patch` hashes identically to `git diff 88c9cb5e..0042f6d`.
- **Unchanged from the base (verified by diff):** public export list, `keybay_v2.dart` public types and enum (only a doc comment changed), `pubspec.yaml`, `pubspec.lock`, dependency pins, the `format/` module, `store_files.dart`, `platform_protector.dart`, test support fixtures and vectors.

---

## 1. Verdict

All five findings are adequately remediated and the informational dispositions are reasonable. The KB-CR-001 release blocker is cleared by a one-symbol, ABI-scoped correction that is now exercised by a native Intel macOS CI job (core suite plus the real Keychain lane) and by a new SDK-level metadata regression. KB-CR-004 was resolved by the simplification I recommended as the preferred option: the record path no longer touches any provider, structurally. KB-CR-003 is implemented with correct ordering (capture before derivation, overwrite before release, release even if clearing fails, primary failure preserved) and is anchored by a real-dependency lifetime test and a fault matrix that never reads freed memory. KB-CR-002 and KB-CR-005 are addressed with wording that is accurate and appropriately cautious ("a conflict is not proof of reinstall; never auto-reset").

Nothing in the remediation changes the architecture, format, public API, or dependency closure. My earlier architecture judgement stands: retain the shared engine and adapters. This follow-up does not constitute release approval; the physical lifecycle, signing/configuration, and device KDF-budget gates are as open as before.

Residual items from this pass are all Info-level (§4).

---

## 2. Per-finding assessment

### KB-CR-001 — Intel macOS `fstat` ABI — **resolved**

- `posix_store_files.dart`: `_darwinFstat` now resolves `fstat$INODE64` when `Abi.current() == Abi.macosX64` and `fstat` otherwise; `_fcntl` is bound with `VarArgs<(Int32,)>` and called with an explicit third argument (also closes KB-CR-010). The struct declaration and the ABI allowlist are unchanged, which is correct: only the symbol selection was wrong.
- New test `descriptor metadata agrees with native file stat` compares the pinned length and the mode gate against `File.statSync()` and rejects a `0644` live file. This runs on every core lane, so both Apple ABIs and Linux now cover the metadata path with the real SDK rather than my C probe.
- CI: `integration-macos` is a matrix of `macos-latest` (arm64) and `macos-15-intel` (x64) with `setup-dart architecture: x64`; the x64 job additionally runs the core suite. Reports record `dartAbi`, and both x64 reports (`run-mdtzOv` core, `run-aP3oYx` macOS lane) show `macos_x64`, Dart 3.13.3, commit `b4b198a`, clean, pass. The retry log shows the seven real-Keychain tests and the public facade passing on Intel.
- The first Intel attempt (`34073103276`) reported `501 tests passed, 1 failed, 3 skipped`; the one failure was `v2_posix_store_files_test`'s cross-process lock worker startup (5 s deadline exceeded while the core suite loaded), and the new metadata test had already passed in that run. The retry reported `502 tests passed, 3 skipped` for the x64 core suite, `+7` for the real-Keychain lane, and `1 test passed` for the public facade on the runner's genuine account. `b4b198a` raises the startup allowance to 20 s and detects worker exit; the SDK's own 1 s lock deadline is untouched. That is a fixture correction, correctly labelled.
- Scope caveat (Info): `Abi.iosX64` keeps the plain symbol. The iOS SDK has only the 64-bit-inode ABI, so that is believed correct, but no x86_64 simulator run exists; the CI iOS job runs on arm64.

### KB-CR-004 — provider access on the record path — **resolved by removal**

- `framed_store_reader.dart`: `_hasNewerAuthenticatedGeneration` and the `storeAuthenticationFailed` reclassification in `_start` are deleted (85 lines). Same-runtime invalidation is intact: `_ensureCurrent`, `_invalidate`, and `_invalidateImmediately` remain and are still used by reset, peer invalidation, and rotation's unknown-outcome branch. I grepped the runtime for `PlatformInteraction.forbidden`: the only remaining uses are the two protector guards, so no caller can reach a provider with a forbidden policy at all.
- `linux_secret_service_protector.dart`: every entry point now passes through `_atSecretServiceBoundary(interaction, …)`, which throws `interactionRequired` before any D-Bus call under `forbidden`. This is now defense in depth rather than a hot path.
- Tests: the interaction contract test asserts, for both a damaged store and a peer-rotated store, that all nine record methods plus `auth.list` fail with `storeAuthenticationFailed` while the fake protector records zero calls and zero accesses, and that the owner's record is preserved. The Linux protector test asserts no read/create/delete and no lock under `forbidden` for all three operations. The passphrase engine test's cross-engine expectations were updated to `storeAuthenticationFailed`, and the native rotation contention test still expects `staleSession` for the same-engine waiting writer, which is the right split.
- Contract change is documented consistently (RFC, `SECURITY.md`, `architecture.md`, `design.md`, `sdk.md`, `keybay_v2.dart` doc comment, CHANGELOG).

### KB-CR-003 — Argon2 workspace clearing — **resolved**

- `passphrase_kdf.dart`: the state is created, `getByteBuffer()` is captured as a `Uint64List` view **before** `deriveKeyBytes`, the view is zeroed in a `finally` after the derived bytes are cleared, and `tryReleaseMemory()` is attempted in an outer `finally` regardless; cleanup failure never displaces a derivation failure, and a cleanup failure with a successful derivation clears and withholds the result. Capturing before derivation is the important detail: the dependency allocates lazily in `getByteBuffer()`, so a capture during cleanup could allocate a fresh empty buffer and clear the wrong memory; the code avoids that and the fault test asserts `allocations == 1`.
- I checked the dependency once more: `getByteBuffer()` is `@protected` on `DartArgon2State` and returns the cached `_buffer`; the subsequent internal call inside `deriveKeyBytesFromPrehashingDigest` returns the same object; the FFI implementation frees that exact address in `tryReleaseMemory()`. The profile's buffer is `1024 × blockCount` bytes, a multiple of 8, so the `Uint64List` view is valid. The view outlives the free as a Dart object but is never touched after release.
- Tests: `v2_crypto_dependency_test` proves with the real dependency that the buffer is the same object after derivation, is 64 MiB, is nonzero after derivation, and is writable; it zeroes and then releases, and does not read afterwards. `v2_passphrase_kdf_test` adds a fault matrix over a fake state (success, allocation failure, derivation failure, release failure, derived-clear failure, derivation plus release failure) asserting single allocation, single release, all-zero workspace at the moment of release, cleared password snapshot, and preserved caller input. Together they establish the production ordering on the real buffer by composition, which matches my recommendation.
- Claims: RFC and `SECURITY.md` now describe the native workspace, the overwrite before release, and the residual dependency-internal hash state and VM copies. No whole-process erasure claim is made.
- Conservatism note (Info): a `tryReleaseMemory()` failure now fails the open/auth operation even though the key was derived correctly. That is safe and matches the fail-closed style; it means a dependency-level release fault is surfaced rather than hidden. Acceptable.

### KB-CR-002 — root-only `storeStateConflict` guidance — **resolved (documentation)**

- `sdk.md` names `storeStateConflict` among the important codes, explains the retained-root case (interrupted first initialization; Apple reinstall or same-device restore), states explicitly that a conflict is not proof of reinstall, requires that the application establish that starting over is appropriate and accept local data loss before calling `reset()`, and forbids automatic reset on every conflict or authentication failure. Both READMEs carry a short pointer; `ios.md` and `macos.md` repeat it for their profiles, and `ios.md` now cites Keychain retention after uninstall as an implementation detail rather than a guarantee. Physical reinstall/restore remains correctly listed as unqualified.
- This is stronger than what I asked for: it also prevents the over-correction (auto-reset) that my recommendation could have invited.

### KB-CR-005 — stale public statements — **resolved**

- Flatpak/Docker wording (`SECURITY.md`, `sdk.md`, package README, `linux.md`), physical upgrade/crash status (`platform-regression.md`), Linux native CI status (`linux.md`), macOS architecture coverage (`platform-regression.md` now names arm64 and Intel runners), the `package:test` limitation (`sdk.md`), the Argon2 memory statement (RFC, `SECURITY.md`), and the unqualified "never prompt" phrasing (now "never prompt or acquire the platform provider, including when an operation fails", which is true by construction) are all corrected. `SECURITY.md` also now records that an AI review was received and where its record lives.

### Informational dispositions

- **006 (lock held during UI/KDF):** ordering unchanged; `sdk.md` documents the one-second deadline and bounded-backoff retry. Acceptable.
- **007 (stale classification under contention):** subsumed by the simplified contract; `sdk.md` tells callers to treat `storeAuthenticationFailed` after a peer rotation as "close and reopen, not permission to erase". Acceptable.
- **008 (exact post-write comparison) and 011 (helper isolates):** left unchanged with the rationale that no defect requires them. Consistent with my Info rating; the RFC now at least states the helper-isolate count.
- **009 (`package:test`):** documented in `sdk.md` with the recommended alternative.
- **010 (`fcntl` variadic):** corrected.

---

## 3. Evidence evaluation

**Clean-source CI (`34073634184` at `b4b198a`):** `ci-final-status.json` records 14 jobs successful and `fuzz-canary` skipped, including both `integration-macos` matrix legs, `integration-linux`, `integration-flatpak`, `integration-android` API 31 and 36, `integration-ios`, `minimum-sdk`, both `analyze-and-test` legs, `provider-impact` and `provider-gate`. All 11 downloaded platform reports name `b4b198a…`, `sourceDirty: false`, and pass; the x64 reports carry `dartAbi: macos_x64`. This is the evidence that clears KB-CR-001.

**Maintainer's local runs:** ARM64 core 502 pass with three D-Bus skips; native Keychain 7 pass; tool tests 40 pass; Rosetta x64 core 502 pass; two Rosetta native-Keychain attempts timed out during passphrase preparation (retained as failures); AOT KDF vectors matched on ARM64 (before and after) and under Rosetta (`kdf-x64-aot.json`: 330–383 ms, ~165 MiB); the JIT comparison timed out on the reviewed source and passed on the remediated source in one sample each. The qualification report describes these limits accurately and does not claim a Rosetta native-lane pass.

**My runs on this host (Apple Silicon, macOS 26.2):**

| Check | Result |
| --- | --- |
| `dart analyze packages/keybay` at `0042f6d`, Dart 3.12.2 | No issues |
| Core lane, arm64, Dart 3.12.2 | **pass**: 502 passed, 3 skipped (`run-TNryNs`) |
| Core lane, arm64, Dart 3.13.3 (CI's pin, SDK at `/private/tmp/keybay-dart3133`) | **pass**: 502 passed, 3 skipped; analysis clean |
| Core lane, arm64, Dart 3.11.0 (minimum, SDK at `/private/tmp/keybay-dart311`) | **pass**: 502 passed, 3 skipped; analysis clean |
| `v2_posix_store_files_test.dart` with the x64 Dart 3.13.3 SDK (`/private/tmp/keybay-dart3133-x64`) under Rosetta | **pass**: 30 tests including `descriptor metadata agrees with native file stat`. This is the direct SDK-level confirmation of the KB-CR-001 fix on this host. |
| macOS native lane with the x64 SDK under Rosetta (disposable Keychain, `run-CiOrRp`, `dartAbi: macos_x64`) | **pass**: 7 tests in 10 s, including passphrase persistence/reset and the locked-Keychain worker that timed out in the maintainer's attempts |
| JIT KDF derivation under Rosetta, alternating sources (`dart run … --derive`, 120 s cap) | remediated: 1 failure (exit 255) then 0.7–1.3 s; reviewed: 1.0 s, **93.8 s**, 1.1 s. Vector matched on every completed run. See the Rosetta paragraph below. |

**Rosetta timeouts explained as environmental, not source-dependent.** Under the x64 JIT VM on Rosetta, the *unchanged reviewed source* produced derivations of 1.0 s, 93.8 s and 1.1 s in three consecutive runs, and the remediated source produced one failed run followed by sub-second runs; AOT under Rosetta is steady at 330–383 ms in the maintainer's `kdf-x64-aot.json`. The maintainer's one-sample comparison (reviewed timed out at 50 s, remediated 4.3 s) is therefore not evidence of a runtime difference in either direction, and the two timed-out native Keychain attempts, which spend their time in exactly this JIT Argon2 path, are consistent with the same variance. A further six alternating runs (`rosetta-x64-jit-error-capture.log`) reproduced the pattern symmetrically: one ~72 s derivation on the remediated source, one ~72 s derivation on the reviewed source, and 0.8–1.3 s for the other four, all matching the vector; the single earlier exit-255 failure did not recur and remains uncharacterized beyond "uncaught error under Rosetta JIT". With the same x64 SDK the macOS native lane passed here in 10 s. The qualification report's refusal to draw a conclusion from those runs was correct; it can now record that the lane does pass under Rosetta and that the JIT-on-Rosetta Argon2 cost is erratic. Native Intel CI, which uses the same JIT test VM without Rosetta, showed no such stalls (core 502 pass in ~80 s).

**Carrying earlier assurance forward.** The runtime changes touch three boundaries: the record-operation failure path in the reader (deleted code only), KDF cleanup, and the Darwin `fstat` symbol on x64 only. Neither the format, the writer/rotation transaction ordering, the provider adapters other than the Linux forbidden guard, nor the Android/iOS/Flatpak host code changed. The Sep 5–6 physical Android/iOS receipts therefore remain applicable to their unchanged native boundaries (identity, Keystore/Keychain custody, no-backup files, crash recovery ordering), but they exercised the old reader failure path and old KDF cleanup; those two paths are now covered by the virtual-device CI lanes at `b4b198a` and by the hermetic suites, not by physical runs. I consider that sufficient for these changes and do not recommend repeating the physical procedures for them. The signed-macOS and Developer ID receipts likewise remain valid for the unchanged Apple adapter; the x64 change does not affect arm64 builds.

---

## 4. Residual observations (Info)

1. **Same-runtime in-flight race.** With the reclassification removed, one operation that was already running when a same-engine rotation committed, and that pinned the new generation, now reports `storeAuthenticationFailed`; the next operation on that session reports `staleSession`. `sdk.md` describes the cross-process case; a clause noting that the same can happen for a single in-flight operation in the same runtime would make the guidance complete. No code change needed.
2. **`iosX64` symbol selection** is believed correct but unexercised (see KB-CR-001).
3. **x64 core coverage is gated** by `provider-impact`, like the rest of `integration-macos`. A change confined to non-provider files would not run the x64 core suite. Acceptable given the ABI-relevant code is provider-adjacent, but worth knowing.
4. **The `@protected` accessor coupling** is now load-bearing. It is protected by the exact pin and `dependency_closure_test`; any future bump of `cryptography` must re-verify `getByteBuffer()` semantics (lazy allocation, caching, and `tryReleaseMemory()` freeing that address).
5. **Rosetta JIT cost is erratic, not merely slow.** The same source varies between about 1 s and about 94 s per derivation under the x64 JIT VM on Rosetta, and one run failed outright (§3). This affects only Rosetta-hosted JIT test runs; native Intel CI and AOT builds are steady. If Rosetta runs remain part of the local routine, the KDF-bearing integration tests need per-test timeouts sized for that variance, or those lanes should be treated as CI-only.
6. **Receipts from the first review** do exist beside the retained report: `build/qualification/claude-review-20260906/review-output/receipts/` (18 files: lane logs and reports, Go output, KDF measurement, both probe sources and outputs). `security-review.md` says they were not supplied with the pasted report, which is accurate; the maintainer may copy them into the project's retained evidence if desired.

---

## 5. Gates that remain open (unchanged by this remediation)

Physical lock/reboot/first-unlock, physical auth-change interruption, backup/restore/transfer and reinstall/restore root-only behavior on devices (`KB-INV-004`, `KB-INV-008`); release signing/configuration decisions and notarization; maintained-device Argon2 acceptance budgets; non-gnome-keyring Secret Service providers; `iosX64`; single-file hardened CLI packaging. None of these is affected by the remediated code, and none is closed by it.

---

## 6. Receipts

`followup-20260907/receipts/`: `runtime-test-ci-88c9cb5e..b4b198a.diff`, `core-lane-arm64-dart3.12.2.log` and `-report.json`, `core-lanes-dart3.13.3-and-3.11.0.log` with `core-lane-arm64-dart3133-report.json` and `core-lane-arm64-dart311-report.json`, `rosetta-x64-chain.sh` and `rosetta-x64-chain.log` (JIT KDF comparison, x64 POSIX test, x64 macOS lane), `macos-lane-rosetta-x64-report.json`, and `rosetta-x64-jit-error-capture.log` (repeat runs capturing the full text of any failed derivation). Scratch copies were built from `git archive` of the clean checkout at `0042f6d` (runtime digest recomputed as `57163d1f…`) and, for the "reviewed" JIT comparison, from the original pack's `source/`. Only the Dart 3.12.2 copy carries a throwaway `git init` commit (`36d83bb2…`); the other copies have no Git metadata, so their reports record a null source identity, as the lane tooling documents for archives.

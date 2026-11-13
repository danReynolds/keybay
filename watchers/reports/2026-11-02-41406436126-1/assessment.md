<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-41406436126-1","status":"needs_attention","summary":"Merged dependency and identity remediation verified; Apple and Android provider qualification remain outstanding, with the unreachable residual Go warning retained.","actions":[{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"},{"label":"Android provider qualification and alias assurance","url":"https://github.com/danReynolds/keybay/issues/117"}]} -->

# Assessment

> Historical assessment and dated follow-up. The original assessment below
> retains its `6eed3eb` source basis, dispositions and validation. Its references
> to “current main,” open maintenance issues or watcher health describe that
> baseline. The November 13 follow-up records verified merged remediation and
> the remaining qualification limits; report publication and health recovery
> remain separate checks.

Status: **Needs attention** for one new dependency-maintenance issue, refreshed
Apple provider qualification, and two existing tracked follow-ups. All three
watchers completed, and the current watcher-health check is healthy.

Assessed on 2026-11-02 against source `6eed3ebfa4e90785985fe87665c616fd6e0361cf`.
The successful scheduled [Actions run](https://github.com/danReynolds/keybay/actions/runs/41406436126)
used the reviewed default-branch watcher. Its Actions-authored branch changes
only this report pair and `watchers/reports/SUMMARY.md`. The immutable raw blob
`4a0f7df2dd3697b407fffb592429e6abdd647f59` was verified before assessment.
This is monitoring and triage evidence, not a release certificate or proof
that no vulnerability exists.

## Delta and reuse basis

The report contains **49 signals: 12 new, 14 updated and 23 reused**. The
dependency set is two new and six reused signals; the platform set is one new
and four reused signals; and the peer set is nine new, 14 updated and 13 reused
signals. Updated peer markers are existing public items whose update timestamp
changed; exact repeats retain the complete prior marker.

Reuse was checked against current source and security assumptions. The report
source and current `main` are exactly the same commit as the reviewed October 26
assessment. No package, provider, dependency lock, security-design or test
source changed. The fixed Android Keystore root, Apple Keychain profiles,
Linux Secret Service and Portal roots, store lifecycle, cross-process locking,
and fail-closed provider boundaries therefore retain the prior applicability
basis. Existing issues [#75](https://github.com/danReynolds/keybay/issues/75),
[#76](https://github.com/danReynolds/keybay/issues/76), and
[#117](https://github.com/danReynolds/keybay/issues/117) remain open.

A focused current-source suite passed **118/118** tests across Android Keystore
and host binding, Apple Data Protection and login-Keychain protection, Linux
Secret Service, store initialization, and native contention. It was run from
the package root with an isolated OpenSSL 3 tool selection matching Homebrew
libfido2; no repository or Homebrew state changed. The nonshipping Go reference
test also passed, and its dependency list still contains no affected SSH or
OpenPGP package.

## Watcher dispositions

### Dependencies: actionable example maintenance; no shipped-runtime finding

- CVE-2026-102554 affects Guava through 33.7.1 via native Java deserialization
  of attacker-controlled `CompactHashMap`, `CompactHashSet`, or
  `MapMakerInternalMap` state. The committed Flutter Android security harness
  pins `guava:33.7.1-android`; 33.7.2 is fixed. Repository source has no
  `ObjectInputStream` or native Java deserialization path, and the harness is a
  consumer example rather than the shipped Keybay Dart SDK or CLI. No reachable
  Keybay vulnerability was established, but the retained example graph should
  be updated.
- CVE-2026-116695 affects Crass through 1.0.7 when a CSS sanitizer parses and
  re-emits untrusted CSS after incorrect bad-URL tokenization. The Rails CLI
  consumer example resolves Crass 1.0.7 through Loofah and
  `rails-html-sanitizer`; 1.0.8 is fixed. The example uses a fixed server-owned
  style block and exposes no untrusted CSS-sanitization path. It is not shipped
  Keybay runtime code, but its committed lock should still be updated.
- [Issue #120](https://github.com/danReynolds/keybay/issues/120) safely tracks
  both fixed-version updates, lock and verification-metadata refreshes, relevant
  example checks, and a clean watcher rerun.
- The remaining six dependency markers are exact repeats. The four Go
  advisories remain unreachable in the nonshipping reference tool and are
  tracked by issue #75. The exact `dbus` 0.8.0 and Keypass 0.1.0-dev.3 release
  markers establish no new Keybay repair.

### Platforms: Apple Keychain qualification required; no disclosed Keybay flaw

The October 26 Apple group is new. Apple reports CVE-2026-28864 for iOS/iPadOS
26.7.2, macOS Sequoia 15.8.2, and macOS Tahoe 26.7.2 as a permissions-checking
issue through which a local attacker may gain access to a user's Keychain
items. That boundary can materially affect Keybay's provider-dependent claims,
so applicable physical-device qualification is triggered and tracked in
[issue #76](https://github.com/danReynolds/keybay/issues/76). The issue was
updated with this marker and the exact patched releases.

Apple's public description does not establish access to Keybay's exact login-
Keychain item or signed Data Protection access group, so it does not establish
a Keybay authentication bypass. The available physical macOS host is 26.2
build 25C56, which predates the named patched releases and cannot qualify the
repaired boundary. Prior receipts remain scoped to their recorded OS builds;
qualification must run on an explicitly selected applicable patched host.

The two Android and two earlier Apple markers are exact repeats. Their prior
dispositions remain valid; the September Apple work is already part of issue
#76. No watcher failed and no separate watcher-health action is warranted.

### Peers: current mechanisms remain separate; existing Android work retained

- Flutter Secure Storage's biometric cancellation hang and fix, cached
  per-operation biometric cipher after migration, reset recursion, compat-mode
  plaintext fallback, legacy migration, and multi-engine RSA-key initialization
  race use biometric prompts, SharedPreferences/Tink stores, migrations,
  automatic reset, and replaceable RSA pairs that Keybay does not import or
  expose. Keybay's provider root creation occurs under its fixed profile-level
  transaction lock, adopts an existing winner, cryptographically reads state
  back, and never auto-resets encrypted state on provider failure.
- Updated Linux PR 1290 concerns libsecret replacing one shared JSON item by
  delete-then-create and sometimes reporting a lost write as success. Keybay
  uses direct Secret Service D-Bus, `CreateItem` with `replace=false`, an exact
  re-query and byte comparison, duplicate rejection, and an independent framed
  file for records. It does not share the affected replacement mechanism.
- Exact Flutter Secure Storage issue 1298 retains the narrower first-creation
  hardening action in [issue #117](https://github.com/danReynolds/keybay/issues/117).
  A complete live Keybay store remains non-mutating and fail-closed when the
  provider is unavailable or reports its key missing.
- The Flutter release, analyzer, Tink, Gradle, Robolectric, simulator and
  Dependabot changes are peer build or release maintenance. Python keyring's
  path expansion and status API, Go keyring's godbus update, and Rust keyring's
  dependency and workflow changes do not share Keybay runtime mechanisms.
  Exact React Native update-first Keychain items and the remaining peer repeats
  retain their prior non-applicability dispositions.

No plausible undisclosed Keybay vulnerability or watcher failure was found.
No private advisory or watcher-health issue was warranted. Issue #120 is the
new action; issues #75, #76, and #117 remain open and are carried forward.

## Validation

The required watcher gates passed: formatting, static analysis, 28 Dart watcher
tests, 19 Python publication tests, and workflow lint. The final assessment and
generated summary were reviewed together, and the raw report remained byte-
identical to blob `4a0f7df2dd3697b407fffb592429e6abdd647f59`.

## November 13 follow-up — verified PR #126 remediation

[PR #126](https://github.com/danReynolds/keybay/pull/126) merged as
`1f22a4c1fc74702cea0490fbb65d5e9ace6530b1`. Its tree exactly matches the
independently reviewed candidate
`fc9e59b7d224c1cce201c9b74b7fa8b7e7a0958d`; the tree comparison has no diff.
This dated follow-up reassesses the changed dependency, Android-provider and
identity boundaries. It supersedes their outstanding-maintenance/reuse
statements in the historical baseline above, while preserving the original
raw discovery, signal counts and assessment record.

### Reassessment of affected repeats

- **Example dependencies remediated.** The merged Android example selects
  Guava 33.7.2-android with refreshed Gradle verification metadata. The Rails
  example resolves Rails 8.1.4.1, Crass 1.0.8, Rack 3.2.8, Loofah 2.25.3,
  Nokogiri 1.19.7 and sanitizer 1.7.2. The original Guava/Crass markers are
  now remediated in the committed examples. Later Rails/Rack findings are
  later evidence, not additions to this report's immutable discovery set.
  [#120](https://github.com/danReynolds/keybay/issues/120) is closed completed;
  dependency PRs #122–125 were closed as superseded by the coordinated repair.
- **Go reference maintenance completed, warning retained.** The merge updates
  x/crypto to v0.56.0 and x/sys to v0.47.0, requiring Go 1.26.0. Recorded local
  module verification/tests passed and all nine reference outputs remained
  unchanged. [#75](https://github.com/danReynolds/keybay/issues/75) is closed
  completed. Actual imports still omit SSH/OpenPGP; GO-2026-5932 remains a
  visible module-level warning with `called:false`. That residual warning
  does not reopen #75 or imply an empty advisory set. Keep its import-level
  disposition visible without module-wide suppression, and assess host Go
  toolchain advisories separately. The dbus/Keypass release-marker conclusions
  are unchanged.
- **Android first creation remains bounded (#117).** The merged repair uses
  public `KeyStore.getKey` before `containsAlias`: an existing AES root is
  adopted, lookup exceptions stop before generation, and an observable
  non-key alias conflict fails closed. This replaces the old
  containsAlias-only implementation basis for Flutter Secure Storage
  #1298/#1306. The profile lock, adopted-root conflict and non-mutating
  live-store paths remain. Public getKey can also return null for pure
  certificate entries; this is AES-root hardening, not universal proof of
  `KEY_NOT_FOUND`. **#117 stays open** for physical Android provider
  qualification and remaining alias-type assurance. The 34 local
  provider/store tests establish synthetic policy and continuity evidence;
  they are not JNI or physical-device qualification.
- **Identity repair qualified in CI.** Linux Dart 3.14 split installed AOT
  images now require the canonical runtime in the same bundle while retaining
  metadata and embedded-declaration agreement checks. Activation tests assert
  the observed source or snapshot evidence and its owning package. Actual
  Linux identity execution passed in the final CI run; recorded local suites
  also passed 60 focused tests each on macOS Dart 3.12.2 and 3.14.0. Identity
  source is therefore a reviewed changed boundary, rather than unchanged
  repeat evidence. The repair does not change the reviewed peer
  storage/migration mechanisms, crypto format, provider addresses for the
  same resolved identity or existing lock policy.
- **Provider qualification remains outstanding (#76/#117).** Apple
  access-group, synchronization and exact-delete checks, Secret Service
  prompt rejection, and the Linux daemon availability disposition retain
  their source basis. #76 still requires qualification on an applicable
  patched physical Apple host; the observed macOS 26.2 (25C56) machine cannot
  qualify the patched October boundary. No Android/Apple physical test was
  run for this follow-up. Other peer/platform repeats retain their bounded
  prior dispositions. CI does not broaden earlier native-device receipts.

### Validation and publication boundary

All applicable checks passed in
[CI run 43449453052, attempt 2](https://github.com/danReynolds/keybay/actions/runs/43449453052/attempts/2),
including actual Linux identity modes. The required full-lockfile OSV gate
passed in
[supply-chain run 43449452959](https://github.com/danReynolds/keybay/actions/runs/43449452959)
with existing scan policy intact. The Flatpak retry passed. The initial Intel
core execution stalled and was cancelled without diagnostic logs; the
unchanged retry passed all checks. No cause for that initial stall is claimed.

The assessment is ready for the verified publication workflow, which must
recheck current main, preserve the original raw blob byte-for-byte, rebuild
and review the generated summary, and require green report-PR checks. This
follow-up does not itself publish or merge either report. Recheck watcher
health after both overdue assessments reach main; collection, repair and
prepared assessments do not establish that #82 is complete. This is
monitoring/remediation evidence, not physical-provider or release
qualification.

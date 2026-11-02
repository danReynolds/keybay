<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-41406436126-1","status":"needs_attention","summary":"All sources completed; example dependency updates and Apple qualification are tracked, with existing Android and Go follow-ups retained.","actions":[{"label":"Example dependency updates","url":"https://github.com/danReynolds/keybay/issues/120"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"},{"label":"Android Keystore alias hardening","url":"https://github.com/danReynolds/keybay/issues/117"},{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"}]} -->

# Assessment

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

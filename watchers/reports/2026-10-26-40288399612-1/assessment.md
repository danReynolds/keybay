<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-40288399612-1","status":"needs_attention","summary":"All sources completed; Android alias hardening is tracked, and existing Go-reference and Apple qualification follow-ups remain.","actions":[{"label":"Android Keystore alias hardening","url":"https://github.com/danReynolds/keybay/issues/117"},{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention** for one new public hardening item and two existing
tracked follow-ups. All three watchers completed, and the current watcher-health
check is healthy.

Assessed on 2026-10-26 against source `283ef5d9fb0f0d523c31083ea945d5ba548743df`.
The successful scheduled [Actions run](https://github.com/danReynolds/keybay/actions/runs/40288399612)
used the reviewed default-branch watcher. Its Actions-authored branch changes
only this report pair and `watchers/reports/SUMMARY.md`. The immutable raw blob
`8c07199eaa87ce221784db10368e927f1f447db1` was verified before assessment.
This is monitoring and triage evidence, not a release certificate or proof
that no vulnerability exists.

## Delta and reuse basis

The report contains **52 signals: 12 new, 8 updated and 32 reused**. The reused
set comprises six dependency, four platform and 22 peer markers that exactly
match retained raw reports. The eight updated markers are existing public items
whose update timestamp changed: Flutter Secure Storage issue 1293, issue 1282,
and PRs 1292 and 1286; Python keyring PR 775; React Native Keychain PR 814; Go
keyring PR 160; and Rust keyring issue 322. The remaining 12 markers are eight
new peer implementation items and four peer maintenance items.

Reuse was checked against current source and security assumptions. Since the
[October 19 assessment](../2026-10-19-39218579897-1/assessment.md), main changed
only `release.toml` to release-kit's schema 3 and retained that assessment. No
package, provider, dependency lock, security-design or test source changed.
The fixed Android Keystore root, Apple Keychain profiles, Linux Secret Service
and Portal roots, store lifecycle, and fail-closed provider boundaries therefore
retain the prior applicability basis. The Go reference still imports only
`golang.org/x/crypto/chacha20poly1305`; `go test ./...` passed.

A focused Dart provider suite passed **123/123** across Android Keystore and
host binding, Apple Data Protection Keychain, Linux Secret Service and Portal,
Flatpak protection, and common platform boundaries. The local Keypass hook was
run with OpenSSL 3 explicitly selected to match Homebrew libfido2's actual
closure; its default OpenSSL 4 selection had correctly failed closed before any
test ran.

## Watcher dispositions

### Dependencies: existing public maintenance; no new runtime finding

All six dependency markers are exact repeats. The four retained
`golang.org/x/crypto` advisories affect SSH or OpenPGP packages that the
nonshipping reference tool does not import; [issue #75](https://github.com/danReynolds/keybay/issues/75)
remains open for the compatible module refresh and explicit reachability record.
The Dart `dbus` 0.8.0 release establishes no required security repair in
Keybay's exact-pinned 0.7.15 direct D-Bus path. Keypass 0.1.0-dev.3 remains the
exact reviewed hosted dependency, and its mixed-OpenSSL rejection is operating
as designed. No dependency signal establishes a Keybay vulnerability.

### Platforms: no new finding; existing Apple qualification remains

All four platform markers are exact repeats. The September and October Android
bulletins do not identify a failure in Keybay's fixed AES-GCM Keystore root or
its Keypass contract. The September 14 Apple group retains the bounded updated-
host and applicable physical-device work in [issue #76](https://github.com/danReynolds/keybay/issues/76);
the September 28 group adds no new Keybay-specific mechanism. These repeats do
not renew prior device evidence or trigger another qualification run by
themselves.

### Peers: one actionable hardening item; otherwise not applicable

- New Flutter Secure Storage issue 1298 establishes that Android 12+'s
  `containsAlias` metadata path can report `false` after a non-`KEY_NOT_FOUND`
  Keystore failure. Keybay does not share the peer's wrapped-RSA-key or automatic
  reset path. When a complete encrypted store exists, Keybay only opens the
  retained provider state; an absent response fails closed and never invokes
  alias creation, so the peer's direct data-loss path does not carry over.
  However, Keybay's first-initialization `createUnderExclusiveLock` also treats
  `containsAlias == false` as definite absence. A transient false-negative can
  therefore replace an orphaned fixed alias instead of adopting it and returning
  the intended state conflict. This is a safe public create-only/adopt-winner
  hardening gap, not an established vulnerability. [Issue #117](https://github.com/danReynolds/keybay/issues/117)
  tracks a non-mutating definitive probe, regression coverage, and bounded
  physical-device qualification with evidence classes kept separate.
- Flutter Secure Storage's legacy SharedPreferences migration, browser first-
  write race, and biometric-per-operation reset/retry items use stores,
  migrations, and user-authenticated keys Keybay neither imports nor exposes.
  Keybay does not auto-reset on provider failure or biometric enrollment.
  The updated example, Gradle and simulator PRs are peer build maintenance.
- React Native Keychain's iOS reports replace values by delete-then-add and now
  propose update-first semantics. Keybay never updates its fixed Apple root:
  initialization uses insert-only `SecItemAdd`, adopts an existing winner, and
  reads back exact bytes; only explicit reset deletes it. The peer interruption
  and duplicate-item paths are therefore not applicable.
- Python keyring's async API request, CLI path expansion, linting and type
  annotations do not share Keybay runtime code. Go keyring's godbus update and
  Rust keyring's feature, dependency and workflow changes are likewise peer-
  only. The Rust password-zeroization discussion does not establish a new
  Keybay claim: Keybay already clears its mutable copies best-effort and
  explicitly disclaims complete zeroing of Dart, OS and immutable-string copies.
- All other peer markers retain their prior dispositions. In particular,
  Keybay's direct Secret Service D-Bus path remains separate from libsecret's
  shared-item behavior, and its Apple path remains direct Security.framework
  rather than the Go reference tool's `/usr/bin/security` backend.

No plausible undisclosed Keybay vulnerability or watcher failure was found.
No private advisory or watcher-health issue was warranted. Issue #117 is the
only new action; issues #75 and #76 remain open and are carried forward.

## Validation

The required watcher gates passed: formatting (15 files, zero changes), static
analysis, 28 Dart watcher tests, 19 Python publication tests, and workflow lint.
The final assessment and generated summary were reviewed together, and the raw
report remained byte-identical to blob
`8c07199eaa87ce221784db10368e927f1f447db1`.

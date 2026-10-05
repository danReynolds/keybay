<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-37280532141-1","status":"needs_attention","summary":"Peer and dependency signals do not establish a Keybay vulnerability; Android bulletin discovery failed and needs repair.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"},{"label":"Android watcher source repair","url":"https://github.com/danReynolds/keybay/issues/89"}]} -->

# Assessment

Status: **Needs attention**

Assessed on 2026-10-05 against the report source and current `main`,
`d71eb38b9a78e78a03e9ba4aaf035d48f4a5729a`. The scheduled
[Actions run](https://github.com/danReynolds/keybay/actions/runs/37280532141)
used `.github/workflows/security-watchers.yml`, attempt 1. The Actions-authored
branch changes only this report pair and `watchers/reports/SUMMARY.md`. Its
original raw blob is `acc3f058cf020b69e29faabc1fc398b030fd0560` and remains
unchanged. This triage is monitoring evidence, not release clearance or proof
that no vulnerability exists.

## Delta and reuse basis

The report contains 37 markers: five dependency signals and 32 peer signals.
Twenty peer sources are new to retained reports, three previously reviewed
peer sources have newer activity, and 14 markers are exact repeats. Counts for
the current report are therefore **20 new, 3 updated and 14 reused**. The
platform watcher failed before producing any platform markers.

The only changes since the [September 28
assessment](../2026-09-28-36394038936-1/assessment.md) are that assessment, its
raw report, and the generated summary. Provider, runtime, dependency-resolution,
CLI, workflow, and security-invariant code are unchanged. The four Go
advisories and `dbus` release are exact repeats. The nine exact-repeated peer
dispositions are also reused because the relevant Android, Apple, Linux, CLI,
and build mechanisms and assumptions are unchanged.

## Watcher dispositions

### Dependencies: actionable public maintenance, no runtime finding

The four `golang.org/x/crypto` v0.52.0 advisories affect SSH and OpenPGP code
that is absent from the nonshipping Go reference tool's dependency graph. They
do not affect the Dart SDK or CLI. The `dbus` 0.8.0 release establishes no
security fix Keybay requires, and all committed Dart resolutions retain the
exact reviewed 0.7.15 pin. [Issue
#75](https://github.com/danReynolds/keybay/issues/75) remains open for the
reference-module refresh and explicit reachability disposition.

### Platforms: watcher failed

Platform advisory discovery did not complete, so this report contains no
Apple, Android, or Linux platform evidence and cannot establish that those
sources were quiet. The run failed closed because Android's former bulletin
index became a category landing page with no dated bulletin links; Android now
publishes those links on its official `asb-overview` page. [Issue
#89](https://github.com/danReynolds/keybay/issues/89) tracks the narrowly scoped
source repair, parser regression coverage, and a complete all-source rerun.
[Issue #76](https://github.com/danReynolds/keybay/issues/76) remains open for
the previously identified Apple updated-host and applicable physical-device
qualification. No current platform disposition is inferred across this
monitoring gap.

### Peers: no finding or not applicable

The 20 new sources and three updated sources were reviewed first.

- Flutter Secure Storage's Android [unbounded reset
  report](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1282)
  and [proposed guard](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1284)
  require its per-operation biometric mode, enrollment invalidation, and
  `resetOnError` delete-and-recreate recursion. Keybay sets
  `setUserAuthenticationRequired(false)`, has no biometric prompt or automatic
  reset-on-error path, and never deletes provider state to recover from an
  ordinary open failure. The peer defect is not applicable.
- The peer's iOS [plugin-registration
  failure](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1283)
  concerns its Flutter method channel on iOS 27. Keybay uses its own direct
  Security.framework FFI boundary and does not depend on that plugin. The
  example AGP [patch](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1281)
  is build maintenance in a peer example.
- Python keyring's macOS [denied-delete
  report](https://github.com/jaraco/keyring/issues/772) and [proposed typed
  mapping](https://github.com/jaraco/keyring/pull/773) concern a peer exception
  taxonomy that could let its callers mistake denial for absence. Keybay's
  prepared reset verifies the exact current root, treats any delete failure as
  `resetIncomplete`, and confirms absence before success. It does not use the
  Python package or that exception contract. The inherited-wrapper
  [fix](https://github.com/jaraco/keyring/pull/770), missing-backend
  [fix](https://github.com/jaraco/keyring/pull/771), lint
  [cleanup](https://github.com/jaraco/keyring/issues/774), and action-pin
  [change](https://github.com/jaraco/keyring/pull/749) likewise do not share a
  Keybay runtime mechanism; Keybay's Actions are already full-SHA pinned and
  covered by grouped update automation.
- React Native Keychain's [DataStore singleton
  fix](https://github.com/oblador/react-native-keychain/pull/793) affects peer
  preferences storage Keybay does not use. Its StrongBox [performance
  report](https://github.com/oblador/react-native-keychain/issues/751) and
  [opt-out request](https://github.com/oblador/react-native-keychain/issues/817)
  concern slow RSA operations with per-use authentication on particular
  devices. Keybay uses one AES-GCM key with user authentication disabled,
  requests StrongBox as fixed policy, measures actual security level only in
  qualification, and never weakens an existing key because an operation is
  slow. These reports establish neither a Keybay failure nor a provider claim
  requiring physical-device qualification.
- The updated React Native [authentication-tag
  report](https://github.com/oblador/react-native-keychain/issues/802) adds
  affected-user comments but still has no reproduction or platform root
  cause. Keybay does not share the peer's storage or bridge code, and its own
  authenticated package and file failures are typed and fail closed. This does
  not establish an affected Keybay mechanism or a device condition to qualify.
- The Rust keyring [Windows credential-manager race
  report](https://github.com/open-source-cooperative/keyring-rs/issues/163)
  now includes a direct Win32 reproduction. Keybay does not support Windows
  and fails closed there. The peer's v4 [crate split](https://github.com/open-source-cooperative/keyring-rs/issues/259)
  and release, audit, documentation, semver, mutation-testing, and workflow
  hardening pull requests [#353](https://github.com/open-source-cooperative/keyring-rs/pull/353),
  [#354](https://github.com/open-source-cooperative/keyring-rs/pull/354),
  [#355](https://github.com/open-source-cooperative/keyring-rs/pull/355),
  [#356](https://github.com/open-source-cooperative/keyring-rs/pull/356),
  [#357](https://github.com/open-source-cooperative/keyring-rs/pull/357),
  [#358](https://github.com/open-source-cooperative/keyring-rs/pull/358), and
  [#359](https://github.com/open-source-cooperative/keyring-rs/pull/359) are
  peer maintenance; Keybay does not depend on those crates or workflows.

The remaining nine exact-repeated peer markers retain their prior Android
namespace, biometric, Apple replacement, CLI, and build-maintenance
dispositions. No plausible undisclosed Keybay vulnerability or additional
public work was identified.

## Actions

- [Go reference dependency maintenance (#75)](https://github.com/danReynolds/keybay/issues/75)
  remains open.
- [Apple provider qualification (#76)](https://github.com/danReynolds/keybay/issues/76)
  remains open.
- [Android watcher source repair (#89)](https://github.com/danReynolds/keybay/issues/89)
  was created for the failed platform watcher and required complete rerun.

No private advisory was warranted. Dependencies and peers were assessed; the
platform watcher failed and this assessment does not present monitoring as
complete.

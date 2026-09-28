<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-36394038936-1","status":"needs_attention","summary":"New and updated peer signals do not establish a Keybay vulnerability; Go reference maintenance and Apple qualification remain tracked follow-ups.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention**

Assessed on 2026-09-28 against the report source and current `main`,
`661754a02a958823218ad6c5c875fd6efa7b174f`. The successful scheduled
[Actions run](https://github.com/danReynolds/keybay/actions/runs/36394038936)
used `.github/workflows/security-watchers.yml`, attempt 1. The Actions-authored
branch changes only this report pair and `watchers/reports/SUMMARY.md`. Its
original raw blob is `44536c588babd6d126e11630cc6861424f47dce8` and remains
unchanged. This triage is monitoring evidence, not release clearance or proof
that no vulnerability exists.

## Delta and reuse basis

The report contains 50 markers: five dependency signals, one Apple advisory
group and 44 peer signals. Eight peer sources are new to the retained reports,
four previously reviewed peer sources have newer activity, and 38 markers are
exact repeats. Counts for the current report are therefore **8 new, 4 updated
and 38 reused**.

The release-only changes since the [September 21
assessment](../2026-09-21-35574369369-1/assessment.md) altered distribution
documentation, workflow comments and package metadata, but not provider,
runtime, dependency-resolution, CLI input or security-invariant code. The four
Go advisories, `dbus` release and Apple bulletin group are exact repeats. All
three committed Dart resolutions still use the reviewed `dbus` 0.7.15; the Go
reference still imports neither affected SSH nor OpenPGP packages. The 32
exact-repeated peer dispositions are also reused because the relevant Android,
Apple, Linux and CLI mechanisms are unchanged.

## Watcher dispositions

### Dependencies: actionable public maintenance, no runtime finding

The four `golang.org/x/crypto` v0.52.0 advisories affect SSH and OpenPGP code
that is absent from the nonshipping Go reference tool's dependency graph. They
do not affect the Dart SDK or CLI. The `dbus` 0.8.0 changelog establishes no
security fix Keybay requires and Keybay retains its exact reviewed 0.7.15 pin.
[Issue #75](https://github.com/danReynolds/keybay/issues/75) remains open for
the reference-module refresh and explicit reachability disposition.

### Platforms: existing qualification work remains open

The September 14 Apple bulletin group is an exact repeat. No provider code or
platform-custody assumption changed. [Issue
#76](https://github.com/danReynolds/keybay/issues/76) remains open for
updated-host and applicable physical-device qualification. This assessment
does not broaden any retained OS/device receipt.

### Peers: no finding or not applicable

The eight new sources and four updated sources were reviewed first.

- The updated [iOS deletion
  report](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229)
  adds follow-up production comments but still concerns a peer's failed-update,
  delete-then-add replacement path. Keybay stores one bounded immutable root,
  uses insert-only/adopt-the-winner creation with exact read-back, and deletes
  only during an explicitly prepared reset. It never uses that replacement
  mechanism.
- The new Android [EncryptedSharedPreferences
  report](https://github.com/juliansteenbakker/flutter_secure_storage/issues/900),
  updated Android 8 [BiometricPrompt class-loading
  report](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1276),
  and new [biometric cancellation
  issue](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1278)
  with its [proposed
  fix](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1279)
  do not share Keybay's mechanism. Keybay supports Android 12+, uses direct JNI
  to one non-exportable Keystore AES-GCM key, has no SharedPreferences/Tink
  migration or reset-on-error path, and does not use BiometricPrompt or require
  per-operation user authentication.
- The new React Native [generic Keystore failure
  report](https://github.com/oblador/react-native-keychain/issues/727) now has
  an unverified diagnostic proposal, not a demonstrated platform root cause.
  Keybay shares the Android Keystore boundary but not that library's cipher
  storage, coroutine, retry or bridge code. Keybay performs no automatic retry,
  reset or weaker fallback; native failures become redacted typed failures and
  continuity is cryptographically read back. The report establishes no
  affected Keybay claim or reproducible device condition, so it does not
  trigger physical-device qualification.
- The new example AGP and Robolectric updates ([#1281](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1281),
  [#1280](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1280))
  and updated React Native [AGP Kotlin-plugin
  fix](https://github.com/oblador/react-native-keychain/pull/812) are peer build
  maintenance. Those packages and Gradle scripts are not Keybay dependencies.
- Python keyring's new inherited-method [wrapper
  fix](https://github.com/jaraco/keyring/pull/770) and newly active [typing
  request](https://github.com/jaraco/keyring/issues/661) concern peer Python
  APIs Keybay does not use. The updated [empty piped-password
  fix](https://github.com/jaraco/keyring/pull/767) adds confirming review but
  does not change its disposition: Keybay deliberately rejects empty
  `set --stdin` input and never falls through from a pipe to an interactive
  value prompt.

The remaining 32 peer markers keep their prior Android namespace/migration,
Apple query/accessibility, Linux provider, native-protocol, and maintenance
dispositions. No plausible undisclosed Keybay vulnerability, new public work,
or watcher failure was identified.

## Actions

- [Go reference dependency maintenance (#75)](https://github.com/danReynolds/keybay/issues/75)
  remains open.
- [Apple provider qualification (#76)](https://github.com/danReynolds/keybay/issues/76)
  remains open.

No new issue or private advisory was warranted. All three watchers completed;
`findings` means reviewable signals, not a watcher failure.

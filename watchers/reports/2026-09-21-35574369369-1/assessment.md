<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-35574369369-1","status":"needs_attention","summary":"Exact repeat of the reviewed September 20 signals; Go reference maintenance and Apple provider qualification remain tracked follow-ups.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention**

Assessed on 2026-09-24 against `0a316136f49f900af08e087362eac0f1da2f2002`, which is newer than the report's discovery source `7965a5ea02e848a4de7216b094563cba5a0c40ee`. The scheduled Actions run used `.github/workflows/security-watchers.yml`, attempt 1. Its original raw blob is `35d6353c62db597e953cd4eb1a1b9d3a11612b49` and remains unchanged.

The unattended review finished on September 21, but its publication step was not approved, so this assessment reached `main` after the 48-hour window. It replaces that draft and covers the changes merged since then. This triage is monitoring evidence. It does not clear a release or prove that no vulnerability exists.

## Delta and reuse basis

All three discovery sections are byte-for-byte identical to the [previous report](../2026-09-20-35540736139-1/raw.md): 104 markers, made up of five dependency signals, one Apple advisory group and 98 peer signals. None are new or updated; all 104 dispositions are reused.

Reuse requires the relevant implementation to be unchanged. These changes landed after the [last assessment](../2026-09-20-35540736139-1/assessment.md):

- [#80](https://github.com/danReynolds/keybay/pull/80) refactored the TUI for the live web demo. The [2026-09-22 pre-release assessment](../../../doc/security-review.md#pre-release-assessment-2026-09-22) reviewed that code.
- [#81](https://github.com/danReynolds/keybay/pull/81) hardened the CLI and TUI: display escaping, core-dump and signal handling, and clipboard markers. Its SDK change adds a presence check before pinned macOS file-Keychain operations. Keychain queries, access control, accessibility and synchronization are unchanged. So is non-terminal (piped) secret input.
- [#83](https://github.com/danReynolds/keybay/pull/83) added Keybay Demo, an unpublished dogfooding app. Its new lockfile resolves `dbus` to the reviewed 0.7.15, and the pull request's OSV check passed.

None of these affects the dispositions below. The Go reference tool, the D-Bus transports and the reviewed-dependency list are unchanged.

## Watcher dispositions

### Dependencies: actionable public maintenance, no runtime finding

The four `golang.org/x/crypto` v0.52.0 advisories affect only the SSH and OpenPGP packages. The Go reference tool doesn't import either, and it doesn't ship. Nothing in the Dart SDK or CLI is affected. `dbus` 0.8.0 contains no security fix that Keybay needs; every lockfile that includes `dbus` stays on the reviewed 0.7.15. [Issue #75](https://github.com/danReynolds/keybay/issues/75) remains open.

### Platforms: existing qualification work remains open

The same September 14 Apple bulletin group repeats under its prior marker. The pinned-Keychain presence check doesn't change the platform-custody assumptions these bulletins bear on. [Issue #76](https://github.com/danReynolds/keybay/issues/76) remains open for updated-host and applicable physical-device qualification. This run qualifies no OS or device.

### Peers: no finding or not applicable

All 98 peer markers keep their reviewed dispositions.

- The Android namespace-deletion, migration, biometric and plugin-lifecycle reports concern mechanisms Keybay doesn't use.
- The Apple accessibility-query and duplicate-item reports don't match Keybay's fixed-profile, non-synchronizing root lookup.
- The Linux libsecret schema and warm-up reports don't match Keybay's typed D-Bus transports.
- The piped-password report still doesn't apply, because #81 didn't change non-terminal input handling.

No undisclosed Keybay vulnerability, new public work, or physical-device trigger was identified.

## Actions

- [Go reference dependency maintenance (#75)](https://github.com/danReynolds/keybay/issues/75) remains open.
- [Apple provider qualification (#76)](https://github.com/danReynolds/keybay/issues/76) remains open.

No new issue or private advisory was warranted. All three watchers completed; `findings` means reviewable signals, not a watcher failure.

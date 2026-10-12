<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-38221007653-1","status":"needs_attention","summary":"All sources completed; no new Keybay defect established. Existing Go-reference and Apple qualification follow-ups remain.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention** for existing tracked follow-ups; all three watchers
completed and the current watcher-health check is healthy.

Assessed on 2026-10-12 against source `4878c26f5ad07f50e1280d979799e400a3196c64`.
The successful scheduled [Actions run](https://github.com/danReynolds/keybay/actions/runs/38221007653)
used the reviewed default-branch watcher. Its Actions-authored branch changes
only this report pair and `watchers/reports/SUMMARY.md`. The immutable raw blob
`aa6a656fa74a9161164708e40378716a756d71e9` was verified before assessment.
This is monitoring and triage evidence, not a release certificate or proof
that no vulnerability exists.

## Delta and reuse basis

The report contains **47 signals: 0 new, 0 updated and 47 reused**: five
dependency, four platform and 38 peer markers. Every marker is an exact match
for a retained raw report, including the public-source update timestamp encoded
in peer markers. The [October 7 assessment](../2026-10-07-37651745087-1/assessment.md),
[October 5 assessment](../2026-10-05-37280532141-1/assessment.md) and
[September 14 assessment](../2026-09-14-34819142373-1/assessment.md) contain the
most recent dispositions for these groups.

Reuse was checked against current code rather than inferred from marker equality.
Since October 7, Keybay removed support and migration for the retired V2
singleton-passphrase policy, revised documentation and release tooling, and
published SDK/CLI artifacts. Current passphrase/passkey methods, the platform-only
encoding, provider roots and provider acquisition/reset boundaries are unchanged.
The removal narrows accepted store formats and does not introduce any peer
storage runtime. Android still uses a direct-JNI fixed Keystore root with user
authentication disabled; Apple still uses direct Security.framework FFI with
exact Data Protection group/file-Keychain profiles; unconfined Linux still uses
typed Secret Service D-Bus; and Flatpak still selects the Secret Portal without
falling back to Secret Service.

Focused current-source tests passed **87/87** across the Android Keystore,
Apple Data Protection Keychain, Linux Secret Service and Flatpak Secret Portal
contracts. The Go reference module verified successfully; its import graph still
contains `golang.org/x/crypto/chacha20poly1305`, not the advisory's SSH or
OpenPGP packages.

## Watcher dispositions

### Dependencies: actionable public maintenance, no runtime finding

The four repeated `golang.org/x/crypto` advisories concern SSH/OpenPGP code that
is absent from the nonshipping Go reference tool's import graph. The recent
reference-vector cleanup removed retired passphrase outputs but did not add an
affected import. These advisories do not reach the Dart SDK or CLI. The repeated
`dbus` 0.8.0 release establishes no required security fix; committed Dart
resolutions retain the exact reviewed 0.7.15 pin. [Issue #75](https://github.com/danReynolds/keybay/issues/75)
remains open for the compatible reference-module refresh and explicit
reachability record.

### Platforms: no new finding; existing qualification remains

The repeated September and October Android bulletins describe OS/framework,
kernel and vendor fixes; they establish no specific defect in Keybay's Keystore
or passkey mechanisms. Source discovery completed successfully, so the prior
Android watcher failure is resolved and [issue #89](https://github.com/danReynolds/keybay/issues/89)
is closed.

The repeated September 14 Apple group includes credential/custody boundaries
that justified the bounded updated-host and applicable physical-device work in
[issue #76](https://github.com/danReynolds/keybay/issues/76). That issue remains
open. The September 28 group establishes OS patch work but no new Keybay-specific
parser or custody defect. This repeat neither renews device evidence nor triggers
additional physical-device qualification.

### Peers: no finding or not applicable

- Flutter Secure Storage's iOS 27 `MissingPluginException` is a Flutter method-
  channel registration failure; Keybay uses its own Security.framework FFI.
  Its Android biometric invalidation/reset reports depend on per-operation
  biometric keys and automatic reset paths Keybay does not have. The remaining
  example, Gradle and Dependabot items are peer build maintenance.
- Python keyring's proposed Secret Portal backend independently retrieves an
  application-bound secret and encrypts a local file. Keybay already has its own
  fail-closed typed D-Bus Secret Portal protector and explicitly refuses a
  Secret Service fallback under confinement. Python CLI path expansion, wrapper,
  exception-mapping and workflow items do not share Keybay runtime code.
- React Native Keychain's DataStore singleton and RELRO reports concern native
  libraries Keybay does not use. Its StrongBox RSA latency and authentication-tag
  reports do not establish a failure in Keybay's AES-GCM root or authenticated
  file/package mechanisms. The SwiftPM item is peer integration maintenance.
- Go keyring's `security -i` line-boundary and shell-quoting defects are absent:
  Keybay's Apple provider calls Security.framework directly, and its child
  process boundary passes argv without this interactive parser. WSL support is
  outside Keybay's supported provider set.
- Rust keyring's Windows race is outside Keybay's supported platforms. Its
  release, semver, mutation, Rustdoc, dependency-audit and workflow changes are
  peer maintenance; Keybay depends on neither those crates nor workflows.

No plausible undisclosed Keybay vulnerability, watcher failure or additional
safe public work was identified. No new issue or private advisory was warranted.
Issues #75 and #76 remain the only actions carried by this report.

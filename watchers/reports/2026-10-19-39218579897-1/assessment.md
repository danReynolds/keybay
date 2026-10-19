<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-39218579897-1","status":"needs_attention","summary":"All sources completed; no new Keybay defect established. Existing Go-reference and Apple qualification follow-ups remain.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention** for existing tracked follow-ups; all three watchers
completed and the current watcher-health check is healthy.

Assessed on 2026-10-19 against source `adf6da6c0f027f2c7ccbfb9714648b0c619ebe24`.
The successful scheduled [Actions run](https://github.com/danReynolds/keybay/actions/runs/39218579897)
used the reviewed default-branch watcher. Its Actions-authored branch changes
only this report pair and `watchers/reports/SUMMARY.md`. The immutable raw blob
`5457e3073e996e7691b8e9fed92b39b76d15fdca` was verified before assessment.
This is monitoring and triage evidence, not a release certificate or proof
that no vulnerability exists.

## Delta and reuse basis

The report contains **58 signals: 24 new, 4 updated and 30 reused**. The reused
set comprises five dependency, four platform and 21 peer markers that exactly
match retained raw reports. The four updated markers are existing public items
whose update timestamp changed: Python keyring PR 771, Flutter Secure Storage
PRs 1286 and 1287, and Rust keyring issue 163. The remaining 24 markers are one
new reviewed dependency release and 23 new peer items.

Reuse was checked against current code rather than inferred from marker equality.
Since the [October 12 assessment](../2026-10-12-38221007653-1/assessment.md),
Keybay added credential-bound method confirmation, public SDK documentation and
the exact Keypass 0.1.0-dev.3 pin, then published 0.3.0 through 0.3.2. The fixed
Android Keystore root, Apple Data Protection Keychain profiles, ordinary-Linux
Secret Service root, Flatpak Secret Portal selection, and provider acquisition/
reset boundaries are unchanged. Method confirmation changes authenticated
package construction above those provider roots; they add no peer runtime.

Focused current-source tests passed **143/143** across Android and Apple host/
provider contracts, Linux Secret Service, Flatpak Secret Portal, auth-package,
method-confirmation and passkey-engine behavior. Three dependency-closure tests
also passed, including the exact hosted Keypass archive check. The nonshipping
Go reference module still imports only `golang.org/x/crypto/chacha20poly1305`
and its internal dependencies, not SSH or OpenPGP; `go test ./...` passed.

## Watcher dispositions

### Dependencies: existing public maintenance; no new runtime finding

The four repeated `golang.org/x/crypto` advisories affect SSH or OpenPGP imports
that are absent from the retained Go reference tool and do not reach the Dart
SDK or CLI. [Issue #75](https://github.com/danReynolds/keybay/issues/75) remains
open for the compatible reference-module refresh and explicit reachability
record. The repeated Dart `dbus` 0.8.0 release establishes no required security
fix; Keybay retains its exact reviewed 0.7.15 pin and its Secret Service code is
unchanged.

The new [Keypass 0.1.0-dev.3](https://pub.dev/packages/keypass/versions/0.1.0-dev.3)
marker is already the exact hosted dependency on current main. Review of
[Keypass PR #7](https://github.com/danReynolds/keypass/pull/7), the served archive,
Keybay's source manifest and [Keybay PR #112](https://github.com/danReynolds/keybay/pull/112)
shows that the release accepts one OpenSSL 3 or 4 library matching libfido2 and
still rejects mixed or unknown libcrypto versions. The C++ hardware adapter and
its CMake configuration did not change. Keybay pins the reviewed archive hash,
and PR #112's full provider matrix and supply-chain checks passed. This build-
closure update does not itself alter device ceremony behavior, so it does not
trigger new physical-device qualification.

### Platforms: no new finding; existing qualification remains

The four platform markers are exact repeats. The September and October Android
bulletins establish OS/framework, NFC, Bluetooth, kernel and vendor patch work,
not a specific failure in Keybay's fixed Keystore root or Keypass contract.
Those mechanisms were already present at the previous assessment; the subsequent
method-confirmation and OpenSSL-bundling changes do not change them.

The September 14 Apple group retains provider/custody changes that justified the
bounded updated-host and applicable physical-device work in
[issue #76](https://github.com/danReynolds/keybay/issues/76). It remains open.
The September 28 group adds OS patching but no new Keybay-specific mechanism.
These exact repeats neither renew old device evidence nor trigger an additional
qualification run.

### Peers: no finding or not applicable

- Flutter Secure Storage's new web first-write race and Android ESP migration
  skip use browser local storage and SharedPreferences migrations that Keybay
  neither supports nor imports. React Native Keychain's corrupt DataStore file
  is likewise a different persistence layer; Keybay authenticates its framed
  store, fails closed on corruption and never auto-resets unreadable state.
- Flutter Secure Storage PR 1290 reports a libsecret read-modify-write item that
  can be dropped or rejected. Keybay does not use libsecret or keep records in a
  shared JSON keyring item. Its direct D-Bus path creates one fixed root with
  `replace=false`, immediately re-searches and byte-compares the result before
  adopting it, and verifies absence after exact reset. The peer report therefore
  exposes no unhandled equivalent commit in Keybay.
- Python keyring's PyGObject CI dependency and fail-backend exception mapping do
  not share Keybay runtime code. The updated PR 771 only added follow-up comments.
  Its Portal, path-expansion and wrapper items remain non-applicable to Keybay's
  existing typed Secret Portal implementation.
- Go keyring's macOS reports confirm the risk of its `/usr/bin/security` backend
  and propose an opt-in Security.framework backend. Keybay already calls
  Security.framework directly and never sends secrets through that CLI. Its
  Linux no-service request is already covered by Keybay's typed, fail-closed
  D-Bus error mapping. The godbus update and other Go changes are peer-only.
- Rust keyring's Windows race is outside Keybay's supported provider set; its
  latest update records an upstream fix awaiting release. Feature-gating,
  visibility, coverage, release, semver, documentation and dependency/workflow
  pull requests are peer maintenance and are not dependencies of Keybay.
- The remaining Flutter example/Gradle/simulator updates are peer build
  maintenance. The two updated dependency PRs do not change the prior
  disposition.

No plausible undisclosed Keybay vulnerability, watcher failure or additional
safe public work was identified. No new issue or private advisory was warranted.
Issues #75 and #76 remain the only actions carried by this report.

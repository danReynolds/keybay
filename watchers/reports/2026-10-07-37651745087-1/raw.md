<!-- keybay-watcher-report: {"schema":1,"report_id":"github-37651745087-1","run_id":"37651745087","attempt":"1","event":"workflow_dispatch","commit":"afcd3e298f249e469455191782f80e2119a82d70","run_url":"https://github.com/danReynolds/keybay/actions/runs/37651745087","started_at":"2026-10-07T16:25:45.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-37651745087-1`](https://github.com/danReynolds/keybay/actions/runs/37651745087) (attempt `1`)
- Started: `2026-10-07T16:25:45.000Z`
- Source commit: `afcd3e298f249e469455191782f80e2119a82d70`
- GitHub event: `workflow_dispatch`

## Dependencies

Sources: OSV against every committed lockfile, plus new releases of specifically reviewed dependencies.

Status: **findings**

- **Resolved dependency advisory: CVE-2026-56854**
  - Subjects: `Committed resolved dependency graph`
  - References: [CVE-2026-56854](https://osv.dev/vulnerability/CVE-2026-56854)
  - Marker: `keybay-dependency-osv-CVE-2026-56854`

- **Resolved dependency advisory: CVE-2026-56855**
  - Subjects: `Committed resolved dependency graph`
  - References: [CVE-2026-56855](https://osv.dev/vulnerability/CVE-2026-56855)
  - Marker: `keybay-dependency-osv-CVE-2026-56855`

- **Resolved dependency advisory: CVE-2026-78662**
  - Subjects: `Committed resolved dependency graph`
  - References: [CVE-2026-78662](https://osv.dev/vulnerability/CVE-2026-78662)
  - Marker: `keybay-dependency-osv-CVE-2026-78662`

- **Resolved dependency advisory: GO-2026-5932**
  - Subjects: `Committed resolved dependency graph`
  - References: [GO-2026-5932](https://osv.dev/vulnerability/GO-2026-5932)
  - Marker: `keybay-dependency-osv-GO-2026-5932`

- **Reviewed dependency release: dbus 0.8.0**
  - Subjects: `Pub/dbus: reviewed 0.7.15; published 0.8.0`
  - References: [Pub/dbus](https://pub.dev/packages/dbus)
  - Marker: `keybay-dependency-release-pub-dbus-0.8.0`

## Platforms

Sources: Apple security releases, Android security bulletins, and narrow Linux credential-provider advisories.

Status: **findings**

- **Android platform advisory triage: 2026-09-01**
  - Subjects: `Android Security Bulletin 2026-09-01`
  - References: [Android Security Bulletin 2026-09-01](https://source.android.com/docs/security/bulletin/2026/2026-09-01)
  - Marker: `keybay-platform-android-2026-09-01`

- **Android platform advisory triage: 2026-10-01**
  - Subjects: `Android Security Bulletin 2026-10-01`
  - References: [Android Security Bulletin 2026-10-01](https://source.android.com/docs/security/bulletin/2026/2026-10-01)
  - Marker: `keybay-platform-android-2026-10-01`

- **Apple platform advisory triage: 2026-09-14**
  - Subjects: `iOS 26.7 and iPadOS 26.7`, `iOS 27 and iPadOS 27`, `macOS Golden Gate 27`, `macOS Sequoia 15.8`, `macOS Tahoe 26.7`
  - References: [iOS 26.7 and iPadOS 26.7](https://support.apple.com/en-us/149041), [iOS 27 and iPadOS 27](https://support.apple.com/en-us/149034), [macOS Golden Gate 27](https://support.apple.com/en-us/149035), [macOS Sequoia 15.8](https://support.apple.com/en-us/149043), [macOS Tahoe 26.7](https://support.apple.com/en-us/149042)
  - Marker: `keybay-platform-apple-2026-09-14-c7dfdd14254e`

- **Apple platform advisory triage: 2026-09-28**
  - Subjects: `iOS 26.7.1 and iPadOS 26.7.1`, `macOS Sequoia 15.8.1`, `macOS Tahoe 26.7.1`
  - References: [iOS 26.7.1 and iPadOS 26.7.1](https://support.apple.com/en-us/149226), [macOS Sequoia 15.8.1](https://support.apple.com/en-us/149229), [macOS Tahoe 26.7.1](https://support.apple.com/en-us/149228)
  - Marker: `keybay-platform-apple-2026-09-28-30eb9ecf1ec4`

## Peers

Sources: OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.

Status: **findings**

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 2 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1286](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1286)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1286-1791365944000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.8.0 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1287](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1287)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1287-1791365897000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.4.0 to 9.4.1 in /flutter\_secure\_storage/example/android in the example-android group**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1281](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1281)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1281-1791364968000`

- **Peer issue: Android: biometric key permanently invalidated after enrollment change cannot be recovered or deleted when requireBiometricsPerOperation is true**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1285](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1285)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1285-1791298750000`

- **Peer pull-request: fix(android): bound resetOnError re-initialization to a single attempt**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1284](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1284)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1284-1791066392000`

- **Peer issue: MissingPluginException IOS 27**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1283](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1283)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1283-1790918874000`

- **Peer issue: resetOnError recurses until the process dies when the fresh key also fails (Samsung, after biometric enrollment)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1282](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1282)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1282-1790677247000`

- **Peer issue: \[iOS\] Stored value disappears on some iOS devices**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1229](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1229-1790229208000`

- **Peer issue: Remove B018 suppressions after adopting skeleton's B018 ignore**
  - Subjects: `jaraco/keyring`
  - References: [issue 774](https://github.com/jaraco/keyring/issues/774)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-774-1791044810000`

- **Peer pull-request: Stop re-wrapping an inherited set\_password once per MRO class**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 770](https://github.com/jaraco/keyring/pull/770)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-770-1791023315000`

- **Peer pull-request: fix: map KeychainDenied on macOS delete to KeyringLocked**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 773](https://github.com/jaraco/keyring/pull/773)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-773-1790830048000`

- **Peer issue: macOS: denied keychain prompt on delete raises PasswordDeleteError instead of KeyringLocked**
  - Subjects: `jaraco/keyring`
  - References: [issue 772](https://github.com/jaraco/keyring/issues/772)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-772-1790795232000`

- **Peer pull-request: Raise from fail.Keyring.get\_credential when the username is omitted**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 771](https://github.com/jaraco/keyring/pull/771)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-771-1790749103000`

- **Peer pull-request: Pin GitHub Actions to full-length commit SHAs**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 749](https://github.com/jaraco/keyring/pull/749)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-749-1790606271000`

- **Peer issue: Add full-fledged type hints**
  - Subjects: `jaraco/keyring`
  - References: [issue 661](https://github.com/jaraco/keyring/issues/661)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-661-1790566072000`

- **Peer pull-request: Add Swift Package Manager manifest (React Native 0.87 SwiftPM)**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 819](https://github.com/oblador/react-native-keychain/pull/819)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-819-1791231344000`

- **Peer issue: Android: update DataStore dependency to incorporate verified GNU\_RELRO alignment fix**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 818](https://github.com/oblador/react-native-keychain/issues/818)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-818-1791201918000`

- **Peer pull-request: fix: make DataStore a singleton to prevent IllegalStateException on Android**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 793](https://github.com/oblador/react-native-keychain/pull/793)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-793-1790925893000`

- **Peer issue: cipher.init() is slow on Motorola Edge 50 Ultra.**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 751](https://github.com/oblador/react-native-keychain/issues/751)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-751-1790862630000`

- **Peer issue: Feature request: option to skip StrongBox on Android (`useStrongBox: false`)**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 817](https://github.com/oblador/react-native-keychain/issues/817)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-817-1790862574000`

- **Peer issue: "Decryption failed: Authentication tag verification failed"**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 802](https://github.com/oblador/react-native-keychain/issues/802)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-802-1790834815000`

- **Peer issue: Windows test instability - hard to reproduce**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 163](https://github.com/open-source-cooperative/keyring-rs/issues/163)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-163-1791131750000`

- **Peer pull-request: Publish from the release environment**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 359](https://github.com/open-source-cooperative/keyring-rs/pull/359)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-359-1791111358000`

- **Peer pull-request: Audit workflows with zizmor**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 358](https://github.com/open-source-cooperative/keyring-rs/pull/358)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-358-1791096361000`

- **Peer pull-request: Check semver compatibility against the latest release in CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 355](https://github.com/open-source-cooperative/keyring-rs/pull/355)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-355-1791094781000`

- **Peer pull-request: ci: gate crates.io publishing on tag CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 353](https://github.com/open-source-cooperative/keyring-rs/pull/353)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-353-1791057219000`

- **Peer pull-request: Mutation-test the lines each pull request changes**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 357](https://github.com/open-source-cooperative/keyring-rs/pull/357)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-357-1791056795000`

- **Peer pull-request: Deny rustdoc warnings in CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 356](https://github.com/open-source-cooperative/keyring-rs/pull/356)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-356-1791055156000`

- **Peer pull-request: Audit dependencies for RustSec advisories in CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 354](https://github.com/open-source-cooperative/keyring-rs/pull/354)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-354-1791053616000`

- **Peer issue: v4: Try the beta!**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 259](https://github.com/open-source-cooperative/keyring-rs/issues/259)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-259-1790793285000`

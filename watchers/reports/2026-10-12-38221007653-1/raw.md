<!-- keybay-watcher-report: {"schema":1,"report_id":"github-38221007653-1","run_id":"38221007653","attempt":"1","event":"schedule","commit":"4878c26f5ad07f50e1280d979799e400a3196c64","run_url":"https://github.com/danReynolds/keybay/actions/runs/38221007653","started_at":"2026-10-12T08:01:55.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-38221007653-1`](https://github.com/danReynolds/keybay/actions/runs/38221007653) (attempt `1`)
- Started: `2026-10-12T08:01:55.000Z`
- Source commit: `4878c26f5ad07f50e1280d979799e400a3196c64`
- GitHub event: `schedule`

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

- **Peer issue: MissingPluginException IOS 27**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1283](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1283)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1283-1791734766000`

- **Peer pull-request: ci: stop dependabot pinning the example's path dependency**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1288](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1288)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1288-1791402058000`

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

- **Peer issue: resetOnError recurses until the process dies when the fresh key also fails (Samsung, after biometric enrollment)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1282](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1282)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1282-1790677247000`

- **Peer issue: Support for Flatpak secrets portal on Linux**
  - Subjects: `jaraco/keyring`
  - References: [issue 748](https://github.com/jaraco/keyring/issues/748)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-748-1791674852000`

- **Peer pull-request: Add XDG Desktop Portal Secret backend for sandboxed Linux environments (Flatpak/Snap)**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 776](https://github.com/jaraco/keyring/pull/776)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-776-1791674802000`

- **Peer pull-request: Expand a leading ~ in the CLI --keyring-path value**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 775](https://github.com/jaraco/keyring/pull/775)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-775-1791642978000`

- **Peer pull-request: Raise from fail.Keyring.get\_credential when the username is omitted**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 771](https://github.com/jaraco/keyring/pull/771)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-771-1791638738000`

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

- **Peer pull-request: Pin GitHub Actions to full-length commit SHAs**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 749](https://github.com/jaraco/keyring/pull/749)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-749-1790606271000`

- **Peer issue: Android: update DataStore dependency to incorporate verified GNU\_RELRO alignment fix**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 818](https://github.com/oblador/react-native-keychain/issues/818)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-818-1791435781000`

- **Peer pull-request: Add Swift Package Manager manifest (React Native 0.87 SwiftPM)**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 819](https://github.com/oblador/react-native-keychain/pull/819)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-819-1791391839000`

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

- **Peer pull-request: fix(darwin): quote security -i arguments without a shell escaper**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 157](https://github.com/zalando/go-keyring/pull/157)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-157-1791739763000`

- **Peer pull-request: Add support for WSL environments to use Windows Credential Manager**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 150](https://github.com/zalando/go-keyring/pull/150)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-150-1791452855000`

- **Peer pull-request: fix(darwin): reject Set commands that security -i would split**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 156](https://github.com/zalando/go-keyring/pull/156)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-156-1791449450000`

- **Peer issue: On macOS, a failing Set can return nil at the largest command length Set allows**
  - Subjects: `zalando/go-keyring`
  - References: [issue 153](https://github.com/zalando/go-keyring/issues/153)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-153-1791445761000`

- **Peer pull-request: Update workflows**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 361](https://github.com/open-source-cooperative/keyring-rs/pull/361)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-361-1791735858000`

- **Peer pull-request: Bump taiki-e/install-action from 2.87.22 to 2.87.24 in the github-actions group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 360](https://github.com/open-source-cooperative/keyring-rs/pull/360)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-360-1791681788000`

- **Peer issue: Windows test instability - hard to reproduce**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 163](https://github.com/open-source-cooperative/keyring-rs/issues/163)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-163-1791680856000`

- **Peer pull-request: Audit workflows with zizmor**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 358](https://github.com/open-source-cooperative/keyring-rs/pull/358)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-358-1791680695000`

- **Peer pull-request: Publish from the release environment**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 359](https://github.com/open-source-cooperative/keyring-rs/pull/359)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-359-1791680634000`

- **Peer pull-request: Check semver compatibility against the latest release in CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 355](https://github.com/open-source-cooperative/keyring-rs/pull/355)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-355-1791680593000`

- **Peer pull-request: Mutation-test the lines each pull request changes**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 357](https://github.com/open-source-cooperative/keyring-rs/pull/357)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-357-1791680554000`

- **Peer pull-request: Deny rustdoc warnings in CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 356](https://github.com/open-source-cooperative/keyring-rs/pull/356)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-356-1791680523000`

- **Peer pull-request: Audit dependencies for RustSec advisories in CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 354](https://github.com/open-source-cooperative/keyring-rs/pull/354)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-354-1791680487000`

- **Peer pull-request: ci: gate crates.io publishing on tag CI**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 353](https://github.com/open-source-cooperative/keyring-rs/pull/353)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-353-1791057219000`

- **Peer issue: v4: Try the beta!**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 259](https://github.com/open-source-cooperative/keyring-rs/issues/259)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-259-1790793285000`

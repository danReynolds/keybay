<!-- keybay-watcher-report: {"schema":1,"report_id":"github-39218579897-1","run_id":"39218579897","attempt":"1","event":"schedule","commit":"adf6da6c0f027f2c7ccbfb9714648b0c619ebe24","run_url":"https://github.com/danReynolds/keybay/actions/runs/39218579897","started_at":"2026-10-19T07:51:29.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-39218579897-1`](https://github.com/danReynolds/keybay/actions/runs/39218579897) (attempt `1`)
- Started: `2026-10-19T07:51:29.000Z`
- Source commit: `adf6da6c0f027f2c7ccbfb9714648b0c619ebe24`
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

- **Reviewed dependency release: keypass 0.1.0-dev.3**
  - Subjects: `Pub/keypass: reviewed 0.1.0-dev.2; published 0.1.0-dev.3`
  - References: [Pub/keypass](https://pub.dev/packages/keypass)
  - Marker: `keybay-dependency-release-pub-keypass-0.1.0-dev.3`

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

- **Peer issue: \[Web\] Concurrent writes on a fresh storage overwrite the encryption key, leaving values undecryptable (OperationError)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1289](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1289)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1289-1792312011000`

- **Peer issue: Android: 9.2.4 (encryptedSharedPreferences: true) → 10.3.4 with migrateWithBackup: true skips the ESP migration (canSkipMarkerlessMigration)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1293](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1293)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1293-1792054160000`

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 2 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1286](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1286)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1286-1792009725000`

- **Peer pull-request: chore(deps): bump futureware-tech/simulator-action from 5 to 6 in the github-actions group**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1292](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1292)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1292-1792009433000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.8.1 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1291](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1291)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1291-1792008899000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.8.0 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1287](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1287)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1287-1792008406000`

- **Peer pull-request: fix(linux): verify keyring stores and surface rejected libsecret calls**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1290](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1290)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1290-1792004502000`

- **Peer issue: MissingPluginException IOS 27**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1283](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1283)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1283-1791734766000`

- **Peer pull-request: ci: stop dependabot pinning the example's path dependency**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1288](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1288)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1288-1791402058000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.4.0 to 9.4.1 in /flutter\_secure\_storage/example/android in the example-android group**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1281](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1281)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1281-1791364968000`

- **Peer issue: Android: biometric key permanently invalidated after enrollment change cannot be recovered or deleted when requireBiometricsPerOperation is true**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1285](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1285)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1285-1791298750000`

- **Peer pull-request: Raise from fail.Keyring.get\_credential when the username is omitted**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 771](https://github.com/jaraco/keyring/pull/771)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-771-1792258447000`

- **Peer issue: pygobject-stubs now requires PyGObject, which can't be installed in CI**
  - Subjects: `jaraco/keyring`
  - References: [issue 777](https://github.com/jaraco/keyring/issues/777)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-777-1792246707000`

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

- **Peer issue: Android: corrupt `RN\_KEYCHAIN.preferences\_pb` causes permanent `CorruptionException` on every get/set/reset (no `corruptionHandler`)**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 820](https://github.com/oblador/react-native-keychain/issues/820)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-820-1792139231000`

- **Peer issue: Android: update DataStore dependency to incorporate verified GNU\_RELRO alignment fix**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 818](https://github.com/oblador/react-native-keychain/issues/818)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-818-1791435781000`

- **Peer pull-request: Add Swift Package Manager manifest (React Native 0.87 SwiftPM)**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 819](https://github.com/oblador/react-native-keychain/pull/819)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-819-1791391839000`

- **Peer pull-request: build(deps): bump github.com/godbus/dbus/v5 from 5.2.2 to 5.2.3 in the all-go-mod-patch-and-minor group**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 160](https://github.com/zalando/go-keyring/pull/160)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-160-1792111394000`

- **Peer issue: Linux: return a typed error when no Secret Service is available**
  - Subjects: `zalando/go-keyring`
  - References: [issue 159](https://github.com/zalando/go-keyring/issues/159)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-159-1792058055000`

- **Peer issue: \[MacOS\] Insecure keychain usage**
  - Subjects: `zalando/go-keyring`
  - References: [issue 110](https://github.com/zalando/go-keyring/issues/110)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-110-1791999293000`

- **Peer pull-request: darwin: implement keyring using purego**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 136](https://github.com/zalando/go-keyring/pull/136)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-136-1791999236000`

- **Peer pull-request: Add New(Options) with an opt-in Security framework backend on macOS**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 158](https://github.com/zalando/go-keyring/pull/158)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-158-1791999101000`

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

- **Peer pull-request: Make crate-internal items private or pub(crate)**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 370](https://github.com/open-source-cooperative/keyring-rs/pull/370)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-370-1792296628000`

- **Peer pull-request: Report test coverage to Codecov**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 371](https://github.com/open-source-cooperative/keyring-rs/pull/371)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-371-1792223094000`

- **Peer pull-request: Bump zeroize from 1.9.0 to 1.9.1 in the cargo group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 368](https://github.com/open-source-cooperative/keyring-rs/pull/368)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-368-1792118452000`

- **Peer pull-request: Bump taiki-e/install-action from 2.87.24 to 2.87.27 in the github-actions group across 1 directory**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 369](https://github.com/open-source-cooperative/keyring-rs/pull/369)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-369-1792117830000`

- **Peer pull-request: Add a ci-success job and name the semver job cargo-semver**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 367](https://github.com/open-source-cooperative/keyring-rs/pull/367)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-367-1792109298000`

- **Peer pull-request: Publish without re-running CI in the release workflow**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 366](https://github.com/open-source-cooperative/keyring-rs/pull/366)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-366-1792107449000`

- **Peer pull-request: Require docs on public items in the docs check**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 365](https://github.com/open-source-cooperative/keyring-rs/pull/365)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-365-1792085828000`

- **Peer pull-request: Gate publishing on the semver and docs checks**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 363](https://github.com/open-source-cooperative/keyring-rs/pull/363)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-363-1792069085000`

- **Peer pull-request: Let the pinned zizmor-action choose the zizmor version**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 364](https://github.com/open-source-cooperative/keyring-rs/pull/364)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-364-1792066370000`

- **Peer issue: Move all keystore implementations to features**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 322](https://github.com/open-source-cooperative/keyring-rs/issues/322)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-322-1792065470000`

- **Peer issue: Windows test instability - hard to reproduce**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 163](https://github.com/open-source-cooperative/keyring-rs/issues/163)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-163-1792021631000`

- **Peer pull-request: Feature gate the db-sqlite keystore**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 362](https://github.com/open-source-cooperative/keyring-rs/pull/362)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-362-1791960913000`

- **Peer pull-request: Update workflows**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 361](https://github.com/open-source-cooperative/keyring-rs/pull/361)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-361-1791735858000`

- **Peer pull-request: Bump taiki-e/install-action from 2.87.22 to 2.87.24 in the github-actions group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 360](https://github.com/open-source-cooperative/keyring-rs/pull/360)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-360-1791681788000`

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

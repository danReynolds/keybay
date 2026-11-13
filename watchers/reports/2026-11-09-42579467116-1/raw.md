<!-- keybay-watcher-report: {"schema":1,"report_id":"github-42579467116-1","run_id":"42579467116","attempt":"1","event":"schedule","commit":"6eed3ebfa4e90785985fe87665c616fd6e0361cf","run_url":"https://github.com/danReynolds/keybay/actions/runs/42579467116","started_at":"2026-11-09T07:28:46.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-42579467116-1`](https://github.com/danReynolds/keybay/actions/runs/42579467116) (attempt `1`)
- Started: `2026-11-09T07:28:46.000Z`
- Source commit: `6eed3ebfa4e90785985fe87665c616fd6e0361cf`
- GitHub event: `schedule`

## Dependencies

Sources: OSV against every committed lockfile, plus new releases of specifically reviewed dependencies.

Status: **findings**

- **Resolved dependency advisory: CVE-2026-102554**
  - Subjects: `Committed resolved dependency graph`
  - References: [CVE-2026-102554](https://osv.dev/vulnerability/CVE-2026-102554)
  - Marker: `keybay-dependency-osv-CVE-2026-102554`

- **Resolved dependency advisory: CVE-2026-116695**
  - Subjects: `Committed resolved dependency graph`
  - References: [CVE-2026-116695](https://osv.dev/vulnerability/CVE-2026-116695)
  - Marker: `keybay-dependency-osv-CVE-2026-116695`

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

- **Android platform advisory triage: 2026-11-01**
  - Subjects: `Android Security Bulletin 2026-11-01`
  - References: [Android Security Bulletin 2026-11-01](https://source.android.com/docs/security/bulletin/2026/2026-11-01)
  - Marker: `keybay-platform-android-2026-11-01`

- **Apple platform advisory triage: 2026-09-14**
  - Subjects: `iOS 26.7 and iPadOS 26.7`, `iOS 27 and iPadOS 27`, `macOS Golden Gate 27`, `macOS Sequoia 15.8`, `macOS Tahoe 26.7`
  - References: [iOS 26.7 and iPadOS 26.7](https://support.apple.com/en-us/149041), [iOS 27 and iPadOS 27](https://support.apple.com/en-us/149034), [macOS Golden Gate 27](https://support.apple.com/en-us/149035), [macOS Sequoia 15.8](https://support.apple.com/en-us/149043), [macOS Tahoe 26.7](https://support.apple.com/en-us/149042)
  - Marker: `keybay-platform-apple-2026-09-14-c7dfdd14254e`

- **Apple platform advisory triage: 2026-09-28**
  - Subjects: `iOS 26.7.1 and iPadOS 26.7.1`, `macOS Sequoia 15.8.1`, `macOS Tahoe 26.7.1`
  - References: [iOS 26.7.1 and iPadOS 26.7.1](https://support.apple.com/en-us/149226), [macOS Sequoia 15.8.1](https://support.apple.com/en-us/149229), [macOS Tahoe 26.7.1](https://support.apple.com/en-us/149228)
  - Marker: `keybay-platform-apple-2026-09-28-30eb9ecf1ec4`

- **Apple platform advisory triage: 2026-10-26**
  - Subjects: `iOS 18.7.11 and iPadOS 18.7.11`, `iOS 26.7.2 and iPadOS 26.7.2`, `iOS 27.2 and iPadOS 27.2`, `macOS Golden Gate 27.2`, `macOS Sequoia 15.8.2`, `macOS Tahoe 26.7.2`
  - References: [iOS 18.7.11 and iPadOS 18.7.11](https://support.apple.com/en-us/149225), [iOS 26.7.2 and iPadOS 26.7.2](https://support.apple.com/en-us/149227), [iOS 27.2 and iPadOS 27.2](https://support.apple.com/en-us/149230), [macOS Golden Gate 27.2](https://support.apple.com/en-us/149521), [macOS Sequoia 15.8.2](https://support.apple.com/en-us/149523), [macOS Tahoe 26.7.2](https://support.apple.com/en-us/149522)
  - Marker: `keybay-platform-apple-2026-10-26-c0acde70aefe`

- **Linux credential-platform advisory triage: CVE-2026-120749**
  - Subjects: `Debian/dbus`, `Ubuntu/dbus`
  - References: [DEBIAN-CVE-2026-120749](https://osv.dev/vulnerability/DEBIAN-CVE-2026-120749), [UBUNTU-CVE-2026-120749](https://osv.dev/vulnerability/UBUNTU-CVE-2026-120749)
  - Marker: `keybay-platform-linux-CVE-2026-120749`

## Peers

Sources: OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.

Status: **findings**

- **Peer issue: Android: 9.2.4 (encryptedSharedPreferences: true) → 10.3.4 with migrateWithBackup: true skips the ESP migration (canSkipMarkerlessMigration)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1293](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1293)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1293-1794082418000`

- **Peer pull-request: fix(web): use one encryption key when first writes run at the same time**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1297](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1297)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1297-1794039327000`

- **Peer issue: Swift Package Manager Support: Add FlutterFramework Dependency**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1307](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1307)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1307-1794032309000`

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 3 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1295](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1295)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1295-1793784740000`

- **Peer pull-request: chore(deps): bump futureware-tech/simulator-action from 5 to 6 in the github-actions group across 1 directory**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1292](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1292)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1292-1793784649000`

- **Peer pull-request: fix(android): preserve RSA keys on incomplete keystore reads**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1306](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1306)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1306-1793699878000`

- **Peer pull-request: fix(android): serialize initialization across engines sharing a key store**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1299](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1299)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1299-1793686677000`

- **Peer issue: Android: transient Keystore error makes `createRSAKeysIfNeeded` replace the RSA pair — all data lost even with `resetOnError: false`**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1298](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1298)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1298-1793686663000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage 11.2.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1304](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1304)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1304-1793684302000`

- **Peer issue: strongBiometricOnly read/write/delete hangs forever when the BiometricPrompt negative button is tapped (regression from #1267)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1278](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1278)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1278-1793568948000`

- **Peer pull-request: fix(android): don't hang when strongBiometricOnly negative button is tapped**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1279](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1279)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1279-1793568947000`

- **Peer pull-request: chore: add analyzer excludes from Flutter 3.47**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1305](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1305)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1305-1793568873000`

- **Peer pull-request: fix(linux): verify keyring stores and surface rejected libsecret calls**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1290](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1290)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1290-1793566695000`

- **Peer pull-request: deps: bump com.google.crypto.tink:tink-android from 1.23.0 to 1.24.0 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1301](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1301)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1301-1793566192000`

- **Peer pull-request: ci: stop dependabot pinning the example's path dependency**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1288](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1288)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1288-1793566056000`

- **Peer pull-request: fix(android): bound resetOnError re-initialization to a single attempt**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1284](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1284)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1284-1793565984000`

- **Peer pull-request: deps: bump org.robolectric:robolectric from 4.16.1 to 4.17 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1280](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1280)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1280-1793565516000`

- **Peer pull-request: fix(android): keep encrypting when EncryptedSharedPreferences fails to open in compat mode**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1300](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1300)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1300-1793454566000`

- **Peer issue: requireBiometricsPerOperation: true  is ignored after a cipher migration —  storageCipher  stays cached for the process**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1303](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1303)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1303-1793256966000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.8.2 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1302](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1302)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1302-1793179888000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.8.1 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1291](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1291)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1291-1793179381000`

- **Peer pull-request: feat(android): add opt-in legacy secure storage migration**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1296](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1296)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1296-1793067706000`

- **Peer pull-request: fix-781 check username to avoid duplicate entries in windows backend**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 782](https://github.com/jaraco/keyring/pull/782)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-782-1793801932000`

- **Peer issue: Duplicated Credentials in WinVaultKeyring backend**
  - Subjects: `jaraco/keyring`
  - References: [issue 781](https://github.com/jaraco/keyring/issues/781)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-781-1793782147000`

- **Peer pull-request: Expand a leading ~ in the CLI --keyring-path value**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 775](https://github.com/jaraco/keyring/pull/775)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-775-1793333556000`

- **Peer issue: Feat: Add keyring.status()**
  - Subjects: `jaraco/keyring`
  - References: [issue 780](https://github.com/jaraco/keyring/issues/780)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-780-1793319437000`

- **Peer pull-request: test: increase timeout in e2e tests**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 745](https://github.com/oblador/react-native-keychain/pull/745)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-745-1794043743000`

- **Peer pull-request: test: allow iOS contract batch time on hosted simulators**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 835](https://github.com/oblador/react-native-keychain/pull/835)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-835-1793970999000`

- **Peer release: v11.0.0**
  - Subjects: `oblador/react-native-keychain`
  - References: [release v11.0.0](https://github.com/oblador/react-native-keychain/releases/tag/v11.0.0)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-release-v11.0.0-1793968463000`

- **Peer pull-request: Release 11.0.0**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 834](https://github.com/oblador/react-native-keychain/pull/834)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-834-1793967981000`

- **Peer pull-request: fix: preserve prompt defaults and align public APIs with native results**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 805](https://github.com/oblador/react-native-keychain/pull/805)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-805-1793967540000`

- **Peer pull-request: test: split native storage coverage from Detox flows**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 833](https://github.com/oblador/react-native-keychain/pull/833)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-833-1793966613000`

- **Peer pull-request: feat(ios): add Swift Package Manager support**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 822](https://github.com/oblador/react-native-keychain/pull/822)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-822-1793964657000`

- **Peer pull-request: chore(docs): migrate to dark VitePress documentation**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 832](https://github.com/oblador/react-native-keychain/pull/832)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-832-1793957676000`

- **Peer pull-request: docs: show how to store multiple independent values**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 831](https://github.com/oblador/react-native-keychain/pull/831)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-831-1793954557000`

- **Peer issue: How to save multiple key value ?**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 299](https://github.com/oblador/react-native-keychain/issues/299)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-299-1793954556000`

- **Peer issue: Does authenticationPrompt need to be declared as of V6**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 330](https://github.com/oblador/react-native-keychain/issues/330)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-330-1793954091000`

- **Peer issue: add CHANGELOG**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 323](https://github.com/oblador/react-native-keychain/issues/323)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-323-1793954087000`

- **Peer pull-request: docs: clarify Android storage defaults and v10 upgrades**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 830](https://github.com/oblador/react-native-keychain/pull/830)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-830-1793953611000`

- **Peer issue: Default "STORAGE\_TYPE" in setGenericPassword**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 782](https://github.com/oblador/react-native-keychain/issues/782)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-782-1793953610000`

- **Peer issue: Question: Differences between `canImplyAuthentication` and `isPasscodeAuthAvailable` / `getSupportedBiometryType`**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 786](https://github.com/oblador/react-native-keychain/issues/786)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-786-1793953157000`

- **Peer pull-request: feat: list internet credential servers without reading passwords**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 828](https://github.com/oblador/react-native-keychain/pull/828)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-828-1793953081000`

- **Peer issue: getGenericPassword result is unclear**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 785](https://github.com/oblador/react-native-keychain/issues/785)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-785-1793952769000`

- **Peer pull-request: docs: clarify getGenericPassword false result**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 799](https://github.com/oblador/react-native-keychain/pull/799)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-799-1793952768000`

- **Peer issue: Android: Fingerprint authentication not implemented yet**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 116](https://github.com/oblador/react-native-keychain/issues/116)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-116-1793952644000`

- **Peer issue: authenticationPrompt does not work in getInternetCredentials**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 201](https://github.com/oblador/react-native-keychain/issues/201)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-201-1793952642000`

- **Peer pull-request: fix(android): update DataStore for RELRO alignment**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 829](https://github.com/oblador/react-native-keychain/pull/829)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-829-1793892941000`

- **Peer issue: Android: update DataStore dependency to incorporate verified GNU\_RELRO alignment fix**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 818](https://github.com/oblador/react-native-keychain/issues/818)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-818-1793892940000`

- **Peer pull-request: fix(android): list stored services and preserve authentication on reads**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 827](https://github.com/oblador/react-native-keychain/pull/827)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-827-1793891517000`

- **Peer pull-request: chore: refresh example app**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 826](https://github.com/oblador/react-native-keychain/pull/826)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-826-1793878842000`

- **Peer pull-request: chore: improve coding agent guidance**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 825](https://github.com/oblador/react-native-keychain/pull/825)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-825-1793829276000`

- **Peer pull-request: fix(ios): respect cloudSync false**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 824](https://github.com/oblador/react-native-keychain/pull/824)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-824-1793828385000`

- **Peer issue: iOS: cloudSync: false is treated as true — items written to iCloud keychain when the caller explicitly opted out**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 800](https://github.com/oblador/react-native-keychain/issues/800)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-800-1793828384000`

- **Peer pull-request: feat!: require React Native 0.82 and the New Architecture**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 823](https://github.com/oblador/react-native-keychain/pull/823)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-823-1793820181000`

- **Peer pull-request: build(deps): bump github.com/godbus/dbus/v5 from 5.2.2 to 5.2.3 in the all-go-mod-patch-and-minor group**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 160](https://github.com/zalando/go-keyring/pull/160)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-160-1793925816000`

- **Peer pull-request: Add New(Options) with an opt-in Security framework backend on macOS**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 158](https://github.com/zalando/go-keyring/pull/158)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-158-1793805075000`

- **Peer pull-request: secret\_service: return an error when a prompt is dismissed**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 162](https://github.com/zalando/go-keyring/pull/162)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-162-1793804920000`

- **Peer issue: Secret Service: dismissed prompts are not treated as errors**
  - Subjects: `zalando/go-keyring`
  - References: [issue 161](https://github.com/zalando/go-keyring/issues/161)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-161-1793668117000`

- **Peer issue: Support for secrets portal**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 376](https://github.com/open-source-cooperative/keyring-rs/issues/376)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-376-1794136779000`

- **Peer pull-request: Bump keyring-core from 1.0.0 to 1.0.1 in the cargo group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 378](https://github.com/open-source-cooperative/keyring-rs/pull/378)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-378-1793986734000`

- **Peer pull-request: Bump the github-actions group with 2 updates**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 377](https://github.com/open-source-cooperative/keyring-rs/pull/377)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-377-1793986684000`

- **Peer pull-request: Report test coverage to Codecov**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 371](https://github.com/open-source-cooperative/keyring-rs/pull/371)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-371-1793667338000`

- **Peer pull-request: Bump keyring-core from 1.0.0 to 1.0.1 in the cargo group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 373](https://github.com/open-source-cooperative/keyring-rs/pull/373)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-373-1793473802000`

- **Peer pull-request: Bump the github-actions group across 1 directory with 3 updates**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 375](https://github.com/open-source-cooperative/keyring-rs/pull/375)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-375-1793469835000`

- **Peer pull-request: Bump the github-actions group with 2 updates**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 374](https://github.com/open-source-cooperative/keyring-rs/pull/374)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-374-1793312581000`

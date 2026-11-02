<!-- keybay-watcher-report: {"schema":1,"report_id":"github-41406436126-1","run_id":"41406436126","attempt":"1","event":"schedule","commit":"6eed3ebfa4e90785985fe87665c616fd6e0361cf","run_url":"https://github.com/danReynolds/keybay/actions/runs/41406436126","started_at":"2026-11-02T07:28:39.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-41406436126-1`](https://github.com/danReynolds/keybay/actions/runs/41406436126) (attempt `1`)
- Started: `2026-11-02T07:28:39.000Z`
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

## Peers

Sources: OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.

Status: **findings**

- **Peer pull-request: chore(develop): release flutter\_secure\_storage 11.2.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1304](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1304)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1304-1793569419000`

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

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 3 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1295](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1295)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1295-1793567154000`

- **Peer pull-request: chore(deps): bump futureware-tech/simulator-action from 5 to 6 in the github-actions group across 1 directory**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1292](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1292)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1292-1793567083000`

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

- **Peer pull-request: fix(android): serialize initialization across engines sharing a key store**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1299](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1299)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1299-1793029435000`

- **Peer issue: Android: transient Keystore error makes `createRSAKeysIfNeeded` replace the RSA pair — all data lost even with `resetOnError: false`**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1298](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1298)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1298-1792963223000`

- **Peer issue: Android: 9.2.4 (encryptedSharedPreferences: true) → 10.3.4 with migrateWithBackup: true skips the ESP migration (canSkipMarkerlessMigration)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1293](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1293)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1293-1792843863000`

- **Peer pull-request: fix(web): use one encryption key when first writes run at the same time**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1297](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1297)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1297-1792772632000`

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 2 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1286](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1286)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1286-1792574577000`

- **Peer issue: resetOnError recurses until the process dies when the fresh key also fails (Samsung, after biometric enrollment)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1282](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1282)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1282-1792506596000`

- **Peer pull-request: fix(android): recover per-operation biometric storage from an invalidated key**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1294](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1294)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1294-1792492006000`

- **Peer pull-request: Expand a leading ~ in the CLI --keyring-path value**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 775](https://github.com/jaraco/keyring/pull/775)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-775-1793333556000`

- **Peer issue: Feat: Add keyring.status()**
  - Subjects: `jaraco/keyring`
  - References: [issue 780](https://github.com/jaraco/keyring/issues/780)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-780-1793319437000`

- **Peer pull-request: Add optional keyring\_type parameter to get\_keyring() and type SecretService.get\_preferred\_collection**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 779](https://github.com/jaraco/keyring/pull/779)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-779-1792832241000`

- **Peer pull-request: Ignore B018 and drop the redundant suppressions.**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 778](https://github.com/jaraco/keyring/pull/778)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-778-1792571444000`

- **Peer issue: create an asyncio interface**
  - Subjects: `jaraco/keyring`
  - References: [issue 397](https://github.com/jaraco/keyring/issues/397)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-397-1792489940000`

- **Peer pull-request: fix: update iOS keychain items in place instead of deleting first**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 821](https://github.com/oblador/react-native-keychain/pull/821)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-821-1792799797000`

- **Peer pull-request: fix: fall back to SecItemUpdate when SecItemAdd reports a duplicate item on iOS**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 814](https://github.com/oblador/react-native-keychain/pull/814)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-814-1792794407000`

- **Peer pull-request: build(deps): bump github.com/godbus/dbus/v5 from 5.2.2 to 5.2.3 in the all-go-mod-patch-and-minor group**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 160](https://github.com/zalando/go-keyring/pull/160)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-160-1793321019000`

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

- **Peer issue: Zeroize passwords**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 372](https://github.com/open-source-cooperative/keyring-rs/issues/372)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-372-1792422638000`

- **Peer issue: Move all keystore implementations to features**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 322](https://github.com/open-source-cooperative/keyring-rs/issues/322)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-322-1792418673000`

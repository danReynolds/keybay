<!-- keybay-watcher-report: {"schema":1,"report_id":"github-36394038936-1","run_id":"36394038936","attempt":"1","event":"schedule","commit":"661754a02a958823218ad6c5c875fd6efa7b174f","run_url":"https://github.com/danReynolds/keybay/actions/runs/36394038936","started_at":"2026-09-28T07:53:36.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-36394038936-1`](https://github.com/danReynolds/keybay/actions/runs/36394038936) (attempt `1`)
- Started: `2026-09-28T07:53:36.000Z`
- Source commit: `661754a02a958823218ad6c5c875fd6efa7b174f`
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

- **Apple platform advisory triage: 2026-09-14**
  - Subjects: `iOS 26.7 and iPadOS 26.7`, `iOS 27 and iPadOS 27`, `macOS Golden Gate 27`, `macOS Sequoia 15.8`, `macOS Tahoe 26.7`
  - References: [iOS 26.7 and iPadOS 26.7](https://support.apple.com/en-us/149041), [iOS 27 and iPadOS 27](https://support.apple.com/en-us/149034), [macOS Golden Gate 27](https://support.apple.com/en-us/149035), [macOS Sequoia 15.8](https://support.apple.com/en-us/149043), [macOS Tahoe 26.7](https://support.apple.com/en-us/149042)
  - Marker: `keybay-platform-apple-2026-09-14-c7dfdd14254e`

## Peers

Sources: OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.

Status: **findings**

- **Peer issue: \[iOS\] Stored value disappears on some iOS devices**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1229](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1229-1790229208000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.4.0 to 9.4.1 in /flutter\_secure\_storage/example/android in the example-android group**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1281](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1281)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1281-1790155964000`

- **Peer pull-request: deps: bump org.robolectric:robolectric from 4.16.1 to 4.17 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1280](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1280)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1280-1790155899000`

- **Peer issue: EncryptedSharedPreferences initialization failed**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 900](https://github.com/juliansteenbakker/flutter_secure_storage/issues/900)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-900-1790062477000`

- **Peer issue: Log error on app open: Rejecting re-init on previously-failed class com.it\_nomads.fluttersecurestorage.FlutterSecureStorage**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1276](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1276)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1276-1789988106000`

- **Peer issue: strongBiometricOnly read/write/delete hangs forever when the BiometricPrompt negative button is tapped (regression from #1267)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1278](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1278)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1278-1789985871000`

- **Peer pull-request: fix(android): don't hang when strongBiometricOnly negative button is tapped**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1279](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1279)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1279-1789985608000`

- **Peer issue: \[Feature Request\] Add Swift Package Manager support for flutter\_secure\_storage**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1277](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1277)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1277-1789739302000`

- **Peer pull-request: docs: improve Linux section in README of flutter\_secure\_storage**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1275](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1275)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1275-1789739038000`

- **Peer issue: \[linux\] support XDG Desktop Secret Portal (org.freedesktop.portal.Secret)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1203](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1203)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1203-1789737873000`

- **Peer issue: iOS: `kSecAttrAccessible` used as strict search filter in 0.3.x breaks reads for items with different accessibility level**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1164](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1164)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1164-1789639369000`

- **Peer pull-request: refactor(linux): communicate with Secret Service (org.freedesktop.secrets) directly over D-Bus**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1182](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1182)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1182-1789560412000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage 11.2.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1262](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1262)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1262-1789559231000`

- **Peer release: flutter\_secure\_storage: v11.2.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage-v11.2.0](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage-v11.2.0)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage-v11.2.0-1789559229000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage\_darwin 0.4.3**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1272](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1272)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1272-1789558462000`

- **Peer release: flutter\_secure\_storage\_darwin: v0.4.3**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_darwin-v0.4.3](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_darwin-v0.4.3)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_darwin-v0.4.3-1789558460000`

- **Peer pull-request: chore(deps): bump org.jetbrains.kotlin.android from 2.4.10 to 2.4.20 in /flutter\_secure\_storage/example/android in the example-android group**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1274](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1274)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1274-1789552439000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage\_platform\_interface 2.1.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1263](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1263)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1263-1789549345000`

- **Peer release: flutter\_secure\_storage\_platform\_interface: v2.1.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_platform\_interface-v2.1.1](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_platform_interface-v2.1.1)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_platform_interface-v2.1.1-1789549343000`

- **Peer issue: After upgrade from v9 to v11 data is lost, but so is after downgrade from v11 to v10**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1237](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1237)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1237-1789503897000`

- **Peer pull-request: docs: add alternative Linux implementations in README**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1273](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1273)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1273-1789474979000`

- **Peer pull-request: fix(android): deleteall clearing data from other stores that share a sharedPreferencesName/storageNamespace**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1265](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1265)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1265-1789471656000`

- **Peer pull-request: fix(android): don't hang when biometric negative button is tapped**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1268](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1268)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1268-1789468369000`

- **Peer issue: \[Linux\] Warning "libsecret\_error: Failed to unlock the keyring"**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 778](https://github.com/juliansteenbakker/flutter_secure_storage/issues/778)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-778-1789444169000`

- **Peer pull-request: fix(darwin): find keychain items across accessibility levels**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1269](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1269)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1269-1789427323000`

- **Peer issue: \[Android\] AEADBadTagException on biometric read after app restart — StorageCipherImplementationAES23 cipher key invalid across process boundaries (Xiaomi/AOSP)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1165](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1165)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1165-1789421213000`

- **Peer pull-request: fix(android): recover biometric-protected storage on post-auth cipher failure**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1271](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1271)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1271-1789421212000`

- **Peer pull-request: fix(android): don't hang when biometric negative button is tapped**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1267](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1267)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1267-1789420461000`

- **Peer issue: Android: strongBiometricOnly read/write hangs forever when the biometric prompt is cancelled**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1161](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1161)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1161-1789420438000`

- **Peer pull-request: fix(android): scope deleteAll to the key prefix instead of clearing the file**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1266](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1266)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1266-1789420048000`

- **Peer issue: `deleteAll` deletes unrelated data**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1144](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1144)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1144-1789420035000`

- **Peer pull-request: docs: warn that macOS Keychain Sharing requires provisioning**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1270](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1270)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1270-1789419836000`

- **Peer issue: Android Zero-Tap Sign-In Requirement**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1240](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1240)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1240-1789419665000`

- **Peer issue: macOS documentation should warn that enabling Keychain Sharing requires provisioning and free Apple Developer accounts cannot distribute the app to other Macs**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1176](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1176)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1176-1789419355000`

- **Peer issue: \[Android\] Issues with enforceBiometrics**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1125](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1125)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1125-1789413404000`

- **Peer pull-request: feat(android): requireBiometricsPerOperation flag**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1264](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1264)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1264-1789413403000`

- **Peer issue: Migration from encryptedSharedPreferences=false to new dependency versions fail and permanently deletes data (even with backup)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1166](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1166)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1166-1789406983000`

- **Peer issue: Documentation Request: Direct upgrade from v9.x to v10.x using storageNamespace causes BAD\_DECRYPT**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1259](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1259)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1259-1789391171000`

- **Peer pull-request: Stop re-wrapping an inherited set\_password once per MRO class**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 770](https://github.com/jaraco/keyring/pull/770)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-770-1790568823000`

- **Peer issue: Add full-fledged type hints**
  - Subjects: `jaraco/keyring`
  - References: [issue 661](https://github.com/jaraco/keyring/issues/661)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-661-1790566072000`

- **Peer pull-request: Fix empty piped password falling through to getpass**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 767](https://github.com/jaraco/keyring/pull/767)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-767-1790508007000`

- **Peer issue: "Keystore operation failed"**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 727](https://github.com/oblador/react-native-keychain/issues/727)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-727-1790153078000`

- **Peer pull-request: fix(android): skip explicit Kotlin plugin when AGP registers the kotlin extension**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 812](https://github.com/oblador/react-native-keychain/pull/812)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-812-1790098065000`

- **Peer pull-request: Bump actions-rust-lang/setup-rust-toolchain from 1 to 2**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 352](https://github.com/open-source-cooperative/keyring-rs/pull/352)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-352-1789487202000`

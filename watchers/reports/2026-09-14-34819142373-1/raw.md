<!-- keybay-watcher-report: {"schema":1,"report_id":"github-34819142373-1","run_id":"34819142373","attempt":"1","event":"schedule","commit":"0ca946dbfbb8086cc75fcf89e82daa819d5947e6","run_url":"https://github.com/danReynolds/keybay/actions/runs/34819142373","started_at":"2026-09-14T07:44:16.000Z","statuses":{"dependencies":"quiet","platforms":"quiet","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-34819142373-1`](https://github.com/danReynolds/keybay/actions/runs/34819142373) (attempt `1`)
- Started: `2026-09-14T07:44:16.000Z`
- Source commit: `0ca946dbfbb8086cc75fcf89e82daa819d5947e6`
- GitHub event: `schedule`

## Dependencies

Sources: OSV against every committed lockfile, plus new releases of specifically reviewed dependencies.

Status: **quiet**

No findings were returned by this watcher.

## Platforms

Sources: Apple security releases, Android security bulletins, and narrow Linux credential-provider advisories.

Status: **quiet**

No findings were returned by this watcher.

## Peers

Sources: OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.

Status: **findings**

- **Peer issue: Linux: the\_schema.name dangles after setLabel() — items stored with a garbage xdg:schema, orphan detection can never match**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1230](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1230)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1230-1789355900000`

- **Peer issue: After upgrade from v9 to v11 data is lost, but so is after downgrade from v11 to v10**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1237](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1237)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1237-1789334956000`

- **Peer issue: Documentation Request: Direct upgrade from v9.x to v10.x using storageNamespace causes BAD\_DECRYPT**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1259](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1259)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1259-1789334909000`

- **Peer pull-request: fix: biometric multi instance race**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1261](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1261)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1261-1789333628000`

- **Peer pull-request: fix: legacy namespace key recovery biometric**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1260](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1260)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1260-1789329425000`

- **Peer issue: Keystore key generation failed (on Android TV)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1138](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1138)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1138-1789281404000`

- **Peer issue: \[linux\] support XDG Desktop Secret Portal (org.freedesktop.portal.Secret)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1203](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1203)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1203-1789173155000`

- **Peer release: v10.3.3**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release v10.3.3](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/v10.3.3)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-v10.3.3-1789157887000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage 11.1.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1258](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1258)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1258-1789157213000`

- **Peer release: flutter\_secure\_storage: v11.1.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage-v11.1.1](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage-v11.1.1)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage-v11.1.1-1789157211000`

- **Peer pull-request: fix(android): read saved key-cipher marker instead of toString() on a KeyCipher**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1257](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1257)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1257-1789156881000`

- **Peer issue: isBiometricAlgorithm fails because .toString() returns object hash instead of enum name**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1255](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1255)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1255-1789155783000`

- **Peer pull-request: fix(android): read saved key-cipher marker instead of toString() on a KeyCipher**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1256](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1256)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1256-1789155782000`

- **Peer issue: Version 10.2.0 crashes at launch with EXC\_BAD\_ACCESS.**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1145](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1145)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1145-1789136938000`

- **Peer issue: \[Linux\] Warning "libsecret\_error: Failed to unlock the keyring"**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 778](https://github.com/juliansteenbakker/flutter_secure_storage/issues/778)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-778-1789136814000`

- **Peer issue: v11 removed APIs leave no migration path for direct upgrades from v9 or lower. App users who skip app versions, removing these items turns a routine app upda...**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1235](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1235)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1235-1789135362000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage\_linux 4.0.0-beta.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1253](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1253)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1253-1789133121000`

- **Peer release: flutter\_secure\_storage\_linux: v4.0.0-beta.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_linux-v4.0.0-beta.1](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_linux-v4.0.0-beta.1)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_linux-v4.0.0-beta.1-1789133119000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage 11.1.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1254](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1254)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1254-1789130620000`

- **Peer issue: \[linux\] xdg:schema (Libsecret schema name) attribute is being set incorrectly**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1181](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1181)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1181-1789129397000`

- **Peer pull-request: fix(linux)!: stop the xdg:schema attribute from going stale after relabeling**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1249](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1249)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1249-1789129396000`

- **Peer pull-request: chore: promote release(s) to master**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1252](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1252)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1252-1789127565000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage\_linux 3.0.3**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1251](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1251)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1251-1789127075000`

- **Peer release: flutter\_secure\_storage\_linux: v3.0.3**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_linux-v3.0.3](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_linux-v3.0.3)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_linux-v3.0.3-1789127073000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage\_darwin 0.4.2**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1250](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1250)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1250-1789124245000`

- **Peer release: flutter\_secure\_storage\_darwin: v0.4.2**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_darwin-v0.4.2](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_darwin-v0.4.2)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_darwin-v0.4.2-1789124243000`

- **Peer pull-request: fix(linux): skip D-Bus keyring warmup when sandboxed**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1223](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1223)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1223-1789123365000`

- **Peer issue: errSecMissingEntitlement (-34018) on macOS when app is signed with Developer ID (outside App Store) — even with sandbox disabled and usesDataProtectionKeycha...**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1104](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1104)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1104-1789123055000`

- **Peer pull-request: fix(darwin): skip synchronizable keychain queries when the data protection keychain is off**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1241](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1241)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1241-1789123054000`

- **Peer pull-request: refactor(linux): communicate with Secret Service (org.freedesktop.secrets) directly over D-Bus**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1182](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1182)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1182-1789094485000`

- **Peer pull-request: feat(linux): support for XDG Desktop Secret Portal (org.freedesktop.portal.Secret)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1204](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1204)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1204-1789086627000`

- **Peer issue: \[Linux\] Breaks Gnome Keyring with Empty Password**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 951](https://github.com/juliansteenbakker/flutter_secure_storage/issues/951)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-951-1789052635000`

- **Peer pull-request: chore: promote release(s) to master**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1248](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1248)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1248-1789026499000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage 11.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1246](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1246)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1246-1789026023000`

- **Peer release: flutter\_secure\_storage: v11.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage-v11.1.0](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage-v11.1.0)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage-v11.1.0-1789026021000`

- **Peer pull-request: docs: add Changelog header, fix platform\_interface entry order**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1220](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1220)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1220-1789021953000`

- **Peer pull-request: ci: gate master promotion on no other pending release PRs**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1219](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1219)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1219-1789021952000`

- **Peer pull-request: fix(darwin): restore access to items written before 0.3.0's SecAccess…**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1183](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1183)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1183-1789021943000`

- **Peer pull-request: ci: repository template files and release please**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1185](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1185)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1185-1789021942000`

- **Peer pull-request: chore: correct release-please bootstrap tracking**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1193](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1193)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1193-1789021940000`

- **Peer pull-request: fix: require flutter\_secure\_storage\_platform\_interface ^2.1.0 for checkUpgradeStatus**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1247](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1247)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1247-1789021827000`

- **Peer pull-request: chore(develop): release flutter\_secure\_storage\_platform\_interface 2.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1245](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1245)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1245-1788992306000`

- **Peer release: flutter\_secure\_storage\_platform\_interface: v2.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_platform\_interface-v2.1.0](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_platform_interface-v2.1.0)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_platform_interface-v2.1.0-1788992304000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 8.13 to 9.7.1 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1233](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1233)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1233-1788989775000`

- **Peer pull-request: test: add regression test for storageNamespace data loss (#1126)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1231](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1231)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1231-1788989488000`

- **Peer issue: Version `^11.0.0` doesn't respect docs Android SDK constraint**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1224](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1224)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1224-1788983261000`

- **Peer pull-request: fix(android): use flutter.compileSdkVersion instead of pinning `compileSdk`**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1236](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1236)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1236-1788983260000`

- **Peer pull-request: chore(deps): bump actions/setup-java from 5 to 6**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1239](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1239)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1239-1788983078000`

- **Peer pull-request: chore(deps): bump the example-android group in /flutter\_secure\_storage/example/android with 2 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1244](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1244)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1244-1788982625000`

- **Peer pull-request: feat: add checkUpgradeStatus() to check for exisiting data after a missing or failed v10 migration**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1243](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1243)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1243-1788981762000`

- **Peer issue: Add migration path for encryptedSharedPreferences=true (Tink) → 11.x (currently silently wipes stored data, no logcat)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1225](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1225)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1225-1788981760000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.3.1 to 9.4.0 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1238](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1238)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1238-1788980523000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 9.6.1 to 9.7.1 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1234](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1234)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1234-1788980520000`

- **Peer pull-request: chore(deps): bump toshimaru/auto-author-assign from 3.0.3 to 3.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1228](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1228)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1228-1788980516000`

- **Peer pull-request: chore: update default files to match standard, add cooldown period for dependency updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1242](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1242)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1242-1788980456000`

- **Peer issue: Can I upgrade from flutter\_secure\_storage: 9.2.4 to the latest flutter\_secure\_storage: 10.3.1?**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1184](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1184)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1184-1788978845000`

- **Peer issue: NullPointerException in FlutterSecureStorage.initialize() when Activity is paused - Android 13**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1084](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1084)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1084-1788978720000`

- **Peer issue: KeyStore exception on first run**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1064](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1064)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1064-1788978656000`

- **Peer issue: storageNamespace deletes previous data from sharedPreferencesName**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1126](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1126)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1126-1788978529000`

- **Peer issue: Migration from encryptedSharedPreferences=false to new dependency versions fail and permanently deletes data (even with backup)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1166](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1166)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1166-1788978382000`

- **Peer issue: \[Android\] v10 Migrator fails to decrypt v9 data saved with AES\_GCM\_NoPadding**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1079](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1079)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1079-1788978332000`

- **Peer release: flutter\_secure\_storage: v10.3.2**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage-v10.3.2](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage-v10.3.2)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage-v10.3.2-1788961145000`

- **Peer issue: iOS loses access to stored values after update to flutter\_secure\_storage 10.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1158](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1158)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1158-1788855998000`

- **Peer release: flutter\_secure\_storage\_darwin: v0.4.1**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [release flutter\_secure\_storage\_darwin-v0.4.1](https://github.com/juliansteenbakker/flutter_secure_storage/releases/tag/flutter_secure_storage_darwin-v0.4.1)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-release-flutter_secure_storage_darwin-v0.4.1-1788855888000`

- **Peer issue: \[Android\] Issues with enforceBiometrics**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1125](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1125)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1125-1788853909000`

- **Peer issue: \[iOS\] Stored value disappears on some iOS devices**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1229](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1229-1788575907000`

- **Peer issue: Android Zero-Tap Sign-In Requirement**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1240](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1240)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1240-1788344488000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.3.1 to 9.3.2 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1232](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1232)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1232-1788340961000`

- **Peer issue: macOS documentation should warn that enabling Keychain Sharing requires provisioning and free Apple Developer accounts cannot distribute the app to other Macs**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1176](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1176)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1176-1788244594000`

- **Peer pull-request: fix(android): keep one DataStore per process so a second React instance cannot open RN\_KEYCHAIN twice**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 816](https://github.com/oblador/react-native-keychain/pull/816)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-816-1789137030000`

- **Peer issue: Could not invoke RNKeychainManager.hasGenericPasswwordForOptions**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 815](https://github.com/oblador/react-native-keychain/issues/815)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-815-1789119614000`

- **Peer pull-request: fix: fall back to SecItemUpdate when SecItemAdd reports a duplicate item on iOS**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 814](https://github.com/oblador/react-native-keychain/pull/814)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-814-1788882930000`

- **Peer issue: iOS: set\* intermittently rejects with errSecDuplicateItem because the SecItemDelete result is ignored**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 813](https://github.com/oblador/react-native-keychain/issues/813)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-813-1788882838000`

- **Peer pull-request: fix(android): skip explicit Kotlin plugin when AGP provides built-in Kotlin**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 812](https://github.com/oblador/react-native-keychain/pull/812)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-812-1788382978000`

- **Peer issue: On macOS, shell quoting is used for a parser that is not a shell, so a backslash silently changes the item's name**
  - Subjects: `zalando/go-keyring`
  - References: [issue 154](https://github.com/zalando/go-keyring/issues/154)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-154-1788456639000`

- **Peer issue: On macOS, a failing Set can return nil at the largest command length Set allows**
  - Subjects: `zalando/go-keyring`
  - References: [issue 153](https://github.com/zalando/go-keyring/issues/153)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-153-1788456635000`

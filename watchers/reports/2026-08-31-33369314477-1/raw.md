<!-- keybay-watcher-report: {"schema":1,"report_id":"github-33369314477-1","run_id":"33369314477","attempt":"1","event":"schedule","commit":"6fbf7a470c105f0e0a70f9c5b13dff2e12929c15","run_url":"https://github.com/danReynolds/keybay/actions/runs/33369314477","started_at":"2026-08-31T07:40:08.000Z","statuses":{"dependencies":"quiet","platforms":"quiet","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-33369314477-1`](https://github.com/danReynolds/keybay/actions/runs/33369314477) (attempt `1`)
- Started: `2026-08-31T07:40:08.000Z`
- Source commit: `6fbf7a470c105f0e0a70f9c5b13dff2e12929c15`
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

- **Peer issue: macOS documentation should warn that enabling Keychain Sharing requires provisioning and free Apple Developer accounts cannot distribute the app to other Macs**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1176](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1176)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1176-1788160984000`

- **Peer pull-request: fix(android): use flutter.compileSdkVersion instead of pinning `compileSdk`**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1236](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1236)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1236-1788091509000`

- **Peer issue: Version `^11.0.0` doesn't respect docs Android SDK constraint**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1224](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1224)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1224-1788087421000`

- **Peer issue: errSecMissingEntitlement (-34018) on macOS when app is signed with Developer ID (outside App Store) — even with sandbox disabled and usesDataProtectionKeycha...**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1104](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1104)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1104-1788073737000`

- **Peer issue: v11 removed APIs leave no migration path for direct upgrades from v9 or lower. App users who skip app versions, removing these items turns a routine app upda...**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1235](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1235)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1235-1787963250000`

- **Peer pull-request: refactor(linux): communicate with Secret Service (org.freedesktop.secrets) directly over D-Bus**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1182](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1182)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1182-1787838014000`

- **Peer issue: Bug: \[Android\] v10 sharedPreferencesName/preferencesKeyPrefix silently ignored on subsequent FlutterSecureStorage instances**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1109](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1109)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1109-1787831459000`

- **Peer issue: iOS: `kSecAttrAccessible` used as strict search filter in 0.3.x breaks reads for items with different accessibility level**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1164](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1164)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1164-1787763843000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.3.1 to 9.3.2 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1232](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1232)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1232-1787736791000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 9.6.1 to 9.7.1 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1234](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1234)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1234-1787736756000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 8.13 to 9.7.1 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1233](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1233)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1233-1787736693000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 9.6.1 to 9.7.0 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1227](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1227)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1227-1787736203000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 8.13 to 9.7.0 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1226](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1226)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1226-1787736183000`

- **Peer pull-request: test: add regression test for storageNamespace data loss (#1126)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1231](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1231)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1231-1787685669000`

- **Peer issue: storageNamespace deletes previous data from sharedPreferencesName**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1126](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1126)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1126-1787683222000`

- **Peer issue: KeyStore exception on first run**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1064](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1064)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1064-1787366117000`

- **Peer issue: Android: strongBiometricOnly read/write hangs forever when the biometric prompt is cancelled**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1161](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1161)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1161-1787366114000`

- **Peer issue: \[iOS\] Stored value disappears on some iOS devices**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1229](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1229-1787294816000`

- **Peer issue: Linux: the\_schema.name dangles after setLabel() — items stored with a garbage xdg:schema, orphan detection can never match**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1230](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1230)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1230-1787220698000`

- **Peer issue: Add migration path for encryptedSharedPreferences=true (Tink) → 11.x (currently silently wipes stored data, no logcat)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1225](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1225)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1225-1787167690000`

- **Peer pull-request: chore(deps): bump toshimaru/auto-author-assign from 3.0.3 to 3.1.0**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1228](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1228)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1228-1787131927000`

- **Peer issue: MissingPluginException(No implementation found for method readAll on channel plugins.it\_nomads.co...**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1000](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1000)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1000-1787107163000`

- **Peer issue: \[Android\] AEADBadTagException on biometric read after app restart — StorageCipherImplementationAES23 cipher key invalid across process boundaries (Xiaomi/AOSP)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1165](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1165)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1165-1787020577000`

- **Peer pull-request: Fix set\_password() rejecting the service= keyword argument**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 769](https://github.com/jaraco/keyring/pull/769)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-769-1787556904000`

- **Peer pull-request: Add ssh-agent-keyring to third-party backends**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 751](https://github.com/jaraco/keyring/pull/751)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-751-1787439014000`

- **Peer pull-request: fix(ios): respect cloudSync false**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 804](https://github.com/oblador/react-native-keychain/pull/804)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-804-1787970933000`

- **Peer pull-request: fix(android): settle biometric operations and release callback resources**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 811](https://github.com/oblador/react-native-keychain/pull/811)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-811-1787891913000`

- **Peer pull-request: fix: honor architecture selection and repair documentation tooling**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 810](https://github.com/oblador/react-native-keychain/pull/810)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-810-1787891911000`

- **Peer pull-request: fix(example): serialize credential actions and keep availability state accurate**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 809](https://github.com/oblador/react-native-keychain/pull/809)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-809-1787891909000`

- **Peer pull-request: fix(android): propagate deletion failures and reduce cipher allocation**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 808](https://github.com/oblador/react-native-keychain/pull/808)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-808-1787891908000`

- **Peer pull-request: fix(ios): preserve query scope and validate credential replacement**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 807](https://github.com/oblador/react-native-keychain/pull/807)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-807-1787891906000`

- **Peer pull-request: fix(android): serialize storage operations and list persisted services**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 806](https://github.com/oblador/react-native-keychain/pull/806)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-806-1787891903000`

- **Peer pull-request: fix: preserve prompt defaults and align public APIs with native results**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 805](https://github.com/oblador/react-native-keychain/pull/805)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-805-1787891902000`

- **Peer issue: iOS: cloudSync: false is treated as true — items written to iCloud keychain when the caller explicitly opted out**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 800](https://github.com/oblador/react-native-keychain/issues/800)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-800-1787787405000`

- **Peer issue: enable usage with configuration cache**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 768](https://github.com/oblador/react-native-keychain/issues/768)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-768-1787461725000`

- **Peer pull-request: fix(android): support Gradle configuration cache**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 803](https://github.com/oblador/react-native-keychain/pull/803)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-803-1787461708000`

- **Peer issue: "Decryption failed: Authentication tag verification failed"**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 802](https://github.com/oblador/react-native-keychain/issues/802)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-802-1787216967000`

- **Peer release: v4.2.0: update the CLI dependencies**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [release v4.2.0](https://github.com/open-source-cooperative/keyring-rs/releases/tag/v4.2.0)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-release-v4.2.0-1788047251000`

- **Peer pull-request: Restore the android-native-keyring-store dependency for the cli.**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 351](https://github.com/open-source-cooperative/keyring-rs/pull/351)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-351-1788047083000`

- **Peer pull-request: Remove mimalloc feature from db-keystore.**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 350](https://github.com/open-source-cooperative/keyring-rs/pull/350)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-350-1788045802000`

- **Peer pull-request: Bump dbus-secret-service-keyring-store from 1.0.0 to 1.0.1**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 348](https://github.com/open-source-cooperative/keyring-rs/pull/348)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-348-1787680278000`

- **Peer pull-request: Bump zbus-secret-service-keyring-store from 1.0.0 to 1.0.1**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 349](https://github.com/open-source-cooperative/keyring-rs/pull/349)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-349-1787680241000`

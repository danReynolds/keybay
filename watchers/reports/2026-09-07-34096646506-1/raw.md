<!-- keybay-watcher-report: {"schema":1,"report_id":"github-34096646506-1","run_id":"34096646506","attempt":"1","event":"schedule","commit":"6fbf7a470c105f0e0a70f9c5b13dff2e12929c15","run_url":"https://github.com/danReynolds/keybay/actions/runs/34096646506","started_at":"2026-09-07T07:41:39.000Z","statuses":{"dependencies":"quiet","platforms":"quiet","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-34096646506-1`](https://github.com/danReynolds/keybay/actions/runs/34096646506) (attempt `1`)
- Started: `2026-09-07T07:41:39.000Z`
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

- **Peer pull-request: Skip synchronizable keychain queries when the data protection keychain is off**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1241](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1241)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1241-1788762101000`

- **Peer issue: \[iOS\] Stored value disappears on some iOS devices**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1229](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1229-1788575907000`

- **Peer issue: Android Zero-Tap Sign-In Requirement**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1240](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1240)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1240-1788344488000`

- **Peer pull-request: chore(deps): bump actions/setup-java from 5 to 6**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1239](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1239)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1239-1788341493000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.3.1 to 9.4.0 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1238](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1238)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1238-1788341470000`

- **Peer pull-request: chore(deps): bump com.android.application from 9.3.1 to 9.3.2 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1232](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1232)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1232-1788340961000`

- **Peer issue: After upgrade from v9 to v11 data is lost, but so is after downgrade from v11 to v10**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1237](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1237)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1237-1788298987000`

- **Peer issue: macOS documentation should warn that enabling Keychain Sharing requires provisioning and free Apple Developer accounts cannot distribute the app to other Macs**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1176](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1176)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1176-1788244594000`

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

- **Peer pull-request: fix(android): skip explicit Kotlin plugin when AGP provides built-in Kotlin**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 812](https://github.com/oblador/react-native-keychain/pull/812)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-812-1788382978000`

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

- **Peer issue: On macOS, shell quoting is used for a parser that is not a shell, so a backslash silently changes the item's name**
  - Subjects: `zalando/go-keyring`
  - References: [issue 154](https://github.com/zalando/go-keyring/issues/154)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-154-1788456639000`

- **Peer issue: On macOS, a failing Set can return nil at the largest command length Set allows**
  - Subjects: `zalando/go-keyring`
  - References: [issue 153](https://github.com/zalando/go-keyring/issues/153)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-153-1788456635000`

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

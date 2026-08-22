<!-- keybay-watcher-report: {"schema":1,"report_id":"github-32593631745-1","run_id":"32593631745","attempt":"1","event":"workflow_dispatch","commit":"0fd57c44752084e840e903fa494ab10b554c3e0d","run_url":"https://github.com/danReynolds/keybay/actions/runs/32593631745","started_at":"2026-08-22T19:25:56.000Z","statuses":{"dependencies":"quiet","platforms":"quiet","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-32593631745-1`](https://github.com/danReynolds/keybay/actions/runs/32593631745) (attempt `1`)
- Started: `2026-08-22T19:25:56.000Z`
- Source commit: `0fd57c44752084e840e903fa494ab10b554c3e0d`
- GitHub event: `workflow_dispatch`

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

- **Peer issue: KeyStore exception on first run**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1064](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1064)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1064-1787366117000`

- **Peer issue: Android: strongBiometricOnly read/write hangs forever when the biometric prompt is cancelled**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1161](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1161)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1161-1787366114000`

- **Peer issue: iOS: `kSecAttrAccessible` used as strict search filter in 0.3.x breaks reads for items with different accessibility level**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1164](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1164)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1164-1787321488000`

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

- **Peer issue: fix(web): defensive readAll() to avoid Storage.forEach crash (edge-case corrupted localStorage)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1063](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1063)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1063-1786848160000`

- **Peer issue: Version `^11.0.0` doesn't respect docs Android SDK constraint**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1224](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1224)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1224-1786798968000`

- **Peer pull-request: fix(android): catch Throwable on worker thread so keystore Errors don't crash the app**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1209](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1209)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1209-1786730186000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 9.6.1 to 9.7.0 in /flutter\_secure\_storage/example/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1227](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1227)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1227-1786527160000`

- **Peer pull-request: chore(deps): bump gradle-wrapper from 8.13 to 9.7.0 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1226](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1226)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1226-1786527070000`

- **Peer issue: java.lang.NullPointerException: Attempt to invoke virtual method 'void O9.l.A(O9.p, O9.u)' on a null object reference**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1094](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1094)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1094-1786332399000`

- **Peer pull-request: libsecret: Add type annotation and fix get\_credential()**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 768](https://github.com/jaraco/keyring/pull/768)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-768-1786880508000`

- **Peer pull-request: Fix empty piped password falling through to getpass**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 767](https://github.com/jaraco/keyring/pull/767)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-767-1786821702000`

- **Peer pull-request: fix: ChainerBackend.delete\_password removes stale entry from lower-priority backends**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 766](https://github.com/jaraco/keyring/pull/766)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-766-1786399078000`

- **Peer pull-request: Add ssh-agent-keyring to third-party backends**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 751](https://github.com/jaraco/keyring/pull/751)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-751-1786266934000`

- **Peer issue: "Decryption failed: Authentication tag verification failed"**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 802](https://github.com/oblador/react-native-keychain/issues/802)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-802-1787216967000`

- **Peer issue: com.oblador.keychain.exceptions.CryptoFailedException: Wrapped error: null**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 730](https://github.com/oblador/react-native-keychain/issues/730)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-730-1786616135000`

- **Peer issue: \[Android\] DataStore created per KeychainModule instance — IllegalStateException on a second React instance (plus a scope-lifetime issue in #793)**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 801](https://github.com/oblador/react-native-keychain/issues/801)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-801-1786611350000`

- **Peer issue: iOS: cloudSync: false is treated as true — items written to iCloud keychain when the caller explicitly opted out**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 800](https://github.com/oblador/react-native-keychain/issues/800)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-800-1786581789000`

- **Peer issue: Secret Service backend sends text/plain content type for set\_secret, rejected by ksecretd**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 347](https://github.com/open-source-cooperative/keyring-rs/issues/347)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-347-1786825076000`

- **Peer pull-request: Bump base64 from 0.23.0 to 0.23.1**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 346](https://github.com/open-source-cooperative/keyring-rs/pull/346)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-346-1786423125000`

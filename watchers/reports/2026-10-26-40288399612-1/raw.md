<!-- keybay-watcher-report: {"schema":1,"report_id":"github-40288399612-1","run_id":"40288399612","attempt":"1","event":"schedule","commit":"283ef5d9fb0f0d523c31083ea945d5ba548743df","run_url":"https://github.com/danReynolds/keybay/actions/runs/40288399612","started_at":"2026-10-26T07:52:49.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-40288399612-1`](https://github.com/danReynolds/keybay/actions/runs/40288399612) (attempt `1`)
- Started: `2026-10-26T07:52:49.000Z`
- Source commit: `283ef5d9fb0f0d523c31083ea945d5ba548743df`
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

- **Peer pull-request: feat(android): add opt-in legacy secure storage migration**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1296](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1296)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1296-1792728548000`

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 3 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1295](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1295)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1295-1792575237000`

- **Peer pull-request: chore(deps): bump futureware-tech/simulator-action from 5 to 6 in the github-actions group**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1292](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1292)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1292-1792574636000`

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

- **Peer issue: \[Web\] Concurrent writes on a fresh storage overwrite the encryption key, leaving values undecryptable (OperationError)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1289](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1289)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1289-1792312011000`

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

- **Peer pull-request: Add optional keyring\_type parameter to get\_keyring() and type SecretService.get\_preferred\_collection**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 779](https://github.com/jaraco/keyring/pull/779)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-779-1792832241000`

- **Peer pull-request: Ignore B018 and drop the redundant suppressions.**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 778](https://github.com/jaraco/keyring/pull/778)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-778-1792571444000`

- **Peer pull-request: Expand a leading ~ in the CLI --keyring-path value**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 775](https://github.com/jaraco/keyring/pull/775)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-775-1792559216000`

- **Peer issue: create an asyncio interface**
  - Subjects: `jaraco/keyring`
  - References: [issue 397](https://github.com/jaraco/keyring/issues/397)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-397-1792489940000`

- **Peer pull-request: Raise from fail.Keyring.get\_credential when the username is omitted**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 771](https://github.com/jaraco/keyring/pull/771)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-771-1792258447000`

- **Peer issue: pygobject-stubs now requires PyGObject, which can't be installed in CI**
  - Subjects: `jaraco/keyring`
  - References: [issue 777](https://github.com/jaraco/keyring/issues/777)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-777-1792246707000`

- **Peer pull-request: fix: update iOS keychain items in place instead of deleting first**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 821](https://github.com/oblador/react-native-keychain/pull/821)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-821-1792799797000`

- **Peer pull-request: fix: fall back to SecItemUpdate when SecItemAdd reports a duplicate item on iOS**
  - Subjects: `oblador/react-native-keychain`
  - References: [pull-request 814](https://github.com/oblador/react-native-keychain/pull/814)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-pull-request-814-1792794407000`

- **Peer issue: Android: corrupt `RN\_KEYCHAIN.preferences\_pb` causes permanent `CorruptionException` on every get/set/reset (no `corruptionHandler`)**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 820](https://github.com/oblador/react-native-keychain/issues/820)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-820-1792139231000`

- **Peer pull-request: build(deps): bump github.com/godbus/dbus/v5 from 5.2.2 to 5.2.3 in the all-go-mod-patch-and-minor group**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 160](https://github.com/zalando/go-keyring/pull/160)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-160-1792716202000`

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

- **Peer pull-request: Bump the github-actions group with 2 updates**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 374](https://github.com/open-source-cooperative/keyring-rs/pull/374)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-374-1792707775000`

- **Peer pull-request: Bump keyring-core from 1.0.0 to 1.0.1 in the cargo group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 373](https://github.com/open-source-cooperative/keyring-rs/pull/373)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-373-1792707770000`

- **Peer issue: Zeroize passwords**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 372](https://github.com/open-source-cooperative/keyring-rs/issues/372)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-372-1792422638000`

- **Peer issue: Move all keystore implementations to features**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 322](https://github.com/open-source-cooperative/keyring-rs/issues/322)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-322-1792418673000`

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

- **Peer issue: Windows test instability - hard to reproduce**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 163](https://github.com/open-source-cooperative/keyring-rs/issues/163)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-163-1792021631000`

- **Peer pull-request: Feature gate the db-sqlite keystore**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 362](https://github.com/open-source-cooperative/keyring-rs/pull/362)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-362-1791960913000`

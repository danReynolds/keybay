<!-- keybay-watcher-report: {"schema":1,"report_id":"github-45131457913-1","run_id":"45131457913","attempt":"1","event":"schedule","commit":"ada85cd4e44e41e89d391c8fc1f9e874f4846588","run_url":"https://github.com/danReynolds/keybay/actions/runs/45131457913","started_at":"2026-11-23T07:30:34.000Z","statuses":{"dependencies":"findings","platforms":"findings","peers":"findings"}} -->

# Raw security watcher report

This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”

- Report: [`github-45131457913-1`](https://github.com/danReynolds/keybay/actions/runs/45131457913) (attempt `1`)
- Started: `2026-11-23T07:30:34.000Z`
- Source commit: `ada85cd4e44e41e89d391c8fc1f9e874f4846588`
- GitHub event: `schedule`

## Dependencies

Sources: OSV against every committed lockfile, plus new releases of specifically reviewed dependencies.

Status: **findings**

- **Resolved dependency advisory: GO-2026-5932**
  - Subjects: `Committed resolved dependency graph`
  - References: [GO-2026-5932](https://osv.dev/vulnerability/GO-2026-5932)
  - Marker: `keybay-dependency-osv-GO-2026-5932`

- **Reviewed dependency release: dbus 0.8.1**
  - Subjects: `Pub/dbus: reviewed 0.7.15; published 0.8.1`
  - References: [Pub/dbus](https://pub.dev/packages/dbus)
  - Marker: `keybay-dependency-release-pub-dbus-0.8.1`

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

- **Apple platform advisory triage: 2026-11-09**
  - Subjects: `iOS 18.7.12 and iPadOS 18.7.12`, `iOS 26.7.3 and iPadOS 26.7.3`, `iOS 27.2.1 and iPadOS 27.2.1`, `macOS Golden Gate 27.2.1`, `macOS Sequoia 15.8.3`, `macOS Tahoe 26.7.3`
  - References: [iOS 18.7.12 and iPadOS 18.7.12](https://support.apple.com/en-us/149717), [iOS 26.7.3 and iPadOS 26.7.3](https://support.apple.com/en-us/149716), [iOS 27.2.1 and iPadOS 27.2.1](https://support.apple.com/en-us/149715), [macOS Golden Gate 27.2.1](https://support.apple.com/en-us/149718), [macOS Sequoia 15.8.3](https://support.apple.com/en-us/149720), [macOS Tahoe 26.7.3](https://support.apple.com/en-us/149719)
  - Marker: `keybay-platform-apple-2026-11-09-e00651e9d810`

- **Linux credential-platform advisory triage: CVE-2026-120749**
  - Subjects: `Debian/dbus`, `Ubuntu/dbus`
  - References: [DEBIAN-CVE-2026-120749](https://osv.dev/vulnerability/DEBIAN-CVE-2026-120749), [UBUNTU-CVE-2026-120749](https://osv.dev/vulnerability/UBUNTU-CVE-2026-120749)
  - Marker: `keybay-platform-linux-CVE-2026-120749`

- **Linux credential-platform advisory triage: CVE-2026-128885**
  - Subjects: `Debian/dbus`, `Ubuntu/dbus`
  - References: [DEBIAN-CVE-2026-128885](https://osv.dev/vulnerability/DEBIAN-CVE-2026-128885), [UBUNTU-CVE-2026-128885](https://osv.dev/vulnerability/UBUNTU-CVE-2026-128885)
  - Marker: `keybay-platform-linux-CVE-2026-128885`

- **Linux credential-platform advisory triage: CVE-2026-128886**
  - Subjects: `Debian/dbus`, `Ubuntu/dbus`
  - References: [DEBIAN-CVE-2026-128886](https://osv.dev/vulnerability/DEBIAN-CVE-2026-128886), [UBUNTU-CVE-2026-128886](https://osv.dev/vulnerability/UBUNTU-CVE-2026-128886)
  - Marker: `keybay-platform-linux-CVE-2026-128886`

- **Linux credential-platform advisory triage: CVE-2026-128987**
  - Subjects: `Debian/dbus`, `Ubuntu/dbus`
  - References: [DEBIAN-CVE-2026-128987](https://osv.dev/vulnerability/DEBIAN-CVE-2026-128987), [UBUNTU-CVE-2026-128987](https://osv.dev/vulnerability/UBUNTU-CVE-2026-128987)
  - Marker: `keybay-platform-linux-CVE-2026-128987`

## Peers

Sources: OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.

Status: **findings**

- **Peer pull-request: fix(flutter\_secure\_storage): support OpenHarmony platform options**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1313](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1313)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1313-1795364283000`

- **Peer issue: Log error on app open: Rejecting re-init on previously-failed class com.it\_nomads.fluttersecurestorage.FlutterSecureStorage**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1276](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1276)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1276-1795250288000`

- **Peer issue: Docs: add a "Related tools" section to the README (starting with xRay)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1312](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1312)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1312-1795166742000`

- **Peer pull-request: chore(deps): bump the example-android group across 1 directory with 3 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1295](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1295)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1295-1794993875000`

- **Peer pull-request: chore(deps): bump the github-actions group across 1 directory with 2 updates**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1310](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1310)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1310-1794993812000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.8.2 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1302](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1302)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1302-1794993770000`

- **Peer pull-request: deps: bump gradle-wrapper from 9.7.1 to 9.9.1 in /flutter\_secure\_storage/android**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1311](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1311)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1311-1794993762000`

- **Peer issue: \[Feature Request\] Add Swift Package Manager support for flutter\_secure\_storage**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1277](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1277)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1277-1794992162000`

- **Peer pull-request: fix(android): preserve RSA keys on incomplete keystore reads**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1306](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1306)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1306-1794902617000`

- **Peer pull-request: chore(deps): bump futureware-tech/simulator-action from 5 to 6 in the github-actions group across 1 directory**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1292](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1292)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1292-1794389010000`

- **Peer pull-request: fix(android): respect requireBiometricsPerOperation after cipher migration (#1303)**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [pull-request 1309](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1309)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-pull-request-1309-1794304890000`

- **Peer issue: \[linux\] 4.0.0-beta.1: deleteAll() / deleting the last key resurrects legacy-schema secrets on the next read**
  - Subjects: `juliansteenbakker/flutter_secure_storage`
  - References: [issue 1308](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1308)
  - Marker: `keybay-peer-github-juliansteenbakker/flutter_secure_storage-issue-1308-1794272057000`

- **Peer pull-request: Defer imports used for backend discovery**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 785](https://github.com/jaraco/keyring/pull/785)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-785-1795113972000`

- **Peer issue: Mac does not implement `get\_credential()`**
  - Subjects: `jaraco/keyring`
  - References: [issue 784](https://github.com/jaraco/keyring/issues/784)
  - Marker: `keybay-peer-github-jaraco/keyring-issue-784-1794716213000`

- **Peer pull-request: Document isolated in-memory keyrings for application tests**
  - Subjects: `jaraco/keyring`
  - References: [pull-request 783](https://github.com/jaraco/keyring/pull/783)
  - Marker: `keybay-peer-github-jaraco/keyring-pull-request-783-1794684223000`

- **Peer issue: Android ≤10: biometric availability fails with AndroidX Core 1.18.0+**
  - Subjects: `oblador/react-native-keychain`
  - References: [issue 836](https://github.com/oblador/react-native-keychain/issues/836)
  - Marker: `keybay-peer-github-oblador/react-native-keychain-issue-836-1794225626000`

- **Peer pull-request: build(deps): bump github.com/godbus/dbus/v5 from 5.2.2 to 5.2.4 in the all-go-mod-patch-and-minor group across 1 directory**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 160](https://github.com/zalando/go-keyring/pull/160)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-160-1795135426000`

- **Peer pull-request: ci: pin vmactions/freebsd-vm to a commit SHA**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 163](https://github.com/zalando/go-keyring/pull/163)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-163-1794972342000`

- **Peer issue: On macOS, a failing Set can return nil at the largest command length Set allows**
  - Subjects: `zalando/go-keyring`
  - References: [issue 153](https://github.com/zalando/go-keyring/issues/153)
  - Marker: `keybay-peer-github-zalando/go-keyring-issue-153-1794943879000`

- **Peer pull-request: fix(darwin): reject Set commands that security -i would split**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 156](https://github.com/zalando/go-keyring/pull/156)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-156-1794943878000`

- **Peer pull-request: feat: add fallback for get login.keyring path**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 109](https://github.com/zalando/go-keyring/pull/109)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-109-1794931881000`

- **Peer pull-request: allow setting of secret description**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 134](https://github.com/zalando/go-keyring/pull/134)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-134-1794931819000`

- **Peer pull-request: Add support for WSL environments to use Windows Credential Manager**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 150](https://github.com/zalando/go-keyring/pull/150)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-150-1794931786000`

- **Peer pull-request: Add New(Options) with an opt-in Security framework backend on macOS**
  - Subjects: `zalando/go-keyring`
  - References: [pull-request 158](https://github.com/zalando/go-keyring/pull/158)
  - Marker: `keybay-peer-github-zalando/go-keyring-pull-request-158-1794931377000`

- **Peer pull-request: Bump taiki-e/install-action from 2.90.1 to 2.90.3 in the github-actions group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 382](https://github.com/open-source-cooperative/keyring-rs/pull/382)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-382-1795111632000`

- **Peer pull-request: Bump keyring-core from 1.0.0 to 1.0.1 in the cargo group**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 379](https://github.com/open-source-cooperative/keyring-rs/pull/379)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-379-1795111095000`

- **Peer pull-request: Bump the github-actions group with 3 updates**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [pull-request 380](https://github.com/open-source-cooperative/keyring-rs/pull/380)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-pull-request-380-1795110754000`

- **Peer issue: Support for secrets portal**
  - Subjects: `open-source-cooperative/keyring-rs`
  - References: [issue 376](https://github.com/open-source-cooperative/keyring-rs/issues/376)
  - Marker: `keybay-peer-github-open-source-cooperative/keyring-rs-issue-376-1795109601000`

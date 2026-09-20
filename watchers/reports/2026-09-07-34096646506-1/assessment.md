<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-34096646506-1","status":"assessed","summary":"Dependencies and platforms were quiet; 38 peer signals were reviewed against current V2 with no applicable vulnerability or additional work identified.","actions":[]} -->

# Assessment

Status: **Assessed**

Assessed 2026-09-20 against Keybay `13444c7a9feccc02a0da54a5056916d4b27bd2fe` and its security invariants. All 38 peer signals were compared with the current V2 design; prior assessments were checked for duplicate work. No applicable vulnerability or additional follow-up was identified. This is monitoring and applicability evidence, not a release certificate or proof of absence of vulnerabilities.

## Provenance

The successful [scheduled Actions run](https://github.com/danReynolds/keybay/actions/runs/34096646506) used `.github/workflows/security-watchers.yml`, attempt 1, source `6fbf7a470c105f0e0a70f9c5b13dff2e12929c15`. The Actions-authored staging branch changed only this report pair and SUMMARY. The raw report blob is `32ee71a368e26881909cc14e82b25b0a81301c09` and is retained unchanged.

## Dependencies and platforms

No finding in either configured discovery window. The report records quiet OSV/resolved-lockfile and reviewed dependency-release scans, plus quiet Apple, Android, and Linux platform sources. These older windows do not clear the release candidate; a fresh all-source run is required on final main.

## Peer applicability

### Android migration and identity

Not applicable to the current storage mechanism. Keybay V2 has one explicit application binding and Keystore root, no SharedPreferences/Tink cipher migration, and no reset-on-error path. V1 data is deliberately not read, migrated, or deleted. Missing roots and unsupported formats fail closed. Peer upgrade-status APIs do not establish Keybay upgrade qualification.

Reviewed sources: [juliansteenbakker/flutter_secure_storage/issues/1235](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1235), [juliansteenbakker/flutter_secure_storage/issues/1109](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1109), [juliansteenbakker/flutter_secure_storage/pull/1231](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1231), [juliansteenbakker/flutter_secure_storage/issues/1126](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1126), [juliansteenbakker/flutter_secure_storage/issues/1237](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1237).

### Android authentication and lifecycle

No applicable mechanism identified. Keybay uses JNI/FFI without the Flutter/React Native plugin, DataStore, Activity callback, or BiometricPrompt lifecycle. Its Keystore key sets user-authentication-required false; per-read biometrics are not claimed. Root errors propagate, mutations are serialized/atomic, and reset reports partial provider failure. Unspecific authentication/bridge reports do not establish a shared defect.

Reviewed sources: [oblador/react-native-keychain/pull/808](https://github.com/oblador/react-native-keychain/pull/808), [oblador/react-native-keychain/pull/807](https://github.com/oblador/react-native-keychain/pull/807), [oblador/react-native-keychain/pull/806](https://github.com/oblador/react-native-keychain/pull/806).

### Apple query, replacement and signing policy

Reviewed against current V2, not the older assessment descriptions. Keybay uses native Security/CoreFoundation FFI, explicit file-Keychain versus exact entitled Data Protection profiles, native false for synchronization, and accessibility only on creation. Keychain stores a bounded root rather than every record. Root creation is insert-only/adopt-the-winner, not delete-then-add record replacement. Reset validates/prepares exact cleanup and reports errors. Entitlements and Developer ID distribution still require their own artifact evidence; no broader isolation or device claim is inferred.

Reviewed sources: [juliansteenbakker/flutter_secure_storage/issues/1176](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1176), [juliansteenbakker/flutter_secure_storage/issues/1104](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1104), [juliansteenbakker/flutter_secure_storage/issues/1164](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1164), [juliansteenbakker/flutter_secure_storage/issues/1229](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1229), [oblador/react-native-keychain/pull/804](https://github.com/oblador/react-native-keychain/pull/804), [oblador/react-native-keychain/pull/811](https://github.com/oblador/react-native-keychain/pull/811), [oblador/react-native-keychain/issues/800](https://github.com/oblador/react-native-keychain/issues/800), [juliansteenbakker/flutter_secure_storage/pull/1241](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1241).

### Linux provider and schema

Keybay V2 uses typed Dart D-Bus with fixed root attributes, not a C++ libsecret schema-name pointer or a JSON/text command protocol. Flatpak chooses Secret Portal explicitly and never falls back to Secret Service; interaction-forbidden operations fail before provider UI. Existing provider-specific qualification limits, including unqualified KWallet configurations, remain unchanged.

Reviewed sources: [juliansteenbakker/flutter_secure_storage/pull/1182](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1182).

### Native protocol and command bounds

The Go findings concern shell quoting supplied to Apple security -i and its line-size/result protocol. Keybay uses Security FFI and passes child argv directly to execve, so those command parsers are absent. The independent CLI prompt review and its remediation remain separate work, not a finding established by these peer reports.

Reviewed sources: [zalando/go-keyring/issues/154](https://github.com/zalando/go-keyring/issues/154), [zalando/go-keyring/issues/153](https://github.com/zalando/go-keyring/issues/153).

### Account transfer

The peer request concerns Android account restore credentials. That consumer sign-in facility does not change Keybay device-bound key or nonmigration policy. No policy deadline is inferred from the issue. The official Restore Credentials documentation was checked; this report does not qualify cross-device secret transfer.

Reviewed sources: [juliansteenbakker/flutter_secure_storage/issues/1240](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1240).

### Peer API, build and release maintenance

These sources concern peer-specific Flutter/React Native/Python/Rust APIs, dependency versions, examples, build configuration, or release automation. None of these peer packages are Keybay dependencies. Release entries were cross-checked with their underlying fixes above where relevant; no applicable additional Keybay change was identified.

Reviewed sources: [juliansteenbakker/flutter_secure_storage/pull/1236](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1236), [juliansteenbakker/flutter_secure_storage/issues/1224](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1224), [juliansteenbakker/flutter_secure_storage/pull/1232](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1232), [juliansteenbakker/flutter_secure_storage/pull/1234](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1234), [juliansteenbakker/flutter_secure_storage/pull/1233](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1233), [juliansteenbakker/flutter_secure_storage/pull/1227](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1227), [juliansteenbakker/flutter_secure_storage/pull/1226](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1226), [oblador/react-native-keychain/pull/810](https://github.com/oblador/react-native-keychain/pull/810), [oblador/react-native-keychain/pull/809](https://github.com/oblador/react-native-keychain/pull/809), [oblador/react-native-keychain/pull/805](https://github.com/oblador/react-native-keychain/pull/805), [open-source-cooperative/keyring-rs/releases/tag/v4.2.0](https://github.com/open-source-cooperative/keyring-rs/releases/tag/v4.2.0), [open-source-cooperative/keyring-rs/pull/351](https://github.com/open-source-cooperative/keyring-rs/pull/351), [open-source-cooperative/keyring-rs/pull/350](https://github.com/open-source-cooperative/keyring-rs/pull/350), [open-source-cooperative/keyring-rs/pull/348](https://github.com/open-source-cooperative/keyring-rs/pull/348), [open-source-cooperative/keyring-rs/pull/349](https://github.com/open-source-cooperative/keyring-rs/pull/349), [juliansteenbakker/flutter_secure_storage/pull/1239](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1239), [juliansteenbakker/flutter_secure_storage/pull/1238](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1238), [oblador/react-native-keychain/pull/812](https://github.com/oblador/react-native-keychain/pull/812).

## Evidence and actions

Compared `doc/design.md` (KB-INV-003, 006, 007, 008), `doc/qualification-status.md`, `doc/cli-qualification-status.md`, current V2 Apple/Android/Linux provider implementations, POSIX container/transaction code, and their existing regression coverage. The 2026-08-24 assessment describes pre-V2 per-record Keychain/secret-tool behavior and was not reused as current architectural evidence.

No public issue or private advisory was warranted. No newly affected provider-dependent claim was identified, so this triage does not trigger new physical-device qualification. Existing release, installed-artifact, Wayland, and hosted-Fleury gates remain open separately.

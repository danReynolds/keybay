# example_flutter — Keybay V2 integration harness

This is a host and integration harness, not a product demo. It exercises the
V2 SDK from real Flutter application bundles against each platform's genuine
file and key-protection APIs.

## Retained integration tests

- `keybay_v2_ios_test.dart`: signed application identity, exact Data Protection
  Keychain group, framed string/byte persistence, passphrase changes, private
  files, reset, and isolate contention on iOS.
- `keybay_v2_android_test.dart`: package/UID identity, `noBackupFilesDir`, the
  Android Keystore root, framed persistence, passphrase protection, and reset
  on API 31+ devices and emulators, with native key-property and key-loss checks.
- `keybay_v2_macos_entitled_test.dart`: signed application identity, exact Data
  Protection Keychain group, framed persistence, passphrase protection, and
  reset in a provisioned macOS app.
- `keybay_v2_macos_continuity_test.dart`: explicit seed and reopen phases for
  passphrase-protected store continuity across separately signed builds.

The iOS host declares:

```xml
<key>KeybayApplicationIdentifier</key>
<string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
```

The processed value and signed group must agree. The entitled macOS leg applies
and restores its signing overlay in the end-to-end runner.

## Running

From the repository root:

```sh
./tool/test_e2e.sh android ios
KEYBAY_APPLE_TEAM_ID=<your-team-id> ./tool/test_e2e.sh macos-signed
```

Android needs exactly one ready emulator. iOS needs macOS, Xcode, and an
available iPhone simulator. Both need Flutter and resolved harness dependencies
(`cd example_flutter && flutter pub get --enforce-lockfile`). The opt-in
`macos-signed` lane needs an Apple Development identity and provisioning access. It runs the signed
baseline and explicit seed/reopen phases across builds 101 and 102, verifies
each signature, and requires reset cleanup.
See [platform regression commands](../doc/platform-regression.md) for `all`,
subsets, Docker, and report semantics.

Simulator/emulator success proves the genuine platform API path, not physical
secure-hardware mediation. The Android and iOS device-security runners select
these V2 scenarios. Physical runs, lifecycle procedures, evidence requirements,
and remaining qualification gates are maintained in
[the security suite](../doc/device-security-suite.md).

## Android build integrity

The Gradle wrapper and distribution are pinned, CI validates the wrapper JAR,
and Gradle verification metadata checks reviewed dependency artifacts. When
intentionally upgrading Android dependencies, refresh verification metadata and
locks from `example_flutter/android`, review the diff, and retain artifacts for
every supported CI host.

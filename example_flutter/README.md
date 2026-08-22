# example_flutter — keybay integration harness

Not a demo app. This is `keybay`'s living, runnable proof that the package
works from inside a real Flutter app bundle against the **real** platform
keystore on each mobile/desktop target — the coverage a pure-Dart CLI test can't
reach — and the reference for the Android backup-exclusion rules.

## What it exercises

`integration_test/keybay_test.dart` runs `SecretStorage(appId:)` end to
end — full round-trip (bytes, strings, labels, enumeration, idempotent delete),
shared backing across two instances, unicode values — and asserts the resolved
scheme plus any protection level the backend can inspect. The harness passes
explicit expectations so detection is *checked*, not trusted:

- **macOS .app (ad-hoc signed):** encrypted file + `loginBound` — the −34018
  branch every CLI takes, here inside a real sandboxed bundle.
- **macOS entitled (Keychain Sharing + dev signing):** native Data Protection
  Keychain items with no inferred hardware level — the native-item success
  branch. Also proves the migration guard:
  a pre-existing file container makes an entitled resolve throw
  `MigrationRequired`.
- **iOS simulator:** native Data Protection Keychain items with no inferred
  hardware level.
- **Android emulator (API 31+):** encrypted file + AndroidKeyStore-wrapped key
  via the pure-FFI JNI shim; the level is measured from the KEK after a write
  (`softwareBacked` on an emulator), and a dedicated test confirms ciphertext +
  the versioned wrapped-key blob land at the derived path.

## Running

Drive the whole matrix with **`tool/test_e2e.sh`** from the repo root (`--entitled`
adds the signed macOS DP-success leg). It boots the simulator/emulator, applies
and restores the entitled macOS overlay, and reports a per-leg pass/fail table.
Requires a macOS dev box with Xcode + an iPhone simulator, the Android SDK + an
AVD, Flutter, and Docker.

The separate [device security suite](../doc/device-security-suite.md) runs
physical-device and adversarial scenarios and produces a sanitized report for
the triggering issue:

```sh
./tool/device_security.sh doctor android
./tool/device_security.sh run android --device <serial>
./tool/device_security.sh run android --device <serial> --tamper \
  --allow-package-reset
./tool/device_security.sh doctor ios
./tool/device_security.sh run ios --device <physical-udid>
./tool/device_security.sh run macos
./tool/device_security.sh run macos --tamper
```

The mobile and macOS harness uses the dedicated test-only identity
`dev.keybay.securityharness`. Android cleanup is scoped to that exact package,
the selected Android user, and the dedicated `com.example.keybayHarness` and
`com.example.keybayDeviceSecurity.*` Keybay namespaces. Baseline qualification
never reboots the target or changes credentials, biometrics, backup transport,
or another application's data. Lifecycle and destructive procedures remain
separately gated as they are implemented.

### Android build integrity

The Gradle 9.1.0 wrapper is committed, its `-bin` distribution is SHA-256
pinned in `android/gradle/wrapper/gradle-wrapper.properties`, and CI validates
the wrapper JAR. `android/gradle/verification-metadata.xml` also makes Gradle
reject plugin or dependency artifacts whose bytes differ from the reviewed
checksums. `android/app/gradle.lockfile` separately pins the debug runtime graph
installed by the device harness for reproducibility and vulnerability scanning.
Flutter's ABI-specific engine artifacts are intentionally excluded from that
lock because the exact Flutter SDK pin controls them and their resolved set
varies between local ARM devices and CI's x86 emulator.
When intentionally upgrading Android dependencies, refresh both from
`example_flutter/android` with
`./gradlew --write-verification-metadata sha256 --write-locks :app:assembleDebug`.
Review the diff before committing, and retain the reviewed Linux AAPT checksum:
a one-host regeneration must not remove the other CI host's platform artifact.

## Android no-backup validation

The harness deliberately carries no host backup rule for Keybay. Its Android
integration test compares Keybay's derived directory with the host's public
`Context.getNoBackupFilesDir()` result, verifies every store artifact remains
beneath it, and exercises the atomic migration from the 0.1.0 files-directory
layout. Backup safety therefore belongs to the package rather than every host
manifest; details are in [`doc/platforms/android.md`](../doc/platforms/android.md).

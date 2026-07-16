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

## Android backup exclusion

`android/app/src/main/res/xml/data_extraction_rules.xml` is the living example of
  the backup exclusion documented in the package's
[`doc/platforms/android.md`](../doc/platforms/android.md). The
  Android Keystore wrapping key is not part of app backup and does not migrate
  with transferred app data, so a restored store cannot be decrypted on another
  device (reported as `KeyInvalidated`);
excluding the store directory from cloud backup and device transfer avoids that
confusing restore state and keeps ciphertext out of backups.

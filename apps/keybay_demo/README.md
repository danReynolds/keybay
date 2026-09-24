# Keybay Demo

A small Flutter app for dogfooding the Keybay SDK on real devices: save, reveal,
edit and delete key/value secrets, add or remove a passphrase, and reset the
store. It runs on iOS, Android and macOS.

It is a demo, not a password manager. Store test values you can afford to lose.

## What it exercises

- `Keybay.open()` with this app's own identity:
  - iOS: the Data Protection Keychain;
  - Android: the Android Keystore;
  - macOS: the entitled Data Protection Keychain.
- Records: `set`, `get`, `listKeys` and `delete`.
- Passphrases: adding, changing and removing one with `auth`, and unlocking
  with `Keybay.open(credential:)`.
- Resetting with `Keybay.reset()`.
- Persistence: the store survives app restarts, device reboots and reinstalls
  of the same signed app.
- Background behaviour: when the app leaves the foreground it covers its
  window and closes the session. On return it opens again, asking for the
  passphrase if one is set.

Failures show Keybay's error code in plain words: a locked device, an
unavailable keystore, a wrong passphrase, and so on.

## Identity

The app is `io.github.danreynolds.keybay.demo` on every platform. It is
separate from `example_flutter`, the integration harness, whose store the
device tests reset.

Keep the same identity and signing to keep your data:
- **Apple:** your team, set with `KEYBAY_APPLE_TEAM_ID`.
- **Android:** this machine's Flutter debug signing key.

A build signed with anything else cannot open the existing store.

## Install

From this directory:

```sh
KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/install.sh ios            # the attached iPhone or iPad
./tool/install.sh android                                    # the attached Android device
KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/install.sh macos          # ~/Applications/Keybay Demo.app
```

**iOS:**
- Name a device (UDID or name) as the second argument when more than one is
  attached.
- Development-signed apps expire with their provisioning profile. Reinstall
  with the same team to keep the store.

**Android:**
- Needs API 31 or later.
- `adb install -r` keeps the app's data.
- Name a serial when more than one device is attached.

**macOS:** Xcode creates the provisioning profile for the Keychain group
entitlement on the first build. This needs your Apple account signed in to
Xcode.

## Development

```sh
flutter pub get
flutter analyze
flutter test
```

The widget tests drive the real Keybay engine over the SDK's in-memory test
boundaries (`packages/keybay/test/support`), so no device or keystore is
needed.

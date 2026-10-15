<p align="center">
  <img src="assets/keybay-mark.svg" alt="" width="72" height="72">
</p>

<h1 align="center">Keybay</h1>

<p align="center">
  <strong>Keep secrets out of Git.</strong><br>
  An encrypted vault on your machine for API keys and tokens.<br>
  Use it from the terminal or from your Dart and Flutter apps.
</p>

<p align="center">
  <a href="https://pub.dev/packages/keybay"><img src="https://img.shields.io/pub/v/keybay?label=pub.dev" alt="Keybay on pub.dev"></a>
  <a href="https://github.com/danReynolds/keybay/actions/workflows/ci.yml"><img src="https://github.com/danReynolds/keybay/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://danreynolds.github.io/keybay/demo/"><strong>Try it in your browser</strong></a> ·
  <a href="#install">Install</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#platforms-and-security">Platforms and security</a> ·
  <a href="#learn-more">Learn more</a>
</p>

<p align="center">
  <a href="https://danreynolds.github.io/keybay/demo/"><img src="assets/tui-tour.svg" alt="The Keybay terminal UI: searching fourteen masked secrets, revealing one, opening security settings, and unlocking with a passphrase" width="704"></a>
</p>

Keybay runs on macOS and Linux, plus iOS and Android for the SDK. Your OS
keychain protects the vault, a passphrase or hardware key (like a YubiKey) can
lock it further, and Keybay makes no network calls.

| Tool | What it does | Learn more |
| --- | --- | --- |
| **`keybay run`** | Runs your app with secrets from your vault, so `.env` doesn't hold them. | [CLI guide](packages/keybay_cli/README.md) |
| **`keybay open`** | A terminal UI to browse, edit and protect your secrets. | [Try it in your browser](https://danreynolds.github.io/keybay/demo/) |
| **`package:keybay`** | Encrypted storage for Dart and Flutter apps. | [SDK guide](doc/sdk.md) |

## Install

### CLI and terminal UI

```sh
brew install danReynolds/tap/keybay
```

Homebrew works on Apple silicon Macs and on Linux x64 and arm64; update with
`brew upgrade keybay`. There's no Intel Mac build of the CLI. You can also:

- **Download a release.** Get the `macos-arm64`, `linux-x64` or `linux-arm64`
  archive from the
  [latest release](https://github.com/danReynolds/keybay/releases/latest),
  extract it, and add the extracted folder (on Linux, its `bin` folder) to your
  `PATH`. Keep the folder together; no Dart SDK is needed.
  [Verify the download](packages/keybay_cli/README.md#verify-a-release-download).
- **Build from source** for development. See
  [development builds](packages/keybay_cli/README.md#development-builds).

On Linux, the CLI needs glibc 2.35+ (Ubuntu 22.04 or newer, for example) and a
Secret Service keyring that's already unlocked; GNOME Keyring is the tested
provider. Keybay won't unlock or create one, so headless servers and CI usually
can't use it.

### Dart and Flutter SDK

```sh
dart pub add keybay      # or: flutter pub add keybay
```

The SDK needs Dart 3.11+ and a one-time setup on each platform:

- **iOS:** add the `KeybayApplicationIdentifier` key to `Info.plist`; see the
  [iOS guide](doc/platforms/ios.md).
- **Android:** set `minSdk = 31`.
- **macOS and Linux:** declare an
  [application ID](doc/sdk.md#application-identity) in `pubspec.yaml`, unless
  your Mac app has a Keychain entitlement. Desktop builds need
  [Keypass's native build tools](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md),
  and Linux needs the same unlocked keyring as the CLI.

> [!NOTE]
> Upgrading a 0.2.0 vault that has a passphrase or hardware key? Follow the
> [CLI](packages/keybay_cli/README.md#install) or
> [SDK](packages/keybay/CHANGELOG.md#030) steps before you upgrade. Vaults from
> 0.1.x aren't migrated.

## Quick start

### CLI

Save a secret. You type the value into a hidden prompt:

```sh
keybay set my-app/openai-api-key
```

Prefixes like `my-app/` just organize names; all your projects share one CLI
vault.

Point `.env` at the secret instead of pasting it:

```diff
-OPENAI_API_KEY=sk-proj-…
+OPENAI_API_KEY=kb://my-app/openai-api-key
```

Leave it unquoted. Keybay reads plain `NAME=value` lines: quotes become part of
the value, and `export` lines are errors. See the
[`.env` format](packages/keybay_cli/README.md#manifest).

Then run your app through Keybay from the folder with `.env` (or name another
file with `-f`):

```sh
keybay run -- npm start
```

Your app gets the real value as an ordinary environment variable, so any
language works. Only run commands and `.env` files you trust.

Next steps:

- Browse and edit your secrets with `keybay open`.
- Add a second factor, a passphrase or hardware key, in `keybay open` →
  Settings → Security. Until you do, `set`, `get`, `list`, `rm` and `run` print
  a warning; afterwards, each of them asks for it.
- See every command with `keybay --help`.

### Dart and Flutter

```dart
import 'package:keybay/keybay.dart';

final session = await Keybay.open();
try {
  await session.set('api-token', 's3cr3t');
  final saved = await session.get('api-token');
} finally {
  await session.close();
}
```

Each app gets its own vault. The [SDK guide](doc/sdk.md) covers adding a
passphrase or passkey with `session.auth.add`, and handling errors.

## Platforms and security

| Platform | SDK | CLI | [Key isolation](doc/security-levels.md#security-classes) | Enforced by |
| --- | :---: | :---: | --- | --- |
| iOS | ✓ | | App-bound | Keychain access group |
| Android 12+ | ✓ | | App-bound | Android Keystore, per app |
| macOS app with Keychain entitlement | ✓ | | App-bound | Keychain access group |
| macOS CLI and other macOS apps | ✓ | ✓ | Account-level | Login Keychain |
| Linux desktop | ✓ | ✓ | Account-level | Secret Service |

- **App-bound:** the OS releases the vault's key only to your app's signed
  identity (on Apple platforms, plus any apps you add to its access group), so
  other apps can't get it, even ones running as you.
- **Account-level:** other user accounts can't get the key, but any process
  running as you can reach your secrets. On Linux, it reads your unlocked
  keyring over D-Bus. On macOS, it runs `keybay` or your app, and for apps run
  with `dart run`, any Dart program can read the key directly.

> [!TIP]
> On account-level platforms, enroll a second factor: a passphrase or a
> compatible FIDO2 hardware key such as a YubiKey. Opening the vault then takes
> the OS key *and* that factor. Use `keybay open` → Settings → Security in the
> CLI, or `session.auth.add` in the SDK. If Keybay ever stops asking for it, the
> vault may have been replaced; don't save new secrets until you've checked.

Key isolation decides who can get the vault's OS key. App sandboxing is
separate: it decides who can read or delete the encrypted file. Windows, web and Snap aren't
supported, and Flatpak support isn't qualified yet.

Everywhere, a copied vault file is useless without the key your OS holds,
though a backup that also includes your keychain or keyring is only as strong as
its password. Keybay can't protect against root access, keyloggers, screen
capture, a modified Keybay binary, someone deleting or rolling back the vault
file, code running inside your app, or what your apps do with a secret once
they have it. It's pre-1.0 and hasn't had an independent security audit.

More in [security levels by platform](doc/security-levels.md), the
[security policy](SECURITY.md) and the [architecture](doc/architecture.md).

## Learn more

- [CLI guide](packages/keybay_cli/README.md): every command, the `.env` format,
  the terminal UI and verifying downloads.
- [SDK guide](doc/sdk.md): setup for each platform, passkeys, errors and
  recovery.
- [Choosing Keybay](doc/ecosystem-comparison.md): Keybay keeps secrets on one
  device and never syncs them. For shared team vaults, use 1Password CLI; for
  encrypted files that travel with a project, dotenvx; for CI, your CI's secret
  store.
- [Keybay Demo](apps/keybay_demo/README.md): a small Flutter app built on the
  SDK.

Issues and pull requests are welcome. Report vulnerabilities privately through
[SECURITY.md](SECURITY.md). Keybay is [MIT licensed](LICENSE).

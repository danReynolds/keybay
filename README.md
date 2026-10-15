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
  <a href="#quick-start">Quick start</a> ·
  <a href="#platforms">Platforms</a> ·
  <a href="#security">Security</a> ·
  <a href="#learn-more">Learn more</a>
</p>

<p align="center">
  <a href="https://danreynolds.github.io/keybay/demo/"><img src="assets/tui-tour.svg" alt="The Keybay terminal UI: searching fourteen masked secrets, revealing one, opening security settings, and unlocking with a passphrase" width="704"></a>
</p>

Keybay runs on macOS and Linux, plus iOS and Android for the SDK. Your OS
keychain protects the vault, a passphrase or YubiKey can lock it further, and
Keybay never uses the network.

| Tool | What it does | Learn more |
| --- | --- | --- |
| **`keybay run`** | Runs your app with secrets from your vault, so `.env` doesn't hold them. | [CLI guide](packages/keybay_cli/README.md) |
| **`keybay open`** | A terminal UI to browse, search and edit secrets. | [Try it in your browser](https://danreynolds.github.io/keybay/demo/) |
| **`package:keybay`** | Encrypted storage for Dart and Flutter apps. | [SDK guide](doc/sdk.md) |

## Quick start

### CLI

```sh
brew install danReynolds/tap/keybay   # Apple silicon Macs and Linux
keybay set my-app/openai-api-key      # type the value into a hidden prompt
```

Point `.env` at the secret instead of pasting it:

```diff
-OPENAI_API_KEY=sk-live-…
+OPENAI_API_KEY=kb://my-app/openai-api-key
```

Then run your app through Keybay, from the folder with `.env`:

```sh
keybay run -- npm start
```

Your app gets the real value as an ordinary environment variable, so any
language works. Only run commands and `.env` files you trust.

### Dart and Flutter

```sh
dart pub add keybay
```

```dart
import 'package:keybay/keybay.dart';

final session = await Keybay.open();
try {
  await session.set('api-token', token);
  final saved = await session.get('api-token');
} finally {
  await session.close();
}
```

Each app gets its own vault. Most platforms need a one-time setup step, covered
in the [SDK guide](doc/sdk.md).

## Platforms

| Platform | SDK | CLI | By default, readable by |
| --- | :---: | :---: | --- |
| iOS, Android 12+ | ✓ | | only your app |
| macOS app with Keychain entitlement | ✓ | | only your app |
| macOS CLI and other apps | ✓ | ✓ | any program you run |
| Linux desktop | ✓ | ✓ | any program you run |

Adding a passphrase or hardware key keeps other programs out on every platform.
The CLI runs on Apple silicon Macs, and on Linux x64 and arm64 with glibc 2.35+
and a desktop keyring such as GNOME Keyring or KWallet. Windows, web and Snap
aren't supported.
[Security levels by platform](doc/security-levels.md) explains each row.

## Security

Your OS keychain always protects the vault, so a copied vault file is useless on
its own. On macOS and Linux, though, other programs you run can read your
secrets until you add a passphrase or a hardware key such as a YubiKey (Mac apps
with the Keychain entitlement are the exception). In the CLI, add one from
`keybay open` → Settings.

Keybay is pre-1.0 and hasn't had an independent security audit. The
[security policy](SECURITY.md) covers what it can't protect against, and the
[architecture](doc/architecture.md) explains how the vault works.

## Learn more

- [CLI guide](packages/keybay_cli/README.md): every command, the `.env` format,
  the terminal UI and verifying downloads.
- [SDK guide](doc/sdk.md): setup for each platform, passkeys, errors and
  recovery.
- [Choosing Keybay](doc/ecosystem-comparison.md): Keybay is for one person on
  one machine. For teams, use 1Password CLI or dotenvx; for CI, your CI's
  secret store.
- [Keybay Demo](apps/keybay_demo/README.md): a small Flutter app built on the
  SDK.
- Upgrading a 0.2.0 vault with a passphrase or hardware key? Follow the
  [CLI](packages/keybay_cli/README.md#install) or
  [SDK](packages/keybay/CHANGELOG.md#030) steps first.

Issues and pull requests are welcome. Report vulnerabilities privately through
[SECURITY.md](SECURITY.md). Keybay is [MIT licensed](LICENSE).

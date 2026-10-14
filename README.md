<p align="center">
  <img src="assets/keybay-mark.svg" alt="" width="72" height="72">
</p>

<h1 align="center">Keybay</h1>

<p align="center">
  <strong>Keep secrets out of Git.</strong><br>
  Commit <code>kb://</code> references instead of API keys. <code>keybay run</code> injects the real values from an encrypted local vault on macOS and Linux.
</p>

<p align="center">
  <a href="https://pub.dev/packages/keybay"><img src="https://img.shields.io/pub/v/keybay?label=pub.dev" alt="Keybay on pub.dev"></a>
  <a href="https://github.com/danReynolds/keybay/actions/workflows/ci.yml"><img src="https://github.com/danReynolds/keybay/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://danreynolds.github.io/keybay/demo/"><img src="assets/tui-tour.svg" alt="The Keybay terminal UI: searching fourteen masked secrets, revealing one, opening security settings, and unlocking with a passphrase" width="704"></a>
</p>

<p align="center">
  <a href="https://danreynolds.github.io/keybay/demo/"><strong>Try the terminal UI in your browser</strong></a> ·
  <a href="packages/keybay_cli/README.md">CLI guide</a> ·
  <a href="doc/sdk.md">SDK guide</a> ·
  <a href="doc/security-levels.md">Security levels</a>
</p>

```sh
keybay set my-app/openai-api-key   # prompts for the value, stores it encrypted
# In .env, replace the plaintext value with a reference that's safe to commit:
#   OPENAI_API_KEY=kb://my-app/openai-api-key
keybay run -- npm start            # npm sees the real value
```

A gitignored `.env` is still plaintext on disk, where backups, sync folders and
every tool that reads your project directory can see each key. Keybay keeps the
values encrypted under a key held by the Keychain on macOS or the Secret Service
keyring on Linux. On its own, that protects copies of the vault file, but not
your secrets from other programs running as you. Add a passphrase or a hardware
key such as a YubiKey, and that key alone is no longer enough.

- **Works with any stack.** Your app reads ordinary environment variables and
  needs no Keybay library.
- **A terminal UI for your vault.** Use `keybay open` to search, reveal, copy,
  edit and add a passphrase or hardware key.
- **Local only.** No account, sync, network access or background process.
  Keybay refuses to run rather than fall back to weaker storage.
- **Dart and Flutter SDK.** An encrypted vault for each app on iOS, Android,
  macOS and Linux.

## Install

```sh
brew install danReynolds/tap/keybay
```

Homebrew works on macOS (Apple silicon) and Linux (x64, arm64). You can also
download a [release archive](https://github.com/danReynolds/keybay/releases/latest)
and follow the [install guide](packages/keybay_cli/README.md#install), or add
the SDK to a Dart or Flutter app with `dart pub add keybay`.

On Linux, the CLI needs glibc 2.35+ and an unlocked Secret Service provider,
such as GNOME Keyring or KWallet.

> [!NOTE]
> Keybay is pre-1.0, so APIs and the vault format may change between minor
> versions. Upgrading a 0.2.0 vault that has a passphrase or hardware key?
> Follow the upgrade steps for the [CLI](packages/keybay_cli/README.md#install)
> or the [SDK](packages/keybay/CHANGELOG.md#030) first.

## Using the CLI

Before launching, `keybay run` shows what it will run and which key each
variable reads, never the values. Then it replaces itself with your command:

```text
$ keybay run -- ./app.sh
warning: platform protection only; no additional credential is configured.
Run: "/Users/you/my-app/app.sh"
Manifest: "./.env"
Environment:
  API_URL (literal)
  OPENAI_API_KEY <- my-app/openai-api-key
```

The warning means no passphrase or hardware key is set, so any program running
as you could read these values too. Add one in `keybay open` → Settings.

If a reference has no value, nothing launches and Keybay prints the
`keybay set` command that fixes it.

The command and anything it starts receive the secrets as ordinary environment
variables, so run only commands and `.env` files you trust.

| Command | What it does |
| --- | --- |
| `keybay open` | Open the interactive vault. |
| `keybay set [--stdin] KEY` | Save a value from hidden input, or from a pipe with `--stdin`. |
| `keybay run [-f FILE] -- COMMAND` | Launch a command with `.env` references resolved. |
| `keybay get KEY` | Print one value to your terminal. Pipes and redirects are refused. |
| `keybay list` | List key names. |
| `keybay rm KEY` | Delete a key. |

To migrate an existing `.env`, `keybay set` each secret, then replace its value
with a `kb://` reference. Secrets from another tool can be piped in without
appearing on screen:

```sh
op read 'op://Engineering/OpenAI/credential' | keybay set --stdin my-app/openai-api-key
```

Prefixes like `my-app/` organize your keys; every project shares the same CLI
vault. Keybay reads `./.env` from the current directory, or another file with
`-f`. Lines are plain `NAME=VALUE`, with no quotes, `export` or inline
comments: `KEY="kb://…"` would pass the quotes and reference through as literal
text. Values that aren't `kb://` references stay plaintext. See the
[manifest format](packages/keybay_cli/README.md#manifest).

## The terminal UI

`keybay open` is a keyboard-driven vault for browsing, editing and protecting
your secrets:

<kbd>/</kbd> search · <kbd>Space</kbd> reveal · <kbd>c</kbd> copy ·
<kbd>n</kbd> <kbd>e</kbd> <kbd>d</kbd> new, edit, delete ·
<kbd>s</kbd> settings · <kbd>q</kbd> quit

Settings is where you add or remove a passphrase and hardware keys, clear or
reset the vault, and pick an accent color. Values stay masked until you reveal
one, and hide again when the terminal resizes or, in terminals that report it,
loses focus. The vault closes after five minutes without input. Copied values go
to the system clipboard, where clipboard managers may keep them; on Linux,
copying needs `wl-copy` or `xclip`.

The [browser demo](https://danreynolds.github.io/keybay/demo/) runs the same
interface against fake records.

## Dart and Flutter

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

Reading and writing never prompt. To require a passphrase, enroll it from an
open session before writing values that should need it:

```dart
await session.auth.add(PassphraseCredential(phrase: enteredBytes));
```

Later, open the vault with the passphrase the user enters:
`Keybay.open(credential: PassphraseCredential(phrase: enteredBytes))`.
Hardware keys and system passkeys work the same way through
`PasskeyCredential.hardware(...)` and `PasskeyCredential.system(...)`.

The [SDK guide](doc/sdk.md) covers native setup for each platform, including
the application ID and build tools that desktop Dart programs need, plus errors
and recovery. [Keybay Demo](apps/keybay_demo/README.md) is a small Flutter app
built on the SDK.

## Supported platforms

| Platform | CLI | Key store | Security class |
| --- | :---: | --- | --- |
| iOS | | Keychain | App-bound |
| Android 12+ | | Android Keystore | App-bound |
| macOS app with Keychain entitlement | | Keychain | App-bound |
| macOS CLI and unentitled apps | ✓ arm64 | Login Keychain | Account-level |
| Linux desktop | ✓ x64, arm64 | Secret Service | Account-level |

The Dart SDK runs on all of these.

- **App-bound:** the OS checks the requesting app's signature, package or
  sandbox ID and refuses other apps, even ones running as you.
- **Account-level:** any program running as you can reach your secrets. On
  Linux it reads the keyring silently. On macOS it can run the app itself, or
  `keybay list` and `keybay run`, with no prompt. A passphrase or hardware key
  closes that gap.

Windows and Snap aren't supported; Flatpak support is implemented but not yet
qualified. [Security levels by platform](doc/security-levels.md) spells out who
can read your secrets on each platform.

## Security model

Two layers protect every vault:

1. **The platform key, always.** A key held by the OS key store seals the
   vault, so a copy of the file reveals nothing and other user accounts are
   kept out.
2. **A passphrase or passkey, optionally.** A passphrase (stretched with
   Argon2id), a FIDO2 hardware key or a system passkey. With one enrolled,
   opening the vault needs the platform key *and* one of them, so the platform
   key alone is no longer enough.

The vault is encrypted with XChaCha20-Poly1305. Each passphrase or passkey also
confirms the vault it opens, so someone holding only the platform key can't
substitute a vault of their own that yours would open. That check arrived in
0.3.0 ([GHSA-2cm6-3f6q-5jqc](https://github.com/danReynolds/keybay/security/advisories/GHSA-2cm6-3f6q-5jqc)).
If a credential is compromised, see
[what to do](doc/security-levels.md#after-a-credential-is-compromised).

Out of scope:

- administrator or root access, code running inside your app, keyloggers and
  screen capture, and a modified Keybay binary;
- deleting, replacing or rolling back the vault file. On account-level
  platforms, a replacement vault with no passphrase opens without asking for
  one, so notice if your passphrase prompt disappears;
- what a launched process or a clipboard manager does with a secret once it has
  it.

Further reading:

- [Architecture](doc/architecture.md): how the vault, its keys and protection
  changes work.
- [Security design](doc/design.md): the threat model and numbered invariants.
- [Security policy](SECURITY.md): guarantees, limitations and private
  vulnerability reporting.
- [Verifying a CLI download](packages/keybay_cli/README.md#verify-a-release-download).

## How it compares

- **vs. 1Password CLI:** no account or subscription, but no team sharing
  either.
- **vs. dotenvx:** no decryption key to distribute, but the vault can't travel
  with the repository.
- **vs. envchain:** also keychain-backed, but secrets are referenced from a
  `.env` you commit rather than grouped by namespace.
- **vs. flutter_secure_storage:** an optional passphrase or FIDO2 key on top of
  the platform store, but no Windows or web support.

Keybay stores values on one device for one person. If you need to share secrets
with a team, deliver them to CI or production, or run on Windows, use
1Password CLI, dotenvx or your platform's secrets manager instead.
[Choosing Keybay](doc/ecosystem-comparison.md) goes into more detail.

## Status

Keybay is pre-1.0 and has not had an independent security audit. Device and
provider coverage is recorded in [release readiness](doc/release-readiness.md),
and changes in the [changelog](packages/keybay/CHANGELOG.md).

## Contributing

Bug reports and pull requests are welcome. Run `dart pub get` at the repository
root, install [Keypass's native build prerequisites](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md),
then run `dart test -x integration` in `packages/keybay` and
`packages/keybay_cli`. The platform suites are described in
[platform regressions](doc/platform-regression.md). Please report
vulnerabilities privately, as described in [SECURITY.md](SECURITY.md), not in
public issues.

## License

[MIT](LICENSE)

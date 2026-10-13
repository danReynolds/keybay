<img src="https://danreynolds.github.io/keybay/assets/keybay-mark.svg" alt="" width="64" height="64">

# Keybay

Encrypted local secrets for Dart applications and the terminal. No Keybay
account, service, daemon or shell hook.

The [Dart SDK](https://pub.dev/packages/keybay) supports iOS, Android 12+, macOS
and ordinary Linux desktop. The [CLI](packages/keybay_cli/README.md) ships for
macOS ARM64 and Linux ARM64/x64. The published versions are 0.2.0; APIs and
formats may change before 1.0. Provider/device coverage is recorded in [release readiness](doc/release-readiness.md).

**Upgrading:** V1 vaults are not migrated. Current source also rejects retired
V2 singleton-passphrase packages, unlike published 0.2.0. Keep access to the old
installation and transfer needed secrets before switching; see the
[changelog](packages/keybay/CHANGELOG.md#030).

## CLI

```sh
brew install danReynolds/tap/keybay
keybay set my-app/api-key
keybay open
```

Commit a reference in `.env`, then launch your application:

```dotenv
API_KEY=kb://my-app/api-key
```

```sh
keybay run -- ./app
```

The child receives the secret as an environment variable. The CLI uses one
store; slash-separated names organize records, not security domains.
See [commands and installation](packages/keybay_cli/README.md).

## Dart and Flutter

```dart
import 'package:keybay/keybay.dart';

final session = await Keybay.open();
try {
  await session.set('api-token', tokenFromOAuth);
  final token = await session.get('api-token');
} finally {
  await session.close();
}
```

Each host application gets one store, derived from its platform identity or
declared desktop namespace. See the [SDK guide](doc/sdk.md) for native setup,
identity and passphrase/passkey enrollment.

## Protection

Platform protection is mandatory. Optional passphrases and passkeys add
cryptographic protection: `platform AND (passphrase OR passkey A OR passkey B)`.
A credential-based open only authenticates; enrollment uses `session.auth.add`.
Record operations never prompt.

Desktop namespaces are not same-user authorization boundaries. Enroll an
additional method to make access to the platform root and file insufficient.
A synced passkey alone does not make the vault portable.

- [Security levels by platform](doc/security-levels.md): who can read your
  secrets on each platform, with and without a passphrase or passkey.
- [Architecture](doc/architecture.md): how the vault, its keys and its
  protection changes work.
- [Security policy](SECURITY.md): guarantees, trust boundaries and reporting.
- [External review guide](doc/external-review.md): source map, evidence and open work.
- [Platform regressions](doc/platform-regression.md): run `./tool/test_e2e.sh all`.

MIT licensed.

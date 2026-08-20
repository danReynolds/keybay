<img src="https://danreynolds.github.io/keybay/assets/keybay-mark.svg" alt="" width="64" height="64">

# Keybay

Keep local secrets out of your repository and in an OS-protected store.

**[See how Keybay works →](https://danreynolds.github.io/keybay/)**

Installation, quickstarts, platform support, and the security design live on
the Keybay site.

Use the five-command CLI to run local processes with the secrets they need on
macOS and Linux desktop, or store values directly with the Dart and Flutter SDK
on macOS, Linux desktop, iOS, and Android 12+.

No Keybay account or hosted service. No Keybay daemon, network path, or shell
hook.

> **Pre-1.0.** The `keybay` and `keybay_cli` packages are available on pub.dev.
> The legacy 0.1.0 GitHub/Homebrew release predates immutable-release
> verification, and its macOS binary does not pass strict code-signature
> verification or launch on macOS 26. Do not use that macOS artifact. Require
> Keybay CLI 0.1.1 or newer, or evaluate from a reviewed source checkout.

## CLI

Commit the reference, not the value.

```dotenv
OPENAI_API_KEY=kb://my-app/openai-api-key
```

```sh
keybay set my-app/openai-api-key
keybay run -- ./app
```

CLI values live in one per-user store. Namespaces prevent naming collisions;
they are not access-control boundaries.

**[Use the CLI →](https://danreynolds.github.io/keybay/docs/cli/)**

## Dart and Flutter

```dart
import 'package:keybay/keybay.dart';

final store = SecretStorage(appId: 'com.example.app');
await store.writeString('api-token', tokenFromOAuth);
final token = await store.readString('api-token');
```

**[Use the SDK →](https://danreynolds.github.io/keybay/docs/guide/)**

## Security

Keybay's security model is two commitments:

1. **Secure on every platform** — secrets live in each platform's own
   credential storage, wired directly and verified from unit tests to real
   devices.
2. **Secure over time** — every change runs against real providers, core
   package publication is independently checked against signed source, and
   security signals are triaged against the model when they occur.

If the required platform store is unavailable, locked, invalidated, corrupt,
tampered with, or unsupported, Keybay fails closed — never plaintext.
Protection ends when a value is read or injected into a process. Same-user
malware, rollback, and root remain outside the threat model. Windows and
headless deployments are unsupported.

The full model, the threat model, and how to verify a release yourself:
[SECURITY.md](SECURITY.md).

MIT licensed.

<img src="https://danreynolds.github.io/keybay/assets/keybay-mark.svg" alt="" width="64" height="64">

# Keybay

Keep local secrets out of your repository and in one encrypted store belonging
to the host application.

Keybay is local-only: no account, hosted service, daemon, network path, or shell
hook. The Dart SDK supports iOS, Android 12+, macOS, and ordinary Linux desktop.
The CLI supports macOS and ordinary Linux desktop.

## CLI

Commit a reference, not its value:

```dotenv
OPENAI_API_KEY=kb://my-app/openai-api-key
```

```sh
keybay set my-app/openai-api-key
keybay get my-app/openai-api-key
keybay run -- ./app
```

The CLI is one application with one store. Slash-separated key names organize
records; they are not separate security domains. See the
[CLI guide](packages/keybay_cli/README.md).

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

There is no runtime application-ID or store selector. Keybay derives an
OS-authenticated application identity where the platform provides one; ordinary
Dart executables declare their namespace in the owning `pubspec.yaml`. See the
[SDK guide](doc/sdk.md).

SDK 0.2.0 replaces the 0.1.x API and encrypted format; V1 stores are not read,
migrated or removed. The [release scope](doc/qualification-status.md#sdk-020-release-scope)
records deferred physical lifecycle qualification and lower-priority Argon2
performance acceptance. They are not passing qualification claims.

A retained platform root without its complete encrypted file returns
`storeStateConflict`, including after some interrupted initializations or Apple
reinstalls/restores. Follow the [deliberate recovery guidance](doc/sdk.md#errors-and-limits);
do not automatically reset on error.

Opening, changing authentication, and resetting may invoke trusted OS/provider
UI. Record operations and authentication listing never prompt.

## Security

Every supported platform uses the same independently encrypted record frames
and an encrypted manifest. One platform-protected root unlocks that
application's store key. Applications can add a passphrase so platform access
alone is insufficient.

Keybay fails closed when identity, platform protection, or authenticated store
state cannot be established. It never falls back to plaintext, process memory,
another provider, or pre-V2 storage. See [SECURITY.md](SECURITY.md) and the
accepted [V2 architecture RFC](doc/rfcs/0001-per-application-stores.md).

The Flatpak candidate uses authenticated sandbox identity, private ciphertext,
and XDG Secret Portal protection. The repeatable Linux regression exercises two
installed application IDs, including inside the tested nested Docker setup.
Remaining release evidence is tracked in the
[security suite](doc/device-security-suite.md). It never falls back to raw
Secret Service. Windows, Snap, and unsupported provider configurations fail
closed. See the [Linux profile](doc/platforms/linux.md), including Flatpak's
retained portal secret after reset.

## Development tests

Run `./tool/test_e2e.sh all` for the routine SDK regressions, or select a subset
such as `./tool/test_e2e.sh linux flatpak`. See the
[platform regression guide](doc/platform-regression.md) for prerequisites,
reports, CI, and the separate physical-device qualification procedures.

Pre-1.0 APIs and the file format may still change. MIT licensed.

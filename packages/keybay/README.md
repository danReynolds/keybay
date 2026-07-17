# keybay

Cross-platform secret storage for Dart and Flutter — no platform channels, no
plugin registration. On iOS, Android 12+, macOS, and Linux desktop,
`SecretStorage(appId:)` applies one documented, OS-backed storage policy for the
current runtime and fails closed when it cannot.

**[Documentation & security design →](https://danreynolds.github.io/keybay/)**

```dart
import 'package:keybay/keybay.dart';

final store = SecretStorage(appId: 'com.example.myapp');

await store.writeString('api_token', 's3cr3t');
final token = await store.readString('api_token');   // 's3cr3t'
await store.delete('api_token');
```

`appId` names the store; the runtime selects the fixed platform scheme. Values
are bytes (`Uint8List`) at the core, with `readString`/`writeString` for
convenience. `SecretStorage.withBackend` is the test/custom hatch.

## How secrets are stored

| Platform | Secrets live in | Protected by |
|---|---|---|
| iOS / entitled macOS | Data Protection Keychain items | fixed device-bound, non-synchronizing item policy |
| macOS CLI / unentitled | authenticated encrypted file | 32-byte store key in the login Keychain |
| Android 12+ | authenticated encrypted file | store key wrapped by Android Keystore |
| Linux desktop | authenticated encrypted file | 32-byte store key in the Secret Service |

The container is XChaCha20-Poly1305 with an HKDF-SHA256 key-commitment header, so
a wrong key or tampering fails closed before plaintext is returned. Windows is
unsupported and fails closed; headless deployment has no supported backend. Full
per-platform detail and the threat model:
[the security design](https://danreynolds.github.io/keybay/docs/design/).

## Companion CLI

[`keybay_cli`](https://pub.dev/packages/keybay_cli) injects secrets into a child
process from a committed manifest — no library dependency in your app.

## License

MIT.

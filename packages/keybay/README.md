# keybay

One encrypted, platform-protected local store per Dart or Flutter application.
No Flutter dependency, Keybay account, daemon or hosted service.

Requires Dart 3.11+. Supports iOS, Android 12+, macOS and ordinary Linux desktop.
See [platform setup](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md#platform-summary)
for native integration and qualification limits.
Desktop builds need [Keypass's native build prerequisites](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md),
even for passphrase-only use. Distribute the complete native bundle; end users
do not need build tools.

**Upgrading:** V1 stores are not migrated. Current source also rejects retired
V2 singleton-passphrase packages, unlike published 0.2.0. Transfer needed secrets
using the old installation before upgrading; see the
[changelog](https://github.com/danReynolds/keybay/blob/main/packages/keybay/CHANGELOG.md#030).

## Open, use, close

```dart
import 'package:keybay/keybay.dart';

final session = await Keybay.open();
try {
  await session.set('api-token', 's3cr3t');
  final token = await session.get('api-token');
  await session.delete('api-token');
} finally {
  await session.close();
}
```

`open()` initializes fully absent state with platform protection. Record
operations and `auth.list()` never prompt; opening, changing authentication and
resetting may invoke provider UI. Binary access uses `getBytes`, `setBytes` and
`getManyBytes`; `listKeys` returns names without decrypting values.

`clearAll` keeps protection while removing records. `Keybay.reset()` deletes
the current store and deletable provider state. Never reset automatically on
an unlock or state-conflict error; see [recovery](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md#errors-and-limits).

## Application identity

Signed/package identity comes from the OS. Ordinary Dart executables on Linux
and unentitled macOS declare a namespace in their owning `pubspec.yaml`:

```yaml
keybay:
  application_id: com.example.my_app
```

Compile with `dart run keybay:keybay_compile bin/app.dart -o build/app` to embed
it. The API has no runtime application-ID, path or store selector. A desktop
namespace prevents collisions, not access by another same-user program.
See [identity and packaging](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md#application-identity).

## Add protection

An open session enrolls protection explicitly. Complete enrollment before
writing values that should require it:

```dart
const credential = PasskeyCredential.system(rpId: 'vault.example.com');
final session = await Keybay.open();
try {
  await session.auth.add(credential, label: 'Personal vault');
  await session.set('api-token', 's3cr3t');
} finally {
  await session.close();
}
```

Later, `Keybay.open(credential: credential)` authenticates that enrollment;
it never creates a passkey or initializes a missing store. Use `methodId:`
when several enrollments match.

Other credentials use the same `open` and `auth.add` operations:

| Credential | Input |
| --- | --- |
| `PassphraseCredential(phrase: bytes)` | Caller-owned passphrase bytes. |
| `PasskeyCredential.system(rpId: domain)` | Native app host and domain association. |
| `PasskeyCredential.hardware(rpId: namespace, pin: bytes)` | Physical FIDO2 key; optional PIN for this attempt, no website required. |

Credentials are data only. Operations copy mutable input synchronously and
clear their copy; clear your own buffers after submitting the call. Hardware
PIN and connection errors let your app request input and retry deliberately.

Protection is `platform AND (passphrase OR passkey A OR passkey B ...)`:
one passphrase at most, eight methods total. Manage them with `auth.add`,
`auth.list` and `auth.remove(method)`; there is no update/replace.
**Removing the last method returns to platform-only protection.** Changing a
passphrase requires separate remove/add commits, leaving that weaker state if
it was the last method and adding fails. Add a replacement passkey before
removing the old one when capacity allows.

Removing a method does not delete its provider credential or revoke older
snapshots. The platform root is always required, so synced passkeys alone do
not make a vault portable.

- [SDK guide](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md): complete flows, cancellation and errors.
- [Security policy](https://github.com/danReynolds/keybay/blob/main/SECURITY.md): guarantees and limitations.
- [External review](https://github.com/danReynolds/keybay/blob/main/doc/external-review.md): exact baselines and outstanding work.

Pre-1.0 APIs and formats may change. MIT licensed.

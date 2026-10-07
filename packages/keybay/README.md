# keybay

One encrypted, platform-protected local store for each Dart or Flutter host
application. No Flutter plugin, account, daemon, or network service.

Requires Dart 3.11 or later, including when used through Flutter.

See the
[release readiness](https://github.com/danReynolds/keybay/blob/main/doc/release-readiness.md)
record for the SDK's qualification scope and the separate CLI distribution gates.

Version 0.2.0 replaces the 0.1.x API and encrypted format. It does not read,
migrate or delete existing V1 stores. An upgrade does not carry those secrets
into a V2 store; applications needing the old data must handle that transition
before adopting this version.

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

Strings are the default. `getBytes`, `setBytes`, and `getManyBytes` support
binary or bounded batch access. `listKeys` returns authenticated names without
decrypting record values. `clearAll` removes records while preserving store
protection; selector-free `Keybay.reset()` removes the current application's
encrypted store, staging, and deletable provider state. It retains nonsecret
coordination locks; the next successful open generates a fresh store key.

A retained platform root without its complete encrypted file returns
`storeStateConflict`, including after some interrupted initializations or Apple
reinstalls/restores. Follow the [deliberate recovery guidance](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md#errors-and-limits);
do not automatically reset on error.

Opening, changing authentication, and resetting may invoke trusted OS/provider
UI. Record operations and `auth.list()` never prompt. Mandatory platform
protection cannot be bypassed. Hardware credentials accept optional PIN bytes;
the application handles typed errors when a PIN or an unambiguous connection is
required. Credential objects do not contain UI callbacks.

## Application identity

The production API accepts no application ID, path, platform-protector override,
or store name.
iOS, Android, and entitled macOS builds use OS-authenticated application facts.
An ordinary Dart executable on Linux or unentitled macOS declares a stable
namespace in its owning `pubspec.yaml`:

```yaml
keybay:
  application_id: com.example.my_app
```

For AOT output, use `dart run keybay:keybay_compile bin/app.dart -o app` so the
declaration is embedded. A declared desktop namespace prevents accidental
collisions but is not an OS-enforced authorization boundary.
Add `--aot-snapshot` before the entrypoint when building a separate native AOT
module. Hardened macOS distribution requires signing the module and its
dedicated Dart AOT runtime with the same Developer ID team. The single-file
Dart executable has a separately recorded hardened-runtime startup limitation.

## Additional passphrase protection

```dart
import 'dart:convert';
import 'dart:typed_data';

final phrase = Uint8List.fromList(utf8.encode(userPassphrase));
try {
  await session.auth.add(PassphraseCredential(phrase: phrase));
} finally {
  phrase.fillRange(0, phrase.length, 0);
}
```

After enrollment, `Keybay.open()` returns `authRequired`; reopen with a
`PassphraseCredential`. Closing the session clears Keybay's in-memory store-key
buffer. The encrypted file never becomes plaintext.

A store supports zero or one passphrase and multiple passkey methods (eight
total methods maximum). Adding a second passphrase throws
`authMethodAlreadyConfigured`; remove the existing method before adding another. These are
alternative unlock methods on top of the mandatory platform root; configuring
both does not require the user to present both.

## Additional passkey protection

Use the same credential API for OS-provider passkeys and physical FIDO2 keys.
Configure the RP once and enroll explicitly on a new or platform-only store:

```dart
const systemPasskey = PasskeyCredential.system(
  rpId: 'vault.example.com',
);
final session = await Keybay.open();
try {
  await session.auth.add(systemPasskey, label: 'Personal vault');
  await session.set('api-token', 's3cr3t');
} finally {
  await session.close();
}
```

Later, `Keybay.open(credential: systemPasskey)` authenticates using the saved
method. Credential-based open never enrolls protection, for either passphrases
or passkeys. If the encrypted file is missing it fails with `storeNotFound`
without creating a root or invoking the passkey provider. Await enrollment
success before writing records that should require the added protection.

To add a passkey to an existing store, first open it using its current
protection, then call `session.auth.add`:

```dart
final method = await session.auth.add(
  PasskeyCredential.hardware(
    rpId: 'dev.example.vault',
    pin: pinBytes,
  ),
  label: 'Backup key',
);

final methods = await session.auth.list();
await session.auth.remove(method);
```

The optional hardware PIN uses caller-owned UTF-8 bytes. Operations copy it
synchronously and clear their copy; clear your own bytes after submitting the
call. Credential objects contain data, not UI callbacks. A sole connection is
selected automatically; ambiguous hardware discovery fails explicitly.

Auth management is `add`, `list`, and `remove` only. Removal accepts the method
object returned by `add` or `list` and checks that it belongs to this vault.
Changing a passphrase means removing it and adding a new one. These are two
commits: removing the last method leaves platform-only protection, including
if the subsequent add fails. For passkeys, add the new key before removing the
old one when capacity allows. Each add gets a fresh method ID.

To reopen, use `Keybay.open(credential: credential, methodId: method.id)`.
Omit `methodId` when exactly one enrollment matches the credential. Passkeys
are scoped by explicit RP ID; provider setup remains the app's responsibility.
The system route needs an appropriate native app host and platform domain
associations. Standalone CLIs use hardware. Keybay adds no hosted service or
automatic browser fallback. Removing an enrollment does not delete its passkey
from the provider. The mandatory platform root remains required; a synced
passkey alone does not make a vault file portable.

See the [SDK guide](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md),
[security policy](https://github.com/danReynolds/keybay/blob/main/SECURITY.md), and
[V2 RFC](https://github.com/danReynolds/keybay/blob/main/doc/rfcs/0001-per-application-stores.md).

Supported production profiles are iOS, Android 12+, macOS, and ordinary Linux
desktop. The Flatpak candidate uses sandbox identity, private ciphertext, and
XDG Secret Portal protection. Two-app isolation has passed for recorded native
Linux and nested Docker configurations; see the [qualification report](https://github.com/danReynolds/keybay/blob/main/doc/qualification-status.md)
for source applicability and remaining gates. Reset retains the portal-owned application
secret, so an older complete encrypted backup can restore access. Flatpak never
falls back to ordinary Secret Service. Windows, Snap, and unsupported provider
configurations fail closed. MIT licensed.

The scoped pre-1.0 release retains platform CI and recorded physical baseline,
upgrade and crash evidence. Remaining lock/reboot, auth-interruption and actual
backup/restore/transfer qualification is deferred. Maintained-device Argon2
latency/memory acceptance is lower priority; no accepted performance budget is
claimed. These limits and the recorded provider/device configurations are part
of the release scope, not passing results for unobserved behavior.

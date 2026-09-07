# keybay

One encrypted, platform-protected local store for each Dart or Flutter host
application. No Flutter plugin, account, daemon, or network service.

Requires Dart 3.11 or later, including when used through Flutter.

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
reinstalls/restores. Follow the [deliberate recovery guidance](../../doc/sdk.md#errors-and-limits);
do not automatically reset on error.

Opening, changing authentication, and resetting may invoke trusted OS/provider
UI. Record operations and `auth.list()` never prompt. There is no public
interaction option.

## Application identity

The production API accepts no application ID, path, provider, or store name.
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

See the [SDK guide](../../doc/sdk.md), [security policy](../../SECURITY.md), and
[V2 RFC](../../doc/rfcs/0001-per-application-stores.md).

Supported production profiles are iOS, Android 12+, macOS, and ordinary Linux
desktop. The Flatpak candidate uses sandbox identity, private ciphertext, and
XDG Secret Portal protection. Two-app isolation has passed for recorded native
Linux and nested Docker configurations; see the [qualification report](../../doc/qualification-status.md)
for source applicability and remaining gates. Reset retains the portal-owned application
secret, so an older complete encrypted backup can restore access. Flatpak never
falls back to ordinary Secret Service. Windows, Snap, and unsupported provider
configurations fail closed. MIT licensed.

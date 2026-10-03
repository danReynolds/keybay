# keybay

One encrypted, platform-protected local store for each Dart or Flutter host
application. No Flutter plugin, account, daemon, or network service.

Requires Dart 3.11 or later, including when used through Flutter.

Version 0.2.0 is prepared but not yet published. See
[release readiness](https://github.com/danReynolds/keybay/blob/main/doc/release-readiness.md)
for its scope and the separate CLI distribution gates.

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
protection cannot be bypassed; direct hardware passkeys use application-supplied
PIN, connection-selection and progress callbacks.

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
`authMethodAlreadyConfigured`; use `auth.update` to replace it. These are
alternative unlock methods on top of the mandatory platform root; configuring
both does not require the user to present both.

## Additional passkey protection

Use the same credential API for OS-provider passkeys and physical FIDO2 keys.
Configure the RP once and enroll explicitly on a new or platform-only store:

```dart
const systemPasskey = PasskeyCredential.system(
  rpId: 'vault.example.com',
  label: 'Personal vault',
);
final session = await Keybay.open();
try {
  await session.auth.add(systemPasskey);
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
    label: 'Backup security key',
    requestPin: ui.requestPin,
    selectConnection: ui.selectConnection,
    onEvent: ui.onHardwareEvent,
  ),
);
```

`ui` is your application's UI. PIN handlers return owned writable UTF-8 bytes;
selection handlers return one of the exact offered `HardwareConnection` objects.
Both receive cancellation signals. `HardwareEvent` reports instructions, not
authentication success. Missing PIN or ambiguous-connection UI produces a typed
failure; Keypass does not automatically retry PINs or switch credentials.

The RP ID is required explicitly and stays stable. System passkeys use the
app-associated domain; direct hardware uses a stable DNS-shaped scope without
requiring a website. It does not change Keybay's application identity or store.
`displayName` defaults to the RP ID; `label` defaults to `Keybay vault` and is used
when enrolling or replacing a method. Construction presents no UI.

Omit `methodId` when adding a passkey. Unlock
may omit it only when one method matches the requested RP ID and route;
otherwise select an exact stored ID. A passkey `auth.update` requires its
existing ID and preserves that Keybay ID while enrolling a replacement; the
replacement may deliberately use a different RP ID or route. Removing a method
preserves the others and does not delete its provider credential. Removing the
final additional method leaves platform-only protection.

`authRequired` and `authMethodSelectionRequired` errors can include
`KeybayException.authMethods` hints. These are not fully authenticated store
policy until unlock succeeds. Use them for choices, keep your expected RP
configuration, and use `session.auth.list()` after opening for authenticated
metadata. Passkey failures have `code == passkeyOperationFailed` and a redacted
`passkeyCode`; record and platform failures retain their own codes.

Keybay internally owns and clears Keypass results. Supply a fresh
`PasskeyCancellation` through the credential when an operation needs cancellation.
Do not abandon its Future or use `Future.timeout` alone: cancel, await settlement,
and close any session returned successfully, including after its initiating UI
has closed. Cancellation does not undo an already committed auth change.

Passkey access additionally needs [Keypass's native host setup](https://github.com/danReynolds/keypass/blob/main/doc/platforms.md):
linked libraries, signing, UI hosts and any device permissions. System-provider
Apple/Android apps also need their domain associations. Native packaging is
manual; the Dart dependency alone does not configure the host. The SDK remains
Flutter-free. See the [passkey guide](https://github.com/danReynolds/keybay/blob/main/doc/sdk.md#add-passkey-protection)
for exact selection/error rules and callbacks. The current checkout uses a pinned
Keypass Git dependency and requires repository access to resolve it.

Passkeys protect encryption material in addition to the platform root. Syncing
a passkey does not by itself make a Keybay store portable or provide a recovery
plan. Existing passphrase callers keep their API.

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

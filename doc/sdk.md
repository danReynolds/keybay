# Dart and Flutter SDK

[Architecture](architecture.md) · [Security policy](../SECURITY.md) ·
[Accepted V2 RFC](rfcs/0001-per-application-stores.md)

Keybay gives each host application one encrypted local store. The production
API has no application-ID, path, provider, or alternate-store selector.

Requires Dart 3.11 or later, including when used through Flutter. CI tests the
SDK at that floor with the reviewed dependency lockfile.

Version 0.2.0 is a breaking API and storage-format change from 0.1.x. V2 neither
reads nor migrates or removes V1 stores; do not expect an upgrade to carry old
secrets into the new store. See the [scoped release evidence](qualification-status.md#sdk-020-release-scope),
including deferred physical lifecycle work and Argon2 performance acceptance.

<a id="sdk-quickstart"></a>

## Open, use, close

```dart
import 'package:keybay/keybay.dart';

final session = await Keybay.open();
try {
  await session.set('service/api-token', 's3cr3t');

  final token = await session.get('service/api-token');
  final present = await session.contains('service/api-token');
  final names = await session.listKeys();

  await session.delete('service/api-token');
} finally {
  await session.close();
}
```

`open` initializes fully absent state. A retained platform root without its
complete encrypted file returns `storeStateConflict`; see [recovery](#errors-and-limits)
before integrating the quickstart. There is no separate create/configure step.
The session retains the recovered store key, not every record name or value.
`close` rejects new work, lets accepted work settle, and clears Keybay's
in-memory store-key buffer. Process exit also releases memory, but explicit
closure keeps the exposure window bounded in long-lived applications.

`Keybay.open()`, `session.auth.add/update/remove`, and `Keybay.reset()` may
invoke trusted OS or provider UI. Applications should call them from a context
that can accommodate that interaction. Record operations and `auth.list()`
never prompt or acquire the platform provider, including when an operation fails.
There is no public interaction option. Keybay does not collect a passphrase
through provider UI; the application supplies `PassphraseCredential` explicitly.

Strings are the default API. Binary callers use `getBytes` and `setBytes`.
`getManyBytes` authenticates one store generation and returns only the exact
requested records. `listKeys` decrypts the authenticated manifest but no record
values. Returned byte arrays belong to the caller.

`clearAll` removes all records but keeps the store and its protection policy.
Selector-free `Keybay.reset()` removes the current application's encrypted store,
staging, and deletable provider state, retaining nonsecret coordination locks.
Reset does not open or initialize a replacement store;
the next successful open generates a fresh store key. Flatpak retains the
portal-owned application secret, so restoring an older complete encrypted store
can restore access with the protection that applied to that snapshot.

## Application identity

iOS, Android, and entitled macOS applications use signed/package identity
facts established by the host platform. The Flatpak candidate uses the running
sandbox's `/.flatpak-info`, independently of a Dart namespace declaration.
Ordinary Dart programs on Linux and
unentitled macOS declare a stable namespace in the pubspec that owns their
entrypoint:

```yaml
keybay:
  application_id: com.example.my_app
```

The declaration is build metadata, not a runtime selector. It prevents
accidental collisions, but on an ordinary unsandboxed desktop it is not an
authorization boundary: another same-user program can declare the same value.
A passphrase is strongly recommended there for passwords and other high-value
credentials.

`dart run` can resolve the owning pubspec. Raw AOT executables cannot, so build
them through:

```sh
dart run keybay:keybay_compile bin/app.dart -o build/app
```

This validates the owning declaration and embeds it in the executable. Add
`--aot-snapshot` before the entrypoint to produce a separate native AOT module.
On macOS, the qualified hardened Developer ID form signs that module and its
dedicated `dartaotruntime` with the same team; see [macOS packaging](platforms/macos.md#hardened-aot-packaging).
Recognized `dart install` bundles retain their owning declaration, which Keybay
checks against any embedded declaration.

The desktop `package:test` runner uses a generated temporary entrypoint whose
owning application identity cannot be established. `Keybay.open()` there fails
closed with `applicationIdentityUnavailable`. Test your application's store
integration through a small declared `dart run` program or the appropriate
Flutter native integration runner. The SDK does not expose an identity override
for tests.

Flutter hosts also need the checked-in integration described by their platform
page, notably `KeybayApplicationIdentifier` in the processed iOS Info.plist.

## Add passphrase protection

Passphrases are additional to mandatory platform protection, never a
replacement for it. A store supports zero or one passphrase method.

```dart
import 'dart:convert';
import 'dart:typed_data';

final session = await Keybay.open();
try {
  final phrase = Uint8List.fromList(utf8.encode(userPassphrase));
  try {
    final method = await session.auth.add(
      PassphraseCredential(phrase: phrase),
    );
    print(method.id); // opaque identifier used for later removal
  } finally {
    phrase.fillRange(0, phrase.length, 0);
  }
} finally {
  await session.close();
}
```

The credential borrows caller-owned mutable bytes. Keybay snapshots them when
the operation is called and clears its copy when that operation settles; the
caller clears its original as soon as practical. Dart cannot guarantee that all
copies made by the VM, strings, or operating system are zeroed, so avoid
constructing passphrases as immutable Dart strings when the input layer can
produce bytes directly.

Once protected, a credential-free open fails with `authRequired`:

```dart
final phrase = await readPassphraseBytes();
final opening = Keybay.open(
  credential: PassphraseCredential(phrase: phrase),
);
phrase.fillRange(0, phrase.length, 0);

final session = await opening;
try {
  final token = await session.get('service/api-token');
} finally {
  await session.close();
}
```

Passphrase management occurs only through an authenticated session:

```dart
final methods = await session.auth.list();

await session.auth.update(
  PassphraseCredential(phrase: replacementPhraseBytes),
);

await session.auth.remove(methods.single.id);
```

`update` replaces the singleton passphrase method while retaining its opaque
method ID. `remove` takes an ID returned by `list`; this also scales to future
hardware methods that may have more than one configured instance.

## Errors and limits

Catch `KeybayException` and branch on `code`, not human-readable text. Important
codes include `authRequired`, `unlockFailed`, `platformProtectorUnavailable`,
`platformProtectorLocked`, `storeAuthenticationFailed`, `storeStateConflict`,
`storeBusy`, `staleSession`, and `sessionClosed`. Error strings never contain
record values, passphrases, provider state, or unrestricted paths.

`storeStateConflict` means the observed files/provider state cannot safely be
opened or initialized. A retained root without a complete file can occur after
an interrupted first initialization, or on iOS/entitled macOS if a reinstall or
same-device restore retains Keychain state while the excluded store file is
absent. It is not proof that reinstall occurred. When the application has
established that starting over is appropriate and accepts loss of any previous
local store, explicitly call `Keybay.reset()`, then reopen. Never automatically
reset every conflict or authentication failure. Physical reinstall/restore
qualification remains tracked in the [mobile procedures](mobile-failure-qualification.md).

A known local invalidation reports `staleSession`. Rotation in another process
or isolate may instead report `storeAuthenticationFailed`, as can damaged or
replaced data. An operation already running during a same-runtime rotation can
also report `storeAuthenticationFailed`; subsequent operations observe the local
invalidation and report `staleSession`. Close the old session and attempt an
authenticated reopen; keep a failed reopen as an error, not permission to erase
state.

Mutations use a one-second lock-acquisition deadline. Another operation may
hold the lock longer while provider UI or Argon2 completes. Retry `storeBusy`
with bounded backoff within your application's deadline; do not spin or treat
it as data loss.

Record keys use 1–120 ASCII characters in slash-separated segments matching
`[A-Za-z0-9][A-Za-z0-9._-]*`. Empty, `.` and `..` segments are invalid. A slash
organizes names; it does not create another store or protection domain.

## Platform summary

All supported profiles store one encrypted framed file and one small
platform-protected root per application:

| Host | Application boundary | File | Platform root |
|---|---|---|---|
| iOS | signed application group | app-private Application Support, excluded from backup | Data Protection Keychain, `WhenUnlockedThisDeviceOnly`, non-syncing |
| Android 12+ | package/UID sandbox | app-private `noBackupFilesDir` | one non-exportable Android Keystore AES-GCM key |
| entitled macOS | signed application group; file isolation depends on App Sandbox | app container or derived Application Support | Data Protection Keychain, exact signed group |
| unentitled macOS / CLI | declared namespace only | derived Application Support directory | one item in the explicit login Keychain |
| ordinary Linux desktop | declared namespace only | derived XDG data directory | one item in unlocked Secret Service |

The Flatpak candidate binds `/.flatpak-info` identity and its fixed private data
directory to the XDG Secret Portal. Its reusable secret is domain-separated into
Keybay's wrapping root. Native Linux evidence with two installed application IDs
has passed for the recorded GNOME configuration, as has the bounded nested
Docker lane. See the [qualification report](qualification-status.md) for source
applicability; these runs do not qualify every provider or permission set. A detected Flatpak never falls back to
ordinary Secret Service. Snap, Windows, and unsupported provider configurations
fail closed.

See the individual [iOS](platforms/ios.md), [Android](platforms/android.md),
[macOS](platforms/macos.md), and [Linux](platforms/linux.md) pages for the exact
guarantees and limitations.

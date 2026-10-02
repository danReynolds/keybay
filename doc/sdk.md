# Dart and Flutter SDK

[Architecture](architecture.md) · [Security policy](../SECURITY.md) ·
[Accepted V2 RFC](rfcs/0001-per-application-stores.md)

Keybay gives each host application one encrypted local store. The production
API has no application-ID, path, provider, or alternate-store selector.

Requires Dart 3.11 or later, including when used through Flutter. CI tests the
SDK at that floor with the reviewed dependency lockfile.

Version 0.2.0 is prepared but not yet published; see [release readiness](release-readiness.md).
It is a breaking API and storage-format change from 0.1.x. V2 neither
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
There is no option to bypass mandatory platform protection. The application
supplies passphrase bytes explicitly; direct hardware passkeys use the
application's PIN, connection-selection and progress callbacks.

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
Additional passphrase or physical-passkey protection is particularly useful
there: the desktop namespace alone does not prevent another same-user program
from reaching the platform root.

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
replacement for it. A store supports zero or one passphrase method alongside
multiple passkey methods. When both are configured, they are alternative ways
to unlock the same store; Keybay does not require both.

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

final passphrase = methods.whereType<PassphraseMethod>().single;
await session.auth.remove(passphrase.id);
```

`update` replaces the singleton passphrase method while retaining its opaque
method ID. `remove` takes an ID returned by `list` and removes only that method.
Other configured methods remain available. Removing the final additional
method deliberately returns the store to platform-only protection.

Adding, changing or removing passphrase protection rotates the store key and
re-encrypts every record. This protects the new generation; an older complete
snapshot remains subject to its original protection when the corresponding
platform material is available. Changing the vault passphrase does not revoke
an API token at its issuer or securely erase external backups.

## Add passkey protection

Passkeys supply additional encryption protection through
[Keypass](https://github.com/danReynolds/keypass). Keybay owns the Keypass client,
temporary secret, key derivation, encrypted method envelopes and their
authenticated persistence. Applications use the same `Keybay.open` and
`session.auth` API as for passphrases; they do not handle a `PasskeyResult`.

To initialize an absent store with an OS-provider passkey, or reopen a store
that already has a matching method:

```dart
final session = await Keybay.open(
  credential: const PasskeyCredential.system(
    rpId: 'vault.example.com',
    label: 'Personal vault',
  ),
);
try {
  await session.set('service/api-token', 's3cr3t');
} finally {
  await session.close();
}
```

An existing platform-only or passphrase-only store does not gain a passkey
through `open`. Open it using its current protection, then explicitly add one:

```dart
final method = await session.auth.add(
  const PasskeyCredential.system(
    rpId: 'vault.example.com',
    label: 'Personal vault',
  ),
);
```

For direct physical FIDO2 keys, use the hardware constructor:

```dart
final backup = await session.auth.add(
  PasskeyCredential.hardware(
    rpId: 'dev.example.vault',
    label: 'Backup security key',
    requestPin: ui.requestPin,
    selectConnection: ui.selectConnection,
    onEvent: ui.onHardwareEvent,
  ),
);
```

Here `ui` represents your application's UI, not a Keybay helper object.
Both credential constructors contain request/configuration metadata only;
construction opens no device and presents no dialog.

| Field | Contract |
| --- | --- |
| `rpId` | Required, stable relying-party identifier. Use the app-associated domain for the system route, or a stable DNS-shaped identifier for direct hardware. Matching is case-insensitive. |
| `displayName` | Optional provider presentation text; defaults to the RP ID. |
| `label` | Enrollment/replacement label; defaults to `Keybay vault`. It does not select a method during unlock. |
| `methodId` | Exact stored Keybay method to unlock or replace. Omit for adding a method or initializing an absent store. |
| `cancellation` | Optional `PasskeyCancellation` for this operation. Use a fresh signal for each attempt. |

The RP ID must be supplied explicitly. It is neither an API endpoint nor a
replacement for `keybay.application_id`. It does not select another Keybay
store, change the host application identity or weaken platform protection.
Existing credentials retain their original RP ID and route; no automatic scope
migration occurs. Choosing the same RP ID for both routes does not make two
separately created credentials interchangeable.

The hardware constructor also accepts these optional handlers:

| Handler | Behavior |
| --- | --- |
| `requestPin` | Receives `HardwarePinRequest` and a cancellation signal. Return owned, writable UTF-8 PIN bytes, or `null` to cancel. Keypass clears those bytes, including late replies. Without a handler, a key needing application PIN entry fails with `pinRequired`. |
| `selectConnection` | Receives offered `HardwareConnection` objects and cancellation. Return one of those exact objects, or `null` to cancel. A sole connection is selected automatically; multiple connections without a handler fail with `deviceSelectionRequired`. |
| `onEvent` | Receives informational `HardwareEvent.touchRequired` or `HardwareEvent.presentKey` instructions. These events do not establish authentication. |

A connection can be a USB candidate or NFC reader; a reader does not prove that
a key is present. Selection belongs to the current operation. Do not cache its
object for the next call. Close PIN and selection UI when its cancellation
signal fires. Keypass never automatically retries a rejected PIN, resets a key,
or switches to a weaker or different credential.

Read any vault data needed by your UI before starting the auth operation.
Calling Keybay from its hardware callbacks (including `close` or `reset`)
fails promptly with `storeBusy`; waiting on the operation that is waiting on
your callback would otherwise deadlock. Ordinary callers outside the callback
can continue using other sessions while enrollment is pending. Auth changes
recheck the package before committing and preserve intervening record writes.

### Select and manage methods

`session.auth.list()` returns fully authenticated `PassphraseMethod` and
`PasskeyMethod` entries without prompting. A passkey entry exposes its stable
Keybay `id`, `rpId`, `route` and `label`; credential records and key material
remain internal.

For `Keybay.open(credential: PasskeyCredential...)` on a methods-package store
(platform-only and legacy passphrase stores first reject passkey requests with
`protectionMismatch`):

| Request | Behavior before a passkey prompt |
| --- | --- |
| Explicit `methodId` exists and matches the requested RP ID and route | Unlock exactly that method. |
| Explicit `methodId` does not exist | `authMethodNotConfigured`. |
| Explicit ID names a different kind, RP ID or route | `protectionMismatch`. |
| No ID and exactly one matching passkey exists | Unlock that method. |
| No ID and no matching passkey exists | `protectionMismatch`; do not enroll over the existing policy. |
| No ID and several matching passkeys exist | `authMethodSelectionRequired` with compatible method hints. |

Keybay does not try every credential until one works. On ambiguity, let the
user choose a method ID and retry using your application's expected RP ID and
route. `label` and `displayName` are not selectors.

`auth.add` enrolls an additional passkey and requires `methodId` to be omitted.
An absent-store initialization has the same requirement. `auth.update` requires
the exact ID of an existing `PasskeyMethod`, enrolls its replacement, and retains
the Keybay method ID. It can deliberately change that method's RP ID or route:

```dart
await session.auth.update(
  PasskeyCredential.hardware(
    rpId: 'dev.example.vault',
    methodId: backup.id,
    label: 'Replacement backup key',
    requestPin: ui.requestPin,
    selectConnection: ui.selectConnection,
    onEvent: ui.onHardwareEvent,
  ),
);

await session.auth.remove(backup.id);
```

Providing an ID to `add` or omitting it from a passkey `update` is
`invalidAuthInput`. Passphrase `update` continues to replace the singleton
passphrase method without an ID. An update is an explicit enrollment operation,
not an attempt to unlock the replacement using the old credential.

Adding, replacing or removing a method updates the encrypted policy atomically
and rotates protection for the new store generation while retaining other
configured methods. A failure before atomic replacement leaves the previous
usable policy intact. An I/O failure reported after replacement can leave the
new policy committed: reopen and inspect before retrying a mutation. A provider
may still retain a newly created passkey if the later transaction fails.
Removing a Keybay method does not delete the
provider's passkey or make older copied snapshots undecryptable.

### Authentication errors and hints

When additional protection exists, a credential-free open returns
`authRequired` without invoking a passkey prompt. Opening the mandatory platform
root may still require its normal OS interaction.

`KeybayException.authMethods` contains method-selection hints for
`authRequired` and `authMethodSelectionRequired`. The platform package has been
authenticated, but these hints are **not trusted as fully authenticated store
policy until a method unlocks successfully**. They may help display choices;
do not use them to grant access, change protection or replace your application's
expected RP configuration. After opening, use `session.auth.list()` for the
authenticated method list.

Keypass failures report `KeybayErrorCode.passkeyOperationFailed` with a
redacted `KeybayException.passkeyCode`. For example:

```dart
try {
  await session.auth.add(
    const PasskeyCredential.system(rpId: 'vault.example.com'),
  );
} on KeybayException catch (error) {
  if (error.code == KeybayErrorCode.passkeyOperationFailed &&
      error.passkeyCode == PasskeyErrorCode.cancelled) {
    // The user canceled the passkey interaction.
  } else {
    rethrow;
  }
}
```

Other passkey details distinguish missing native hosts, unsupported PRF,
unavailable credentials, rejected/blocked PINs and verification failures.
They contain no raw provider response or secret. An unavailable passkey does
not authorize trying a passphrase automatically; the application may offer an
independently configured method for the user to choose.

### Cancellation and native setup

Always await `open` and authentication-management operations to settlement.
Abandoning their Futures or calling `Future.timeout` alone neither cancels
native work nor closes a session returned later.

```dart
final cancellation = PasskeyCancellation();
final opening = Keybay.open(
  credential: PasskeyCredential.system(
    rpId: 'vault.example.com',
    cancellation: cancellation,
  ),
);
// Connect a Cancel control to cancellation.cancel().
final session = await opening;
try {
  // Use the authenticated session, or close it if its initiating UI has gone.
} finally {
  await session.close();
}
```

Keep cleanup running if the initiating screen closes: cancel the signal, await
the original Future, and close any successful session. Keybay clears its own
Keypass result and temporary derived material. Your PIN-input copies and
returned record values remain your responsibility. Cancellation does not undo
an already committed authentication change.

Passkey support needs [Keypass's manual native host setup](https://github.com/danReynolds/keypass/blob/main/doc/platforms.md)
in addition to Keybay's platform integration. Adding the Dart dependency does
not link native libraries, configure signing or grant permissions.

- System passkeys use the OS provider dialog. Apple apps need their associated
  domain/AASA and native host; Android apps need Digital Asset Links and the
  native Activity integration.
- Direct desktop hardware uses the packaged USB adapter. Phone hardware uses
  the corresponding NFC/USB adapter and permissions. This direct route requires
  no hosted website, AASA, Digital Asset Links or Keypass API key.
- Native window/Activity discovery, supported transports and provider PRF
  capability still apply. Follow Keypass's platform matrix; its deferred
  qualifications are not blanket support claims.

The SDK has no Flutter dependency; Flutter can be a native application host.
Passkeys remain additional to Keybay's mandatory platform root. A synced
passkey does not by itself make the encrypted Keybay store portable to a new
device, and successful authentication does not imply a backup/recovery policy.
Once open, record operations and `auth.list()` remain prompt-free.

## Errors and limits

Catch `KeybayException` and branch on `code`, not human-readable text. Important
codes include `authRequired`, `authMethodSelectionRequired`,
`passkeyOperationFailed`, `unlockFailed`, `platformProtectorUnavailable`,
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

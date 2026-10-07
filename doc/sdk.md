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

Credential-free `open()` initializes fully absent state with platform protection.
`open(credential: ...)` only authenticates an existing store: it never enrolls
protection, even on first use or after reset. A missing encrypted file returns
`storeNotFound` before accessing a credential provider or creating a platform
root. Use an authenticated session's `auth.add` to enroll protection before
writing records that should require it.

A retained platform root without its complete encrypted file makes
credential-free initialization return `storeStateConflict`; see
[recovery](#errors-and-limits). There is no separate create/configure step.
The session retains the recovered store key, not every record name or value.
`close` rejects new work, lets accepted work settle, and clears Keybay's
in-memory store-key buffer. Process exit also releases memory, but explicit
closure keeps the exposure window bounded in long-lived applications.

`Keybay.open()`, `session.auth.add/remove`, and `Keybay.reset()` may
invoke trusted OS or provider UI. Applications should call them from a context
that can accommodate that interaction. Record operations and `auth.list()`
never prompt or acquire the platform provider, including when an operation fails.
There is no option to bypass mandatory platform protection. The application
supplies passphrase bytes explicitly; direct hardware passkeys use the
application's supplied PIN bytes. Credential objects have no UI callbacks;
missing PINs and ambiguous connections return typed errors for the application
to handle.

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
    print(method.id); // Nonsecret enrollment identifier; remove accepts method.
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
final passphrase = methods.whereType<PassphraseMethod>().single;
await session.auth.remove(passphrase);

// A different passphrase is a new enrollment with a new ID.
await session.auth.add(
  PassphraseCredential(phrase: newPhraseBytes),
);
```

Auth management consists of `add`, `list`, and `remove`. There is no `update`
or `replace`. Removing and adding are separate commits. To change a passphrase,
remove the current one before adding another. If it was the only method, the
vault uses platform-only protection between those calls and stays that way if
adding fails. Other enrolled methods remain available.

Adding or removing protection rotates the store key and re-encrypts every
record. This protects the new generation; an older complete snapshot retains
its original protection when the corresponding platform material is available.
Removing an unlock method does not revoke API tokens at their issuers or erase
external backups.

## Add passkey protection

Passkeys supply additional encryption protection through
[Keypass](https://github.com/danReynolds/keypass). Keybay owns the Keypass client,
temporary secret, derivation, encrypted method envelopes and their authenticated
persistence. Applications never handle a `PasskeyResult` or saved Keypass record.

Credentials contain authentication input. Constructing one opens no device or
provider UI. System credentials can be reused as immutable configuration:

```dart
const systemPasskey = PasskeyCredential.system(
  rpId: 'vault.example.com',
);

final session = await Keybay.open();
try {
  await session.auth.add(systemPasskey, label: 'Personal vault');
  await session.set('service/api-token', 's3cr3t');
} finally {
  await session.close();
}
```

For an already protected store, first open it with its existing credential.
Await enrollment before writing data that should require the new protection.
On a later run, authenticate with the existing enrollment:

```dart
final session = await Keybay.open(credential: systemPasskey);
try {
  final token = await session.get('service/api-token');
} finally {
  await session.close();
}
```

Opening never creates a passkey. A missing encrypted file produces
`storeNotFound` before platform-root access or a passkey ceremony.

For physical FIDO2 keys, provide an optional PIN as UTF-8 bytes:

```dart
final pin = await readHardwarePinBytes(); // Your app's input UI.
final adding = session.auth.add(
  PasskeyCredential.hardware(
    rpId: 'dev.example.vault',
    pin: pin,
  ),
  label: 'Backup key',
);
pin.fillRange(0, pin.length, 0);
final backup = await adding;
```

Keybay snapshots PIN bytes synchronously, as it does passphrases, and clears
its copy when the ceremony finishes or the operation fails. It never saves the
PIN in an enrollment. The caller remains responsible for clearing its own copy.
The optional PIN must contain 4–63 UTF-8 bytes with no NUL; the authenticator
applies its own PIN policy. Omit it when the platform/key supplies user
verification itself. A key requiring application PIN entry then returns
`passkeyOperationFailed` with `passkeyCode == pinRequired`. The app can ask for
input and deliberately retry; rejected PINs are never retried automatically.

| Credential field | Contract |
| --- | --- |
| `rpId` | Required relying-party scope. Use the associated domain for system passkeys, or a stable DNS-shaped identifier for direct hardware. |
| `displayName` | Optional provider presentation text, defaulting to the RP ID. |
| `pin` | Hardware-only, optional caller-owned UTF-8 bytes for this attempt. |

The RP ID is not an endpoint, a Keybay store selector, or a replacement for
`keybay.application_id`. Direct hardware access needs no hosted website and
makes no claim to authenticate the calling executable. Using the same RP ID
for two routes does not make separately enrolled credentials interchangeable.

There are no PIN prompts, connection pickers, or event callbacks in a Keybay
credential. The app owns input and progress UI. Direct hardware discovery
selects a sole connection; multiple candidates report `deviceSelectionRequired`.
Disconnect other keys/readers before retrying. Advanced connection selection
and event handling remain available in Keypass itself.

### Select and manage methods

The accepted consumer surface is:

```dart
Keybay.open(credential: credential, methodId: selectedId);
session.auth.add(credential, label: 'Everyday key');
session.auth.list();
session.auth.remove(method);
```

`methodId` is optional on `open`. Labels are optional on `add`, defaulting to
`Passphrase` or `Keybay vault`. Both `open` and `add` accept an optional
`PasskeyCancellation` for passkey attempts; neither stores it in the credential.

Protection remains `platform AND (passphrase OR passkey A OR passkey B ...)`.
A store supports zero or one passphrase and multiple passkeys, up to eight total
methods. Adding a second passphrase fails with `authMethodAlreadyConfigured`.
Every successful add creates a new opaque method ID; adding never overwrites
an enrollment.

`auth.list()` returns immutable, fully authenticated descriptors without
prompting. Every method exposes `id` and `label`. A `PasskeyMethod` also exposes
`rpId` and `route`. Descriptors contain no credential material. They can be
passed directly to `remove`, including after reopening the same vault:

```dart
final methods = await session.auth.list();
final selected = await chooseMethod(methods); // Your app's selection UI.
await session.auth.remove(selected);
```

Removal validates both vault identity and method ID. A method from another
vault, a reset vault, or an already removed enrollment fails with
`authMethodNotConfigured`. Object instance identity is irrelevant. Removing
the last method deliberately returns the store to platform-only protection.

For passkey unlock, `methodId` selects among this vault's enrolled methods:

| Request | Behavior before a passkey prompt |
| --- | --- |
| Explicit ID exists and matches kind, RP ID and route | Unlock exactly that method. |
| Explicit ID does not exist | `authMethodNotConfigured`. |
| Explicit ID names a different kind, RP ID or route | `protectionMismatch`. |
| No ID and one matching method exists | Unlock that method. |
| No ID and no matching method exists | `protectionMismatch`. |
| No ID and several matching methods exist | `authMethodSelectionRequired` with compatible hints. |

```dart
final session = await Keybay.open(
  credential: PasskeyCredential.hardware(
    rpId: 'dev.example.vault',
    pin: enteredPinBytes,
  ),
  methodId: backup.id,
);
```

The RP ID scopes credentials; it is not a unique passkey identifier. Keybay
loads the selected enrollment's internal record to request that exact passkey.
It never tries every credential until one works. Labels and display names do
not select methods. The application retains its expected RP configuration.

To swap hardware keys, add the new key before removing the old enrollment:

```dart
final next = await session.auth.add(
  PasskeyCredential.hardware(rpId: 'dev.example.vault', pin: newKeyPinBytes),
  label: 'New everyday key',
);
await session.auth.remove(backup);
```

During these two commits, both keys are enrolled. If removal fails, the old
method may still be enrolled; inspect the list before retrying. At the method
limit, an enrollment must be removed before another can be added.

Each add or remove atomically commits its own encrypted policy and rotated
store generation. An I/O failure reported after file replacement can leave
that operation committed: reopen and inspect before retrying. Provider
registration may leave a newly created passkey behind if local persistence
fails. Removing a Keybay method does not delete the provider's passkey or make
older complete snapshots undecryptable.

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
  ),
  cancellation: cancellation,
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

Desktop Dart execution uses [Keypass's build hook](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md).
The build host needs its documented compiler and native-library development
prerequisites even when the application only uses passphrase protection. Build
on the target OS and architecture; desktop cross compilation is not supported
by this hook. Distributable applications must retain the full native bundle
and notices so end users need no compiler. Flutter desktop packaging remains
separately qualified; the hook alone does not establish that integration.

System and mobile passkey support needs [Keypass's manual native host setup](https://github.com/danReynolds/keypass/blob/main/doc/platforms.md)
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
codes include `storeNotFound`, `authRequired`, `authMethodSelectionRequired`,
`passkeyOperationFailed`, `unlockFailed`, `platformProtectorUnavailable`,
`platformProtectorLocked`, `storeAuthenticationFailed`, `storeStateConflict`,
`storeBusy`, `staleSession`, and `sessionClosed`. Error strings never contain
record values, passphrases, provider state, or unrestricted paths.

`storeNotFound` means a credential-based open found no live encrypted file
(and no incomplete staging state). No method was enrolled, no root was created
or acquired, and no passphrase was derived. This does not prove that the
platform root is absent. Do not automatically treat a failed unlock as permission
to initialize or reset; make first-use setup an explicit application flow.

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

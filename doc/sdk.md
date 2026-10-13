# Dart and Flutter SDK

Keybay gives each host application one encrypted local store. Requires Dart
3.11+; Flutter is an optional native host, not an SDK dependency.

[Security](../SECURITY.md) · [Architecture](architecture.md) ·
[Passkey construction](rfcs/0003-passkey-methods.md) · [External review](external-review.md)

**Format compatibility:** V1 stores are not read, migrated or deleted. Current
source also rejects retired V2 singleton-passphrase packages; published 0.2.0
retains that conversion. Current methods-based and platform-only encodings are
unchanged. See [release readiness](release-readiness.md) before upgrading.

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

- `open()` initializes fully absent state with platform protection.
- `open(credential: ...)` authenticates an existing store; it never enrolls.
  With no live file or staging state, it returns `storeNotFound` before platform
  or credential access. Enroll through `session.auth.add` before writing values
  that should require the added protection.
- A retained platform root without a complete file returns `storeStateConflict`
  on initialization. Do not automatically reset; see [recovery](#errors-and-limits).
- `close()` rejects new work, drains accepted operations and clears the owned
  store-key buffer. Keep sessions open only as long as needed.

Open, auth changes and reset may invoke trusted provider UI. Record operations
and `auth.list()` never prompt or acquire a provider, even on failure.

| Operation | Behavior |
| --- | --- |
| `get` / `set` | String values. |
| `getBytes` / `setBytes` | Binary values; returned buffers belong to the caller. |
| `getManyBytes` | Exact requested records from one authenticated generation. |
| `listKeys` | Authenticated names without decrypting record values. |
| `clearAll` | Remove records, keep protection. |
| `Keybay.reset()` | Delete current store, staging and deletable provider state; retain coordination locks. |

Reset does not initialize a replacement. The next open creates a fresh store key.
Flatpak retains its portal secret; restoring an old complete snapshot can restore
access under that snapshot's policy.

## Application identity

The API has no application-ID, path, provider or store selector. iOS, Android and
entitled macOS use platform-authenticated identity. Flatpak uses sandbox facts
from `/.flatpak-info`. Ordinary Dart executables on Linux and unentitled macOS
declare a stable namespace in the pubspec owning their entrypoint:

```yaml
keybay:
  application_id: com.example.my_app
```

This prevents accidental collisions, not access by another same-user program.
Additional passphrase or hardware protection makes platform/file access alone
insufficient.

`dart run` resolves the owning pubspec. Embed the declaration for AOT builds:

```sh
dart run keybay:keybay_compile bin/app.dart -o build/app
```

Use `--aot-snapshot` before the entrypoint for a separate AOT module. Hardened
macOS distribution signs that module and a dedicated `dartaotruntime` with the
same team; see [macOS packaging](platforms/macos.md#hardened-aot-packaging).
Recognized `dart install` bundles retain their declaration, checked against any
embedded value.

The generated desktop `package:test` entrypoint has no resolvable application
identity and fails with `applicationIdentityUnavailable`. Use a declared
`dart run` integration program or native Flutter runner; there is no test override.
Flutter hosts also need platform integration, including
`KeybayApplicationIdentifier` in the processed iOS Info.plist.

## Add passphrase protection

Protection is `platform AND (passphrase OR passkey A OR passkey B ...)`.
A store allows one passphrase and eight total methods. Adding a second
passphrase fails with `authMethodAlreadyConfigured`.

```dart
final session = await Keybay.open();
try {
  final phrase = await readPassphraseBytes(); // Your app's input UI.
  final adding = session.auth.add(PassphraseCredential(phrase: phrase));
  phrase.fillRange(0, phrase.length, 0);
  final method = await adding;
} finally {
  await session.close();
}
```

Operations synchronously copy caller-owned passphrase/PIN bytes and clear that
copy when they settle. Clear your input buffers after submitting the call.
Prefer bytes from your input layer: immutable Dart strings and VM/OS copies
cannot be reliably erased.

After enrollment, credential-free open returns `authRequired`. To reopen:

```dart
final phrase = await readPassphraseBytes();
final opening = Keybay.open(credential: PassphraseCredential(phrase: phrase));
phrase.fillRange(0, phrase.length, 0);
final session = await opening;
try {
  final token = await session.get('service/api-token');
} finally {
  await session.close();
}
```

To change a passphrase, remove the old method and add a new one:

```dart
final methods = await session.auth.list();
await session.auth.remove(methods.whereType<PassphraseMethod>().single);
await session.auth.add(PassphraseCredential(phrase: newPhraseBytes));
```

These are separate commits. **Removing the last method returns to platform-only
protection**, which persists if adding fails. There is no update/replace.
Auth changes rotate the store key and re-encrypt records; they do not revoke
older snapshots, issuer tokens or external backups. To fully revoke a
compromised credential on Linux or unentitled macOS, remove every method and
add back the trusted ones; see
[security levels](security-levels.md#after-a-credential-is-compromised).

## Add passkey protection

Keybay owns the [Keypass](https://github.com/danReynolds/keypass) client, temporary
secret, derivation and authenticated records. Your app supplies credential data
and UI; constructing a credential does not start a ceremony.

```dart
const systemPasskey = PasskeyCredential.system(rpId: 'vault.example.com');
final session = await Keybay.open();
try {
  await session.auth.add(systemPasskey, label: 'Personal vault');
  await session.set('service/api-token', 's3cr3t');
} finally {
  await session.close();
}
```

For an already protected store, open with its existing credential first.
Later, `Keybay.open(credential: systemPasskey)` authenticates the saved method;
opening never creates a passkey.

For a physical FIDO2 key:

```dart
final pin = await readHardwarePinBytes();
final adding = session.auth.add(
  PasskeyCredential.hardware(rpId: 'dev.example.vault', pin: pin),
  label: 'Backup key',
);
pin.fillRange(0, pin.length, 0);
final backup = await adding;
```

| Credential field | Meaning |
| --- | --- |
| `rpId` | Required scope: associated domain for system passkeys, stable DNS-shaped namespace for direct hardware. |
| `displayName` | Optional provider text; defaults to the RP ID. |
| `pin` | Hardware-only UTF-8 bytes for this attempt; optional, never persisted. |

The RP ID is not an endpoint, unique credential ID or Keybay application ID.
Direct hardware needs no website and does not authenticate the calling
executable. Matching RP IDs do not make separate enrollments interchangeable.

A supplied PIN must be 4–63 UTF-8 bytes with no NUL; the key also applies its
own policy. Omit it if verification happens on the key/platform. When a PIN is
needed, Keybay returns `passkeyOperationFailed` with `passkeyCode == pinRequired`.
Ask for input and retry deliberately; rejected PINs are never retried automatically.

Credentials have no callbacks. A sole hardware connection is selected;
multiple candidates return `deviceSelectionRequired`. Disconnect other keys or
readers before retrying. Keypass itself supports richer connection/event UI.

### Select and manage methods

```dart
Keybay.open(credential: credential, methodId: selectedId);
session.auth.add(credential, label: 'Everyday key');
session.auth.list();
session.auth.remove(method);
```

Every add creates a fresh method ID. Optional labels default to `Passphrase`
or `Keybay vault`. `auth.list()` returns immutable, authenticated descriptors
with `id` and `label`; `PasskeyMethod` also has `rpId` and `route`.
Descriptors contain no credential material and can be removed after reopening
that same vault:

```dart
final methods = await session.auth.list();
final selected = await chooseMethod(methods); // Your app's selection UI.
await session.auth.remove(selected);
```

Removal checks vault identity and method ID, not object identity. Foreign,
reset-vault and already removed descriptors return `authMethodNotConfigured`.
Removing the last method leaves platform-only protection.

For passkey unlock, selection happens before prompting:

| Request | Result |
| --- | --- |
| Explicit ID matches kind, RP ID and route | Unlock exactly that method. |
| Explicit ID is absent | `authMethodNotConfigured`. |
| Explicit ID has another kind, RP ID or route | `protectionMismatch`. |
| No ID; one matching method | Unlock it. |
| No ID; no matching method | `protectionMismatch`. |
| No ID; several matching methods | `authMethodSelectionRequired` with compatible hints. |

```dart
final session = await Keybay.open(
  credential: PasskeyCredential.hardware(
    rpId: 'dev.example.vault',
    pin: enteredPinBytes,
  ),
  methodId: backup.id,
);
```

Keybay requests the selected record's exact credential. It does not try every
passkey, and labels do not select methods. Keep your expected RP configuration
in the application.

For replacement keys, add before removing when capacity allows:

```dart
await session.auth.add(
  PasskeyCredential.hardware(rpId: 'dev.example.vault', pin: newKeyPinBytes),
  label: 'New everyday key',
);
await session.auth.remove(backup);
```

Each auth change commits independently. An I/O error after file replacement may
mean it committed: reopen and inspect before retrying. Registration can leave
an orphan provider credential if local persistence fails. Removal does not
delete a provider credential or revoke older snapshots.

### Authentication errors and hints

Catch `KeybayException` and branch on `code`, not message text.
Credential-free open of a protected store returns `authRequired` without a
passkey ceremony, though platform-root access may invoke OS UI.

`authRequired` and `authMethodSelectionRequired` can carry `authMethods` hints.
These are authenticated by the platform package, **not yet by the store's
credential-protected manifest**. Use them for display/selection only, never to
grant access, change policy or replace expected RP configuration. After opening,
`auth.list()` supplies the authenticated list.

Passkey failures use `passkeyOperationFailed` and a redacted `passkeyCode`,
including `cancelled`, missing host/PRF/credential, PIN errors and verification
failure. They do not expose raw provider data or secrets. Failure does not
trigger fallback; offer another enrolled method for the user to choose.

### Cancellation and native setup

`open` and `auth.add` accept an optional `PasskeyCancellation`:

```dart
final cancellation = PasskeyCancellation();
final opening = Keybay.open(
  credential: const PasskeyCredential.system(rpId: 'vault.example.com'),
  cancellation: cancellation,
);
// Connect a Cancel control to cancellation.cancel().
final session = await opening;
try {
  // Use the session, or close it if the initiating screen has gone.
} finally {
  await session.close();
}
```

Cancel, await settlement and close any successful session even if its screen
has gone. `Future.timeout` alone does not cancel native work. Cancellation
cannot undo an already committed auth change. Keybay clears its temporary
Keypass/derived material; your input copies and returned values remain yours.

Desktop Dart builds use [Keypass build hooks](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md).
Install their native build prerequisites even for passphrase-only apps. Build
on the target OS/architecture and distribute the complete bundle and notices.
The hook does not qualify Flutter desktop packaging.

[Keypass native setup](https://github.com/danReynolds/keypass/blob/main/doc/platforms.md)
is additional to Keybay's platform setup:

- System: Apple associated domain/AASA and native host; Android Digital Asset
  Links and Activity integration. The OS presents the provider dialog.
- Hardware: desktop USB adapter or phone NFC/USB adapter and permissions.
  No website, association file or Keypass API key.

Support depends on the native host, transport and provider's PRF capability.
A Dart dependency alone cannot configure signing, libraries or permissions.
Passkeys do not replace the platform root or make vaults portable by themselves.

## Errors and limits

| Error | Response |
| --- | --- |
| `storeNotFound` | Credential-based open found no live file or staging state. No provider/root access or enrollment occurred; a root may still exist. Offer explicit first-use setup. |
| `storeStateConflict` | Files/provider state cannot safely open or initialize. Investigate; reset only when deliberate data loss is acceptable. |
| `staleSession` / `storeAuthenticationFailed` | Close and attempt authenticated reopen. Failure is not permission to erase state. |
| `storeBusy` | Retry with bounded backoff within the application's deadline. |
| `sessionClosed` | Open a new session. |

A retained root after interrupted initialization or an Apple reinstall/restore
can cause `storeStateConflict`; the error does not prove its cause. Deliberate
recovery is `Keybay.reset()` followed by open. Never reset automatically on
conflict or authentication failure. [Physical restore qualification](mobile-failure-qualification.md)
remains incomplete.

Local invalidation reports `staleSession`. Cross-process rotation, an operation
already running during rotation, or damaged/replaced data may instead report
`storeAuthenticationFailed`. Locks have a one-second acquisition deadline;
provider UI or Argon2 may hold them longer.

Keys are 1–120 ASCII characters in slash-separated segments matching
`[A-Za-z0-9][A-Za-z0-9._-]*`; empty, `.` and `..` segments are invalid.
Slashes organize names, not security domains.

## Platform summary

| Host | Application boundary | File | Platform root |
|---|---|---|---|
| iOS | signed application group | app-private Application Support, excluded from backup | Data Protection Keychain, `WhenUnlockedThisDeviceOnly`, non-syncing |
| Android 12+ | package/UID sandbox | app-private `noBackupFilesDir` | one non-exportable Android Keystore AES-GCM key |
| entitled macOS | signed application group; file isolation depends on App Sandbox | app container or derived Application Support | Data Protection Keychain, exact signed group |
| unentitled macOS / CLI | declared namespace only | derived Application Support directory | one item in the explicit login Keychain |
| ordinary Linux desktop | declared namespace only | derived XDG data directory | one item in unlocked Secret Service |

See [iOS](platforms/ios.md), [Android](platforms/android.md),
[macOS](platforms/macos.md) and [Linux](platforms/linux.md) for setup.
The Flatpak candidate uses sandbox identity and XDG Secret Portal; it never
falls back to Secret Service. Snap, Windows and unsupported providers fail
closed. The [qualification report](qualification-status.md) records observed
configurations and remaining work.

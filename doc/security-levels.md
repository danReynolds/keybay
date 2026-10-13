# Security levels by platform

Keybay keeps an application's secrets, such as API tokens and passwords, on
the device. This page explains how well those secrets are protected on each
platform, who could read them, and what adding a passphrase or passkey changes.
[Architecture](architecture.md) explains the mechanics in more detail.

## How a vault is protected

Each application that uses Keybay, including the Keybay CLI, gets one **vault**:
a single encrypted file holding all of that application's secrets. Two layers
protect it.

1. **The platform root.** A key held by the operating system's own key store:
   the Keychain on Apple platforms, the Keystore on Android, or the Secret
   Service keyring on Linux. The vault file cannot be decrypted without it, so
   a copy of the file on its own reveals nothing. This layer is always present.
2. **Methods (optional).** A passphrase, or passkeys such as a phone passkey or
   a hardware security key. Once you enroll one, opening the vault needs the
   platform root *and* one of your methods.

The vault file itself is encrypted the same way everywhere. What differs
between platforms is how strictly the operating system guards the platform
root: whether it checks *which application* is asking before handing it over.

## Security classes

| Class | What the operating system checks | What that means |
| --- | --- | --- |
| **App-bound** | The requesting application's identity: its code signature, installed package, or sandbox ID. | Only your application can obtain the platform root. Other apps on the device are refused, even ones running as you. |
| **Account-level** | Only that the request comes from your user account. | Programs running as you can obtain the platform root, on macOS after a Keychain prompt and on Linux silently. The application's declared name organizes the vault but does not protect it. |

Key protection and file isolation are separate questions. An app-bound key
stops other programs decrypting the vault, but whether they can see or delete
the encrypted file depends on whether the application is sandboxed.

## Per platform

| Platform | Class | How the platform root is guarded | Where the vault file lives |
| --- | --- | --- | --- |
| iOS | App-bound | A Data Protection Keychain item in an access group tied to the app's signed identifier. Usable only while the device is unlocked, never synced or backed up. | The app's private container, excluded from backups. |
| Android 12+ | App-bound | A non-exportable AES key generated inside Android Keystore: in StrongBox or the TEE where the device provides them, otherwise in software. The OS ties it to the app's user ID. | The app's private no-backup directory. |
| macOS app, entitled | App-bound | A Data Protection Keychain item in the app's signed access group, device-only and never synced. | The App Sandbox container if sandboxed. Otherwise a private folder in `~/Library/Application Support`, which other programs running as you can read or delete. |
| macOS app, unentitled | Account-level | An item in your login Keychain whose access list trusts the app's code signature. Another program reading it directly triggers the "allow access" prompt, but any program can still run the app itself. | A private folder in `~/Library/Application Support`. |
| macOS CLI | Account-level | The same login-Keychain item, trusting the signed `keybay` binary. Any program running as you can run `keybay` itself, which reaches the item without a prompt. | A private folder in `~/Library/Application Support`. |
| Linux desktop | Account-level | An item in your Secret Service keyring (GNOME Keyring or KWallet). Any program in your session can read it over D-Bus while the keyring is unlocked, with no per-app check. | A private folder in `~/.local/share` (or `$XDG_DATA_HOME`). |
| Flatpak app (candidate) | App-bound against other sandboxed apps; account-level against unsandboxed programs | A per-app secret from the XDG Secret Portal, which identifies the sandboxed app by its Flatpak ID. With GNOME Keyring the portal stores that secret as an ordinary keyring item, so unsandboxed programs running as you can read it. | `~/.var/app/<app-id>/data/keybay-v2`. |

"Private folder" means directories created `0700` and files `0600`, opened
without following symbolic links. That keeps other user accounts out, not
programs running as you.

## Who can read your secrets

With platform protection only, meaning no passphrase or passkey:

| Platform | Other user accounts | Copied files and backups | Other programs running as you | Someone using your unlocked device or account |
| --- | --- | --- | --- | --- |
| iOS | Not applicable | Protected | Protected | Whatever the app shows |
| Android 12+ | Protected | Protected | Protected | Whatever the app shows |
| macOS app, entitled and sandboxed | Protected | Protected | Protected | Whatever the app shows |
| macOS app, entitled, not sandboxed | Protected | Protected | Can read or delete the encrypted file, but not decrypt it | Whatever the app shows |
| macOS app, unentitled | Protected | As strong as your login password, if the backup includes your login Keychain | Need you to approve a Keychain prompt, or can run the app | Whatever the app shows |
| macOS CLI | Protected | As strong as your login password, if the backup includes your login Keychain | **Can read every value** with `keybay list` and `keybay run` | **Can read every value** |
| Linux desktop | Protected | As strong as your keyring password, if the backup includes the keyring; exposed if it has none | **Can read every value**, silently | **Can read every value** |
| Flatpak app (candidate) | Protected | As strong as your keyring password, if the backup includes the keyring | Other sandboxed apps: protected. Unsandboxed programs: **can read every value** | Whatever the app shows |

"Whatever the app shows" means Keybay adds no check of its own: someone holding
your unlocked phone or logged-in account can see whatever the application itself
displays. The Flatpak row reflects the GNOME Keyring portal backend; other
backends may differ.

## With a passphrase or passkey

Enrolling a method turns every exposed cell above into "needs your passphrase
or passkey". On account-level platforms that is the difference between any
program you run being able to read your secrets and none of them being able to.
A method also means that holding the platform root and the file is not enough
to build a substitute vault your method would accept. When several methods are
enrolled, any one of them opens the vault.

| Method | What an attacker needs | Watch out for |
| --- | --- | --- |
| Passphrase | The passphrase | Anyone with the platform root and the file can guess offline, at one Argon2id derivation (64 MiB) per guess. Use a long, unique passphrase. |
| Hardware passkey | The key, plus its PIN or touch | On Linux, a program running as you can ask your key directly and needs only your touch and PIN. On a key with a fingerprint sensor, your fingerprint replaces the PIN. |
| System passkey | Your OS passkey provider and its verification | Needs a supported app host and domain association. A synced passkey follows your platform account but never replaces the device's platform root. |

## Never protected

On every platform, with or without a method:

- Anyone who can write your files can delete or corrupt the vault.
- Restoring an older genuine copy of the vault brings back that copy's records
  and the methods that opened it then. Keybay has no rollback detection.
- Administrator or root access, code running inside the application, keyloggers,
  screen capture, and a modified Keybay binary are out of scope.
- Values the application has already read are ordinary data in its memory.

## After a credential is compromised

Remove the method. That replaces the vault's encryption key, so the old
credential cannot read anything written afterwards.

On account-level platforms, also remove every method and add back the ones you
trust. Removing a single method keeps the vault's confirmation secret, so its
former holder, with an old copy of the vault, the platform root, and write
access to your files, could still substitute a vault your remaining methods
accept. Removing every method discards that secret, and adding one creates a
new one. The vault has platform-only protection in between.

## Platform guides

Each guide covers setup, recovery and qualification evidence in detail:
[iOS](platforms/ios.md), [Android](platforms/android.md),
[macOS](platforms/macos.md) and [Linux](platforms/linux.md). The
[security design](design.md) defines the threat model and numbered invariants.

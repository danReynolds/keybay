# Security levels by platform

Keybay always encrypts the vault and always requires the platform's protected
root key. How far that protection reaches depends on what the operating system
enforces around the root, and on whether you add a passphrase or passkey. This
page states the exposure per platform. [Architecture](architecture.md) explains
how it works.

## Platform protection only

What each party can do to a vault with no passphrase or passkey:

| Platform | Level | Other user accounts | Copied files and backups | Other programs running as you | Someone using your unlocked session |
| --- | --- | --- | --- | --- | --- |
| iOS | App-bound | Not applicable | Protected: the file is excluded from backup and the key never leaves the device | Protected | Whatever the app shows |
| Android 12+ | App-bound | Protected | Protected: no-backup directory and a non-exportable Keystore key | Protected | Whatever the app shows |
| macOS app, entitled and sandboxed | App-bound | Protected | Protected: the key is a device-only Keychain item | Protected | Whatever the app shows |
| macOS app, entitled, not sandboxed | App-bound key | Protected | Protected | Values protected; the encrypted file can be read or deleted | Whatever the app shows |
| macOS app, unentitled | Account-level | Protected | As strong as your login password, if the backup includes the login Keychain | Reading the key directly shows a Keychain prompt; programs can still run the app | Whatever the app shows |
| macOS CLI | Account-level | Protected | As strong as your login password, if the backup includes the login Keychain | **Can read every value** with `keybay list` and `keybay run`, without a prompt | **Can read every value** |
| Linux desktop | Account-level | Protected | As strong as your keyring password, if the backup includes the keyring; exposed if the keyring has no password | **Can read every value**, without a prompt | **Can read every value** |
| Flatpak app (candidate) | App-bound against other sandboxed apps | Protected | As strong as your keyring password, if the backup includes the keyring | Other sandboxed apps: protected. Unsandboxed programs: **can read every value** | Whatever the app shows |

**App-bound** means the operating system or sandbox checks which application is
asking before it releases the root key. **Account-level** means anything running
under your user account can reach the root: the application's declared name
organizes the vault but is not a security boundary. App-bound key access and
file isolation are separate: an entitled but unsandboxed macOS app keeps its key
to itself, but its encrypted file sits in a folder other programs can read. The
Flatpak row reflects the GNOME Keyring portal backend, which keeps each app's
portal secret as an ordinary keyring item; other backends may differ.

## With a passphrase or passkey

Enrolling a method turns every exposed cell above into "needs your passphrase
or passkey". On account-level platforms that is the difference between any
program you run being able to read your secrets and none of them being able to.
A credential also means that holding the root and the file is not enough to
build a substitute vault your credential would accept. When several methods are
enrolled, any one of them opens the vault.

| Method | What an attacker needs | Watch out for |
| --- | --- | --- |
| Passphrase | The passphrase | Anyone with the root and the file can guess offline, at one Argon2id derivation (64 MiB) per guess. Use a long, unique passphrase. |
| Hardware passkey | The key, plus its PIN or touch | On Linux, a program running as you can ask your key directly and needs only your touch and PIN. On a key with a fingerprint sensor, your fingerprint replaces the PIN. |
| System passkey | Your OS passkey provider and its verification | Needs a supported app host and domain association. A synced passkey follows your platform account but never replaces the device's root key. |

## Never protected

On every platform, with or without a credential:

- Anyone who can write your files can delete or corrupt the vault.
- Restoring an older genuine copy of the vault brings back that copy's records
  and the methods that opened it then. Keybay has no rollback detection.
- Administrator or root access, code running inside the application, keyloggers,
  screen capture, and a modified Keybay binary are out of scope.
- Values the application has already read are ordinary data in its memory.

## After a credential is compromised

Remove it. That rotates the store key, so it cannot read anything written
afterwards.

On account-level platforms, also remove every method and add back the ones you
trust. Removing a single method keeps the vault's confirmation secret, so its
former holder, with an old copy of the vault, the platform root, and write
access to your files, could still substitute a vault your remaining methods
accept. Removing every method discards that secret; adding one creates a new
one. The vault has platform-only protection in between.

## Platform guides

Each guide opens with the same summary of key access, file isolation, hardware
assurance and limitations:
[iOS](platforms/ios.md), [Android](platforms/android.md),
[macOS](platforms/macos.md) and [Linux](platforms/linux.md). The
[security design](design.md) defines the threat model and numbered invariants.

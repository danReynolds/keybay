# Keybay Security

Keybay holds secrets for apps and CLIs on macOS, iOS, Android, and Linux.
It is austere on purpose: the smallest design that can be trusted, no
security knobs to misconfigure, and no claim without evidence.

## Where your secrets live

On each platform, Keybay uses the storage the platform itself provides for
credentials — directly, with no plugin layer and no deprecated wrappers.

| Platform | Storage | Key protection |
| --- | --- | --- |
| iOS | Data Protection Keychain items | Device-bound, never synced |
| macOS (entitled app) | Data Protection Keychain items | Device-bound, access-group pinned |
| macOS (CLI, `dart run`) | Encrypted container, XChaCha20-Poly1305 | Key in the login Keychain |
| Android 12+ | Encrypted container, XChaCha20-Poly1305 | AES-256-GCM key in Android Keystore, StrongBox when available |
| Linux desktop | Encrypted container, XChaCha20-Poly1305 | Key in Secret Service |

Accessibility and sync policy are fixed constants chosen from each platform's
current guidance — there is no setting that selects weaker storage. Hardware
backing is measured from the platform's own key metadata, never assumed from
the API used.

Nothing is written to disk in the clear, and no failure downgrades silently:
a corrupted store, a missing key, a lost entitlement, a changed signing
identity — each is a typed error. An unreachable store never reads as an
empty one. Lifecycle behavior — reboot, backup, restore, reinstall — is
documented per platform ([macOS](doc/platforms/macos.md),
[iOS](doc/platforms/ios.md), [Android](doc/platforms/android.md),
[Linux](doc/platforms/linux.md)) and exercised by the
[device security suite](doc/device-security-suite.md).

The full threat model, and the numbered `KB-INV-*` invariants these
properties decompose into: [doc/design.md](doc/design.md).

## How it stays that way

Every change runs against the real providers: login Keychain, GNOME Keyring,
Android emulators, the iOS simulator. Release candidates run the device suite
on physical hardware for qualified configurations, and each release carries a
signed statement of what was verified on that exact build — and what wasn't:

```sh
./tool/verify_release.sh keybay <version>
```

A weekly canary build runs against current OS images. Dependency advisories
are scanned on every commit; runtime dependencies: one (`cryptography`,
exact-pinned), with CI failing if the tree changes. Platform guidance changes
land as changelog entries with updated tests.

Critical and High findings block a release. A release never claims what its
evidence doesn't show; gaps are declared in its manifest.

No independent security review has been performed yet. Keybay has a single
maintainer. If development ever stops, the packages will be marked as
discontinued on pub.dev with migration guidance.

## What Keybay does not defend

Code running as you while the store is unlocked reads what you can read. An
attacker holding your unlocked device gets what you would get. Process
memory, OS rollback, and timing side channels are out of scope — each
decision recorded, with rationale, in [doc/design.md](doc/design.md).

## Reporting

Use GitHub [private vulnerability reporting](https://github.com/danReynolds/keybay/security/advisories/new)
or email **me@danreynolds.ca**. Do not open a public issue for an undisclosed
security bug. Expect acknowledgement within three business days and an
initial severity assessment within ten. Security fixes target the latest
minor release and `main`.

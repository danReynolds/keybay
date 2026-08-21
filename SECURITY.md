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
Android emulators, and the iOS simulator. Hermetic tests, dependency scans,
fresh-seed fuzzing, and repository-configuration checks run in CI. Results live
where they are produced — Actions and code scanning — rather than being copied
into a second assurance ledger.

The operating model is event-driven. A new advisory, security-shaped issue,
relevant implementation or platform change, or release review is triaged
against the numbered guarantees in [doc/design.md](doc/design.md). Actionable
or uncertain signals are tracked as GitHub issues. A quiet scanner creates no
maintainer paperwork; a scanner that cannot complete is not treated as a clean
result.

Physical and signed-host scenarios run when a claim depends on affected OS,
hardware, entitlement, lifecycle, or provider behavior. Their reports identify
the clean source commit, named configuration, date, results, and limitations.
They are scoped observations, not release certificates, and a release alone
does not require them. Missing evidence narrows the affected qualification
claim rather than becoming a pass.

Releases are signed with a key held in this machine's Secure Enclave, which
cannot be copied off it and cannot be used without the maintainer's
fingerprint. To check a release yourself:

```sh
git verify-tag v<version>          # signed by the key published at
                                   # github.com/danReynolds.keys
```

Publication is performed locally by rk. A credential-free GitHub auditor
checks the signed core tag, the exact successful source commit, and whether the
package pub.dev serves has the same canonical contents as that tagged source.
CLI binary provenance remains a separate release concern because consumers run
those exact bytes.

Dependency advisories are scanned on every change and by scheduled monitoring;
the runtime dependency set contains one exact-pinned third-party package
(`cryptography`) and CI fails if its reviewed closure changes. Platform-guidance
changes become issues and then code, test, or documentation changes when they
are applicable. The small watcher set and its issue methodology are defined in
[watchers/README.md](watchers/README.md).

Critical and High findings block a release. A release never claims what its
evidence does not show.

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

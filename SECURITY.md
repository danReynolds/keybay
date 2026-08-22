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

Every change runs the hermetic tests, analysis, dependency scans, and
repository checks. A package version change or shared core change runs every
supported provider lane. Provider-specific implementation or harness changes
run the affected login Keychain, GNOME Keyring, Android-emulator, and
iOS-simulator lanes. Documentation-only and unrelated tooling changes do not
spend those runners. All provider lanes can also be started on demand from the
CI workflow's **Run workflow** button. Fresh-seed fuzzing runs on its scheduled
canary.

The operating model is event-driven. A new advisory, security-shaped issue,
relevant implementation or platform change, or release review is triaged
against the numbered guarantees in [doc/design.md](doc/design.md). Actionable
or uncertain signals are tracked as GitHub issues. Weekly and on-demand public
source watchers keep one compact [raw report and separate Codex
assessment](watchers/reports/SUMMARY.md) per run. A quiet scanner creates no
issue; a scanner that cannot complete is recorded as failed, never clean.

Physical and signed-host scenarios run when a claim depends on affected OS,
hardware, entitlement, lifecycle, or provider behavior. Their reports identify
the clean source commit, named configuration, date, results, and limitations.
They are scoped observations, not release certificates, and a release alone
does not require them. Missing evidence narrows the affected qualification
claim rather than becoming a pass.

Releases are signed with a maintainer-controlled SSH key. To check a release
yourself:

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
(`cryptography`) whose new releases receive explicit review. Applicable public
signals become issues and then code, test, device qualification, or claim
changes. Plausible undisclosed Keybay vulnerabilities move to private draft
security advisories. The small watcher set and report methodology are defined
in [watchers/README.md](watchers/README.md).

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
security bug. Reports go directly to the maintainer; response times are
best-effort because Keybay currently has one maintainer. Critical and High
findings block the next release. Security fixes target the latest minor release
and `main`.

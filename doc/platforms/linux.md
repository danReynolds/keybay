# Keybay on Linux

## Ordinary desktop profile

An unsandboxed Dart executable declares its stable namespace in the owning
pubspec or embeds it with `keybay_compile`. Keybay stores one encrypted framed
file beneath `${XDG_DATA_HOME:-~/.local/share}` in an identity-derived private
directory. One identity-derived Secret Service item holds the platform root;
record values do not become separate keyring items.

The file hierarchy and fixed live/stage/lock names are handled with
descriptor-relative no-follow operations. Keybay creates `0700` directories
and `0600` files, pins reader generations, locks mutations, fsyncs staged state,
and atomically replaces the live file.

Keybay speaks the Secret Service D-Bus protocol directly through exact-pinned
`package:dbus`. It never calls `Unlock`, `Prompt`, or `CreateCollection`. A
locked item, prompt path, absent default collection, timeout, or late reply is a
typed failure rather than a new empty store. Provider-specific access-control
UI is outside the protocol's prompt-object mechanism: root acquisition therefore
requires allowed interaction. Only open, authentication changes and reset
acquire the provider. Record operations and authentication listing never do.

First creation is insert-only and runs under a fixed provider lock in private
`XDG_RUNTIME_DIR`; a racing initializer adopts only the exact authenticated
winner. Reset deletes only the already-derived item and file state. Secret
Service has no atomic compare-and-delete, so a same-user actor may still race
reset as denial of service.

## Security boundary

This profile is `namespaceOnly`. Secret Service attributes do not authenticate
the declaring application, so another authorized same-user process may claim
the same namespace and reach the root item; it may also modify the user's
files. Authenticated encryption detects modification but cannot stop deletion.

Add a Keybay passphrase for passwords and high-value credentials. It prevents
the Secret Service root item and encrypted file alone from yielding the store
key. It cannot defend plaintext already returned to a compromised process or
prevent same-user denial of service.

The retained real-provider evidence uses gnome-keyring in a disposable D-Bus
session. It does not claim to qualify every Secret Service implementation.

## Flatpak candidate

The candidate profile `linux.flatpak.secret-portal-file.v1` takes the application
ID from `[Application] name` in the fixed `/.flatpak-info`. It requires a valid
`[Instance] instance-path` and stores ciphertext only at
`<instance-path>/data/keybay-v2`. It ignores `FLATPAK_ID`, `HOME`, and
`XDG_DATA_HOME` as identity or storage selectors. Runtime-only metadata,
duplicate fields, malformed identity, and unsupported paths fail closed.
See the [Flatpak metadata reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-metadata).

The private directory uses the same descriptor-relative no-follow operations
and private permissions as other POSIX profiles. The isolation claim assumes
default confinement. A positive `xdg-data/keybay-v2` grant, or a grant below that
subtree, is rejected because it can remount host data over the store. Broader
filesystem or host privileges can weaken isolation; Keybay does not turn them
into a portable sandbox guarantee. Flatpak documents these
[filesystem grants](https://docs.flatpak.org/en/latest/sandbox-permissions.html).

Keybay retrieves the sandbox caller's application secret through
[XDG Secret Portal v1](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Secret.html).
The secret is reusable and owned by the portal. The transport accepts 1–4096
bytes; the protector requires 32–4096 bytes, a supported subset of the portal's
variable-length contract. This minimum size does not establish entropy, and
HKDF cannot add it. Keybay derives its own 32-byte wrapping root with
HKDF-SHA256, the resolved storage domain as salt, and the fixed
`keybay:v2:linux-flatpak:portal-root:v1` label. It stores no separate
Keybay root item and clears operation-owned root buffers after use.

`Keybay.open()`, authentication changes, and reset may invoke trusted provider
UI. Record operations and `auth.list()` never acquire the portal, including
on authentication failure. The initial profile rejects continuation
tokens and nonempty persisted provider state. Cancellation, timeout, malformed
response, or missing portal fails closed. A detected Flatpak never falls back
to ordinary Secret Service, including when that service is reachable.

Portal cancellation reports `platformInteractionRequired`. Timeout or malformed
responses report `platformOperationFailed`; unavailable providers or unsupported
continuation tokens report `platformProtectorUnavailable`.

Reset deletes the encrypted store and staging, retains the fixed nonsecret
coordination lock and its directory, and initializes no replacement store.
Unlinking a held lock could let processes lock different inodes. The next
successful open generates a fresh store key. The portal exposes no secret
deletion API, so reset retains the application secret. Restoring an old complete encrypted
store can restore access under the same identity and file domain, with its old
passphrase if one was configured. Rollback resistance and root rotation remain
deferred. Changing the Flatpak application ID is a new identity, not migration.

## Flatpak qualification

Qualification requires retained Linux evidence of isolation with two installed
Flatpak application IDs. Hermetic transport and
engine tests cover malformed responses, bounds, token rejection, cancellation,
timeout, passphrases, reset, concurrency, and the no-prompt/no-fallback rules.

The three real D-Bus transport tests passed locally on 2026-09-04 with Dart
3.11.0 and 3.12.2 against an isolated D-Bus 1.14.10 daemon on macOS. They exercise
Unix descriptor transfer and EOF, early responses, cancellation dispatch, and
token rejection using a test portal service. These transport tests cannot prove
sandbox caller authentication or per-application isolation. The ordinary Docker
Secret Service lane cannot supply that proof either.

The Flatpak lane uses a disposable session bus, the real portal frontend and
gnome-keyring Secret backend, and the same AOT harness installed as two minimal
Flatpaks with default filtered bus access. It compares in-memory challenge
responses from concurrent first requests to prove same-ID continuity and
distinct IDs, separately checks private file access, and runs the public SDK
lifecycle. It restarts both the portal and keyring and reopens both stores to
check that the application secrets persist beyond the provider processes.
Qualification also reviews the selected backend's random-secret generation;
length and distinct outputs alone do not establish entropy.
No portal secret or derived response is logged or retained. A configured lane
is a test plan; only a successful retained run is execution evidence.

Source review of [Ubuntu's GNOME Keyring 46.1 package](https://archive.ubuntu.com/ubuntu/pool/main/g/gnome-keyring/gnome-keyring_46.1-2ubuntu0.2.dsc)
found independent 64-byte random secrets stored by application ID in the default
keyring. This is a review of generation and persistence, not an entropy
measurement. Continuity depends on that provider state surviving; deleting or
replacing the default keyring can lose access. The lane uses an unlocked
backend for this historical run. Later native x64 qualification also exercised
prompt cancellation, timeout and overlapping cancellations; see the dated
[qualification report](../qualification-status.md). Timeout recovery explicitly
dismisses any remaining provider dialog; automatic UI dismissal is not claimed.

The complete two-application lane passed locally on 2026-09-05 in Ubuntu 24.04
arm64 under Docker Engine 29.6.1, using Linux 6.12.76-linuxkit, Flatpak 1.14.6,
GNOME Keyring 46.1, and XDG Desktop Portal 1.18.4. It verified inner mount/PID
namespaces, active seccomp, no-new-privileges, and zero effective capabilities,
alongside the identity, file, lifecycle, concurrency, restart, and no-fallback
checks above. Native Ubuntu 24.04 x64 CI subsequently passed on 2026-09-06,
including the prompted cases. Both receipts apply to their recorded sources and
provider configurations, not every Linux desktop; current source applicability
is recorded in the [qualification report](../qualification-status.md).

Nested Docker needs a private system D-Bus daemon and the outer-container
options `--security-opt seccomp=unconfined` and
`--security-opt systempaths=unconfined`. They permit namespace creation and a
private `/proc` mount; the harness verifies that Flatpak installs its own inner
sandbox. The observed run required no privileged mode or added capabilities.
See [Docker's seccomp documentation](https://docs.docker.com/engine/security/seccomp/)
and [nested-container mount requirements](https://github.com/moby/buildkit/blob/master/docs/rootless.md).

Run `bash tool/test_flatpak.sh` on Ubuntu 24.04 with the script's listed
prerequisites. It creates and removes a disposable OS account. The
`integration-flatpak` CI job retains a receipt containing versions, application
IDs, effective permissions, and result booleans. It emits a passing receipt only
after verifying removal of the disposable account, processes, and files.

Snap remains deferred until confinement identity, persistent storage, provider
binding, upgrade continuity, and reset behavior qualify together. It never
falls back to the ordinary profile.

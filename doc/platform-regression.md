# SDK platform regressions

See the [latest reviewed qualification report](qualification-status.md) for
what has been checked per platform and what remains open.

One entrypoint runs the maintained SDK tests locally and in CI:

```sh
dart pub get --enforce-lockfile
./tool/test_e2e.sh all
./tool/test_e2e.sh linux flatpak
./tool/test_e2e.sh core macos
./tool/test_e2e.sh android ios
```

No arguments means `all`. Names select a subset, in the order given; duplicates
run once. There is no discovery framework or test registration API: the small
selector calls the existing platform scripts. CLI tests remain separate.

| Lane | Tests | Prerequisites |
| --- | --- | --- |
| `core` | Hermetic SDK tests, crypto vectors, hostile store inputs, all platform contracts over fakes | Dart and resolved workspace dependencies |
| `macos` | Native file Keychain, private storage, passphrase/reset, locked record operations | macOS user session and Apple command-line tools |
| `linux` | Real Secret Service, clean-account paths, locked collection | Linux with GNOME Keyring, D-Bus and GLib tools; otherwise Docker |
| `flatpak` | Two installed apps, sandbox identity/isolation, real portal, prompted cancellation/recovery, provider restarts, reset and no fallback | Ubuntu 24.04 provider stack, GCR, Xvfb, xdotool and passwordless sudo for a disposable account; otherwise Docker |
| `android` | SDK integration using genuine Android APIs | Flutter, Android SDK, exactly one ready API 31+ emulator |
| `ios` | SDK integration through XCTest using genuine Apple APIs | Flutter, macOS, Xcode and an available iPhone simulator |

For mobile tests, first run `flutter pub get --enforce-lockfile` in
`example_flutter`. Android does not boot an arbitrary AVD or restart your adb
server. iOS boots an available iPhone simulator using the existing XCTest runner.

`all` includes every row, even if the current host lacks a prerequisite. A
complete local `all` therefore needs a suitably equipped Mac. CI distributes
the same commands across its Linux, macOS and mobile jobs. Provider-sensitive
changes select affected jobs; a manual CI run selects every provider. macOS
provider CI includes native arm64 and Intel x64 runners. The x64 job also runs
the core suite, covering the Darwin descriptor ABI with the actual x64 SDK.
Local Rosetta runs use the same commands with an x64 Dart SDK on PATH.

## Results and failures

Each invocation prints a unique `build/regression/run-*/report.json` path. The
summary records source commit and dirty state, host, Dart version and ABI, start/finish
time, and each selected lane's status and exit code. Console diagnostics stay
in the terminal or CI log. Flatpak additionally writes its detailed provider
receipt beside the summary (or to `KEYBAY_FLATPAK_REPORT` when explicitly set).
CI uploads the same summaries, including failed runs.

- Every selected lane passes: exit **0**.
- A test fails: exit **1**, even if another lane is blocked.
- Missing prerequisite with no test failure: **blocked**, exit **69**.
- Invalid selection: exit **64**, before running tests.

Failures and blocked lanes do not prevent later selected lanes from running.
An interruption stops the run; an unfinished report never becomes a pass.
Reports identify a development run, not an immutable release artifact. Preserve
the exact source and platform evidence separately for release qualification.

## Linux and Flatpak in Docker

On macOS, `linux` and `flatpak` automatically use `tool/test_linux_docker.sh`.
On Linux, they use native providers; explicitly call
`bash tool/test_linux_docker.sh linux` or `flatpak` to use Docker instead.

The bootstrap builds a cached image from `tool/linux_test.Dockerfile`, copies
the current source (including uncommitted files) into a disposable container,
resolves the committed dependency lock, and runs the same native script. It
does not mount a personal keyring, Docker socket, or writable source tree. The
tests use an unprivileged account and private provider state. The container is
removed on exit. The first run downloads the image packages and Flatpak runtime.

Nested Flatpak needs two outer Docker exceptions: `seccomp=unconfined` and
`systempaths=unconfined`. It also uses a private system D-Bus. It does not use
privileged mode or host namespaces. The inner Flatpak tests verify their own
namespace separation, seccomp, capabilities, filtered bus, and two-app
isolation. Ordinary Linux tests use Docker's default restrictions.

Base images are pinned by digest. Package updates require an explicit image
rebuild (`docker build --no-cache -t keybay-linux-regression:local - <
tool/linux_test.Dockerfile`); Flatpak receipts record observed provider/runtime
versions. A pass applies to that tested stack, not every desktop provider.

## Additional qualification

Signed macOS has an opt-in development baseline and build-continuity check,
excluded from `all`:

```sh
KEYBAY_APPLE_TEAM_ID=<your-team-id> ./tool/test_e2e.sh macos-signed
```

It temporarily applies and restores signing configuration and verifies the
actual signed app after each phase. It requires different signed builds for
seed/reopen and verifies reset cleanup. See
[signed macOS verification](../tool/dp_keychain_verification.md) for prerequisites
and the evidence retained beside the regression summary.

The standalone Developer ID SDK lane is also explicit:

```sh
KEYBAY_APPLE_TEAM_ID=<your-team-id> ./tool/test_e2e.sh macos-developer-id
```

It requires clean source and a Developer ID Application identity. It signs
a dedicated runtime and two distinct native AOT modules, requires actual native exits and matching receipts,
and exercises a fresh SDK namespace in the genuine account's login Keychain.
It preserves the user's Keychain search list/default and resets only its own
provider item and encrypted files. It does not publish or notarize anything.
The runtime and modules retain hardened runtime, library validation and empty
entitlements. This form passed native continuity; the single-file executable's
startup failure remains recorded in [the review handoff](security-review.md).

Physical Android/iOS use the existing `tool/device_security.sh` commands in the
[security suite](device-security-suite.md). Their `--lifecycle` selections run
the opt-in physical Profile/AOT separate-process checks, with their own reports.
Use `--upgrade` instead to replace build 101 with 102 and verify passphrase-protected
continuity. Use `--crash` to kill the exact fixture process after acknowledgment
and again during a bounded write workload, then verify passphrase and record
recovery in a third process. Both physical upgrade and crash procedures passed on the recorded Pixel 6a
and iPhone 16 configurations; see the [qualification report](qualification-status.md)
for exact sources and remaining lock/reboot/restore cases. The `core` lane also exercises real process kills around POSIX store
replacement on macOS/Linux, using disposable provider state.
Routine emulator/simulator results
do not establish physical secure-hardware behavior, process/update continuity,
maintained-device KDF budgets, or independent security review. Those use their
own evidence. The Claude review is now accepted; the scoped SDK 0.2.0 closeout
defers remaining device procedures and Argon2 acceptance as recorded in the
[qualification report](qualification-status.md#sdk-020-release-scope).
The [remaining mobile procedures](mobile-failure-qualification.md) spell out
the device-dependent failure cases and distinguish them from implemented lanes.

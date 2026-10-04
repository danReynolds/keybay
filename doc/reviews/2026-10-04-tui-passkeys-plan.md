# Hardware passkeys in the Keybay TUI

Date: October 4, 2026. Status: local implementation ready for attended testing; no TUI device qualification yet.
Depends on [PR 88](https://github.com/danReynolds/keybay/pull/88) and the
accepted [SDK contract](../sdk.md#add-passkey-protection).

## Readiness

The SDK is sufficient for a first macOS USB integration without changing its
public API. The native TUI now retains method hints and typed provider failures, and
implements the hardware flow below.

| Layer | Current evidence | Work before a real TUI test |
| --- | --- | --- |
| Keybay SDK | Explicit add/list/remove, authentication-only open, exact method selection, PIN ownership and operation cancellation; automated vault tests | Exercise the default Keypass adapter with a real key and native Keybay store |
| Desktop hardware adapter | Keypass implements macOS/Linux USB using libfido2; prior Keypass device tests are separate evidence | Build the pinned native source, place the library beside the test executable, verify loading |
| TUI | Hardware enrollment, exact method selection, masked PIN input, cancellation and typed failures; SDK-backed model/widget regressions | Attended physical enrollment and fresh-process unlock |
| CLI commands | Passphrase-only `get`, `set`, `list`, `rm`, `run` | Initially give accurate TUI guidance for hardware-only stores; attended hardware unlock parity before shipping general CLI support |
| Distribution | CLI archive currently contains one executable; the local hardware dylib links Homebrew libfido2/OpenSSL | Bundle/locate dependencies, include notices, update archive/formula checks and qualify signed runtime loading |
| Public CI/release | Keypass is a private SSH Git dependency | Resolve dependency distribution; do not waive the publication gate |

The SDK and TUI are ready to consume locally; portable release packaging remains
unimplemented. No further passkey architecture research is needed for the first
USB test. Native lifecycle and packaging details still need qualification.

## Local test build

`tool/build_cli_hardware_test.sh` builds the pinned Keypass USB adapter and an
AOT TUI executable under `build/hardware-tui-test`. It creates a persistent,
unique disposable Keybay application identity and a separate `.test` RP. Open
`Start hardware test.command` there to run it in Terminal. The harness seeds
one synthetic marker, verifies it on every successful open, and records
operation outcomes and process IDs without PINs or key material. It does not
open the normal CLI vault. Quit and relaunch the same executable for the
fresh-process unlock test.

The first local build passed the native adapter CTest (1/1); read-only discovery
loaded ABI 1 and returned no connected devices in 26 ms. The CLI suite passed 245 tests (18 hardware cases using a fake provider);
38 native terminal PTY checks, 45 root tooling/demo tests, Dart analysis and
the browser demo compile also passed. These are separate from physical-device proof. The pending native
cancellation/discovery timing and signed distribution gates below still apply.

## Unattended terminal follow-up

The October 4 follow-up adds `hardware_pty_harness.dart` and
`tool/test_cli_hardware_tui.py` to `tool/test_cli_core.sh`. They run the real SDK
engine, TUI and POSIX driver with disposable storage/platform roots and a fake
Keypass provider. No native hardware adapter is loaded and no physical key or
normal vault is accessed.

The 18 terminal cases cover enrollment and unlock: masked PIN paste through
blur and resize at both supported minimum sizes; explicit retry after a rejected
PIN; blocked-PIN submission refusal; cancellation followed by retry only after
drain; termination while waiting; interruption during PIN entry; idle exit; and
loss of foreground ownership. The provider returns after cancellation to expose
late-result cleanup. Receipts assert session closure, cleared operation inputs,
released provider secrets, unchanged storage for aborted operations and no
plaintext disclosure. Foreground-loss cases use only their own shell/PTY jobs.

This found and fixed a real keyboard issue: selecting a hardware enrollment
opened a form with no focused input or button, so Enter did not start unlock.
The Unlock action now receives initial focus and regains it after a retryable
failure without a PIN field. Two widget regressions cover entry and retry at
40×24 and 80×20. The full CLI suite now passes 247 tests; the 32 SDK tests sharing
the extended fake provider and Dart analysis also pass.

These results qualify the app's simulated terminal lifecycle. They do not
measure physical USB cancellation, discovery latency with a problematic key,
or native firmware PIN behavior. The attended test remains pending. The
prepared live-test executable is rebuilt with the focus fix under the same
disposable identity and path.

## User flow

1. Open Keybay normally. First use stays `Keybay.open()`; existing protection
   still has to authenticate before any enrollment action.
2. Settings → Security lists the enrolled methods and offers **Add passphrase**
   when none exists, **Add hardware key**, and **Remove** for a selected method.
   Labels distinguish multiple hardware enrollments. There is no update/replace.
3. **Add hardware key** collects an optional label and starts an explicit
   attempt. Show: “Connect one hardware key. Touch it when it flashes. Setup may
   ask more than once.” The application chooses the RP; users do not configure
   a website or RP in this screen.
4. First try without a PIN, allowing on-key verification. If Keypass returns
   `pinRequired`, show a masked **Hardware key PIN** field and wait for Submit
   before starting another attempt. Do not silently retry or reuse a rejected
   PIN. Explain that this is the key's existing PIN, not a new vault password.
5. Clear the submitted field/undo history and caller bytes as soon as the SDK
   snapshots them. The SDK owns its operation copy through the multiple setup
   ceremonies. Show a stable waiting screen and Cancel; no hardware event
   callback is needed for this first flow.
6. Show success only after `auth.add` completes and `auth.list` refreshes.
   Failed/cancelled setup may leave a provider credential even when no method
   was saved locally. Explain that outcome without auto-enrolling again or
   deleting provider credentials.
7. On the next process launch, `authRequired.authMethods` supplies the chooser.
   A sole passphrase retains the existing form; hardware methods have an
   explicit **Unlock** action. Pass the selected method's exact ID, RP and route
   to `Keybay.open`. Never try every enrollment or automatically switch routes.
8. Remove uses the descriptor returned by `auth.list`, with a confirmation
   naming the method and the resulting policy. Remaining methods are
   alternatives. Removing the final method explicitly returns to platform-only
   protection. Removal does not erase the passkey on the physical key.

Standalone CLI hardware access uses a stable DNS-shaped RP without a website.
Use `io.github.danreynolds.keybay.cli` for new production CLI enrollments,
matching the existing signing identifier, and a separate test RP. Freeze this
constant with the implementation. It belongs to the CLI, not to the Keybay SDK.
Existing enrollments use their saved RP after explicit selection; show that
scope in method details. An RP is not a unique enrollment ID and does not
authenticate the executable. Keybay's mandatory platform root remains in force.

System passkeys are unsupported in the ordinary CLI. Show them in the method
list as unavailable here, rather than pretending they disappeared or routing
them to hardware. No browser helper or hosted Keypass service is added.

## Implementation sequence

### 1. Native boundary and model

- Extend the internal `SessionOpener` typedef in `application.dart` to forward
  `methodId` and `cancellation`, retaining the data-only credential API.
- Replace `TuiSession.passphraseId` and passphrase-only removal with portable
  method descriptions and add/remove operations in `tui/store.dart`. The native
  adapter retains the actual SDK method objects; the shared web UI must not
  import `dart:io` or the native SDK.
- Preserve redacted method hints and typed passkey errors in
  `tui/native_model.dart`. The model tracks all methods; replace the ambiguous
  `protected` passphrase boolean with explicit passphrase/method state.
- Keep the web demo synthetic. Its capabilities must hide or clearly disable
  hardware actions; no real WebAuthn bridge is implied by shared widgets.
- Keep one operation token and cancellation signal per accepted hardware
  attempt. Cancel/Escape, quit, idle exit, signals and terminal ownership loss
  cancel the pending attempt **before** awaiting it. Drain it before releasing
  the terminal or starting another attempt. Close any late returned session.
- Current `_perform(protection: true)` closes on every auth error. Classify
  expected, uncommitted passkey failures separately so a rejected PIN or absent
  key can leave enrollment usable. Storage/platform/commit ambiguity still
  closes and requires reopening. Cancellation after a commit is not rollback;
  inspect the resulting policy before claiming that nothing changed.

### 2. Screens and supported-method policy

- Add method selection, label/PIN input and waiting views to `tui/forms.dart`
  and `tui/screen.dart`; reuse `SecretDraft` with a 4–63 UTF-8 byte PIN bound,
  no NUL/newlines, masking and disabled clipboard/semantics disclosure.
- Update `tui/settings.dart` to render methods and the add/remove actions.
  Escape and width-bound provider/user labels before terminal display.
- Retain the temporary removal guard from the PR review until the TUI can
  reopen a surviving hardware method. Keep it for stores whose only survivors
  are unsupported system methods. Do not impose that UI restriction on the SDK.
- Distinguish `pinRequired`, `pinInvalid`, `pinBlocked`, `pinTemporarilyBlocked`,
  `deviceUnavailable`, `deviceSelectionRequired`, capability failure,
  cancellation and timeout. Multiple attached keys get “Connect only the key
  you want to use.” PIN-blocked outcomes stop; no reset/PIN-management feature.
- No device-presence monitor, automatic PIN retry, background credential
  lookup, record-operation prompts or callback fields on credentials.

### 3. Disposable macOS test build

- Extend the real-provider CLI integration harness, not the in-memory TUI
  preview. Compile with a unique `keybay.application_id` and a separate test
  hardware RP. Keep the test executable/path stable across the reopen test.
- Build the hardware adapter from Keypass's exact pinned source revision.
  Reuse the installed native build dependencies for this local probe. The old
  `keypass/build/hardware` dylib is evidence of local availability, not a
  verified artifact for the new build.
- Put `libkeypass_hardware.dylib` beside the compiled test executable, as its
  loader expects. `dart run` instead needs the compile-time
  `KEYPASS_HARDWARE_LIBRARY` define; do not install a library beside the shared
  Dart runtime or load a path supplied by vault metadata.
- Use the existing disposable provider fixture/identity patterns and synthetic
  records. Never reset or migrate the ordinary `keybay-cli` vault for this test.
- Retain a receipt with code/native revisions, application/test identity,
  operation outcomes and fresh process IDs. Never record PINs, PRF outputs,
  store keys or raw credential records.

### 4. CLI parity and distribution

For the first TUI probe, preserve current passphrase support in other commands.
Hardware-only failures must direct users to `keybay open` without initializing
or downgrading the store. Before advertising general CLI hardware support,
extend the attended command unlock path to the same explicit method selection,
PIN ownership and cancellation behavior. Do not steal a command's piped stdin
for PIN input or contaminate stdout/child environments with prompts.

Update `tool/package_cli_release.sh`, `tool/verify_cli_archive.sh`, archive
tests and Homebrew packaging together when shipping native libraries. macOS
must validate dependency install names and signed/hardened runtime loading;
Linux needs qualified libfido2/OpenSSL resolution and USB HID permissions.
Neither a locally installed Homebrew dependency nor a passing no-device test
qualifies the final archive. Include native dependency notices. Linux physical
USB testing follows macOS; Windows remains deferred.

## Acceptance tests

Automated tests precede the physical ceremony:

- SDK-backed TUI tests for platform-only, passphrase-only, hardware-only,
  mixed and multiple-hardware policies; exact method selection and descriptor
  removal, no enrollment during open, stale sessions and failed commits.
- PIN-required and rejected-PIN flows, fresh input for deliberate retries,
  cleared buffers/undo history, unavailable/ambiguous device and unsupported
  capability errors, and unchanged policy after pre-commit failures.
- Cancel while waiting, exit/idle/foreground loss, cancellation during discovery,
  late success after dismissal and terminal restoration. Measure native drain
  latency rather than assuming that a cancelled Dart future stopped device I/O.
  Keypass's current readiness discovery uses its own signal; verify this bound
  before claiming prompt cancellation at every phase.
- Fleury tests at 40×24 and 80×20, keyboard-only navigation, masked PIN and
  redacted semantics, pasted control characters in labels, plus existing TUI,
  web-demo and CLI regressions. A fake provider is not hardware proof.

Then run an attended macOS USB test with the user's key:

1. Add a hardware method in the TUI to the disposable vault and save a marker.
2. Exit the process, relaunch, select the saved method and recover the marker.
3. Cancel a pending unlock, then deliberately retry with correct input; unplug
   the key for an unavailable-device check. Do not intentionally guess PINs or
   exercise lockout on the user's key.
4. Add a passphrase alternative, verify both paths across fresh processes,
   remove one method, and confirm the survivor still opens the same records.
5. Exercise two enrollments under the same RP (one physical key suffices),
   remove one by its method object and prove the remaining enrollment works.
   A second physical device is needed to qualify backup-device selection.

Pause interaction while the user enters the PIN or touches the key. Observe
only the settled result. Local passkey removal/reset cleans up the disposable
vault only; deleting residual credentials from the user's hardware is separate.

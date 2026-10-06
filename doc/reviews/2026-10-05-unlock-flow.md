# Remembered TUI unlock and immediate hardware access

The operator reported successful hardware enrollment through the normal local
Keybay command. Reopening still required a method choice and a second Unlock
action. The TUI now remembers the last successfully authenticated enrollment and
starts hardware access when that method is entered.

## Interaction contract

- Prefer the saved method ID only if it is still offered and usable here.
- Otherwise enter a single usable method directly; show a chooser for several.
- Hardware entry checks for a connected key without asking for a PIN or touch.
  Missing hardware is polled until connected, cancelled, or a two-minute deadline.
  Only discovery repeats. Authentication, PIN submissions and failures never
  retry automatically.
- A PIN-required result focuses a masked field as the next normal step. A rejected
  PIN shows an error and requires fresh input. Blocked PINs disable retry.
- Escape offers Other methods when an alternative is usable. Cancellation drains
  discovery or authentication before showing the chooser. It stays there until
  the operator chooses; remembering a method does not create a restart loop.
  Escape quits when there is only one usable method.
- Enrollment remains an explicit Add operation. A new enrollment does not become
  preferred until it actually unlocks the store.

## Data and authority

The optional preference contains only a version and the 16-byte method ID encoded
as hexadecimal. It cannot supply credentials, enroll a method, choose an arbitrary
RP or bypass the SDK's mandatory platform protection and credential validation.
The method's RP and saved passkey record still come from the SDK's existing path.
No PIN, passphrase, PRF material, vault key or label is written to this preference.

macOS stores the hint under `~/Library/Application Support/keybay/`; Linux uses
`$XDG_STATE_HOME/keybay/` or `~/.local/state/keybay/`. Reads are bounded and malformed
or unsupported data is ignored. The writer stages in a uniquely owned sibling
directory and atomically replaces the regular file. Symlink and non-file targets
are ignored. All I/O is best effort; failure cannot turn successful authentication
into failure. This is local presentation state, not a security boundary.

The CLI file-writer firewall has one reviewed exception for that staged JSON
write. It retains its other file, process and network restrictions. Command
authentication outside the TUI retains its existing explicit-choice behavior.
The SDK credential API, encryption policy and auth lifecycle are unchanged.

## Dependency change

Keypass is pinned to `e5fbdda99639d0b0693b3b0f60ca9825cd5fc336`. Its prompt-free
`check(cancellation:)` now accepts the same cancellation object as other operations
and releases the backend only after native discovery has drained. The CLI uses
that public API for connection discovery; actual authentication remains in Keybay.

Updating the Git dependency exposed retained CMake metadata containing the previous
checkout's absolute path. The hook now refreshes configure metadata when it runs,
preserving downloaded dependencies and other build outputs. A transitive-consumer
test moves the source package while retaining the consumer build cache, then checks
source execution and a relocated four-library CLI bundle.

## Verification scope

Keypass analysis and all 167 Dart tests pass on macOS. Transitive source runs,
dependency-source relocation, and relocated CLI/symlink ABI checks pass. These
checks do not enumerate devices or access physical credentials. All ten platform
CI jobs pass at the pinned commit, including the desktop build-hook checks.

Keybay tests exercise saved exact-key selection, passphrase selection, stale and
unavailable preferences, failed preference I/O, insertion waiting, timeout,
cancellation/draining, sole-method quit, explicit PIN retries and secret clearing.
File tests cover malformed/oversized data, atomic replacement and symlink rejection.
Native terminal tests use a simulated provider with the real SDK/TUI; physical
unlock with this revised flow remains an attended operator check.

Current checks pass: scoped analysis, 267 CLI tests, 45 repository tests, three
SDK dependency checks, 38 general TUI terminal cases, 19 hardware TUI cases,
13 hardware command cases and 22 hidden-input boundary cases. An unrelated
mobile-runner test timed out in the initial concurrent repository run and passed
in the complete sequential rerun. SDK dependency tests were rerun from their
required package directory after an initial invocation from the workspace root.
The normal rk-managed command resolves to `~/.local/share/rk/bin/keybay` and prints
`0.2.0` from a fresh fish shell outside the repository with the updated hook.
CLI lifecycle/exec, clipboard, archive/identity, source caller-directory and
relocated native ABI checks also pass. The current unsigned release candidate
passes archive, binary and child-process checks; this does not qualify notarized
distribution or physical-key access.

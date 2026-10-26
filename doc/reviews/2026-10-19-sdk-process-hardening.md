# SDK process hardening review — October 19, 2026

Commit `848073e` moved the CLI's process hardening into the SDK as
`Keybay.hardenProcess()`. It added a result an application can check, the
Linux Yama and X11 signals, X11 warnings at the CLI and TUI passphrase and PIN
prompts, and docs. A fresh-context reviewer (Claude Opus, xhigh effort, reading
only git objects) reviewed that commit. Its full text follows, then the
response to each finding. Commit `b1b5b67` answered the review; the same
reviewer checked it, and the final commit answers that check.

## Verification

- `dart analyze --fatal-infos` is clean for both packages.
- macOS arm64: the SDK suite (`dart test -x integration`) passed 610 tests,
  with 3 skipped, and the CLI suite passed 291.
- Linux has no local run of the package suites: Keypass's native build hook
  needs libfido2 and OpenSSL development files, which an offline Docker image
  lacks. Instead, a scratch probe ran the same
  `packages/keybay/lib/src/process_hardening.dart` in Docker (`dart:stable`
  3.13.5, linux_arm64, Yama absent). Hosted CI runs the Linux suites, and
  x86_64 was not run locally. The probe found:
  - **Plain process, as root without `CAP_SYS_PTRACE` and as `nobody`.**
    Dumpability went from 1 to 0. A same-user child read `/proc/<pid>/environ`
    and opened `/proc/<pid>/mem` before the call, and was refused after it.
    The result was `applied`.
  - **App in a user namespace** (`unshare --user --map-root-user`, as
    `nobody`). A same-user process outside the namespace could still read
    `environ` and open `mem`. `848073e` reported `applied`; the fix reports
    `failed`.
  - **Under a tracer.** A Perl tracer used `PTRACE_TRACEME` and then exec. The
    result reports `debuggerAttach: failed (process N was already tracing…)`.
  - **Non-UTF-8 thread name.** Set through `PR_SET_NAME`, it no longer hides
    the tracer state.

The reviewer's text follows verbatim, with its headings moved down one level.

## Review of 848073e: SDK process hardening

**Verdict: Ready after fixes.** For an ordinary Linux or macOS process, the FFI and the kernel claims are correct. The CLI's exec hand-off and the X11 prompts are preserved, and the tests would catch the hardening being removed. One case needs fixing before release: inside a user namespace the user owns (Flatpak, toolbox/distrobox, rootless containers), the result reports `debuggerAttach: applied` and every doc says "refused", but the protection is not in effect there. The other findings are small.

### Findings

#### 1. Medium: `applied` and "Refused" are false inside a user namespace the user owns

**Where:**
- `packages/keybay/lib/src/process_hardening.dart:146-152`, and the field docs at 56-76
- `doc/sdk.md:85, 107-111`
- `doc/security-levels.md:96, 106-108`
- `SECURITY.md:93-94`
- `packages/keybay/README.md:40-42`
- `packages/keybay_cli/README.md:333-335`

**What is wrong:**
- **Non-dumpable doesn't stop the namespace owner.** Even when the process is non-dumpable, `__ptrace_may_access` lets a caller through if it has `CAP_SYS_PTRACE` in the target's `mm->user_ns`. This is the "unless the reader has `CAP_SYS_PTRACE`" in sdk.md:85.
- **The owner is the user.** A process in a parent namespace whose euid owns a child user namespace has every capability in it (`cap_capable`, user_namespaces(7)). Flatpak's unprivileged bwrap, toolbox/distrobox and rootless podman all run the app in a namespace owned by the user's own uid. So after the call, any unsandboxed program running as that user can still attach a debugger or open `/proc/<pid>/mem`.
- **Yama doesn't help.** Scopes 1 and 2 both accept `ns_capable(child's user_ns, CAP_SYS_PTRACE)`. So `ptraceScope: 1` together with `ptraceUnrestricted: false` gives the app false comfort there.
- **The tracer check is blind in Flatpak.** Flatpak uses a separate PID namespace. A tracer outside it shows as `TracerPid: 0`, because `task_pid_nr_ns` returns 0 for a PID the reader can't see.

**Why it matters:**
- sdk.md:58 names Flatpak as an SDK host, and the CLI runs inside toolbox.
- The result says `applied` ("confirmed that it is in effect"), with the detail "same-user ptrace and /proc/<pid>/mem need CAP_SYS_PTRACE". That reports a protection the platform did not establish, against `KB-INV-005`.
- It matters most for passphrase-protected stores: their store key is exactly what an attach would read.

**Fix:**
- Detect a non-initial user namespace: `/proc/self/uid_map` is anything other than the single line `0 0 4294967295`.
- In that case, don't report `debuggerAttach: applied`. Either report `failed` with a detail such as "in a user namespace; processes of its owner outside it keep CAP_SYS_PTRACE over this process", or add a distinct status or field if the CLI should keep running in toolbox.
- State the limit in sdk.md, security-levels.md (using Flatpak as the example), SECURITY.md and both READMEs, and qualify the Yama text.

**Confidence:** this comes from reading the kernel code paths; I did not run it. To settle it:
1. On a Linux host with Yama 1, write a probe that calls `Keybay.hardenProcess()`, prints the result and its PID, then sleeps.
2. Run it under `unshare --user --map-root-user`, or under `flatpak run`.
3. From an ordinary shell as the same user, run `gdb -p <pid>` and `head -c1 /proc/<pid>/environ`.

I expect both commands to succeed while the probe prints `debuggerAttach: applied`.

#### 2. Low: the "Child programs" advice can't be followed from the API, and spawned children silently get core limit 0

**Where:** `doc/sdk.md:98-100`; `packages/keybay/lib/src/process_hardening.dart:104-105`; `packages/keybay_cli/lib/src/process_hardening.dart:16-23, 42-77`.

**What is wrong:**
- The guide says an app "can restore that program's soft limit first". But the result doesn't carry the soft limit that `hardenProcess` replaced, and the same guide says to make the call first in `main`, so nothing earlier has read it.
- The only way to restore it is the CLI's way: write your own `getrlimit` FFI and read the limit before the call. That is why the rlimit struct and bindings now exist twice (SDK and CLI), so the hand-off is not single-sourced.
- Most Dart apps start children with `Process.start` or `Process.run`. Those fork and exec inside the VM with no hook in between, so the children inherit a soft `RLIMIT_CORE` of 0. The guide doesn't mention this.

**Fix:** either of these:
- Report the prior soft limit in the result (for example `int? previousSoftCoreLimit`). Have the CLI's `restoreForExec` use it and delete the CLI's own FFI.
- Or reword the bullet:
  - Children inherit a soft limit of 0.
  - The hard limit is unchanged, so a child can raise its own.
  - Restoring it before `execve` means reading it before the call, as the CLI does.

#### 3. Low: the check for an already-attached tracer reads only the main thread

**Where:** `packages/keybay/lib/src/process_hardening.dart:116, 134-150, 223-238`; `doc/sdk.md:94-96`.

**What is wrong:**
- `/proc/self/status` is the thread-group leader's status only.
- ptrace attaches per thread (`PTRACE_ATTACH` or `PTRACE_SEIZE` on a TID). A tracer holding any one stopped thread can read the whole address space with `PTRACE_PEEKDATA`.
- The Dart VM already runs several threads before `main`. A tracer attached earlier to a worker thread leaves `TracerPid: 0` on the leader, and the result reports `applied` ("non-dumpable … and untraced").
- sdk.md:94-96 promises `failed` "when a debugger was already attached". gdb is caught because it attaches every thread; a deliberate tracer need not.

**Fix:** read `/proc/self/task/*/status`, and report `failed` if any thread's `TracerPid` is non-zero or unreadable. Test it through the seam described in finding 6.

#### 4. Low: a non-UTF-8 thread name makes every call report `failed`

**Where:** `packages/keybay/lib/src/process_hardening.dart:238` (`_readStatus`), surfacing at 134-139.

**What is wrong:**
- `readAsStringSync()` decodes strict UTF-8 and throws on malformed bytes.
- The first line of `/proc/self/status` is `Name:`. The kernel fills it from the basename of the executable or symlink used at exec, cut to 15 bytes regardless of character boundaries, and escapes only `\n` and `\\`.
- A non-ASCII name cut mid-character, such as a `dart compile exe` binary named `k日本語アプリ`, makes the read throw. `linuxTracerPid` then returns null, and `debuggerAttach` reports `failed` ("could not read TracerPid") on every launch, even though the protection is in effect.
- An app following the sdk.md sample exits every time. So does the CLI if it is invoked through such a symlink.

**Fix:** read the file as bytes and parse the ASCII `TracerPid:` line (decode with `latin1`, or `utf8.decode(..., allowMalformed: true)`). Add a parser test case with invalid UTF-8 in `Name:`.

#### 5. Low: the documented log line drops the reason, and the CLI error repeats itself

**Where:** `packages/keybay/lib/src/process_hardening.dart:91-95, 124-133`; `doc/sdk.md:76`; `packages/keybay_cli/lib/src/entrypoint.dart:29-35`.

**What is wrong:**
- `KeybayProcessHardening.toString()` prints only the status names and `ptraceScope`.
- So the guide's `stderr.writeln('Not handling secrets: $hardening')` logs `debuggerAttach: failed` without the `detail`, which is the reason requirement 2 asks for. It also omits `ptraceUnrestricted`.
- When `PR_SET_DUMPABLE` doesn't take effect, the two measures' details differ only by a suffix. The CLI's de-duplicating set keeps both, so it prints: "PR_SET_DUMPABLE 0 did not take effect (dumpable: 1), so a core-pattern pipe can still dump this process; PR_SET_DUMPABLE 0 did not take effect (dumpable: 1)."

**Fix:**
- Build `toString` from each measure's own `toString` (which includes `detail`), plus `ptraceUnrestricted`.
- Give the debugger measure a detail that doesn't repeat the core-dump one (for example "non-dumpability not in effect; see coreDumps"), or have the CLI print one line per failed measure.

#### 6. Low: tests miss the failure branches and leave the shared test process hardened

**Where:** `packages/keybay/test/process_hardening_test.dart:66-67`; `packages/keybay_cli/test/process_hardening_test.dart:22-26, 42-46`.

**(a) Failure branches are untested.**
- Nothing exercises these branches in `applyProcessHardening` (lines 119-153):
  - `!applied`
  - `tracer == null`
  - `tracer != 0`
  - how `failed` combines the measures
- On an untraced CI runner, every test still passes if `tracer != 0` is inverted or the tracer check is dropped.
- Neither package tests the CLI's refusal to run or its error message.

**(b) The shared test process is left changed.**
- `dart test` runs a package's test files as isolates inside one runner process.
- The SDK's second test hardens with no teardown. It leaves the runner non-dumpable with soft `RLIMIT_CORE` 0, which every child spawned by later tests inherits.
- CLI test 1 never restores dumpability. Test 2's teardown restores whatever value it found, which is 0 by then.
- CLI test 1 also asserts `linuxDumpable == 0` without first setting it to 1, so on its own it can't catch a missing `prctl`. Test 2 does catch it.
- I checked both packages: no other test reads the runner's `/proc` entries or depends on its core limit, so nothing breaks today.

**Fix:**
- Give `applyProcessHardening` internal `readStatus`, `readScope` and `environment` parameters, like `linuxTracerPid(read:)`. Then write a table test of the branches and of `failed`.
- Wherever a test hardens the process, restore dumpability and the soft limit in a teardown, or run the hardening tests in a spawned process.

#### 7. Nit: wording and consistency

- **`failed` wording.** `process_hardening.dart:11-13` documents `failed` as "not in effect". But when `TracerPid` can't be read (136-139), non-dumpability is in effect and the result still says `failed`. Say "not confirmed in effect".
- **`ptraceUnrestricted` name.** It can be `true` while `debuggerAttach` is `applied`, because it describes Yama and the window before the call, not this process now. A name like `yamaUnrestricted` would read less like a contradiction. `toString` also omits it.
- **Stop or continue?** `packages/keybay/README.md:39` says to stop if the result has `failed`. `doc/sdk.md:96-97` says continuing is the application's decision. Pick one.
- **macOS overclaim in the intro.** `doc/sdk.md:63-66` says the call keeps same-user programs from reading memory. On macOS it only sets the core limit. Add "on Linux".
- **Sample vs. advice.** The sdk.md sample calls `hardenProcess` unconditionally, right after advising release builds only (lines 89-91). Gating the sample on `const bool.fromEnvironment('dart.vm.product')` (or `kReleaseMode` in Flutter) would match the advice.
- **Long lines.** `packages/keybay/CHANGELOG.md:11` and `packages/keybay_cli/README.md:337` are unwrapped long lines.

### Checked and fine

- **FFI and constants:**
  - `prctl` is declared as an `Int32` option plus `VarArgs` of four `UnsignedLong`. That matches glibc's and musl's variadic `int prctl(int, ...)` on Linux x86_64 and arm64, and it is only resolved on Linux.
  - `_Rlimit` is two `Uint64` fields; `rlim_t` is 64-bit on Linux LP64 and on Darwin.
  - `RLIMIT_CORE` is 4 on both; `PR_GET_DUMPABLE` and `PR_SET_DUMPABLE` are 3 and 4.
  - `RLIM_INFINITY` (-1 as a Dart int on Linux) round-trips through the CLI's saved limit.
- **Never throws:** FFI lookups are lazy and wrapped in `_attempt`, and the `/proc` reads are caught. The iOS, Android and other-platform paths touch no FFI. Repeat calls are harmless; the CLI's failed-exec path exercises this.
- **Linux ordering:** the process becomes non-dumpable before `TracerPid` is read, so no new same-user tracer can attach in between. `coreDumps: applied` is confirmed with `PR_GET_DUMPABLE`.
- **Linux kernel claims, all accurate:**
  - `do_coredump` gives up on a non-dumpable process before both pipe and file core patterns.
  - Pipe core patterns ignore `RLIMIT_CORE`, except the special value 1.
  - `execve` restores dumpability, except for setuid or unreadable images.
  - A `/proc/<pid>/mem` descriptor opened before the call keeps working, and the docs say so.
  - The Yama scope descriptions are correct.
  - Denied access to `/proc/<pid>/environ` is a valid test control.
- **macOS claims, all accurate:**
  - Hardened Runtime without `get-task-allow` refuses `task_for_pid`, and notarization requires both.
  - `PT_DENY_ATTACH` doesn't stop task-port reads, a debugger that launches the process can step around it, and it exits a process that is already traced.
  - The reason for not using it is stated in the code and in sdk.md.
- **CLI behaviour:**
  - The caller's soft limit is captured before hardening, and `restoreForExec` runs immediately before `execve`.
  - After a failed `execve`, the policy is re-applied after errno is read and before the signal state is put back, with no I/O hazard.
  - `tool/test_cli_exec.py` still asserts the child's core limit.
  - The exit code is unchanged, and the new tracer gate is documented in the CLI CHANGELOG and README.
  - No test or harness asserts the old error text.
- **X11 warning:**
  - Detection follows the requested rule and precedence.
  - The warning appears at:
    - the CLI passphrase prompt (the launch summary ends in a newline, and the multi-method chooser case is handled)
    - the CLI PIN prompt
    - the TUI unlock, add-passphrase and hardware-PIN forms
  - The hardware form's error-box height accounts for the warning wrapping to two lines at 36 columns.
  - Tests at 40×24 and 80×20 assert the warning, the actions and the labels.
  - In CI, the only Xvfb run is the clipboard check, which never reaches a prompt, so CI output is unchanged.
- **Tests fail if hardening is removed:**
  - The soft limit is preset non-zero and dumpability is preset to 1.
  - `/proc/<pid>/environ` serves as a positive control.
  - `runKeybay(['--version'])` proves the CLI still hardens itself.
  - The tests skip only when the hard core limit is 0.
- **Docs:** all of requirement 5 is covered. sdk.md, security-levels.md, SECURITY.md, architecture.md, both READMEs and both CHANGELOGs agree with each other, apart from the items above.

## Responses

1. **User namespace — fixed.** The probe above confirmed the finding.
   - `debuggerAttach` now fails unless `/proc/self/uid_map` is the identity map
     `0 0 4294967295`, or when it is unreadable. Its detail names the namespace
     owner's retained `CAP_SYS_PTRACE`. Core files stay `applied`.
   - The limit is now stated in `doc/sdk.md`, `doc/security-levels.md`,
     `SECURITY.md`, both READMEs, both CHANGELOGs and the `hardenProcess`
     dartdoc. The Yama text is qualified.
   - **Decision for the maintainer:** the CLI stops whenever `failed` is true,
     so it now refuses to run in toolbox, distrobox and rootless containers,
     and so does the TUI. Keeping those working would mean gating the CLI on
     `coreDumps` and an attached tracer only.
2. **Child programs — reworded, not added to the API.**
   - The guide now says children, including those started through
     `Process.run`, inherit a soft limit of 0. The hard limit is unchanged, so a
     child can raise its own. Restoring the limit before `execve` means reading
     it before the call, as the CLI does.
   - A `previousSoftCoreLimit` field would serve only a host that calls
     `execve` itself, which `Process.run` cannot. The CLI keeps its own
     `getrlimit`/`setrlimit` bindings for that hand-off. The hardening policy
     stays in the SDK, and the CLI calls `Keybay.hardenProcess()` again after a
     failed exec.
3. **Per-thread tracer — fixed.** `linuxTracerPid` reads
   `/proc/self/task/*/status`.
   - A thread that exits between listing and reading (ENOENT or ESRCH) is
     skipped. Any other unreadable status, or no status at all, fails.
   - Table tests cover a traced worker thread. The Docker probe covers a real
     tracer.
4. **Non-UTF-8 thread name — fixed.**
   - Status files and `uid_map` are read as bytes and decoded as Latin-1.
   - A Linux-only test sets the thread name to invalid UTF-8 through
     `PR_SET_NAME`, then expects `TracerPid` 0.
5. **Log line and repeated error — fixed.**
   - `toString` includes each measure's detail and `yamaUnrestricted`.
   - The CLI prints one line per failed measure.
   - The debugger detail for a dumpable process no longer repeats the core-dump
     detail.
6. **Tests — fixed.**
   - **Branch coverage.** The Linux result is built by `linuxHardeningResult`,
     a pure function, and a table test covers every branch and `failed`.
   - **CLI refusal.** `runKeybay` takes a `hardenProcess` hook, and a test
     checks that a failed result (dumpable, or traced) stops the command.
   - **Test hygiene.** Every test that hardens the process restores the soft
     limit and dumpability in teardown. CLI test 1 now sets dumpability to 1
     first.
   - **User namespaces.** The live tests accept `failed` for `debuggerAttach`
     there, and the CLI live test expects its refusal there.
7. **Nits.**
   - **Done:**
     - `failed` is documented as "could not confirm".
     - `ptraceUnrestricted` is renamed `yamaUnrestricted`.
     - The guide says Keybay leaves the decision to the application and that
       the sample stops, as the CLI does. The README's "stop" matches.
     - The guide's intro is limited to Linux for debuggers.
     - The long lines are wrapped.
   - **Declined: gating the sample on `dart.vm.product`.** That constant is
     false under `dart run` and `dart pub global activate`, so tools shipped
     that way would never harden. The guide now says to call it in every build
     you ship, and to leave it out only while attaching a debugger.

## Follow-up check of b1b5b67

The same reviewer checked the fixes in `b1b5b67`. Its text follows verbatim,
with its heading moved down one level.

### Follow-up check of b1b5b67

**Verdict:** All six findings are fixed correctly. The delta adds no correctness bugs, only the two Low and three Nit items below, so it is ready after those or once they are accepted as known limits.

**Per finding:**
1. **User namespace: fixed.** Only the single identity line `0 0 4294967295` counts as the initial namespace; whitespace is normalised and an unreadable `uid_map` fails. `coreDumps` correctly stays `applied`. The Flatpak PID-namespace `TracerPid` blind spot is now covered by the namespace failure.
2. **Child programs: resolved by rewording.** Declining `previousSoftCoreLimit` is reasonable, since `Process.run` gives no exec hook anyway.
3. **Per-thread tracer: fixed.** `/proc/self/task/*/status` is walked. ENOENT and ESRCH cover a thread that exits between listing and open, and between open and read. Any other error, a failed listing or an empty list returns null and so reports `failed`. A thread created after the listing can't hide a tracer that attached earlier.
4. **Latin-1: fixed.** Latin-1 decodes every byte, and the `PR_SET_NAME` test (0x6b 0xe6 0x97) would fail if strict UTF-8 came back. The test stays on one thread because it has no await, and it restores the name.
5. **Log line and repeated error: fixed.** `toString` now carries each detail. The CLI prints one line per failed measure, details carry no trailing period, and the duplicate line is gone.
6. **Tests: fixed.** `linuxHardeningResult` is pure and table-tested on every branch. The CLI hook is a constant static tear-off. Teardowns are registered in the right order and restore both the soft limit and dumpability; CLI test 1 now sets dumpability to 1 first.

**New or remaining findings:**
1. **Low: the CLI now also refuses in root-owned user namespaces (`packages/keybay/lib/src/process_hardening.dart:206-211, 257-269`; `packages/keybay_cli/README.md:336`).** Unprivileged LXD/Incus containers, Docker with userns-remap and Kubernetes user namespaces all have a non-identity `uid_map`. Their owner is root, so same-user programs outside can't attach. The CLI still refuses every command there, and the detail blames "programs its owner runs". The README and CHANGELOG name only toolbox, distrobox and rootless containers.
   - Fix: document this, and reword the detail to "unless its owner is root".
   - Optional: refine the check with `ioctl(/proc/self/ns/user, NS_GET_OWNER_UID)`, which returns the overflow uid when the owner is unmapped. Treat that as a heuristic only, because a newuidmap setup can leave a same-user owner unmapped.
2. **Low: Flatpak apps can't follow the guide (`doc/sdk.md:58, 97`; `packages/keybay/README.md:39`).** In Flatpak, `debuggerAttach` is always `failed`, and the sample and README stop on `failed`. So a Flatpak SDK app either never starts or must tell "user namespace" apart from "tracer attached" by matching `detail` text, which the docs say not to branch on.
   - Fix: expose the cause as data (for example `bool userNamespace`, or a reason enum on the measure). Then tell Flatpak apps to accept that case knowingly while still stopping for a tracer or a dumpable process.
3. **Nit: SDK test 1 isn't namespace-safe (`packages/keybay/test/process_hardening_test.dart:42, 45`).** The two denial asserts fail when the runner is root inside a user namespace (`unshare -r`, rootless podman as root). A child there holds `CAP_SYS_PTRACE` in `mm->user_ns`, so it can still read `environ` and open `mem`. That contradicts the response that the live tests accept user namespaces; toolbox, which keeps the user's uid, is fine.
   - Fix: skip both asserts unless `linuxInitialUserNamespace() == true`.
4. **Nit: "release builds" wording remains.** `packages/keybay/lib/src/v2/keybay_v2.dart:66-68` and `doc/security-levels.md:100-101` still say "release builds", while `doc/sdk.md:89-92` now says "every build you ship". Align them.
5. **Nit: the new per-measure stderr lines are untested.** The refusal test checks only the exit code because `runKeybay` writes to the real stderr. Assert the lines through an injected sink, or accept them as untested.

### Responses to the follow-up

1. **Root-owned namespaces: documented, and still failed.**
   - The detail now says the owner is the user in Flatpak, toolbox or a
     rootless container, and root in LXD, Incus or userns-remapped Docker, and
     that Keybay cannot tell which. The CLI README and CHANGELOG say the same.
   - `NS_GET_OWNER_UID` was not adopted. From inside `unshare -r`, the user who
     owns the namespace appears as uid 0, and an unmapped owner can be the user
     too, so no answer would be reliable.
   - Whether the CLI should refuse there stays the maintainer's decision.
2. **Flatpak apps: the cause is now data.**
   - A failed measure carries `cause`, a new exported `KeybayHardeningCause`:
     `settingRejected`, `unreadable`, `traced` or `userNamespace`.
   - The namespace is checked last, so `userNamespace` means nothing else
     failed.
   - `doc/sdk.md` shows a Flatpak app accepting only that cause, and the table
     test covers the ordering.
3. **Namespace-safe test: done.** The denial asserts run only in the initial
   user namespace.
4. **Wording: aligned.** The dartdoc and `doc/security-levels.md` now match
   `doc/sdk.md`.
5. **Error lines: tested.** `ProcessHardening.failureLines` builds the CLI's
   error, `runKeybay` writes it, and a test asserts its lines.

## Automatic hardening rework

After `6e11521`, the maintainer asked for these changes:

- **Automatic.** Hardening becomes the default: Keybay applies it at the first
  open, in release and profile builds, and skips debugger blocking in debug
  builds.
- **One rarely used opt-out.**
- **A read-only status** apps can check.
- **No X11 warnings,** and no X11 signal in the API. X11 stays a documented
  limit.
- **Containers keep working.** The CLI and TUI run in containers, and the
  status shows in an existing surface rather than as a warning on every run.

`658d9d8` made those changes, and the fixes below answer its re-check.

### Choices

- **Opt-out.** The opt-out is the build define
  `--dart-define=keybay.process_hardening=false`. `keybay_compile` gets a
  `--no-process-hardening` flag for it. It is fixed at build time, it is in
  effect before the first open, and no dependency can change it at run time.
  It is the mechanism already used to embed `keybay.application_id`.
  - Not a pubspec key: the `keybay:` block is read at run time only for source
    runs, and Flutter builds never read it.
  - Not `Keybay.configure`: it would be Keybay's first run-time knob.
- **Status.** `Keybay.processHardening` is the status.
  - `open` applies hardening every time and records the result. A failure
    stays recorded.
  - The getter applies hardening only when no open has run yet. That lets the
    CLI harden before it reads a passphrase.
- **CLI.** The CLI stops only when core files stay enabled, as it did before
  this branch. Neither keybay has a status or doctor command, so the TUI's
  Settings, Security screen shows "Hardening: On", "Partial", "Debug" or
  "Off".
- **X11.** The X11 prompt warnings are reverted to main, and `x11Session` is
  gone.

### Verification after the fixes

- **Analyzer:** `dart analyze --fatal-infos` is clean for both packages.
- **Formatting:** changed files pass `dart format` under Dart 3.13.5.
- **macOS suites:** the SDK suite passed 613 tests with 3 skipped; the CLI suite
  passed 284.
- **Repo checks:** the invariant, CI-impact and site-demo checks pass, and the
  browser demo still compiles to JavaScript.
- **Compiled fixture:** the AOT identity fixture now prints `releaseBuild` and
  `hardeningEnabled`. Its source run is a debug build, its `keybay_compile`
  output a release build, and its `--no-process-hardening` module has hardening
  off.
- **Linux probe** in Docker (Dart 3.13.5, arm64):
  - A JIT run stays dumpable, with soft limit 0, and reports `debugBuild`.
  - A `dart compile exe` build goes non-dumpable and denies same-user reads of
    `environ` and `mem`.
  - A build with the opt-out changes nothing.
  - The user-namespace and tracer cases report `failed` with causes
    `userNamespace` and `traced`.
- **Two-step build:** a kernel-then-exe build with `-D` defines, like
  `keybay_compile`, reported a release build on Dart 3.12.2 and 3.13.5.

### Re-check of 658d9d8

A fresh reviewer (Claude Opus, xhigh effort, reading only git objects) checked
`658d9d8`. Its text follows verbatim, with headings moved down three levels.

#### Re-check of 658d9d8: automatic process hardening

**Verdict: Ready after fixes.**

The commit meets the five points: hardening is automatic, there is one opt-out, the status is readable, the X11 warnings are gone, and containers keep working. One defect in the build helper very likely leaves `keybay_compile` output unhardened on Linux, and no test can catch it. I read git objects only and ran no builds, so finding 1 is inferred from the code (see its verification step).

##### Findings

1. **High: `keybay_compile` output very likely hardens as a debug build.** `packages/keybay/bin/keybay_compile.dart:47-76`, `packages/keybay/lib/src/process_hardening.dart:11-13`, `doc/sdk.md:83-87`
   - **What is wrong.** The helper compiles in two steps:
     - `dart compile kernel -Dkeybay.application_id=…`
     - then `dart compile exe application.dill`, with no `-D` at all.
   - **Why that matters for `releaseBuild`.** `v2_identity_modes_test.dart` shows the compiled fixture still resolves `keybay.application_id`, so the kernel step must already fold every `fromEnvironment` constant. Nothing defines `dart.vm.product` or `dart.vm.profile` in that step, so both fold to false, and `releaseBuild` is false in the AOT binary.
   - **Who it affects.**
     - Linux apps built the way `doc/sdk.md:168-172` tells AOT Dart apps to build. They stay dumpable and attachable by same-user programs and report `debugBuild: true`, while sdk.md:85 promises the full policy.
     - The CLI binaries built by `tool/build_cli_test_bundle.sh` and `tool/test_cli_core.sh`, and the CLI README's development build.
     - Probably not the shipped CLI: rk's release compiles from source with the define. Confirm this.
   - **How to verify.** Build with the README's `keybay_compile` command on Linux and open Settings → Security. I expect "Hardening: Debug build".
   - **Fix.**
     - Add `-Ddart.vm.product=true` to the kernel step. This is what `dart compile exe` passes when it compiles from source.
     - Have the `v2_identity_modes` fixture also print `Keybay.processHardening.debugBuild`, and expect `false` for both compiled outputs.

2. **Medium: no test catches an AOT build classified as debug.** `packages/keybay_cli/test/process_hardening_test.dart:25-27`, `packages/keybay/test/process_hardening_test.dart:72`
   - **What is wrong.** The SDK tests check `releaseBuild == false` only under `dart test`, and test the release path only through `applyProcessHardening(release: true)`.
   - **The CLI test's comment is wrong.** It says `tool/test_cli_tui.py` and `test_cli_exec.py` check release builds, but neither looks at dumpability:
     - The TUI core check runs only when the core pattern is a plain `core` file. There, soft `RLIMIT_CORE` 0 alone prevents the file, so dumpability is never tested.
     - The exec check reads only the child's soft limit.
   - **Why it matters.** Finding 1 passes every suite.
   - **Fix.**
     - Add the fixture assertion from finding 1.
     - On Linux, have `test_cli_tui.py` assert that a same-user child cannot read `/proc/<tui pid>/environ` while the TUI is open.
     - Correct the comment.

3. **Low: the CLI docs promise non-dumpable and a refusal in JIT runs, where neither holds.** `packages/keybay_cli/README.md:332-334`, `packages/keybay_cli/CHANGELOG.md:5-7`, `SECURITY.md:97-98`, `packages/keybay/README.md:39`
   - **What changed.** On main the CLI always made itself non-dumpable and refused to run otherwise. Now a JIT CLI stays dumpable on Linux, for example the README's `dart pub global activate --source path` install or `tool/keybay-dev`.
   - **What happens there.** `coreDumps` is `notAttempted`, so `refusal` lets the command run, and a core-pattern pipe may still receive a dump.
   - **Why it matters.** This follows the debug-build direction. But "same policy as before" and "stops if core files stay enabled" are false for that install path. The CHANGELOG entry at lines 11-12 mentions only `dart run`.
   - **Fix.**
     - In the CLI README, say that source and Pub installs are debug builds: dumpable on Linux, and shown as "Hardening: Debug build".
     - Limit the CHANGELOG, SECURITY.md and SDK README sentences to release builds.

4. **Low: the status is a fresh re-application, not what applied at open.** `packages/keybay/lib/src/v2/keybay_v2.dart:58, 97`
   - **What is wrong.** `open` throws away the result of `applyProcessHardening()`, and the getter re-applies and re-observes on every read.
   - **Why it matters.** Suppose a tracer is attached during `open` and detaches before the app reads the status. The app then sees `applied` and never learns the store key loaded under a tracer. A getter that changes process state also conflicts with "read-only".
   - **Fix.** Record the most severe result seen by any application (per isolate is enough) and return it. Apply from the getter only when nothing has been applied yet.

5. **Low: the opt-out reasoning misreads RFC 0001, and `keybay_compile` builds cannot opt out.** `doc/sdk.md:133-141`, the commit message, `keybay_compile.dart:12-19, 49-53`
   - **RFC 0001.** Line 483 rules out a separate `create()`/`configure()` step for initializing a store, not configuration in general.
   - **The define itself is sound.** It is fixed at build time, it is in effect before the first open, and no dependency can flip it at run time.
   - **The gap.** `keybay_compile` accepts exactly three arguments and forwards no defines. Its users therefore have no opt-out, and sdk.md names only `flutter build` and `dart compile exe`.
   - **Fix.**
     - Justify the define on the grounds above.
     - Either have `keybay_compile` read an optional `keybay: process_hardening: false` from the owning pubspec, as it reads `application_id`, and pass the define; or document that `keybay_compile` builds cannot opt out.

6. **Low: the new Security line overflows the narrowest layout.** `packages/keybay_cli/lib/src/tui/settings.dart:355-361`, `native_model.dart:24`
   - **What is wrong.** At 40×24 the settings content column is 20 columns by 16 rows.
     - Before this commit, a store with a passkey and no passphrase filled it exactly: heading, spacer, 3 status lines, spacer, 3 actions of 2 rows each, spacer and a 3-line description make 16 rows.
     - The new line makes 17, which clips the description.
     - "Hardening: Debug build" is 22 characters, so it wraps to a second row, despite the code's "one short word" comment.
   - **The test misses it.** It checks only "Partial", with no passkeys.
   - **Fix.** Use one-word labels (for example "Debug"). Test every label at 40×24 with a passkey and no passphrase.

7. **Low: an unrelated test now changes the shared test process.** `packages/keybay/test/v2_keybay_test.dart:61`
   - **What is wrong.** That test's `Keybay.open()` now sets the test runner's soft core limit to 0 and never restores it.
   - **Why it matters.** `dart test` runs test files at the same time, as isolates in one process. The call can land between `_setSoftCoreLimit(caller)` and `expect(softCoreLimit, caller)` in the opt-out test (`process_hardening_test.dart:128-146`). That failure would be rare but random.
   - **Fix.** Restore the limit in that test's teardown, or tag the hardening tests to run alone.

8. **Nit: misplaced doc comment.** `native_model.dart:17-19`. The doc for `createNativeTuiModel` now sits above `tuiHardeningStatus`, so `tuiHardeningStatus` has two comments and `createNativeTuiModel` has none.

##### Checked and fine

- **Ordering.** `open` hardens synchronously before `_withCredential` copies the credential. The CLI hardens before it parses a command or reads a passphrase. The "Earlier hardening" bullet covers a passphrase collected before `open`. `Keybay.reset()` does not harden, but it decrypts nothing.
- **Repeat calls and isolates.** Hardening keeps no Dart state, and `prctl` and `rlimit` are process-wide, so calling it again from any isolate is safe. `ProcessHardening.apply` records the caller's soft limit before the SDK sets it to 0.
- **Debug detection.** `dart.vm.product || dart.vm.profile` matches Flutter's release and profile modes and `dart compile exe` from source. Only the exact value `false` turns hardening off, as sdk.md says.
- **Status values.**
  - Linux debug: `notAttempted`, and the detail says a core-pattern pipe may still receive a dump.
  - Opt-out: `notAttempted` with `disabled` set, and the process is left untouched.
  - macOS debug: core files `applied`; debugger `notAttempted`, with the code-signature detail.
  - `failed` is never true in a debug build or with the opt-out.
- **`keybay run`.** The caller's soft limit is restored right before `execve`, and set back to 0 after a failed exec. A failed exec leaves dumpability unchanged, and a successful one restores it for the new program.
- **CLI gate and TUI.** Only failed core-file protection stops a command. User-namespace and tracer failures let it run, and both are tested. The label order (Off, Partial, Debug build, On) is correct.
- **X11.** The CLI and TUI files the warnings touched are identical to main (283ef5d). No `x11Session`, `isX11Session`, `x11Warning` or `hardenProcess` remains. X11 is still listed as a limit in sdk.md, security-levels.md and SECURITY.md.
- **Browser demo.** `model.dart` and `settings.dart` do not import `package:keybay`. The mapping from the SDK status lives in `native_model.dart`.
- **Docs.** They state every limit: root and the kernel, code injected at launch, the window before hardening, X11, user namespaces, debug builds, and the opt-out weakening protection.
- **Hardening tests.** They restore the soft limit and dumpability in teardown. The `open` test fails at `invalidAuthInput` before any platform access.

### Responses to the re-check

1. **`keybay_compile` and release detection — not reproduced, guarded.**
   - On Dart 3.12.2 and 3.13.5, a kernel step with `-D` defines followed by
     `dart compile exe` produced `releaseBuild` true. The kernel step leaves
     `dart.vm.product` unevaluated, and the AOT step sets it.
   - `keybay_compile` now passes `-Ddart.vm.product=true` anyway, so detection
     no longer depends on when constants are folded.
   - The identity fixture asserts that its output is a release build.
2. **No AOT test — fixed.**
   - The compiled-fixture assertion is that test.
   - The misleading CLI test comment is corrected.
   - The proposed `/proc/<tui pid>/environ` check in `tool/test_cli_tui.py` was
     not added. It can run only in Linux CI, which this worker could not run
     locally.
3. **JIT CLI docs — fixed.** The CLI README, CHANGELOG, `SECURITY.md` and the
   SDK README now limit the full policy and the refusal to release builds. They
   say source and Pub installs are debug builds that show "Hardening: Debug".
4. **Re-applied status — fixed.**
   - `open` records each application. A failure stays recorded
     (`worseHardening`).
   - The getter applies hardening only before the first open.
   - The two live CLI tests now run in fresh isolates, since each command is
     its own process.
5. **Opt-out reasoning and `keybay_compile` — fixed.**
   - The define is justified on its own merits, as above.
   - `keybay_compile --no-process-hardening` passes it on. The fixture's AOT
     module uses that flag and checks that hardening is off.
6. **Security line overflow — fixed.**
   - The labels are one word: On, Partial, Debug, Off.
   - In the narrow layout, the hardening line takes the blank row before the
     actions.
   - A test renders every label at 40×24 and 80×20 with a passkey and no
     passphrase, and checks the description's last word.
7. **Shared test process — fixed.**
   - `v2_keybay_test` restores the soft limit after its real `open`.
   - The opt-out test sets and reads the limit back-to-back, which leaves the
     smallest window another isolate could hit.
8. **Doc comment — fixed.**

## Not covered here

- The package suites did not run on Linux locally, and nothing ran on Linux
  x86_64. The probe exercised the SDK source, not the packaged CLI.
- The CLI's X11 warnings are covered by tests with injected readers and the
  TUI tester, not by a PTY run in a real X11 session.
- No Flatpak, toolbox or Yama 1 host was used. The user-namespace case used
  `unshare` in Docker, with seccomp unconfined.
- The follow-up changes after `b1b5b67` were not reviewed again, and neither
  were the fixes after `658d9d8`'s re-check.

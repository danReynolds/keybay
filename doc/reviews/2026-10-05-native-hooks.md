# Native build hooks and local command execution

Keypass commit c44ba295a2309eead76108a7aa1b1f49711eccee adds a desktop
code-assets hook and @Native bindings. Ordinary Dart run/test/build consumers
receive the hardware adapter plus relocated libfido2, OpenSSL and CBOR libraries.
Source-build prerequisites are explicit; hooks never install system packages.
Mobile hosts retain native linking/lifecycle and no desktop library is emitted.

## Dependency review

New exact Keypass dependencies are Dart team's hooks 2.2.0 and code_assets 2.1.0.
They orchestrate builds and represent code assets; they do not implement vault
cryptography or introduce a credential/provider service. Their package sources,
SDK floors and dependency manifests were inspected locally and resolved from the
hosted registry. record_use 1.1.1 is the new transitive protocol package; its
meta ^1.19.0 requirement advances the workspace's meta version to 1.19.0.
Other newly runtime-reachable packages (logging, path, pub_semver, source_span,
string_scanner, term_glyph, yaml) were already in the workspace's hosted closure.
The SDK and CLI closure firewalls now explicitly cover these versions/sources.
Keypass remains pinned to a reviewed Git commit; no path override is shipped.

The hook uses the existing CMake source, pinned JSON-header download/checksum,
and bounded four-library packaging policy. It tracks source and resolved library
inputs for cache invalidation, rejects foreign desktop targets, and never starts
a credential ceremony. Native dependency notices ship with Keypass's source.
The runtime's binary PIN/secret ABI and cleanup remain unchanged. Missing assets
fail availability instead of silently switching to another library/provider.

## Existing custom AOT packaging

The signed runtime/module packaging is preserved through an explicit compile-time
manual-bundle selection. Its fixed sibling-library layout and signing constraints
remain verified by the existing packaging suite. This is a compatibility path;
it does not make the custom AOT packager consume hook outputs. Generic rk release
code-asset staging/signing remains a separate work item.

## rk local execution

Dart 3.12 resolves hook preparation relative to its invoking project. An absolute
entrypoint from an unrelated cwd can skip the hook and reuse stale cached assets.
A generic rk local bootstrap prepares hooks in the owning package, restores the
caller cwd and spawns the original entrypoint with its explicit package config.
It preserves Platform.script, stdin, arguments and exit status. The regression
uses a transitive native dependency and changes its C source between invocations.
Plain local Dart packages keep the direct launcher. Reselect Local to generate
a hook-aware launcher after installing the rk fix.

## Evidence boundaries

Keypass: macOS 164 tests; Linux container 163 tests and one platform skip.
Both platforms pass independent transitive-consumer Dart runs and relocated
compiled bundles (including symlink invocation). The real ABI/worker probe
rejects invalid input before device I/O. These are loading/package checks,
not hardware enrollment or physical-key proof. Ordinary-user Linux USB access,
Flutter desktop framework packaging, signing/publication and installed upgrades
retain their own qualification gates.

## Keybay verification

The SDK run passed 587 tests with 12 platform/integration skips and two crash
worker timing failures under local load. The isolated eight-case crash-recovery
rerun passed, covering both failures. The CLI core runner then passed cleanly:
254 Dart tests, 38 general TUI PTY cases, 18 simulated hardware TUI cases, 13
hardware command cases, 22 hidden-input boundary cases, source-runner caller-cwd
checks, clipboard, archive/identity checks and relocated native ABI loading.
Repository tests passed (45), and scoped analysis was clean.

rk commit 45b39e8 adds generic local hook preparation and separates local
installation discovery from release dependency-source validation. Its 119
focused installation/resolver/review cases passed across a focused run and CLI
rerun. The broad rk run was stopped after unrelated timing failures on the busy
host; it is not a full-suite pass. The original-entrypoint bootstrap retains
Dart defines, including the CLI application identity.

The local rk installation was updated from 6e7bb16 to 45b39e8 and selected this
checkout with `rk use local -p keybay_cli`. A fresh fish shell resolves `keybay`
to rk's managed command and prints 0.2.0 from outside the repository. The old
installation revision is retained in Git. No user's vault or physical key was
accessed in this qualification.

The rk source launcher separately passed all 18 hardware TUI and 13 hardware
command scenarios with the simulated provider. Source compilation received a
larger startup allowance on the busy host; PIN, cancellation, signal and
terminal-restoration deadlines were unchanged. The two foreground-loss checks
were rerun separately because their original ready deadline covered compilation.
An actual Keypass native ABI/worker probe also passed through rk from an unrelated
cwd in Keybay's workspace, rejecting invalid input before device enumeration.
Physical enrollment and reopen through the ordinary Keybay command remain the
operator's next check.

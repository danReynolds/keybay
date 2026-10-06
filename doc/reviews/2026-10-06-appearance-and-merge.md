# Appearance and merge review

The outer frame now uses the same accent style as the plain `keybay` title.
Changing the accent therefore updates both immediately. Focus, warning and
error roles retain their separate styles, and the renderer still owns
`NO_COLOR` handling. The README describes this behavior.

This is a local engineering follow-up to the reviews recorded in
`2026-10-02-keypass-integration.md`, `2026-10-04-tui-passkeys-plan.md`, and
`2026-10-05-unlock-flow.md`, not a new independent security audit. The review
checked the frame/theme changes, settings focus and choice handling, preference
read/write bounds and cleanup, application of preferences before unlock, and
the existing auth/secret-cleanup boundaries. No new code blocker was found in
the appearance changes. Existing GitHub review submissions and inline threads
were empty when inspected.

Current local validation:

- CLI analysis: clean.
- Appearance and complete TUI widget suites: 129 passed, including the supported
  compact terminal sizes, persistence, focus, confirmations and masking.
- Native terminal suite: 39 passed, including `NO_COLOR`, signal/foreground
  behavior, secret masking, resize handling and terminal restoration, using
  the disposable SDK harness compiled with the accent-border change.
- SDK suite excluding integration: 588 passed, three skipped, one subprocess
  timeout under concurrent test load. The complete affected Secret Portal file
  passed all 39 cases when rerun alone. This is recorded as a rerun, not a clean
  first pass or native Linux-provider qualification.

The branch incorporates `origin/main`'s October 5 security assessment without
changing its report or disposition. The untracked September 28 research notes
were left untouched.

## Dependency access follow-up

With the owner's explicit approval, `danReynolds/keypass` became public on
October 6. Anonymous HTTPS discovery succeeded without a credential helper.
The SDK/CLI manifests and all three lockfiles now use HTTPS for the unchanged
reviewed commit `e5fbdda99639d0b0693b3b0f60ca9825cd5fc336`; the dependency-source
firewall expects the same public URL. Workspace resolution with
`--enforce-lockfile` succeeds. No dependency version, commit, or hosted package
hash changed. Hosted CI must still pass before merge; pub.dev publication is a
separate release action.

## Fresh hosted CI and compiler follow-up

Run `37475712941` can fetch the public dependency. It exposed three remaining
issues: one CLI test needed formatting, the publishable SDK rejects a Git
dependency, and Keypass's hook dependencies conflicted with Flutter 3.44.4's
`meta` pin. Native integration jobs also reached the CLI build and found that
current Dart refuses direct source AOT compilation for a package with hooks.
The Flatpak, site and Gradle-wrapper checks passed in that run.

The controlled compiler now resolves the application's identity and manual
native-bundle define into a temporary kernel, then compiles that kernel into
the requested executable or AOT module. The temporary stage is always removed;
the native companion validation and signing contract are unchanged. Validation:

- Dart 3.13.5: all four identity-mode tests passed, including executable and
  separate-AOT identity parity, activation and installation.
- Dart 3.13.5 and minimum Dart 3.11.0: the real CLI compiled and reported its
  version successfully.
- Dart 3.13.5: the macOS release candidate built and launched; native CTest and
  relocated/symlink ABI loading passed. Missing companions were rejected. No
  device was accessed and this was not a notarized release.
- Targeted compiler analysis and diff whitespace checks passed.

Keypass PR 3 prepares compatible `hooks 2.0.2` / `code_assets 1.2.1`, a locked
Flutter consumer-resolution CI check and a public package archive. Its local
suite passed 166 tests with one platform skip, and the transitive/cache/source
relocation and CLI bundle checks passed. Committed-archive publication dry-run
reports only the three intentional exact-pin warnings. Publication itself is
pending owner approval; no pub.dev upload has occurred. The SDK dependency must
be switched to the resulting hosted release and all CI rerun before merge.

## Approved hosted release

The owner explicitly approved the permanent pub.dev release. Keypass
`0.1.0-dev.2` is published from merged commit
`e4c933a5a7a63ed51bdfa211e528a42659cd6f1c` (all eleven prerequisite CI jobs passed).
The served archive has SHA-256
`9c46f2bb0413b4f891d5e7eddce46830d2fa4c5c83ebad08b14333efe051c1ec`.
All 103 published files match the release commit, accounting for the repository's
explicit CRLF checkout rule for `native/android/gradlew.bat`.

Both Keybay packages now use the exact hosted version. All three dependency
locks resolve with enforcement; SDK and CLI source checks require hosted
Keypass and the SDK checks the registry archive hash. Native builds verify a
checked-in hash manifest for the release's native inputs and license instead
of requiring a Git checkout. Six tests cover accepted published source and
rejection of modified, missing, added and linked inputs. Bundle metadata still
records the reviewed source commit and verifies its native companion hashes.

Full workspace analysis, SDK dependency checks, 275 CLI tests, 39 general TUI
PTY checks, 19 simulated hardware TUI checks, 13 simulated hardware command
checks, and the Flutter demo's analysis and ten tests passed locally. The
macOS CI delete-confirmation test previously accepted a key name from the
still-arriving dialog as evidence of returning to the list. It now waits for
the unique list footer before reopening the dialog. No production interaction
was changed for this test synchronization fix. Final hosted CI remains required.

### Original blocker

At the initial review, PR 88 depended on the private, unpublished `danReynolds/keypass` repository
through `git@github.com:danReynolds/keypass.git`. GitHub run `37379487368` fails
dependency resolution with `Permission denied (publickey)` before the affected
CI lanes can analyze, build or test. Live inspection confirmed Keypass remains
private and Keybay had no repository Actions secret configured for it.

The existing local dependency cache made local tests possible, but did not
resolve fresh-checkout or public-consumer builds. The follow-up above resolves
that access blocker without adding a private CI credential. No check was
disabled or bypassed.

Publication, signed distribution, installed upgrades and physical-device
qualification remain separate obligations in the existing release documents.

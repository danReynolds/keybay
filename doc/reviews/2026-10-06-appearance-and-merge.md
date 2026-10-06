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

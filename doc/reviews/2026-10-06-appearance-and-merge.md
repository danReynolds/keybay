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

## Merge blocker

PR 88 still depends on the private, unpublished `danReynolds/keypass` repository
through `git@github.com:danReynolds/keypass.git`. GitHub run `37379487368` fails
dependency resolution with `Permission denied (publickey)` before the affected
CI lanes can analyze, build or test. Live inspection confirmed Keypass remains
private and Keybay has no repository Actions secret configured for it.

The existing local dependency cache makes local tests possible, but does not
resolve fresh-checkout or public-consumer builds. A publicly accessible Keypass
source with HTTPS pins, or an explicitly chosen private-dependency distribution
and CI access arrangement, is required before merging. Changing repository
visibility or granting CI access requires the owner's authorization; neither
was done as part of the visual change. No check was disabled or bypassed.

Publication, signed distribution, installed upgrades and physical-device
qualification remain separate obligations in the existing release documents.

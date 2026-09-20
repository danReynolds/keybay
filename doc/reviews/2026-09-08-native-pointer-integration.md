# Native pointer and exact-text integration

Keybay pins published Fleury commit
`82065f614050f134b95448c6084614953839f8a2`, combining
[PR #233](https://github.com/danReynolds/fleury/pull/233) native pointers with
[PR #235](https://github.com/danReynolds/fleury/pull/235) exact-text editing.
No local dependency overrides remain. Both PRs merged after their final hosted
checks passed: #233 as `343ae093` and #235 as `61f41689`. The pinned commit is
an ancestor of Fleury main, with identical runtime source and dependencies.

## Review findings and resolution

Independent agent review found that a captured native drag lost its cursor
when the mouse moved outside its original region. The fix retains the press
owner's cursor through capture and handles release, cancellation, disabled or
removed controls, and terminal authority loss. The unchanged reproducer and
follow-up button-capture cases pass; no remaining pointer finding was reported.

The upgrade also exposed a pre-existing incompatibility: Fleury's canonical
editing model transformed control characters and line endings. Two existing
Keybay tests caught escaped-preview changes and potential silent corruption on
an untouched save. Their original expectations remain intact.

PR #235 adds one explicit `preserveText` policy to the existing editing model
and controller. It preserves text through edits, paste, composition and history.
Disposal drops controller references. Renderers replace unsafe graphemes while
measuring and painting in the original offset space. Masking, semantic redaction
and clipboard policies remain separate. Review caught two additional paths—submission-history
restoration and CRLF navigation/deletion—and verified their fixes with unchanged
independent reproducers. No remaining actionable finding was reported.

The final combined commit was independently reviewed again, including its
generated browser client, text-widget merge, and Keybay adapters. The client
freshness check, 20 integrated Fleury tests, and five focused Keybay tests passed.

## Keybay changes

- Use the current list API (`initialIndex`, `currentIndex`,
  `onFocusedItemChanged`, `onSelect`, automatic item-key reconciliation) and
  single-argument pointer callbacks.
- Declare enabled/busy cursor hints on custom action and settings rows.
  Fleury owns protocol negotiation, hit testing, capture and terminal restoration.
- Opt only secret controllers into exact text, including recreated controllers
  after submission/erasure. Name and search fields retain their existing policy.
- Retain the two original preservation tests; add an exact passphrase setup and
  unlock test containing tabs, CRLF, Unicode and escape characters.

## Validation

`./tool/test_cli.sh core` passed against the published pin, with no overrides:
168 CLI tests, fatal-info analysis, 34 native TUI PTY cases, and the workflow's
command/prompt/exec/clipboard/archive checks. Receipt:
`build/regression/run-M71xYd/report.json`.
The new PTY case negotiates pointer support through the production native driver,
checks text/hand/default transitions, and verifies one matching push/pop with
restoration before leaving the alternate screen. Tests use a disposable SDK
engine and private clipboard; no real vault data is involved.

Upstream pointer CI passed all hosted checks, including the full cross-package
check, hot-reload gate, fast performance gates, documentation, and generated
project checks on Linux/macOS/Windows. The separate exact-text patch passed
the full local `dart tool/fleury_dev.dart check` and 272 focused editing/widget
tests; its new coverage includes both fields,
masked/unmasked rendering, batched paste, composition, selection, history,
CRLF, and controller disposal.

Final combined-head CI also passed the full cross-package check, hot-reload
and fast performance gates, docs build, and all four generated-project checks.
The local global activation was refreshed; `keybay --version` passed outside
the repository without opening a vault.

An earlier hidden Kitty 0.47.4 protocol probe confirmed native shape negotiation,
hand-pointer selection and restoration of the prior shape. Other terminals
need protocol support; unsupported terminals and multiplexers keep their normal
pointer. These are CLI/framework regression receipts, not new SDK platform or
signed-distribution qualification claims.

## macOS Terminal capability check (2026-09-09)

A disposable Terminal 2.15 (466) window received the same five-shape OSC 22
query used by Fleury, followed by the device-attributes query as a sentinel.
It answered device attributes and gave no pointer-shape response. Negotiation
therefore remains disabled in this terminal. Hover underlining still works
because mouse events and native pointer shapes are separate capabilities.
The probe restored terminal modes and did not open a Keybay store. This is
local evidence for the tested Terminal build, not a universal terminal claim.

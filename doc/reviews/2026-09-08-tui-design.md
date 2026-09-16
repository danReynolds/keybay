# Keybay TUI design review

> Current follow-up: [September 12 UX and framework plan](2026-09-12-tui-ux-and-fleury-plan.md),
> including fresh interaction probes and a prioritized implementation sequence.

Reviewed 2026-09-08 against the working tree on `codex/rfc-2-cli-tui`, based on
`f14e30e`. Runtime/regression source digest:
`6ea4111ca5f1aa4198160d6c8dc79057a0e31101d8e9e8d814a91cabeaae078c`.

## Verdict

Implementation follow-up: the user approved this cleanup and the revised blur/
resize policy. The implementation now preserves locally rejected drafts,
restores search/cancel focus, shares action eligibility, and refines the form
and secondary-screen hierarchy. Masked drafts survive blur and resizing, with
cleanup retained at submission/cancellation/invalidation/exit. The findings
below describe the reviewed baseline; current verification is tracked in
[CLI qualification status](../cli-qualification-status.md).

Subsequent product decisions: renaming remains outside scope. Edit uses the
key name itself as its title, followed directly by Value. New retains its
editable key field; the SDK API stays unchanged. The vault and forms share
aligned action columns, bracketed shortcut hints and calmer label weight.
Settings now groups actions in a bordered list with a full-row focus marker,
shortcuts, and a description of the selected action. Status stays above the
menu, protection and data actions are separated, and a compact footer handles
navigation. The same confirmation and session boundaries remain in place.

The one-list vault, compact Key/Value form and small confirmation dialog are a
sound design for an austere secure key store. The happy path is substantially
clearer than the earlier dogfood versions. We should keep that architecture and
layout, but finish a bounded recovery and consistency pass before calling the
UX high quality.

Three independent agents reviewed interaction design, visual design, and peers.
All three identified correction/recovery as the main remaining weakness. The
review also included current Fleury cell renders at 40 and 80 columns and five
targeted executable checks. The existing 140-test CLI suite and 23 native PTY
cases passed before this review; the findings below expose gaps in that coverage.

Peer comparisons use current primary documentation, rather than hands-on peer
sessions. Renders use an illustrative xterm palette. Real terminal themes,
assistive technology and first-time-user trials remain outside this evidence.
Only disposable data and fake clipboard callbacks were used. Production code
was not changed during the review.

## Peer comparison

| Reference | Documented behavior | Implication for Keybay |
|---|---|---|
| [gopass](https://github.com/gopasspw/gopass/blob/master/docs/commands/show.md), terminal secret-store peer | Its `--clip` action copies without displaying the secret; missing entries can invoke fuzzy search. | Keep explicit Copy separate from Reveal. A simple substring filter remains appropriate for Keybay's scope. |
| [KeePassXC](https://keepassxc.org/docs/KeePassXC_GettingStarted), GUI secret-manager reference | Explicit reveal/copy controls; keyboard save/search; Esc clears search. Deletion can use an optional Recycle Bin. | Keep visible actions and Save chords. Improve filter recovery and say deletion has no undo in Keybay. The comparison does not call for a recycle bin or richer record types. |
| [Lazygit](https://github.com/jesseduffield/lazygit/blob/master/docs/keybindings/Keybindings_en.md), terminal interaction reference | `/` searches, `?` opens keybinding help, Esc cancels, and actions depend on context. | Keybay's visible action row is a good fit. Focus context and enabled actions should agree. No panel framework or command palette is warranted. |

These are interaction references, not evidence that Keybay matches any peer's
security guarantees or complete feature set.

## Fix before calling the UX polished

### 1. Preserve drafts on correctable name errors

**Confirmed defect, highest priority.** New → invalid or duplicate name → enter
a value → Ctrl+S erases the value before displaying the name error. The field
still has focus, while the actual problem is in Key. Correcting only the name
and saving again can create a record with an unintended empty value; that
sequence was also reproduced.

Cause: `SecretForm._submit` calls `_erase()` before `TuiModel.save` performs
name/duplicate validation. See `packages/keybay_cli/lib/src/tui/screen.dart:804`
and `packages/keybay_cli/lib/src/tui/model.dart:258`.

Validate locally detectable name errors before transferring/clearing the value.
Retain the masked operation-owned draft, focus Key, and associate feedback with
that field. Keep the established cleanup on accepted submission, cancellation,
invalid oversized/control input, and session/security invalidation. Do not add
a draft cache or preserve secrets across sessions.

Acceptance: invalid and duplicate names retain the draft; correcting a name
saves the original exact bytes; no SDK write occurs on local rejection; accepted
submission still clears the field and undo state.

### 2. Recover from zero-result search

**Confirmed defect.** `/` → a query with no matches → Esc → `q` leaves Search
focused and appends `q` to the query. The empty-state branch unmounts the list,
but Escape tries to focus that list. Down has no destination either.

See `screen.dart:449` and `screen.dart:467`. Define one simple rule: Escape from
an active filter clears it and returns focus to the first result. A genuinely
empty vault should focus New key. Use “No keys yet” for an empty store and
“No matching keys” for an unsuccessful filter.

Acceptance: no-result Esc restores a useful focus target and ordinary action
shortcuts; keyboard and mouse paths agree; search/selection still read no values.

### 3. Keep shortcut availability consistent with buttons

**Confirmed defect.** In an empty vault, Delete is disabled, but pressing `d`
opens a confirmation with no key name. The button checks `names.isEmpty`; the
shortcut navigates directly. See `screen.dart:354` and `screen.dart:407`.

Use the same action eligibility for shortcuts and buttons. This needs a shared
guard, not a generalized command system. Acceptance: every disabled action is
also unavailable from its accelerator, including empty/filtered and busy states.

### 4. Make form state and return destinations explicit

**Observed affordance issue:** Edit's Key field looks editable and accepts focus
while `readOnly: _replacing` silently rejects typing (`screen.dart:897`). Retain
the requested field traversal, but label it “Key · read-only”. Implementing
rename is outside this cleanup.

**Confirmed navigation inconsistency:** Settings → Add passphrase → Esc returns
to the vault, because `_back` sends every authenticated form there
(`screen.dart:736`). Return to the invoking screen for these few known flows.
An explicit return target is sufficient; keep the single-current-view model.

## Visual refinement

The present roles—green primary actions, cyan field focus, amber disclosure and
red destructive actions—are understandable. Keep ordinary text legible and
retain inverse focus/explicit labels so color supplements meaning.

The visual reviewers agreed on the following small changes:

- Extend the cyan focus cue to Search. Keep the selected row visible as the
  selection while clearly identifying where typing will go.
- Group Settings information and actions. Shorten the idle sentence, subordinate
  explanatory notes, and prevent the documentation URL wrapping its final slash
  onto a separate line. Stay within the existing minimum-size budget.
- Separate Reset from routine Unlock actions. Preserve Cancel as the initial
  focus in destructive confirmations.
- Use Reveal/Hide terminology consistently. Say deletion has no undo in Keybay;
  avoid implying physical erasure or deletion of external copies.
- Give failure/recovery headings an attention treatment instead of the generic
  green heading. Simplify first-use prose while retaining its platform-access
  and passphrase limitations.

There was a mild aesthetic disagreement: one reviewer would reduce green
headings and use a neutral deletion frame; another considered the existing
palette sufficiently restrained. Exact saturation varies with terminal themes.
Settle that with a quick dark/light/monochrome visual check, after recovery fixes.
Do not add new colors, decorative panels, icons or animation for this pass.

## Separate policy tradeoff

The runner currently discards an active create/edit/passphrase form on terminal
focus loss or resize (`packages/keybay_cli/lib/src/tui/runner.dart:78`). This is
an intentional security policy, but switching to a browser to retrieve a value
or resizing while editing can therefore lose the draft. Treat this as a product
and threat-model decision, separate from avoidable validation loss. Do not
silently relax it during visual cleanup. If retained, the dismissal should be
understandable to the user.

## Evidence and next pass

The lead reviewer reproduced invalid/duplicate saves at both 40×24 and 80×24.
Five executable observation checks established duplicate-name draft loss,
unintended empty-value save after correcting the name, zero-result Escape focus,
passphrase Cancel's destination, and the empty-vault Delete shortcut. These
checks assert the current problematic behavior; they are not acceptance tests.

Disposable render artifacts are under `build/design-review-20260908/` and
`build/recovery-preview-20260908/` (ignored by Git). These fixtures have been
rerun during remediation and now show the corrected behavior. The pre-review
regression receipt was `build/regression/run-BETEd7/report.json`; the latest
receipt is linked in the qualification status above.

Recommended next work: fix the first four items, apply the small hierarchy/copy
refinements, turn the reproductions into desired-behavior regressions, then
dogfood search → copy, create → correct error → save, edit → cancel, and
delete → cancel/confirm at the supported terminal sizes. Reuse the existing CLI
regression workflow. The shared SDK and TUI architecture can stay in place.

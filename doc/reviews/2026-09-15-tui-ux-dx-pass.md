# Keybay TUI UX/DX follow-up — 2026-09-15

## Improvements made

- **Read values as text, not menu items.** `ValueView` now uses Fleury's existing `ListView(selectable: false)`. All revealed lines retain disclosure styling, instead of one line receiving a second selection highlight. `EdgeBehavior.contain` prevents a Down/PageDown at the end from selecting another key and hiding the value. No new widget or framework API is needed.
- **Complete the keyboard round trip.** Right enters a revealed value; Left returns to the selected key without hiding it or resetting its scroll position. The field-local hint states the return path. Right while masked or still loading stays on the key instead of spatially traversing to an unrelated footer button.
- **Validate names at the right moment.** Enter in New key validates a missing, invalid or duplicate name before moving to Value. The same `_validateName` path is used by Save; correction retains the existing masked secret draft.
- **Make reset eligibility visible.** Delete all data is disabled until the exact confirmation is entered. Incorrect Enter submissions give inline, semantic field feedback and retain focus; editing clears that feedback. The model still independently validates the confirmation.

## Fleury bug upstreaming

The dim-background fix is in Fleury, not in Keybay. [PR #254](https://github.com/danReynolds/fleury/pull/254) merged to main as `c98b795e` on 2026-09-15, after review of head `7e959146`. The local Keybay UX branch includes the reviewed implementation as `7e009b6b`, and the identity-aware dogfood binary has been rebuilt.

Review found and corrected compound-layer alpha: overlapping block rectangles and box junctions must not become brighter where they intersect. With a solid cell background, glyph ink is preblended once and rendered opaque; without a cell background, group opacity remains valid. Ordinary text uses foreground alpha. The changelog also follows Fleury's version-heading contract.

The focused branch passes 30 Chrome surface/fill tests, client freshness, the changelog contract, and analysis of changed files. All final-head PR checks passed: the website build, four platform creation-smoke jobs and the full framework gate, including hot reload, repaint-cache validation and performance gates. A code-review record is posted on the PR. An additional `@codex review` was requested, but no external review response was recorded before merge. Exact receipts are under `build/tui-integration-20260915/upstream-review-*`, `dogfood-reviewed-*` and `fleury-pr-254-ci.log`.

## Bounded-input follow-up — implemented 2026-09-16

Keybay's name, search and reset fields now use Fleury's controller-owned
`TextEditPolicy` with a 120-code-unit limit and printable ASCII admission.
Rejected edits preserve accepted text, selection and undo/redo; the forms can
show rejection feedback without rewriting the controller. The duplicated
post-edit clearing callbacks are removed.

[Fleury PR #259](https://github.com/danReynolds/fleury/pull/259), merged after
all final-head CI checks passed, implements the
policy across typing, replacement, paste, composition, semantic edits and
programmatic assignment. Rejection is atomic rather than clipping. Bounded
fields collect only admissible paste segments and apply once at the final
marker; invalid or interrupted pastes leave no partial prefix. Oversized raw
input is rejected before normalization and grapheme processing. SecretDraft's
byte limits and deliberate erasure remain a separate security contract.

The Keybay TUI suite passes all 120 tests, including preservation of text and
selection in all three bounded fields after invalid and oversized paste.

## Evidence

`build/tui-integration-20260915/final-pass-*` contains 107 passing TUI tests, native PTY verification and the identity-aware dogfood binary rebuild. Regression coverage includes both 40×24 and 80×20 minimum sizes, name correction, reset eligibility and value-scroll boundaries. Changed CLI code analyzes cleanly. The live synthetic-data preview was visually checked for multiline disclosure, return navigation, early name errors and reset field feedback. This is local UX evidence, not a full release qualification or a claim that the pending Fleury API integration is published.

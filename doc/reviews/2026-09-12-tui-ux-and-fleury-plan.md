# Keybay TUI UX and Fleury dogfood plan

September 15: the final local integration resolves the button, toast and
Container follow-ups. Binding discovery remains unchanged by agreement.
See [the integration status](2026-09-13-fleury-api-proposals.md#september-15-integration)
for the current local dependency/publication boundary; the review baseline and
intermediate receipts below are historical.


Reviewed 2026-09-12 against the existing working tree on
`codex/rfc-2-cli-tui`, based on `f14e30e`. The initial pass added review evidence
and a plan. The subsequently authorized Keybay implementation is recorded below;
the Fleury checkout and dependency pin are unchanged.

The [September 13 API follow-up](2026-09-13-fleury-api-proposals.md) refines
these proposals with React/Flutter comparisons and notification examples. It
also corrects item 4: the consumed Fleury commit already has
`TextPastePolicy.immediate()`, which the initial review missed. The default
chunked-paste/unmount observation remains valid, but Keybay's bounded form
does not require a new framework API to express its mitigation.

## Implementation follow-up

The changes available on the existing Fleury pin are implemented:

- U1: Escape hides first, preserving selection/filter; the next Escape clears
  the filter without jumping selection. Edit-save/cancel retain the filter;
  New clears only a filter that would hide the result. Search handoff checks
  shortcut eligibility at input time, including Enter immediately followed by
  Space before a rebuild.
- U2, available portion: idle Escape reaches the existing Toaster dismissal.
  Notice replacement, bounded stacking and persistent errors await Fleury.
- U3: short terminals reserve one busy row and omit the gap above results.
  The 35-key probe now shows **7 rows at 80×20** and **9 at 40×24**. The built-in
  list scrollbar reserves a stable gutter when the list can overflow. Taller
  layouts retain their spacing.
- U4: local hints follow search/results/value/action focus and Settings panes.
  New/Edit show their multiline/save guidance only while Value is focused.
  The current row becomes bold with list focus; its fill stays mounted because
  of the newly reproduced Container lifecycle issue below. Automatic key-hint
  integration and removing that fill on blur await Fleury.
- U5: Key and passphrase fields expose their existing errors through Fleury's
  `validationError`; correction clears the field's error. Draft ownership and
  cross-field validation stay in Keybay. A Form-wide refactor is not required
  to deliver this UX fix.

The findings in U1–U5 below describe the original review baseline. Updated
observations and cell snapshots are under `build/ux-followup-20260912/`.
The follow-up passes **100 TUI tests**, **35 native PTY cases** and fatal-info
analysis of the CLI and both review probes. The native executable is rebuilt
through the identity-aware Keybay compiler. Full platform workflow and CI
evidence remain unchanged.

## Direction

Keep the searchable vault, compact forms and small confirmations. They fit the
product. The remaining work is to make routine operations preserve context,
make the keyboard instructions tell the truth at each focus position, and give
the user's records more of the terminal. More screens or more shortcuts would
not solve the problems observed here.

For a developer, a great session is: find the right key, copy it without
displaying it, inspect or replace it deliberately, correct mistakes without
retyping, and return to the same place. Protection settings should explain the
current state and the consequence of changing it. These flows should work by
ordinary keyboard navigation and visible clickable controls; learning the
accelerators should make an already usable UI faster.

The Fleury bar is equally concrete: Keybay should own its secret/session policy
and visual composition. Fleury should own button activation, focus and pointer
behavior, field validation semantics, navigation-key discovery and notification
lifecycle. A custom visual does not justify duplicating those behaviors.

## What is already good

- One searchable list, with fixed masks and separate Copy and Reveal actions.
  Browsing and selection do not read values.
- New/Edit put the work directly in front of the user. Edit names the key in
  its heading and focuses Value. Correctable name and passphrase errors retain
  masked drafts; blur and resizing conceal without losing an active draft.
- Destructive confirmations are compact, explain the consequence and focus
  Cancel. Settings separates Security and Data and distinguishes current rows
  from keyboard focus.
- Save/reveal chords, Tab/Shift+Tab, mouse interaction, exact-text handling and
  native terminal cleanup have meaningful regression coverage.

These are capabilities worth preserving through framework adoption. The small
terminal renders are legible; the issue is allocation of space and feedback,
not a need to redesign the visual language.

## UX work, in priority order

### U1. Hide and return without losing the user's place

**Confirmed behavior:** select `service/01`, reveal, press Escape: selection
changes to `service/00`. Filter to `service/2`, reveal, press Escape: the filter
is cleared as well. The visible hint says `Esc hide`.

`Vault._focusResults` always selects the first result, and the Escape handler
both conceals and clears the filter. Separate entering search results from
returning focus to an existing selection. Escape should first hide a disclosure
while preserving the selected key and filter. A subsequent Escape can clear
the filter. With neither state active, it should not jump to the first key and
should allow applicable outer dismissal bindings to run.

**Related design change:** saving an existing key currently clears the query in
`TuiModel.save`. Keep the filter after Edit; the unchanged name still matches
it. Creating a new key can clear a filter that would hide the new result.
This is a proposed workflow improvement, not a claim that the current save
behavior violates an existing contract.

Acceptance: keyboard and pointer hide agree; selection/filter survive hide,
Edit-save and Edit-cancel; the selected row remains visible. The current
End → Edit → Cancel path already preserves the last key and its viewport,
so retain that behavior rather than rebuilding navigation generally.

Sources: `packages/keybay_cli/lib/src/tui/vault.dart:37,183`;
`packages/keybay_cli/lib/src/tui/model.dart:342`.

### U2. Make feedback one readable result

**Confirmed behavior:** seven Copy presses within the confirmation lifetime
create seven separate toasts. At 40×24 they cover portions of the action area
and footer; at 80×20 the stack also exceeds the available screen height.
Keyboard operation continues, but visible content is obscured. A single-copy
layout test does not establish that repeated use works well.

Use one current operation notice; a repeated result replaces it and restarts
its expiry. A failure should stay available until explicitly dismissed or
resolved by the relevant retry. Current error toasts disappear after 15 seconds
even if the model still records the error. Escape in the idle vault cannot
reach Toaster's dismissal handler because Vault consumes it unconditionally.

The application decides which messages supersede which. Fleury should provide
the bounded presentation and replacement/dismissal mechanism. Keep slow-operation
feedback separate from completed-result notices, but place it in an existing
compact status/footer row.

Acceptance: rapid Copy/Save attempts cannot cover working controls; replacement
has one timer; a previous success cannot dismiss a newer failure; a resolved
failure does not linger over a successful retry; dismissal works by the chosen
keyboard and semantic paths without cancelling a form accidentally.

Sources: `packages/keybay_cli/lib/src/tui/screen.dart:344`;
`packages/keybay_cli/lib/src/tui/model.dart:35`.

### U3. Spend short-terminal space on records

**Observed at the supported minimums:** a 35-key store displays four ordinary
rows at 80×20 and six at 40×24. `BusyIndicator` reserves three rows even when
idle, in addition to gaps around actions and the footer. The main list has no
scrollbar enabled.

Use a compact layout when height is limited. Reclaim the idle three-row block
and reduce redundant blank lines while preserving the separation between list,
actions and instructions. Show the existing Fleury list scrollbar when useful;
reserve its gutter consistently. An initial design target is at least seven
ordinary rows at 80×20 and eight at 40×24, with all actions visible. Validate the
actual layout rather than treating those targets as proven measurements.

Keep roomier spacing on tall terminals. Do not turn minimum-size support into
the default density everywhere.

Sources: `packages/keybay_cli/lib/src/tui/chrome.dart:20`;
`packages/keybay_cli/lib/src/tui/vault.dart:292,375`.

### U4. Make instructions and focus agree

**Confirmed mismatch:** the footer continues to say `Enter edit` while search
has focus. Enter there moves to results; letters such as `c` are search input.
The zero-result screen says `No matching keys` but still advertises selection
and editing, without explaining Escape recovery. Settings likewise says
`↑↓ category` when the content pane's arrows move between actions.

Use focus-specific hints: search → `Enter results · Esc clear`; results →
selection/edit; revealed value → scrolling/hide; Settings content → action
selection/back to categories. Keep clickable action buttons available while
search is focused, but make it clear that their plain-letter accelerators apply
outside text fields. Apply Settings' distinction between current item and
keyboard focus consistently to the vault.

September 15 refinement: keep only app-specific guidance in the footer.
Retain `Enter results`, `Enter edit`, the current Escape action and Settings'
left/right pane movement; remove ordinary arrow, Tab and button activation
reminders. Action rows continue to advertise their own shortcuts. No Fleury
key-hint discovery change is needed.

New/Edit also need a discoverable multiline affordance. The README documents
Enter-to-save and Alt+Enter-to-add-a-line; the form itself only advertises
Ctrl+S. Keep the accepted keymap and show a short hint when Value is focused,
using the space reclaimed above. This is a usability recommendation, not a
new shortcut.

Acceptance: follow every displayed instruction at each focus position; repeat
with zero results and the minimum widths. No hint should promise an action
that the focused control handles differently.

Source: `packages/keybay_cli/lib/src/tui/vault.dart:379` and
`packages/keybay_cli/lib/src/tui/settings.dart`.

### U5. Connect visible validation to the field

**Confirmed gap:** submit `bad key`. The border is red, the message is visible
and Key receives focus, but its semantic `validationError` is null.

Fleury already has `TextInput.validationError` and `Form`/`FormField` support.
Pass the error to the existing field API first. Then evaluate replacing the
manual validate/focus/revalidate plumbing with the existing Form mechanism.
The attached synthetic Form probe rejects the invalid submission, preserves
the external controller's text, focuses the field, and exposes its error.

No new Fleury validation API is justified by this case. Form owns no values;
Keybay must continue to own draft concealment, byte validation and erasure.
Check cross-field confirmation and escaped-preview replacement before adopting
Form throughout the sensitive forms.

Source: `packages/keybay_cli/lib/src/tui/forms.dart:245,301`.

## Fleury work that would remove real friction

The consumed dependency is `82065f614050f134b95448c6084614953839f8a2`.
Public main was verified as `df0f1a9451c442452772566fa08e7420921fa89f`.
Relevant main files were read separately; main was not installed or tested.
The recommendations below account for its current Button, export, list,
key-hint, Form and Toaster sources.

| Area | Current friction | Smallest useful route | Proof and adoption |
|---|---|---|---|
| **Button content** | Keybay's roughly 135-line `TuiAction` reimplements focus, Enter/Space, pointer, hover, disabled behavior and semantics to render `[shortcut] Label`. Public Button fixes the whole presentation to `[ Label ]` and uses that same string as the accessible name. | Extend the existing Button with a narrow content customization point while retaining a distinct semantic label and its existing interaction implementation. The framework already has internal `FocusableControl`; avoid importing internal APIs from Keybay or creating another interaction engine. | Preserve current action appearance with native Button behavior. Verify full hit area, focus transfer, Enter/Space, disabled state, hover/pointer and semantic focus/activation. Remove Keybay's duplicated handlers; retain its action-grid alignment. |
| **Contextual key hints** | The live key resolver in the vault reports only `search` and `next`; ListView's internally handled Enter/Up/Down do not contribute to it. Manual footer strings drift from actual focus. | Have built-in interactive controls contribute their active claimed keys through the existing binding-source mechanism. Expose the application-specific action label for activation, and allow already-visible action hints to be excluded. | A real search/list/edit example can use KeyHintBar without duplicate strings or fake bindings. Verify text-field claims, empty lists, bubbling at list edges, aliases, disabled actions and narrow-width overflow. |
| **Toaster lifecycle** | `show` returns no handle; each call appends a timed toast. There is no public replacement identity, bounded-stack option or explicit persistent lifetime. | Add the minimum replacement/dismissal and lifetime support needed for one current notice. Decide the concrete API in a small framework proposal; use keyed replacement or a handle rather than a second application queue. Preserve ordinary transient toasts. | Adopt it for U2. Exercise bursts, replacement during expiry, persistent errors, route changes, focus and screen bounds with a fake clock and real keys. |
| **Accepted paste ownership** | The existing probe still retains only 2,048 of 262,144 received code units if TextArea unmounts immediately, while the external controller survives. Keybay works around this by applying an in-limit record paste as one edit. | Document received versus committed input and define the smallest completion boundary for temporary unmounting. Evaluate the existing paste driver/controller ownership before adding APIs. | Distinguish submit, temporary resize/unmount/remount, explicit cancel and exit. Retain Keybay's mitigation until a replacement preserves exact text and cleanup with equivalent evidence. |

Button is the clearest duplication to eliminate. Hints and Toaster directly
support visible UX improvements. Paste remains a framework lifecycle issue,
but it is not currently an unmitigated Keybay defect. Form adoption is a Keybay
task using existing APIs.

References at verified main:
[Button](https://github.com/danReynolds/fleury/blob/df0f1a9451c442452772566fa08e7420921fa89f/packages/fleury/lib/src/widgets/button.dart),
[KeyHintBar](https://github.com/danReynolds/fleury/blob/df0f1a9451c442452772566fa08e7420921fa89f/packages/fleury_widgets/lib/src/key_hint_bar.dart),
[Toaster](https://github.com/danReynolds/fleury/blob/df0f1a9451c442452772566fa08e7420921fa89f/packages/fleury_widgets/lib/src/toaster.dart),
[Form](https://github.com/danReynolds/fleury/blob/df0f1a9451c442452772566fa08e7420921fa89f/packages/fleury_widgets/lib/src/form.dart).

### Close stale findings before opening new work

The September 8 report describes an older dependency. Fresh probes show styled
RichText spaces retain inverse styling and separated-list dividers no longer
activate the preceding item. Button is now in core. Keybay already imports
`fleury_widgets` for Dialog and Toaster. Do not reopen those packaging/rendering
items or repeat the claim that Keybay avoids the widget suite.

The implementation follow-up reconciles `doc/tui-integration.md` with the actual
companion dependency and Toaster ownership/lifetimes. The RFC retains bounded
replacement and persistent errors as the target, explicitly marking the
current gap. Historical passing receipts remain historical.

### Additional finding: preserve state when only a background changes

The focus implementation reproduced a fifth Fleury issue on the consumed pin:
changing `Container.color` from a color to null changes its internal wrapper
tree and unmounts its child. In Keybay, removing the selected-row fill when
focus entered the revealed value discarded that viewer's scroll position and
keyboard focus. The unchanged existing scroll regression detected this.

The framework probe now includes an even smaller case: type `synthetic draft`
into a TextInput inside a colored Container, then rebuild the same Container
and child with a null color. The field becomes empty. This is a state-lifecycle
issue, not a request for another decoration API.

Recommended route: preserve the child beneath a stable fill layer when only
the background changes, including the transparent case. Qualify null → color
→ null, externally and internally owned editor controllers, focused descendants
and scrolled descendants, plus the cost of an unpainted fill layer. Check main
before implementing; this new reproducer was run on Keybay's pin.

Keybay currently retains the selected row's fill and varies text emphasis with
focus. Its existing revealed-value scrolling regression passes again. Once
Fleury preserves the child, Keybay can make the unfocused row use only its
current-item marker, matching Settings, without building a custom decorator.

## Implementation sequence and completion bar

1. **Keybay context and field correctness — small, low risk.** Implement U1 and
   U5 using the existing pin. Add regressions for the exact failures above;
   preserve the passing cancel/viewport and masked-draft cases.
2. **Compact layout and honest hints — medium, primarily presentation.** U3
   and U4, with a minimal local context mapping until Fleury exposes the
   required hints. Use one source for the app's action eligibility and labels.
3. **Fleury Button and notification improvements, followed by Keybay adoption —
   medium.** Use this report's concrete screens as acceptance examples. Remove
   duplicated Keybay behavior in the same integration that consumes each API.
   Keep migration and cross-package compatibility review separate from visual
   polish; upgrade to a reviewed published commit with the native checks passing.
4. **Hint integration and paste ownership — medium and higher risk,
   respectively.** Replace the temporary hints once built-in key discovery is
   available. Treat paste lifecycle as its own bounded change with exact-text,
   cancel and disposal regressions.

Framework work should earn its place through a runnable example and reduced
application responsibility. Accept a change when the UX is better, ownership
is clearer and the Keybay workaround can actually be removed. A shorter widget
tree alone is insufficient. Keep `SecretDraft`, terminal authority, idle policy,
clipboard transport and session serialization in Keybay.

Final dogfood: give a developer a synthetic store with 35 keys and ask them to
find/copy a key, reveal/hide it, edit/save it, correct an invalid New key,
create multiline text, cancel deletion, and inspect protection. Repeat at
40×24 and 80×20 with keyboard and mouse. Record hesitation, accidental actions,
lost context and unreadable/covered controls. Test dark/light terminal palettes
and a monochrome interpretation; current cell renders use an illustrative
palette, and no first-time-user or assistive-technology trial was performed.

## Evidence and reproduction

- Fresh baseline: **90 TUI tests pass**; **34 native PTY cases pass** against a
  freshly compiled command harness using the production SDK with disposable
  test boundaries. This is local evidence, not CI or platform qualification.
- Fatal-info analysis of the CLI and both review probes passes; `git diff
  --check` passes. No production behavior was modified during this review.
- [UX probe](fixtures/tui_ux_probe.dart): keyboard workflows, 35 synthetic keys,
  both minimum sizes, real field semantics, repeated feedback and an existing
  Fleury Form example. Observations describe the baseline rather than asserting
  that its defects are desirable behavior.
- [Framework probe](fixtures/fleury_keybay_probe.dart): refreshed for `onSelect`;
  verifies RichText, separator clicks and received-paste/unmount behavior.
- Current cell snapshots and observations are generated under
  `build/ux-review-20260912/`. Browse, search, errors, Settings, forms and delete
  were inspected as cell output; contact sheets also show the repeated-copy
  obstruction. All content is synthetic; clipboard delivery is a fake callback.

```sh
dart --suppress-analytics test packages/keybay_cli/test/tui_test.dart --reporter expanded
dart --suppress-analytics run doc/reviews/fixtures/tui_ux_probe.dart build/ux-review-20260912
dart --suppress-analytics run doc/reviews/fixtures/fleury_keybay_probe.dart
dart --suppress-analytics compile exe packages/keybay_cli/tool/command_harness.dart -o /tmp/keybay-ux-review-harness
python3 tool/test_cli_tui.py /tmp/keybay-ux-review-harness
dart --suppress-analytics analyze --fatal-infos packages/keybay_cli doc/reviews/fixtures/tui_ux_probe.dart doc/reviews/fixtures/fleury_keybay_probe.dart
```

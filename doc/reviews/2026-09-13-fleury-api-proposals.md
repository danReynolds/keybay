# Fleury API follow-up: composition, hints, toasts and lifecycle

## September 16 upstream integration

The user authorized upstream publication and Keybay integration. The APIs are
merged in [Fleury PR #258](https://github.com/danReynolds/fleury/pull/258) as
`2e5fd0e5ba1a1ea40c016c7eac0b66e7bb5cf7c3`, including the previously merged dim
and alignment fixes. All final-head checks passed. Keybay pins this revision
without a local path override. The [qualification status](../cli-qualification-status.md)
records the clean-checkout receipts.

The integration review added the missing companion `ButtonAppearance` export
and classified `ToastHandle` as a lifetime handle in storybook's coverage list.
The previously recorded web-tool analysis warning came from inheriting Keybay's
root analysis settings through a nested worktree; isolated Fleury analysis
passes that stage without modifying the unrelated web tool.

## September 15 integration (historical)

The final integration is implemented locally against Fleury commit
`e847797a6c4434699015819e08d2a30a21441d7b` on `codex/keybay-ux-primitives`.
It adds `ButtonAppearance.plain` independently of the text/child choice and a
read-only `ToastHandle.isActive` snapshot. Keybay now uses a stateless action
wrapper over Button, one replacing toast with persistent errors, and focus-only
row fill with stable descendants. Settings clears the newer ListView's inherited
selection text style through DefaultTextStyle before applying its custom row
styles. No hint-discovery expansion or custom input widget was needed.

The generated Fleury browser-client fingerprint was refreshed. The framework
widget suite passes 1,288 tests. The full core run passed 3,579 with one skip,
but failed its stale generated-client check and ten server-startup cases;
after regeneration all 32 tests in those four affected suites passed serially.
The older full contributor-gate web-tool warning remains separately recorded.

At this stage, automatic approval review rejected publication without explicit
user authorization. The user subsequently authorized upstream publication and
integration on September 16. The receipts in this section used an uncommitted
path override; they are historical local evidence, not the final portable
dependency-closure qualification.

The sections below retain the design discussion and earlier receipts.


Design discussion and implementation follow-up, 2026-09-13. The toast and
Container changes are implemented on the isolated Fleury branch
`codex/keybay-ux-primitives` in `build/fleury-ux`. Keybay's record editor now
uses the existing `TextPastePolicy.immediate()` API. Button composition is now
implemented on the same isolated Fleury branch. The September 15 follow-up keeps key-hint discovery unchanged
and simplifies Keybay's contextual guidance. Keybay's
tracked dependency still consumes `82065f614050f134b95448c6084614953839f8a2`;
consuming the new Fleury branch is a subsequent integration step.
Public main was rechecked as `df0f1a9451c442452772566fa08e7420921fa89f`;
relevant source was inspected without installing main.

The Fleury implementation is commit
`c820f7c33b36dbc58d7b4eaa4de561d56615cb12` for toasts and Container;
the existing `/Users/dan/Coding/fleury` working tree was not changed. The
commit is local, not merged or published. Its runnable toast example is
`build/fleury-ux/packages/fleury_widgets/example/toast_lifecycle.dart`.
The Button follow-up is commit `f351c35e4709d0889badf234eaa40d2870d1140f`
on that same branch. Its worktree is clean; this commit is also local only.

Validation: **3,517 Fleury core tests** pass (one skipped), **1,288 widget tests**
pass, and fatal-info analysis of changed Dart files passes. The standard full
check stopped before tests on the existing `strict_raw_type` warning in
`packages/fleury_web/tool/web_frame_report.dart:101`; that file is byte-identical
to the public-main base. This is not a full contributor-gate or CI pass.

Keybay's active paste cleanup passes **101 TUI tests**, **35 native PTY cases**,
and fatal-info CLI/probe analysis against its unchanged tracked Fleury pin.
The framework changes must be consumed in a subsequent dependency update
before Keybay can adopt persistent/replacing toasts or remove the selected-row
fill on blur. The button update described below is also local to the Fleury
branch; no key-hint API change is needed.

## 1. Button: mutually exclusive text and child

Implemented September 15 after the user's selection: `String? text` and
`Widget? child`, with exactly one required. This replaces `Button.label` and
supersedes the earlier `Button.custom`/`ButtonBase` alternatives. Active
framework callers, companion controls, scaffold templates, examples and website
snippets have been migrated. Historical audit fixtures remain historical.

| Library or widget | Simple and composed content |
|---|---|
| [Flutter Tab](https://api.flutter.dev/flutter/material/Tab/Tab.html) | `text: String?` or `child: Widget?`; supplying both is forbidden. An icon-only tab is also valid. |
| [Flutter InputDecoration](https://api.flutter.dev/flutter/material/InputDecoration/InputDecoration.html) | `labelText: String?` or `label: Widget?`, with corresponding pairs for helper, hint and error content. Each pair is mutually exclusive. |
| [Flutter Tooltip](https://api.flutter.dev/flutter/material/Tooltip/Tooltip.html) | Exactly one of `message: String?` and `richMessage: InlineSpan?`. |
| [Flutter TextButton](https://api.flutter.dev/flutter/material/TextButton-class.html) | Always a widget `child`; a simple label is `Text(...)`. The class name identifies a visual style. |
| [MUI](https://mui.com/material-ui/api/button/) / [React Aria](https://react-aria.adobe.com/Button) | One `children` slot accepts text or composed elements; React Aria additionally supports a function of button state. |
| [SwiftUI Button](https://developer.apple.com/documentation/swiftui/button) | One Button type with a title-string convenience initializer or a view-building label closure. |

These are related conventions rather than one universal syntax. React's child
type already includes strings; Dart's Widget does not. For Fleury's existing
string-based Button, the Flutter paired-parameter convention makes the
composition path discoverable on the same class. The chosen `text` name is a
breaking rename from `label`:

```dart
// Plain content; migrate Button(label: ...) to Button(text: ...).
Button(text: 'Copy', onPressed: copy);

// Composed content: provide child instead of text.
Button(
  semanticLabel: 'Copy',
  onPressed: copy,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('[c] ', style: CellStyle(bold: true)),
      Text('Copy'),
    ],
  ),
);
```

Require exactly one of `text` and `child`, rejecting both or neither. The const
constructor asserts this contract; build also validates it when assertions are
disabled. An empty string counts as supplied content. `semanticLabel` names the
action when composed content includes decoration such as a shortcut; it must
agree with the visible action name. It is not a second visible label.

Keep appearance independent of content: switching to `child` must not silently
remove the button's brackets, padding or interaction styling. Keybay also needs
an explicit plain appearance to preserve its unframed action rows. That visual
option should work with either a string or a widget; it is not a reason to add
a separate raw-button class or call the composition constructor `custom`.
The current implementation keeps bracketed framing for both forms. A plain
appearance is not part of the approved text/child API change, so Keybay's
unframed action migration still follows that styling decision and dependency
integration.

The existing internal `FocusableControl` should remain the single interaction
implementation for both content forms, retaining focus, Enter/Space, disabled
behavior, hover, pointer and semantic activation. Child content inherits the
resolved style. An explicit semantic name replaces the child's semantic text;
without one, descendant semantics remain available. Nested interactive controls
are documented as unsupported. This case does not need a public state builder.

Validation: 3,524 core tests pass (one skipped), 1,288 widget tests pass, and all
97 selected documentation tests pass across the initial batch and the corrected
snippet-test rerun. Button source and tests pass fatal-info analysis. Migration
analysis reports no errors or warnings (15 existing informational lints).
An assertions-disabled probe rejects both invalid content combinations. The
standard full contributor check still stops at the unchanged raw Map warning
in `fleury_web/tool/web_frame_report.dart:101` before running its test stage.
Logs are under `build/fleury-api-20260913/fleury-button-*`.

Additional dogfood observation, recorded for a separate layout fix:
`SizedBox(width: 10, child: Row(mainAxisSize: MainAxisSize.min,
mainAxisAlignment: MainAxisAlignment.spaceBetween, children:
[Text('[ '), Text('Go'), Text(' ]')]))` paints `[ Go ]` rather than distributing
the enforced width (`[   Go   ]`). RenderFlex positions children using its
natural width before applying the parent's minimum width. The probe output is
`fleury-button-row-probe.log`. A follow-up should compute alignment from the
constrained main-axis extent and cover both Row and Column. This button change
does not alter general Flex layout; its private frame paints styled padding
and positions composed content directly.

Fleury already exports `GestureDetector`. It remains available for bespoke
pointer interactions, but does not by itself provide the complete behavior of
a button. Flutter likewise has a separate
[FocusableActionDetector](https://api.flutter.dev/flutter/widgets/FocusableActionDetector-class.html)
for composing focus, keyboard actions and hover. Keybay's action wrapper should
own presentation and reserved widths, not duplicate that input machinery.

## 2. Hints: app commands and selective local guidance

Agreed September 15: leave Fleury's KeyHintBar and binding discovery unchanged.
Do not add automatic discovery of ordinary control navigation or an opt-in
teaching API for this use case. Existing labelled bindings and `hideFromHintBar`
remain sufficient for command discovery.

Keybay's action rows advertise their shortcuts. The contextual footer only
explains app-specific behavior; it does not repeat every visible action or
teach ordinary Tab/Enter/arrow operation. The implemented copy is:

| Focus | Example relevant guidance |
|---|---|
| Search with matches | `Enter results`, plus the current Escape action if any |
| Search without matches | `Esc clear` when a filter is present |
| Key list | `Enter edit · / search`, plus `Esc clear` when filtered |
| Key list with a revealed value | `→ value · Enter edit · Esc hide` |
| Revealed value | `Esc hide` |
| Editable value | `Enter save · Alt+Enter new line` |
| Escaped editor preview | `Ctrl+R to edit` |
| Settings pane | `→ actions` or `← category` |
| Action button | Only a relevant Escape action, otherwise no footer hint |

The vault reserves one footer row even when its hint is empty. Search never
advertises `Esc clear` without a filter, and a revealed value makes `Esc hide`
the first Escape operation even while search has focus. Local instructions
remain app-owned; no fake bindings are registered to populate a hint bar.

Validation for this September 15 app change: all 101 TUI tests pass, including
the 40x24 and 80x20 focus/layout cases; fatal-info analysis of TUI source and its
test passes. No native binary rebuild or PTY rerun is claimed for this change.

## 3. Toaster: identity, dismissal, lifetime and a finite host

Implemented on the Fleury branch: `ToastHandle`, optional replacement `id`,
`persistent`, and `maxToasts`, exported from both native and web barrels.
"Notice" in the early examples meant feedback generically, not a toast type
or severity. New public API and the runnable example use toast terminology.
The severity enum remains info/success/warning/error.

Useful precedents: [Chakra](https://chakra-ui.com/docs/components/toast) supports
ID-based update/dismissal and a visible limit; overflow is queued.
[Flutter's ScaffoldMessenger](https://api.flutter.dev/flutter/material/ScaffoldMessengerState/showSnackBar.html)
returns a controller and displays one SnackBar at a time, queuing later calls.
Keybay's repeated Copy results should replace one notice rather than produce
a backlog. We should adopt identity and lifecycle ownership without requiring
that queue behavior.

Proposed additive API:

```dart
Toaster(
  maxToasts: 1, // New: maximum retained notices, with oldest evicted on overflow.
  child: app,
);

// show still accepts the existing severity/style/action arguments.
// New: optional id, persistent flag, and a returned ToastHandle.
final toast = Toaster.show(
  context,
  'Copied',
  id: operationToastId,
  severity: ToastSeverity.success,
  duration: const Duration(seconds: 3),
);

toast.dismiss(); // Idempotent and scoped to this exact toast instance.
```

Contracts:

- With no ID, `show` creates a distinct toast, preserving ordinary existing
  calls. The host limit defaults to the existing unrestricted behavior for
  compatibility; Keybay explicitly opts into one.
- Reusing an ID replaces that notice atomically in its existing position and
  starts its new lifetime. There is no dismiss/insert flicker or pending queue.
- `persistent: true` creates no expiry ticker. Existing omitted/null `duration`
  continues to mean inherit the host duration. Reject an explicit duration
  together with persistence, rather than silently ignoring a contradictory
  argument. Duration.zero must not mean forever.
- A handle belongs to one generation. An old handle or expiry callback cannot
  dismiss a replacement with the same ID. Dismissal, eviction and host disposal
  release timers, actions, content references and the inactive overlay.
- `maxToasts` is a positive count of retained notices. A new distinct notice
  evicts the oldest when full; replacement does not consume another slot.
  Persistence prevents timeout, not explicit replacement or capacity eviction.
- Keyboard/semantic dismissal and optional actions remain available. A toast
  does not steal editor focus. Escape follows normal bubbling, so hiding a
  disclosure or cancelling a form retains precedence. Persistent semantics
  must not announce a transient lifetime or expose a fictitious timeout.

Keybay's presenter can retain one opaque ID and one handle:

```dart
final operationToastId = Object();
ToastHandle? currentToast;

// A copy failure persists while the user decides what to do.
currentToast = Toaster.show(
  context,
  'Copy could not be confirmed. The clipboard may have changed.',
  id: operationToastId,
  severity: ToastSeverity.error,
  persistent: true,
);

// After the relevant retry succeeds, replace the error in place.
currentToast = Toaster.show(
  context,
  'Copied',
  id: operationToastId,
  severity: ToastSeverity.success,
  duration: const Duration(seconds: 3),
);

// Explicit clear, route invalidation or presenter disposal.
currentToast?.dismiss();
```

The app must decide which result resolves an earlier failure. Keep operation
identity/revision in Keybay; an unrelated success must not silently replace an
unacknowledged failure. `_perform` currently clears status at operation start,
so the adoption must distinguish starting a retry from actually resolving the
notice. `_MessagePresenter` should handle explicit clears and discard stale
post-frame presentations using the model revision. It should own no expiry
timer or shadow toast queue. BusyIndicator remains the pending-work display.

A count cap alone does not prove layout safety: constrain the toast to the
viewport, wrap messages and keep dismissal reachable. Verify long failures
and the one-notice host at 40x24 and 80x20. If even one persistent overlay
obscures a necessary control, use a reserved notice region in a separate
presentation follow-up; do not claim replacement alone solves arbitrary layout.

Tests should cover repeated same-ID updates, transient-to-persistent and reverse
replacement, stale timers/handles, unrelated IDs and eviction, disposal,
Escape precedence, semantic dismissal, and long text at minimum sizes. An
update method, controller singleton, promise wrapper, queue policy matrix and
notification history are unnecessary for this first adoption.

## 4. Paste: an existing policy was missed in the initial review

Concrete default-policy example: paste 262,144 ASCII characters into an empty
TextArea, then resize below Keybay's supported minimum before later frames
apply the remainder. The resize prompt unmounts the input while SecretDraft's
external controller survives. The default first edit commits 2,048 characters;
input disposal discards the scheduled remainder. Returning to the editor shows
only that prefix. This concerns already-received text, not bytes still arriving
from the terminal.

The earlier Keybay code in `forms.dart` made a received, in-limit record paste
synchronous:

```dart
pastePolicy: const TextPastePolicy(
  largePasteThreshold: KeybayLimits.recordValueBytes,
  chunkSize: KeybayLimits.recordValueBytes + 1,
),
```

The record limit is 1 MiB of UTF-8. Fleury's thresholds use Dart code units;
any accepted UTF-8 record fits this code-unit ceiling. SecretDraft separately
validates bytes/NUL and erases rejected drafts. There is no scheduled tail for
an in-limit received segment to lose.

Correction: `TextPastePolicy.immediate()` already exists in both the consumed
commit and verified main, and explicitly documents bounded forms that unmount
while their external controller survives. The first review missed it. This
existing API expresses the intent more directly and is now used by Keybay:

```dart
pastePolicy: const TextPastePolicy.immediate(),
```

The fresh synthetic comparison retained exactly 262,144 of 262,144 characters
for both Keybay's current settings and `.immediate()`; the default retained
2,048. The standalone comparison is `fixtures/paste_policy_probe.dart`.
The implementation follow-up also exercises a full 1 MiB accepted record
through immediate resize and a 1 MiB + 1 byte record through draft/undo erasure.
The existing byte/NUL checks remain. Immediate also processes oversized
segments synchronously; this does not add an unbounded-work guarantee. Neither
policy preserves future segments after the field has gone away.

Reclassify this from a required new Fleury API to existing-policy adoption and
clear guidance. A controller-owned asynchronous paste session is a separate
design only if a real consumer needs frame-chunked work to survive view
unmounting. Automatically flushing during every dispose would be wrong for
explicit cancel, controller replacement and secret erasure.

## 5. Container: preserve the layer while changing its paint

Implemented on the Fleury branch, with regressions for internal editor state,
external selection/focus, list position, background removal and empty layout.

[Flutter's Container implementation](https://api.flutter.dev/flutter/widgets/Container/build.html)
conditionally inserts ColoredBox when color is non-null. Combining this with
[Flutter's type/key matching rule](https://api.flutter.dev/flutter/widgets/Widget/canUpdate.html)
implies the same state-loss hazard for an ordinary unkeyed descendant when
toggling that wrapper. This is source-based reasoning, not a Flutter runtime
test. Flutter does not guarantee preservation for this Container transition.

Flutter's [StatefulWidget guidance](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html)
recommends stable subtree depth with changing properties. An explicit
ColoredBox kept mounted can vary between a highlight and Colors.transparent;
its [updateRenderObject](https://api.flutter.dev/flutter/widgets/ColoredBox/updateRenderObject.html)
changes rendering properties without replacing children.

For Fleury, always retain the private fill wrapper at the same position when a
child is present; give its render object a nullable color. Null means paint no
background and forward the child, preserving the underlying terminal surface.
Do not substitute the theme background, which is an opaque fill. Color changes
invalidate painting, including clearing the previous highlight, without
remounting descendants. No new public property or application GlobalKey is
needed. Preserve the existing empty-container sizing and filled/framed
constructor behavior; avoid broadening this to every optional Container
property without separate evidence.

Prove null -> color -> null retains internal text, external-controller text,
caret/selection, focused descendants and scrolled descendants. Test null paint
over an existing parent background, removal of old fill, empty layout and the
cost of an unpainted wrapper. The current Fleury probe again reproduced the
empty draft after color -> null, and verified main still has the conditional
fill wrapper. After the fix, Keybay can remove row fill on blur without losing
the revealed viewer's focus or scroll position.

## 6. Browser dim styling: keep the row background opaque

The September 15 browser annotation exposed a renderer defect, not a missing
widget API. A selected row has a green fill, while its eight masked bullets use
the standard `CellStyle(dim: true)`. Fleury's CSS applied `opacity: .6` to the
whole text span, fading both glyphs and the inherited selection background.
This made the mask region visibly darker than the rest of the row.

The reviewed fix merged to main as `c98b795e` in [Fleury PR #254](https://github.com/danReynolds/fleury/pull/254), after review of head `7e959146`. Ordinary text dims only its foreground. Compound blocks and box-drawing gradients preblend the foreground against a solid cell background so overlapping layers retain uniform intensity. With no cell fill, group opacity still correctly dims only the ink. Inverse styles resolve before dimming, and text with no explicit foreground preserves its inherited color. Keybay retains its standard dim mask style; no custom widget or application color compensation is necessary.

Thirty browser surface/fill tests, the rebuilt-client freshness test and the changelog contract pass. The refreshed Keybay preview shows a continuous selected-row fill; the local UX branch incorporates the reviewed correction as `7e009b6b`. All final-head PR checks passed before merge, including the full framework gate, website build and four platform smoke jobs. Earlier framework API commits remain a separate local integration.

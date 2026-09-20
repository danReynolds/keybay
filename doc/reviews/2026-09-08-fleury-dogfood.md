# Fleury through the Keybay TUI build

> Current follow-up: [September 12 UX and framework plan](2026-09-12-tui-ux-and-fleury-plan.md).
> It rechecks the current pin and closes several findings below that have since been fixed.

Reviewed 2026-09-08. This is a framework/DX review, not a fresh security audit
or a release qualification. No Keybay or Fleury production code changed during
this review. The accompanying probe uses synthetic text and no SDK or clipboard.

## Assessment

Keep Fleury. Its widget tree, layout constraints, controllers, focus/key
primitives, native terminal driver, and test harness were sufficient for the
finished interaction model. We did not need a second UI framework, an SDK
change, a route stack, or a custom text editor.

The build was not uniformly smooth. Three native/input capabilities needed
small upstream changes. Several current framework behaviors need correction
or a clearer contract. Choosing core-only composition also meant rebuilding
ordinary control behavior that Fleury already implements in its widget suite.

Our early UX mistakes remain ours: fixed value-column widths, duplicated
masked/revealed displays, oversized confirmations, confusing read-only inputs,
missing root focus traversal, weak action hierarchy, and erasing correctable
drafts. Fleury had tools to compose these correctly. Application-level
keyboard/mouse and rendered-layout testing should have happened earlier.

## Evidence boundaries

- Keybay pins Fleury `3f33ad8d0eb574c08aa53469ed88f23ccb14c878`.
- Public `main` was checked with `git ls-remote`: it resolved to
  `6bccd2e4a8e712719ca6de575fa88fe96e7721fc`.
- The user's Fleury checkout is a dirty `danreynolds/launch-audit-fixes` branch
  at `a9eb740a`; it was read, not changed. It is not treated as current main.
- The [executable probe](fixtures/fleury_keybay_probe.dart) ran on the pinned
  dependency, the local checkout, and an isolated archive of the verified main
  commit. The main probe reused Keybay's installed dependency versions; this is
  a focused reproduction, not a full Fleury mainline test run.
- Keybay's existing mitigations are covered by the latest
  [CLI regression receipt](../cli-qualification-status.md). Its 158 tests and
  29 native terminal cases do not prove general Fleury behavior or usability.

Run against Keybay's pin from the repository root:

```sh
dart run doc/reviews/fixtures/fleury_keybay_probe.dart
```

## 1. Incorporate the existing support fixes into main and a hosted release

Two published support-branch commits were necessary:

- `e43f761e`: masked multiline `TextArea` input and
  `PosixTerminalDriver(suspendOnCtrlZ: false)`, letting Keybay close its session
  rather than suspend with secrets retained.
- `3f33ad8d`: restore termios through an owned close-on-exec descriptor even
  after stdin closes. A native PTY test exposed this lifecycle failure.

Verified main does not contain these capabilities: `TextArea` lacks
`obscureText`, Ctrl+Z remains driver-owned, and the mode controller still restores
through descriptor 0. Reconcile these changes with main's subsequent editor
and paste refactors instead of blindly replacing files.

Keep the existing, narrow APIs. Single-line masking already existed; there is
no demonstrated need for a new password-specific editor. Main should qualify
multiline masking/redacted semantics and clipboard behavior, reveal toggling,
application-owned Ctrl+Z handling, and restore-after-stdin-close. A hosted
release is also needed to remove Keybay CLI's Git dependency before Pub publish.

## 2. Preserve styles on ordinary spaces in RichText

**Confirmed rendering defect on the pin and verified main.** Rendering
`TextSpan(text: 'New key', style: CellStyle(inverse: true))` yields inverse flags:

```text
N     e     w     space  k     e     y
true  true  true  false  true  true  true
```

The wrapping implementation preserves a separator's style only when it carries
a link; other separators become `CellStyle.none`. This caused holes in focused
multiword action highlights. Keybay currently uses adjacent ordinary `Text`
widgets for shortcut and label.

Recommendation: preserve the original separator style for all spans. Add
regressions for inverse/background/underline, consecutive spaces, span
boundaries, links, and real wrap boundaries. This should be a rendering fix,
not a new styling option.

Main source: `packages/fleury/lib/src/widgets/rich_text.dart`,
`RenderRichText._wrapParagraph`.

## 3. Give list separators an inert pointer region

**Confirmed on the pin and verified main.** Clicking the divider in
`ListView.separated` invokes `onActivate(0)` for the item above it. The gesture
region wraps the item and its separator. Public documentation says a separator
selects the preceding item; an internal comment incorrectly says clicks do
nothing, and the actual behavior also activates it.

For a Settings action menu this is surprising. Keybay consumes separator
tap-down events explicitly so a rule cannot open a protection form.

Recommendation: restrict item activation to the item's bounds and make
separators inert. Preserve correct pointer geometry after scrolling and cached
repaints. Test item, separator, blank trailing area, variable-height rows, and
scrolled lists. Prefer one corrected behavior over a new policy matrix.

Main source: `packages/fleury/lib/src/widgets/list_view.dart`, lazy separated
item construction and `_handleItemTap`.

## 4. Clarify accepted-paste ownership when an editor unmounts

**Confirmed lifecycle behavior; the intended contract needs a decision.** The
probe gives `TextArea` an externally owned controller, delivers one complete
256 KiB paste, then removes the widget before another frame:

| Source | Received | Retained in external controller |
|---|---:|---:|
| Keybay pin / local checkout | 262,144 code units | 32,768 |
| Verified main | 262,144 code units | 2,048 |

The editor owns the uncommitted paste tail and discards it on disposal, even
though the external controller survives. Waiting for settle first hides this
edge case. This is distinct from intentionally cancelling an entire draft.

Keybay's bounded record editor configures the existing paste policy to apply
received, in-limit text in one edit before a resize can unmount the input.
Controllers remain owned by the active form. Ordinary editing/submission
already has a paste-completion barrier; temporary unmounting is the gap.

Recommendation: document this ownership explicitly and provide a minimal way
to finish accepted input before temporarily removing a control. Evaluate
preserving it with an external controller or exposing an explicit completion
boundary through the existing paste implementation. Do not indiscriminately
flush input on deliberate cancellation or add a new draft service. Regression
tests should distinguish submit, resize/unmount/remount, cancel, and exit.

Main source: `packages/fleury/lib/src/widgets/text_area.dart`, `dispose()` and
the existing `TextPasteDriver` in `editing/text_paste.dart`.

## 5. Make ordinary controls usable with a small dependency closure

`TextInput`, `TextArea`, focus and lists are available in core, but `Button`,
`Dialog`, and `Form` live in `fleury_widgets`, which depends on `image`.
Keybay consequently implements its own roughly 100-line `TuiAction` combining
focus, Enter/Space, mouse activation, disabled state, semantics, and styling.
This is real duplicate framework behavior.

This is a package/dependency concern, not evidence that image code executes or
necessarily survives AOT tree shaking. Application-specific shortcut alignment
and action grouping would remain Keybay's responsibility.

Recommendation: review the basic-control boundary. Prefer moving the existing
minimal Button interaction into core, or moving image-dependent widgets out of
the ordinary control package. Preserve one implementation and compatibility
exports. Do not create a third button API or a special Keybay widget library.

## Documentation and testing improvements

- Add one small, runnable core-only screen example: search, list, editor,
  actions, and a compact confirmation. Show pointer plus keyboard traversal
  and empty-result recovery. The focus guide already documents bare-root
  `FocusTraversalGroup`; our initial omission was not a missing capability.
- Add a sensitive-input recipe around existing masking, explicit clipboard
  policy while revealed, externally owned controllers, undo disposal, paste
  completion, and temporary concealment. A recipe is preferable to a broadly
  named “secure field” that implies guarantees it cannot provide.
- Show how a custom native-only host uses the explicit driver and runtime
  options. Keep vault-specific foreground checks, clipboard transport, idle
  exit and session policy in Keybay unless other applications demonstrate the
  same need. No large “secure mode” preset is justified by this build alone.
- Use focused borders/backgrounds without making field text less readable.
  Our initial default blue focus text was weak against the user's dark theme;
  contrast should be exercised in theme examples rather than inferred from
  one terminal palette.
- Finish the existing typed testing-target work rather than creating another
  testing API. The dirty Fleury checkout already has `button(...).press()` and
  failure checks for unsupported actions. Logical semantic activation still
  needs separate real-key/pointer tests; it does not prove focus traversal,
  hit regions, native clipboard delivery, or terminal restoration.

Recommended order: reconcile the existing native/masking fixes; fix styled
spaces and separator hit regions; settle the paste lifecycle contract; then
make the narrow control-packaging and documentation improvements. No broad
Fleury rearchitecture follows from this review.

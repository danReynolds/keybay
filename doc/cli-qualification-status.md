# CLI qualification status

Reviewed **2026-09-21**. The approved TUI is locked in; C0–C3 are integrated.
[PR #69](https://github.com/danReynolds/keybay/pull/69) merged as `6b867f2`.
The latest [engineering audit](security-review.md#engineering-audit-2026-09-21)
at `7965a5e` passed **211 CLI tests**, **36 native TUI PTY cases**, **22
hidden-input cases**, and private-pasteboard/archive/identity checks on macOS
ARM64 / Dart 3.12.2. It did not renew real-provider or distribution evidence.
C4 installed-artifact qualification and hosted Fleury dependencies remain
outstanding; [release readiness](release-readiness.md) defines those gates.
The separate [SDK qualification](qualification-status.md) retains its scope.
The dated sections below retain earlier checks and their original scope.

### Desktop provider follow-up (2026-09-21)

After recovering local Docker, the macOS CLI provider lane and Docker Linux
`core`/provider lanes passed against `7965a5e` plus documentation changes.
macOS used ARM64 / Dart 3.12.2; the Ubuntu container used Linux ARM64 / Dart
3.13.3. Both CLI receipts record source digest
`274bbc685db74d095d23ac08ace93fa5cbf5fcd751764c04decdfe5961759017`.

Linux passed 211 Dart tests, 36 native TUI PTY cases, 22 hidden-input cases,
isolated X11 clipboard, child execution, archive/formula checks, protected
real-store command/TUI flows and locked-provider guidance. macOS passed its
protected real-store command/TUI flows. Test stores were disposable, and the
Docker containers were removed. Logs and copied receipts are retained locally
in `build/release-qualification-20260921/`.

These renew the named desktop regressions. They do not establish Linux x64,
Wayland, final installed-package upgrades, Homebrew or notarized distribution.

### Website TUI follow-up (2026-09-21)

The website demo now mounts the production Fleury widgets and model with a
temporary sample-data adapter. Native storage and SDK error classification
live in a separate TUI adapter; the SDK, providers and encryption are unchanged.

After that separation, `./tool/test_cli.sh all` passed core, macOS and Docker
Linux lanes in `build/regression/run-RcMgHf/report.json`, source digest
`364447bf1f5403de95825f14c875c65a808c277d96e3ea63b9cc6a28e5137480`.
Each core lane passed the existing 211 tests and native terminal/archive checks.
A subsequent focused run passed the three disclosure-redaction tests plus a
new assertion keeping the portable TUI's size limit equal to the SDK limit.
Three website adapter/lifecycle tests, whole-workspace analysis and workflow
lint also passed. Browser checks exercised search, reveal, edit/save, creation,
reset and quit/restart, with desktop and 375-pixel layouts inspected.

This is local regression evidence for an uncommitted working tree, not an
independent review or final release qualification. Logs and receipts are under
`build/release-qualification-20260921/`. The browser uses fake in-memory data;
it does not qualify native custody. The host's initial-focus adjustment and
remaining Fleury API gap are recorded in the [site guide](../site/README.md).

### CLI review remediation (2026-09-20)

Hidden CLI prompts now own their controlling-terminal descriptor through
cleanup. They use a bounded byte editor instead of the terminal's canonical
line buffer, preserve bracketed-paste bytes (including CRLF), and restore the
caller's configured terminal modes on completion, EOF, and handled signals.
The pipe reader remains separate and retains its one-producer-ending rule.
Cleanup flushes input without waiting for unrelated terminal output to drain.

The revealed value viewer now excludes plaintext rows from Fleury semantics.
The regression checks raw semantics, inspection JSON, and accessibility output
for vault values and escaped record/passphrase previews at 40×24, 80×20, and
120×32, including scroll and concealment. This corrects Keybay's use of an
existing Fleury API; it does not require a framework patch.

The CLI suite now has **211 tests**. New native checks cover **22** EOF,
configured-mode restoration, byte-boundary, multibyte, exact-paste, and overflow
cases. The signal fixture keeps a synthetic caller alive after the command
returns; its comparison excludes only Darwin's transient PENDIN kernel state.
Separate controlling-terminal passphrase input preserves piped stdin.
Local receipts are retained under `build/security-remediation-20260920/`;
these are engineering regression evidence, not an independent audit or a
signed/notarized release qualification. The distribution gates below remain.

### Merge review (2026-09-16)

The final pass reviewed the complete CLI/TUI branch, including SDK workspace
identity, session cleanup, disclosure lifetimes, executable lookup, input
bounds, demo manifests and archive packaging. The latest local macOS arm64 /
Dart 3.12.2 core run passes **205 CLI tests**, including **120 TUI tests**,
**36 native TUI PTY cases**, command/exec/prompt checks, private-pasteboard
checks and archive/identity validation. Receipt:
`build/regression/run-scz0dE/report.json`.

SDK core passes **505 tests** with three host-specific skips in
`build/regression/run-rqXagZ/report.json`. Repository source formatting,
fatal-info analysis, **42 tooling tests**, **25 watcher tests**, release-tool
checks, archive-comparison tests and checksum-pinned workflow lint also pass.
The first CI attempt exposed a Dart 3.12/3.13 formatter difference; final
formatting uses Dart 3.13, matching CI. Local formatting checks tracked source
because `build/` contains ignored Fleury worktrees; CI checks its clean checkout
in full. The documentation site also builds successfully.

The first CI attempt also caught missing root dependency resolution in the
mobile jobs and an outdated quickstart error transcript. Those harness issues
are corrected; Flatpak display-startup failures now retain a useful diagnostic.

Review corrected a CI mismatch: the CLI is explicitly nonpublishable while
Fleury is Git-pinned, so CI validates its native archive and retains the SDK's
Pub archive check. A hosted Fleury release and restored CLI Pub validation are
required before CLI package publication. Installation instructions now use
the normal activated command; stale command counts and historical evidence
headings are corrected. No package or native release was published.

### Bounded-input follow-up (2026-09-16)

The requested input-preservation fix uses Fleury's `TextEditPolicy`; it removes
Keybay's post-edit clearing of name, search and reset fields. Fleury
[PR #259](https://github.com/danReynolds/fleury/pull/259) covers atomic rejection,
selection/history preservation, IME, semantic assignment and bounded streamed
paste. It merged as `1f967547915ce0ae7be717cf677e803e958ece5b` after every
final-head CI check passed, including the full framework, repaint-cache and
performance gates. The merged tree exactly matches tested candidate
`a1620ef8750704742b2fce067400bc37bdc3c665`. Both Fleury packages and the root
source override now pin the merged revision. SecretDraft byte limits and
erasure are unchanged.

On macOS arm64 / Dart 3.12.2, `./tool/test_cli.sh core` passes against upstream
candidate `a1620ef8750704742b2fce067400bc37bdc3c665`: **205 CLI tests**, including
**120 TUI tests**, **36 native TUI PTY cases**, command/exec/prompt tests,
private-pasteboard and archive/identity checks. The working-tree report is
`build/regression/run-KBrSUv/report.json`. This does not renew the older native
provider or Linux receipts below. Fleury's initial local core suite passed **3570 tests** (one
skipped); its final rebased head also passed all upstream CI gates.

The native dogfood executable is rebuilt at `build/keybay`; the
[CLI dogfood checklist](cli-dogfood.md) uses disposable keys and values.

### Final integration (2026-09-16)

The approved UX is frozen. Fleury's dim-renderer fix is merged in
[PR #254](https://github.com/danReynolds/fleury/pull/254), and its alignment fix
is merged in [PR #257](https://github.com/danReynolds/fleury/pull/257).
[PR #258](https://github.com/danReynolds/fleury/pull/258) integrates the approved
Button content/appearance API, managed toast lifetimes and state-preserving
Container backgrounds. It merged as
`2e5fd0e5ba1a1ea40c016c7eac0b66e7bb5cf7c3` after every final-head check passed,
including the full framework gate, repaint-cache checks and performance gates.
The merged tree is identical to reviewed candidate `e409b549`.

At that lock-in revision, both Fleury packages and the root source override
pinned that merged revision;
the temporary path override is removed. From clean Keybay commit
`e3f26e93cf5b721db4590312e4a0ab643d57804a`, `dart pub get --enforce-lockfile`
and `./tool/test_cli.sh all` pass. The subsequent closeout commit changes only
this documentation.

- macOS arm64 / Dart 3.12.2: **202 CLI tests** (including **117 TUI tests**),
  **36 native PTY cases**, command/exec/prompt checks, private-pasteboard checks,
  archive/identity checks and disposable Keychain provider flows pass.
- Linux arm64 / Dart 3.13.3 in the pinned Docker image: the same **202 CLI
  tests** and **36 native PTY cases**, isolated X11 clipboard, private D-Bus
  Secret Service provider flows and locked-provider guidance pass.
- Both environments report source digest
  `305344f2876a5925991f84d7aa5a22ce7c97d09e167547212d20ae801d8ea1c9`.
  The native report records `sourceDirty: false`; Docker's copied source has
  the same digest. These are local arm64 receipts, not signed-distribution,
  x64 or Wayland qualification.
- The identity-aware `build/keybay` binary was rebuilt from the merged pin.
  Its version (`0.2.0`) and help were checked outside the repository.

Final receipt: `build/tui-lock-in-20260916/final-report.json`; detailed output:
`build/tui-lock-in-20260916/final-clean-qualification.log`. Framework review,
CI, merge and build receipts share that directory. All provider data is
synthetic and disposable; clipboard checks use private/isolated boards.
Keybay's local integration commits are unsigned because the configured SSH
signing key was not loaded; persistent signing settings were left unchanged.

The preliminary clean run caught a harness-routing bug: a synthetic-only
pointer setup flag reached the real-provider binary. The corrected macOS and
Linux provider runs pass. Final review also moved display-width memoization
into the model's disclosure lifecycle, removing a plaintext reference retained
by the vault after hiding; concealment, rereveal and edit-transfer regression
checks pass. These corrections do not change the approved visuals.

Bounded-input filtering is resolved by the upstream Fleury follow-up recorded
above.
There is no further UX redesign in this integration. The dated sections below
retain earlier local evidence; their temporary pins and pending-work statements
describe those dates rather than the current integration.

### Reset and recovery polish (2026-09-16)

Unlock now offers a neutral **Forgot passphrase?** link. A separate explanation
offers Back first and Reset second; neither an authentication failure nor
opening the explanation starts a reset. Leaving unlock erases the passphrase
draft. The final screen says that saved keys will be deleted, the passphrase
removed, and the action cannot be undone. It requires the exact word `RESET`;
the destructive button remains disabled until the confirmation matches.

The full-width hover underline was a Fleury `Align` bug: one unbounded axis
caused it to retain tight constraints on the other axis. Local Fleury commit
`8777e105` fixes this; [upstream PR #257](https://github.com/danReynolds/fleury/pull/257)
contains the isolated fix and regression tests. It merged as `f00a5b31` after
all final-head checks passed on September 16. Keybay needs no width workaround.

Validation: **116 TUI tests, 36 native PTY checks, 1,309 local Fleury widget
tests and 1,313 upstream Fleury widget tests pass**. Hover and click bounds,
recovery navigation and draft erasure are covered at 40×24 and 80×20. Analysis,
formatting and both embedded-client freshness checks pass. The identity-aware
dogfood binary was rebuilt. Receipts: `build/tui-recovery-20260916/`.

### Unlock transition follow-up (2026-09-16)

Startup initially renders only the app frame; the Opening panel appears after
the existing 150 ms busy threshold. Credential checks retain the same unlock
form, disable editing and show delayed Unlocking feedback. Failed credentials
produce inline, semantic field feedback with space reserved to keep actions
stationary. Editing clears the error, and failed submissions restore field
focus after it is enabled. Submitted drafts and undo history are still erased;
Cancel during authentication closes any late session.

**114 TUI tests and 36 native PTY cases pass**, including delayed startup at
40×24 and 80×20, stable form identity, immediate retries, masked input and
pending-unlock cancellation. CLI analysis and diff checks pass. The
identity-aware `build/keybay` binary was rebuilt and its help/version checked
outside the repository. Receipts are in `build/tui-unlock-20260916/`; validation
used disposable stores, with no real vault or clipboard access. These are
Keybay flow changes; existing Fleury widgets provide the needed behavior.

### Final UX/DX follow-up (2026-09-15)

The [second pass](reviews/2026-09-15-tui-ux-dx-pass.md) replaces the value
viewer's line selection with Fleury's scroll-only mode, contains its scroll
edges, adds Left-to-keys without losing disclosure/position, validates names
before Enter advances and shows reset eligibility with inline errors. Rapid
Right input during reveal loading no longer moves focus to a footer action.
All 107 TUI tests pass, including both minimum layouts. The focused upstream
dim-rendering fix merged to main as `c98b795e` in
[Fleury PR #254](https://github.com/danReynolds/fleury/pull/254), after review of
head `7e959146`. Review corrected overlapping compound-glyph alpha;
30 browser tests, client freshness, the changelog contract and changed-file
analysis pass. All final-head PR checks passed before merge: the website
build, four platform smoke jobs and full framework gate, including hot reload,
repaint-cache validation and performance gates.

The local UX branch incorporates the reviewed correction as `7e009b6b` and
`build/keybay` has been rebuilt with the identity-aware compiler. Run
`/Users/dan/Coding/keybay/build/keybay open` in a foreground terminal to dogfood
the native TUI. Earlier Button/toast API commits remain a separate local
integration. See `build/tui-integration-20260915/final-pass-*`,
`upstream-review-*` and `merged-fleury-keybay-build.log` for receipts.

### Browser annotation follow-up (2026-09-15)

Revealed values now share the masks' right edge. New/Edit place the multiline
hint beside Value and omit the duplicate save hint. Settings action rows are
neutral before their destructive confirmations, and Clear's description is
shorter. Settings reads the host's actual idle policy: native defaults to five
minutes; the annotation preview has it disabled. No user-facing timeout
configuration was added.

Fleury's DOM renderer previously implemented dim with whole-element opacity,
which faded the selected background under masked values. Local commit
`b3576e5f` dims only foreground ink, including block and box glyphs, and
regenerates the embedded client. No application workaround was needed.

The `annotation-*` receipts in `build/tui-integration-20260915/` record **105
TUI tests, 35 native PTY cases, 29 browser rendering tests and the client-asset
freshness test passing**. CLI analysis and analysis of the changed Fleury
sources are clean. Fleury's full web-package analysis still reports its
existing tool warning and unrelated lint infos; this is not a full framework
gate receipt. The native dogfood binary was rebuilt. The live in-app browser
was refreshed and visually checked for alignment, continuous mask highlight,
form hints and both Settings categories. Publication and portable dependency
integration remain pending as described below.

### Final local UX integration (2026-09-15)

The app now delegates action interaction to Fleury's Button while preserving
unframed shortcut rows. Copy feedback uses one replacing toast, errors persist
through retries, and unrelated success cannot erase a visible failure. Opening
errors use the same revisioned path and successful unlock clears the failure.
The selected-row fill follows list focus without remounting its descendants.
Settings explicitly resets inherited list text paint for its custom rows.

Local evidence is under `build/tui-integration-20260915/`:

- **103 TUI tests pass**. The final authentication/message checks also pass in
  a five-test focused rerun after the successful-unlock cleanup.
- **35 native PTY cases pass** against the disposable SDK harness. The hover
  fixture now handles the expected slave-close EIO while still requiring the
  close marker and successful exit.
- Fatal-info analysis passes for the CLI and review probes.
- Inspected rendered cell snapshots at 40×24 and 80×20: browse, revealed-value
  focus, persistent copy failure, field validation, Settings and confirmation.
  The 35-key fixture retains nine/seven visible rows and one toast after seven
  Copy actions; actual copy-error text leaves action buttons visible.
- `build/keybay` was rebuilt with the identity-aware compiler. `--version` and
  `--help` work from outside this repository. No real secret store or system
  clipboard was used by the UX validation.
- Fleury's 1,288 widget tests pass. Its broad core run passed 3,579 tests and
  skipped one, with a stale generated-client fingerprint and ten startup
  failures. After regeneration, all 32 tests in those four affected suites
  pass serially. This is not a clean one-shot full contributor-gate receipt.

Fleury commits `c820f7c3`, `f351c35e` and `e847797a` are on the isolated local
branch `codex/keybay-ux-primitives`; the original Fleury checkout was untouched.
At this point, automatic approval review had rejected publishing without
explicit user authorization, and the app used a temporary path override.
The user subsequently authorized publication and integration on September 16.
See the current integration status above; this section records historical
local validation, not the final dependency resolution.

### Fleury Button content API (2026-09-15)

The isolated Fleury branch now requires exactly one of `Button.text` and
`Button.child`, replacing `Button.label`. It retains shared interaction
behavior, adds an accessible-name override for composed content, and migrates
active framework callers and documentation. Its 3,524 core tests (one skipped)
and 1,288 widget tests pass; selected documentation tests pass, and the
assertions-disabled content guard was verified. The full contributor gate
still stops on the previously recorded web-tool warning. This change has not
been consumed by Keybay's tracked Fleury pin. See the
[API follow-up](reviews/2026-09-13-fleury-api-proposals.md) for receipts and the
separate plain-appearance integration step.

### Contextual hint simplification (2026-09-15)

Action rows retain their shortcuts. Footers explain search/result handoff,
Enter-to-edit, the current Escape action, multiline entry and Settings pane
movement; they omit ordinary arrow, Tab and button-activation reminders.
The vault retains one footer row when no guidance is needed. Fleury's binding
discovery is unchanged.

All **101 TUI tests** pass, including supported minimum layouts and focus
transitions. Fatal-info analysis of TUI source and its test passes; formatting
is unchanged. Logs are `build/fleury-api-20260913/keybay-hint-tui-suite.log` and
`keybay-hint-analysis.log`. The native binary and PTY suite were not rerun for
this copy/layout change; their earlier receipts below remain dated.

### Paste policy cleanup and Fleury implementation (2026-09-13)

Keybay uses the existing `TextPastePolicy.immediate()` API for received record
paste segments. A full 1 MiB value survives immediate resize; oversized record
input erases the draft and undo history. The active checkout passes **101 TUI
tests**, **35 native PTY cases** and fatal-info CLI/probe analysis. The tracked
Fleury pin is unchanged.

The [API follow-up](reviews/2026-09-13-fleury-api-proposals.md) records a separate
local Fleury commit adding toast replacement/handles/persistence/capacity and
state-preserving Container backgrounds. Core and widget suites pass, but the
full contributor gate stops on an existing web-tool analysis warning. Keybay
adoption of those two framework changes follows the dependency update. Button
composition remains a design decision. The September 15 follow-up drops the
proposed key-hint API expansion; bounded forms do not need a new paste API.

### Context, density and field feedback follow-up (2026-09-12)

The non-blocked [UX changes](reviews/2026-09-12-tui-ux-and-fleury-plan.md) pass
**100 TUI tests**, **35 native PTY cases** and fatal-info CLI/probe analysis.
Escape preserves selection and filters when hiding, Edit-save/cancel keep
search context, idle Escape dismisses a notice, and immediate search-to-result
shortcut handoff works before a rebuild. Field errors expose their existing
Fleury validation semantics. Hints follow the focused control; Value explains
its existing Enter/Alt+Enter keymap.

The short layout displays seven ordinary records at 80×20 and nine at 40×24
with 35 synthetic keys. Updated cell renders and observations are under
`build/ux-followup-20260912/`. The native pointer and row-click coordinates were
updated for this layout; the new PTY case verifies filter preservation through
reveal/hide/edit/save. Existing exact-text, masked-draft, viewport, reveal-scroll,
focus, mouse, cancellation and lifecycle checks remain passing.

At the September 12 review, Fleury's pin was unchanged. Button content, automatic key-hint integration,
notice replacement/persistence and accepted-paste ownership remain upstream
work. A new framework probe shows that changing Container's color to null
recreates its child. Keybay retains its selected-row fill so value focus and
scrolling survive; removing the fill on focus loss waits for that fix.

This is local CLI/TUI evidence. The complete platform workflow and CI were not
rerun for this follow-up.

### Settings and form follow-up (2026-09-09)

Fleury’s built-in `FocusDetector` now separates keyboard focus from the current
row in both Settings panes. Only the focused row has a filled highlight;
the current row keeps its `›` marker when focus moves elsewhere. All **87 TUI
tests** and fatal-info analysis pass. The new cases verify Tab/Shift+Tab,
left/right arrows, hover, click focus and rendered/semantic focus agreement at
40×24 and 80×20. Disposable renders of sidebar, content and Back focus were
inspected under `build/settings-focus-preview/`. The local activation was
refreshed and `keybay --version` passed outside the repository.

The same-day form pass uses muted grey placeholders, one space between each
shortcut and label, and regular-weight field labels/warnings beneath bold
headings. Passphrase guidance is separated from the inputs; field groups get
extra space when height permits. Empty-submit correction exposed a lost-input
bug: giving each field a stable widget key preserves routing when feedback
appears or disappears. The expanded regression failed before that fix and
passed afterward. New-key, passphrase/error and Settings renders were inspected
at 40×24, 80×20 and 100×32 under `build/form-polish-preview/`.

The form-wide Reveal/Hide action now controls both passphrase inputs together.
The shared secret-field renderer handles each controller’s masking and escaped
preview, preserving focus and exact drafts. Coverage includes differing values,
button/keyboard toggles, concealment on validation and blur, pasted controls in
confirmation, cancelled drafts and saving with two escaped previews. Rendered
hidden/revealed forms were inspected at both minimum sizes and 100×32 under
`build/reveal-both-preview/`.

A separate disposable window verified that macOS Terminal 2.15 (466) answers
device attributes but not the pointer-shape query; it keeps its default pointer.
The [integration note](reviews/2026-09-08-native-pointer-integration.md) distinguishes
this terminal limitation from the earlier positive Kitty probe. No native-driver
or SDK changes were made, and the complete platform workflow was not rerun.

### Historical Fleury integration pass (2026-09-08)

On 2026-09-08, the published pointer/exact-text integration passed the repeatable
`./tool/test_cli.sh core` workflow: **168 CLI tests**, fatal-info analysis, and
**34 native TUI PTY cases**, plus command, prompt, exec, clipboard and archive
checks. The local receipt is `build/regression/run-M71xYd/report.json`.
Notifications were also rendered and inspected at 80×20 and 40×24. This is
local CLI evidence, not a new platform or signed-distribution qualification.
The [integration note](reviews/2026-09-08-native-pointer-integration.md) records
upstream reviews, the exact dependency, and preservation regressions.

## Historical integration snapshot (2026-09-08)

This section preserves the earlier checkpoint and its evidence. The current
dependency pin and final integration results are recorded above.

The CLI/TUI implementation is on `codex/rfc-2-cli-tui`, based on checkpoint
`f14e30e`, with the C1 finder and form/feedback changes in the working tree. The finder replaces
the split view with names and fixed masks in one list, shared actions and a
bounded revealed-value column. New/Edit use compact labeled fields and Enter
to advance/save; completed actions show temporary green feedback. Storage,
crypto and provider policy are unchanged. Fleury is pinned
to published commit `82065f614050f134b95448c6084614953839f8a2`, with no local
dependency overrides. See [integration review](tui-integration.md) for its
scope, dependency closure and upstream fixes.

Field Reveal/Hide uses Fleury's built-in masking, with a single escaped preview
for text requiring it. Revealed list values align with their masks; focused
placeholders use muted grey. Search/arrow/click handoffs check
live focus, search resets the result viewport, and editor shortcut hints are removed.

The root now installs Fleury's standard focus traversal. Tab/Shift+Tab move
through fields and actions; edge arrows connect search and results. Values
use the spare width beside their name instead of a fixed percentage. Delete,
Clear and Remove passphrase share compact confirmations with Cancel focused.
Ordinary panels and forms have no extra scroll-container focus stops; editor
height adapts to keep the action row visible in short terminals.

Form buttons now advertise Ctrl+S Save and Ctrl+R Reveal/Hide. The chords work
from fields and actions while plain letters remain input. Passphrase confirmation
and typed reset remain required. Primary actions/success use green, disclosure
uses amber, focused field borders use cyan, and destructive actions/errors use
red. Inverse button focus and explicit revealed labels supplement color.

Correctable key-name errors retain the masked value, focus Key and display
feedback beside it. Escape clears search and restores results or New key;
buttons and shortcuts share availability checks. Form Cancel returns to its
origin, Edit uses the key name as its title, and destructive confirmations
state that Keybay has no undo. Settings and Unlock separate ordinary and
destructive actions.

The vault and forms share aligned action cells. Bracketed shortcuts use bold
text; labels use ordinary weight. The vault adapts between four and two
columns, and forms wrap Save, Reveal/Hide and Cancel together. Each shortcut
has one space before its label, including Esc. Reveal/Hide leaves the
grid positions unchanged. The Edit title replaces both the generic heading and
the redundant read-only label; Value receives focus directly. Existing minimum
size checks now include action wrapping and maximum-length key titles.

Settings now keeps Security and Data in a left sidebar with content beside it.
Sidebar selection changes content without invoking actions; Enter/→ focuses
content, ← returns to the sidebar, and Tab traverses panes and Back.
Escape/Back exits Settings; cancelling a form restores its category. Stable
identity keeps the content focus node attached during category changes.

Space toggles a selected vault value; Enter opens its masked editor. Row clicks
only select. → focuses a revealed value for scrolling. Space remains text inside
search and forms; Ctrl+R remains the form reveal chord. The header shows only
the brand. Buttons and menu rows underline on hover without taking keyboard
focus, and mouse-motion reports do not extend the idle timeout. Supporting terminals
show hand/text pointers through Fleury's negotiated native cursor support;
unsupported terminals retain their normal pointer.

Missing or mismatched passphrase confirmation is now a correctable field error.
Both drafts remain masked, the invalid field gets a red border and focus, and
short inline feedback replaces the global byte-limit error. Editing revalidates;
accepted submission and cancellation still clear controllers and Undo histories.

Terminal-window blur and resize conceal values while retaining active masked
drafts in their existing controllers, including below the minimum terminal
size. Returning never reveals automatically. Accepted record pastes apply as
one edit before inputs can unmount. Cancellation, accepted submission, session
invalidation, timeout and exit retain their cleanup boundaries; foreground TTY
loss still closes the session.

The latest complete platform receipt, preceding the sidebar, shortcut, hover and
passphrase-validation changes above, is `build/regression/run-OiSamP/report.json`
for core, macOS and Linux, including the nested Linux report. All selections
pass, including the simplified Edit title, aligned actions, and the Settings menu.
That receipt's native and Docker source digests match:

```text
fa1b6f935e6c694d9d24937fb232097329a6da29f580620cf31d9ef82c499c34
```

Disposable renders were inspected at 40 and 80 columns for the vault, forms,
Settings, first use and deletion, including validation errors and revealed
values. Settings was also inspected in protected/unprotected states at 80×20.
The form/vault previews are under `build/layout-preview-20260908/`; current
Settings previews are under `build/settings-preview-20260908/` (ignored by Git). Both local commands were refreshed and smoke-tested outside the
repository. These renders use an illustrative terminal palette, not a theme
or assistive-technology qualification.

The category-menu and passphrase-validation update was checked locally on
2026-09-08: all 161 CLI tests pass (the dependency-closure test was rerun with the
Dart SDK directly on PATH after the Flutter wrapper hit a sandbox write limit),
`dart analyze --fatal-infos packages/keybay_cli` passes, and the native TUI PTY
suite passes 30 cases. New coverage proves in-place mismatch correction, SDK
protection and reopen with the corrected phrase, masked draft retention,
cancel/submission cleanup, field error colors, category navigation and safe
confirmation defaults at 40×24 and 80×20. Disposable previews are under
`build/settings-validation-preview/`. The globally activated source command was
smoke-tested from outside the repository. This update has not rerun the complete
macOS/Linux platform selections or CI; the earlier platform digest is historical.

The subsequent sidebar/Space/Enter/hover update passes all 165 CLI tests,
`dart analyze --fatal-infos packages/keybay_cli`, and 33 native TUI PTY cases.
The terminal suite includes Space toggling, Enter editing, a corrected zero-result
search followed immediately by Enter, sidebar traversal, and continuous pointer
motion while the idle timeout still exits. Widget checks cover full-width clicks,
hover without focus/activation, disabled actions, stable Reveal/Hide positions,
and protected/unprotected settings at 40×24 and 80×20. Disposable cell renders
were inspected under `build/sidebar-preview/`. This is local CLI/TUI evidence;
it does not replace the complete platform receipt or claim native pointer-shape
support. The locally activated source command continues to use this checkout.

The receipts cover the runtime and CLI regression sources. SDK core passed
505 tests with three host-specific skips in `build/regression/run-FXCPiV/report.json`,
including real standalone/workspace Pub activation. Generated reports and logs
are ignored by Git; CI retains the
same report convention as workflow artifacts. CI has not yet run this change.

## Historical qualification results (2026-09-08)

| Selection | Checked configuration | Result |
|---|---|---|
| Core | macOS arm64, Dart 3.12.2 | Pass: 158 CLI tests, including 73 TUI component/model tests; native AOT builds; 29 TUI PTY cases; command, prompt, exec and archive checks |
| macOS | Ordinary unentitled arm64 AOT, real Keychain, disposable application identity | Pass: concurrent writes, platform-only/protected commands, simple and namespaced keys, protected TUI open/reveal/close, interruption, reset cleanup |
| Linux | Ubuntu 24.04 arm64 in Docker, Dart 3.13.3, private D-Bus/gnome-keyring session | Pass: the same 158 tests and 29 TUI PTY cases, real-provider command/TUI flows and locked-provider guidance |
| macOS clipboard | Typed AppKit API, uniquely named private pasteboard | Pass: exact UTF-8/CRLF/RTF-prefix round trip, without using the user's general clipboard |
| Linux clipboard | X11 on isolated Xvfb, fixed `/usr/bin/xclip` helper | Pass: exact UTF-8/CRLF/RTF-prefix round trip. Native Wayland remains unqualified. |
| Repository checks | macOS arm64, preceding checkpoint | Pass: whole-workspace fatal-info analysis, 42 tooling tests, changed shell scripts and checksum-pinned workflow lint. The current run repeats CLI fatal-info analysis and exercises the updated native TUI regression script; workflow sources are unchanged. |
| Local Pub path activation | macOS arm64, Dart 3.12.2, outside the repository | Pass: activated executable version/help and owning-package identity probe. Source development mode through the shared Dart VM; no new signed-distribution or real-vault claim. |
| Fleury upstream fixes | Isolated support branch, macOS arm64 | Pass: 64 masked-editor/signal/suspend checks and 10 native-mode/signal/suspend checks, including deterministic restoration after stdin closes |

The TUI tests cover authentication before names, explicit disclosure, exact
Copy/Edit, CRUD/protection/reset, stale operations/sessions, input bounds,
controller/undo disposal, adaptive layout, resize/focus cleanup, inactivity,
handled signals, foreground TTY restrictions and capture/developer refusals.
C1 checks additionally assert equal masks aligned with each name, no storage
reads on selection/focus, a persistent selection marker, full value scrolling
without changing keys, and no lost characters at the scroll gutter. Layouts
are checked at 40×24, 80×20, 80×24 and 120×32 cells.
New-form tests follow Key → Enter → Value → Enter at 40×24, 80×24 and 180×50,
including native PTY creation, masked input and controller disposal. Alt+Enter
and multiline paste retain draft newlines without submitting. Confirmation
tests cover clipboard completion, green bottom-row feedback, three-second
expiry and preservation of a newer error.
Focus tests exercise mouse search, typing, Down, row clicks and Copy, including
returning to search without firing a shortcut. Native PTY cases cover keyboard
and mouse search handoffs. Field tests cover editing while shown, clipboard and
semantic redaction, a single escaped preview, and preserving an entire
control-character paste while concealing it. Revealed values share the mask's
right edge, and focused placeholders remain readable.
The UX pass additionally checks full New/Edit Tab cycles, Up/Down search
round trips, native Tab/Shift+Tab form submission, safe native deletion,
maximum-length names in compact confirmations, empty-vault focus, keyboard
settings navigation, and the resize screen's Quit action. Every view's actions
are checked for visibility at 40×24 and 80×20, including escaped editor previews.
Disposable-data renders were also inspected at 40×24 and 80×24.
Shortcut checks cover plain-letter input, focus retention through disclosure,
escaped-preview round trips, controller disposal on save, passphrase confirmation,
and the absence of a reset shortcut. Rendered cells verify focus, disclosure and
danger colors. Alignment checks compare action columns and row positions before
and after disclosure, and focus rendering checks include spaces between the
shortcut and label. Native PTY checks exercise Ctrl+R/Hide/Ctrl+S and assert IXON is
disabled so Ctrl+S cannot pause output.
Recovery checks verify invalid/duplicate names preserve exact draft bytes,
zero-result Escape restores focus, disabled shortcuts remain unavailable,
Cancel returns to the invoking screen, and blur does not cancel an accepted
save. New/Edit/passphrase/unlock retain masked input through blur and an
undersized terminal; returning cannot re-expose it automatically. A large
record paste survives immediate resize without losing its tail. Native PTY
cases repeat name correction, search recovery, edit blur, new-key resizing
and partial passphrase entry across blur/resize.
Simple names (`x`) and namespaced names (`x/y`) work in the same store and in
`kb://` references. Real-provider flows exercise a simple name through
set/get/list/run/rm alongside namespaced concurrent writes.

The native development executable is `build/keybay`; launch `build/keybay open`
from a foreground terminal. No CLI package, tag or hardened release was
published. The Fleury support branch was published with explicit approval.

## Repeatable commands

```sh
./tool/test_cli.sh core
./tool/test_cli.sh macos
./tool/test_cli.sh linux
./tool/test_cli.sh all
```

No arguments selects core. Multiple names select a subset. Linux uses the
shared disposable Docker setup on macOS; `all` therefore requires macOS and
Docker. Missing prerequisites produce a blocked result (69), never a pass.
Reports distinguish `cli-regression` from `sdk-regression` and include the
nested Linux host/ABI when Docker is used. CI invokes the same selectors.

## Remaining qualification

- Rerun the full configured CI matrix on the final release candidate, including
  macOS x64, Linux x64 and minimum Dart. These source checks are separate from
  installed-artifact qualification.
- Qualify native Wayland clipboard delivery before advertising that path as
  qualified.
- Qualify actual installed artifacts and upgrades. Hardened macOS distribution
  still needs the signed runtime/module form and signing/notarization evidence.
  Structural checks on an ad-hoc copy do not establish launchability.
- Replace Git-pinned Fleury with reviewed hosted releases and restore CLI Pub
  validation before publication. The CLI remains `publish_to: none` meanwhile.
- Follow the [release closeout](release-readiness.md#final-publication-checks)
  for final security triage, version/install claims and channel verification.

Flatpak CLI packaging, Snap, Windows and mobile CLI distribution remain outside
this release scope. These CLI changes do not broaden the SDK's security claims.

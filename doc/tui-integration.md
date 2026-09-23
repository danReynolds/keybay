# Foreground TUI integration

`keybay open` remains inside `keybay_cli`. The SDK's storage, crypto and
provider boundaries are unchanged. Its ordinary Dart resolver also supports
Pub workspace activation by selecting the owning package from bounded local
metadata. The CLI owns a single session
and settles at most one SDK action at a time.

The implementation has these internal modules:

- `tui/store.dart`: the small storage contract shared by the native TUI and
  website demo. Borrowed value and passphrase bytes are consumed or copied
  before an adapter returns its future, so callers can immediately erase them.
- `tui/native_model.dart`: the production SDK adapter, including redacted error
  classification. It preserves the SDK's credential and session ownership.
- `tui/model.dart`: session, authenticated names, selected value, operation
  serialization, mutation/protection handling and stale-result rejection.
- `tui/screen.dart`: the root widget selecting one current Fleury view, plus
  the shared panel and confirmation shells. It re-exports the view modules so
  `screen.dart` remains the single presentation entry point. No retained route
  stack, record cache or background store reads.
- `tui/chrome.dart`: shared busy indicator, rule, resize prompt, bounded value
  view and action grid. `TuiAction` is presentation over Fleury's plain Button;
  it does not implement input, focus or semantics itself.
- `tui/theme.dart`: shared palette and application text accents.
- `tui/vault.dart`: the C1 finder — search, name list, constant masks and the
  bounded revealed-value column.
- `tui/settings.dart`: the Security and Data categories and their action lists.
- `tui/forms.dart`: one small widget per Unlock, New/Edit, passphrase and reset form.
- `tui/secret_draft.dart`: draft ownership, erasure, byte validation and shared
  masked/revealed field lifecycle.
- `tui/runner.dart`: controlling-terminal checks, filtered native events,
  foreground and inactivity exit, Fleury startup and cleanup.
- `tui/clipboard.dart`: discarded field clipboard and explicit write-only
  platform transport. No secret register, shell, PATH lookup or fallback.
- `tui/clipboard_contract.dart`: the platform-independent discarded clipboard
  and copy failure type used by both hosts.

The static website compiles `site/demo/main.dart` with Fleury's web host and
embeds it in an iframe. It uses the same widgets, forms and model as the native
TUI, with a website-only in-memory adapter seeded with fake values. Resetting
or reloading restores the samples. There is no SDK, native provider, persistence
or server in that demo; it demonstrates interactions, not storage security.
The browser clipboard is written only after an explicit Copy action. Idle exit
is disabled. The separate development preview below still runs a native model
through Fleury's remote surface. Neither demo changes the production runner's
foreground, provider or remote-output restrictions.

A form owns its drafts through `SecretDraft`, which pairs one masked
controller with its focus node and byte contract. Erasing replaces the
controller rather than clearing it, and disposal is idempotent, so the release
discipline does not depend on the order in which a rejected input erases the
draft and navigates away. Reveal state is an epoch compared against the
model's conceal revision, so blur, resize and validation expire an earlier
reveal without a separate cleanup path.

Escaping and wrapping a revealed value are memoised per value and geometry,
and the decoded value text is cached for the life of one disclosure. A 1 MiB
record is therefore escaped and sliced once per reveal instead of once per
frame, which also avoids scattering fresh plaintext copies across the heap on
every repaint. Layout decisions that only need the widest escaped line measure
it without building the escaped value.

The C1 finder uses one centered list: names on the left, eight fixed mask
characters on the right, and shared selected-key actions underneath. Selecting
or searching never reads records. Space toggles visibility; Enter opens the
selected key’s masked editor. A row click only selects it. Reveal replaces only
the selected mask with
a bounded, scrollable value column beside the name; → focuses it
and Escape hides it. Left returns to the keys without hiding the value or
resetting its scroll position. The viewer uses a non-selectable Fleury list
with contained scroll edges: no extra line highlight, and reaching the end
cannot change the selected key. Right while masked or loading stays on the
current key. Revealed lines share the masks' right edge (inside the
scroll gutter when present). Each name takes its natural width and the value takes the remaining
space. When both cannot fit, the name is capped at half the available row.
A scroll gutter is reserved
only when scrolling is needed. There is no detail pane, additional route or
value cache. Actions and focus use the terminal palette; the selected row uses
a muted green background, and its marker also identifies selection
without color. New, Delete, Settings and Quit retain their existing actions.
Search changes reset the result viewport. Up at the first result focuses
search; Down/Enter chooses the first search result. Result clicks focus the
list; shortcuts consult current focus when invoked. Field focus
keeps the terminal foreground instead of applying Fleury's blue focus color.
Escape first hides a disclosure while preserving the selected key and filter.
With no disclosure, it clears a filter and restores the current result after
the list mounts; an empty vault focuses New key. An idle Escape bubbles to
Fleury's notification dismissal. Edit-save and cancellation retain the filter;
New clears it only if it would hide the created key. Search's marker uses the same cyan focus cue as
form borders. Buttons and keyboard accelerators share action eligibility. An empty store
says how to start rather than only that it is empty. Action columns are each
only as wide as the actions in them, and confirmations and first-use panels use
the same aligned grid as the vault and forms, showing `[Esc] Cancel` where
Escape is actually bound.

At 24 rows or fewer, the busy area reserves one row instead of three and the
list omits its top blank row. A 35-key synthetic store shows nine rows at 40×24
and seven at 80×20. Taller layouts retain their spacing. Fleury's list scrollbar
reserves a stable gutter when the list can overflow, allowing for expansion of
the selected row. The selected row's text is bold only while the list has
keyboard focus. Its background now clears when focus leaves the list; Fleury's
stable Container fill layer preserves the revealed viewer and scroll position.
Settings rows explicitly reset inherited list text styling before applying
their own current-item and focus styles.

The bare root installs Fleury's `FocusTraversalGroup` for Tab/Shift+Tab and
directional traversal. The list bubbles edge arrows. Forms and ordinary panels
use bounded columns without extra scroll-container focus stops. Clicking an
action focuses it, and its semantics report the same focus state. Empty stores
focus New key. Delete/Clear/Remove-passphrase confirmations share a centered,
content-height panel with Cancel initially focused; Escape returns to the
invoking view. These remain single current views without a retained dialog stack.

Settings has a persistent left sidebar for Security and Data with content beside
it, at both supported minimum sizes. ↑/↓ changes the displayed category without
invoking an action. Enter/→ focuses content, ← returns to the sidebar, and Tab
moves between sidebar, content and Back. Escape/Back exits Settings. Security
contains passphrase state, its actions and the host's idle-exit policy; Data
contains Clear/Reset. Cancellation returns to the originating category.
The native timeout defaults to five minutes, with a thirty-second warning;
there is no user-facing timeout setting. The annotation preview disables the
timer and displays Off. Settings menu actions use neutral text and ordinary
selection paint; destructive confirmation controls retain their error color.
The action list has a stable key across category changes so its shared focus
node stays attached as the surrounding content changes. Fleury’s `FocusDetector`
rebuilds each pane when focus enters or leaves; a row is focused only when it
is current and its list’s `FocusNode.hasFocus` is true. Only that row gets the
filled highlight. Each list’s current row keeps the same `›` marker when focus
leaves; hovering underlines without changing focus. Destructive actions
still require their existing confirmations. The header contains only the brand.

The dim footer explains app-specific behavior: search/result handoff, empty
search recovery, hiding a revealed value and movement between Settings panes.
Ordinary arrow navigation, Tab traversal and button activation are omitted;
action rows already advertise their shortcuts. New/Edit show Alt+Enter-to-add-a-line
beside the Value label while it is focused; an escaped preview instead
shows how to return to editing. Field errors use Fleury's
`validationError` as well as the visible border and message, including
passphrase confirmation. Enter validates New's key name before moving to Value,
using the same validation path as Save. Reset's destructive action is disabled
until its confirmation matches; an incorrect Enter stays in the field with
inline feedback. Buttons and menu rows underline on hover without
moving keyboard focus or activating. Native mouse-motion reports are enabled but do not reset the idle
timer. Fleury negotiates native pointer shapes with supporting terminals, using
[Kitty’s pointer-shape protocol](https://sw.kovidgoyal.net/kitty/pointer-shapes/).
Enabled actions/menu rows declare a hand cursor; text fields declare a text
cursor. Unsupported terminals retain their default pointer: a local probe of
macOS Terminal 2.15 (466) answered device attributes but did not answer the
pointer-shape query. Keybay declares
only `MouseRegion` metadata; Fleury owns negotiation, routing, capture and
restoration. See the [integration review](reviews/2026-09-08-native-pointer-integration.md).

New/Edit are compact Key/Value forms. Enter advances from the key to the
masked value, then submits; Fleury's existing multiline submit keymap keeps
Alt+Enter and pasted newlines as draft input. No new input adapter is added.
The editor shows one to three lines according to the available height, keeping
its actions visible even at 80×20. Escaped previews use the same row budget.
Reveal/Hide changes Fleury's built-in `obscureText`, with
`TextClipboardPolicy.redacted` retained in both modes. Text needing terminal
escaping replaces the field with one escaped, read-only value view; Hide
restores the original editor and its focus. Passphrase Reveal/Hide controls
both inputs together, including confirmation, through this same field helper.
Each preview uses its own controller. If unsafe text is pasted into either shown
input, both are concealed without unmounting it or interrupting the paste. The form
shows labeled fields, action buttons and the focused Value input hint.
The shared model validator checks record names before the editor transfers its
bytes. Local name errors retain a concealed draft and focus Key; the error
occupies the existing spacer beneath that field. Edit uses the key name itself
as its wrapping title, followed by Value. It has no key input or focus stop;
initial focus goes to Value. One small action-grid widget lays out the vault
and forms with shared column widths; the vault uses four or two columns, and
forms wrap Save, Reveal/Hide and Cancel together. Bracketed shortcuts are bold,
action labels use ordinary weight, and each shortcut has one space before its
label. Padding belongs between action cells, not inside the shortcut/label pair. Reveal/Hide cannot shift other actions. Form height
accounts for wrapped titles and action rows at the supported minimum size.
Renaming is outside scope and requires no new SDK API.
A single return-view value restores the invoking screen on form cancellation;
Unlock cancellation closes the invocation. No route stack is introduced.
Ctrl+S saves a record/passphrase form and Ctrl+R toggles disclosure, including
while a field is focused. Labels carry the chords; plain letters remain input.
These use existing Fleury key bindings, outside its editor keymap, and native
PTY coverage verifies that raw terminal mode disables Ctrl+S flow control.
A missing or mismatched confirmation is a local validation error: keep both
controllers and their drafts, conceal both fields, focus the field needing
correction, and show a short inline error with a red border. Revalidate on edits.
Each field has a stable widget key so adding or removing inline feedback
preserves its input routing. Cancellation and accepted submission still clear
controllers and Undo histories.
Reset retains its typed confirmation without a save shortcut. Form headings are bold; field labels and the passphrase warning use ordinary
weight. The warning sits beneath the heading with a blank line before the
inputs. Passphrase field groups have an extra gap when height permits.
Placeholders stay muted grey while focused or unfocused. A focus detector
colors the active field border; action styles distinguish primary, disclosure
and destructive actions while preserving inverse focus and semantic labels.
A pending operation is announced only after it has run longer than 150ms, so
an ordinary local write completes without flashing a notice; the caveat that
submitted changes may outlive the process now appears on the closing screen,
where it is true, rather than on every save. Thirty seconds before the idle
exit the notice says the session is closing; the deadline itself does not move,
and keyboard, paste or mouse-button activity resets both timers. Mouse motion
alone does not extend the session.
The model exposes message revisions; Fleury's Toaster owns notification
lifetimes. Clipboard success is announced only after delivery. Success lasts
three seconds; errors persist until dismissal, route invalidation or a
successful retry of the same action. See Notification presentation.

Both Fleury packages are pinned to merged main commit
`1f967547915ce0ae7be717cf677e803e958ece5b`. This includes the
[Button/toast/lifecycle APIs](https://github.com/danReynolds/fleury/pull/258),
[dim-renderer fix](https://github.com/danReynolds/fleury/pull/254) and
[alignment fix](https://github.com/danReynolds/fleury/pull/257). All final-head
checks passed before the support PRs merged. The temporary local path override
has been removed. The root Fleury override only unifies the Git source with
the companion package's hosted dependency and names the same exact revision;
`pubspec.lock` records Git sources for both packages.
The [qualification status](cli-qualification-status.md) records current receipts.
The CLI consumes both `fleury` and `fleury_widgets`, using the latter's Dialog
and Toaster. The reviewed dependency closure includes its image/archive
dependencies even though Keybay does not use those widgets. `characters` is a
direct dependency for grapheme-cluster wrapping. Existing crypto/FFI
dependencies remain shared. Core Fleury includes optional development/runtime
facilities, but this invocation
injects the native driver, disables hot reload/debug, and refuses all nonempty
`FLEURY_*` configuration and an active Dart VM service before SDK access.
The dependency test pins the closure and allows only the workspace's Fleury
source override to the same exact commit; no local-code override is allowed.

The merged Fleury support changes provide masked multiline input and an option
to deliver Ctrl+Z to the application instead of suspending. A native PTY test
also exposed restoration through an already-closed stdin descriptor; the fix
retains a close-on-exec descriptor until modes are restored. These changes do
not modify the user's active Fleury development checkout.

Keybay filters native events before Fleury widget dispatch and checks the
foreground terminal again before every output frame. Ctrl+C, Ctrl+Z, handled
signals, terminal loss and five-minute inactivity initiate session cleanup.
Dart cannot run code for SIGTSTP, SIGTTIN, SIGTTOU or SIGQUIT, and Fleury
documents external SIGTSTP as unsupported, so the runner ignores those four
while it owns the terminal (the hidden-input prompt shares the same guard).
An external stop or quit signal therefore neither suspends the vault with a
value on screen nor core-dumps it. Every command also disables its own core
files and, on Linux, makes the process non-dumpable.
Reported focus loss and resize conceal values while preserving masked drafts
in the active form. A conceal revision makes any previous form reveal expire;
it does not invalidate an accepted form write. Below the minimum size, the form
state stays mounted with its controllers, while its inputs are replaced by a
resize prompt. `TextPastePolicy.immediate()` applies each received record paste
segment as one edit, so input unmounting cannot leave a scheduled tail of an
accepted paste behind. `SecretDraft` enforces the 1 MiB UTF-8 limit and erases
oversized input and its undo history. This does not retain future terminal
segments after the input has gone away.
The form is still disposed on cancellation, session invalidation and exit.
No draft cache or extra plaintext model storage is added. Unsupported
external process stopping/killing remains outside immediate-cleanup claims.

Display-width measurement is cached with the model's active disclosure and
cleared on concealment or edit transfer. The vault keeps no separate plaintext
reference solely for width-cache identity.

Stored values are read only for Reveal, Copy or Edit. Name selection, search,
dismissal and exit invalidate pending disclosures. Submitted writes still
settle. Secret input controllers are emptied, disposed and replaced, releasing
undo/redo/composition history. UTF-8 copies passed to SDK operations are cleared
after synchronous snapshotting. Immutable strings and terminal/OS copies cannot
be guaranteed erased. Shown values escape C0/C1 controls, DEL, line/paragraph
separators, lone surrogates and every Unicode 16 format (Cf) or other
default-ignorable code point that can make the display disagree with the stored
bytes: bidi overrides and isolates, joiners and zero-width marks, prepended
concatenation marks, annotation and tag characters, and fillers. Variation
selectors are kept so emoji render. Any remaining cluster text that Fleury would
draw in zero cells, such as a stray combining mark, is escaped as well, plus the
backslash that introduces an escape. `get` refuses the same set. The shared
predicate lives in `display_safety.dart`. Ordinary printable text, including
accented, CJK and emoji characters, renders as itself. Display width is
measured in terminal cells through Fleury's width resolver and wrapping never
splits a grapheme cluster, so a wide glyph cannot overflow its column;
Copy, Edit and passphrase entry preserve the original bytes, including pasted
controls and CRLF. Secret controllers opt into Fleury's `preserveText` policy;
name/search fields retain ordinary canonicalization. Existing clipboard and
semantic redaction remain in effect in masked and revealed modes. The bounded
value viewer wraps its plaintext rows in `ExcludeSemantics`, so revealed vault
values and escaped form previews never become semantic labels. Regression
tests inspect raw semantics, inspection JSON, and accessibility output in
masked, revealed, scrolled, and concealed states at three viewport sizes.

macOS Copy uses AppKit's typed string API, avoiding `pbcopy` type inference.
The native boundary follows Apple's [NSPasteboard API](https://developer.apple.com/documentation/appkit/nspasteboard).
It prepares the pasteboard with `NSPasteboardContentsCurrentHostOnly`, so
Universal Clipboard does not sync the value, and publishes the
`org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` markers
before the value, so a failure leaves no unmarked secret. Clipboard managers
choose whether to honor the markers.
Linux chooses one absolute helper based on the desktop environment before any
record read; X11 requires a local `:display` address. It sends UTF-8 only through
stdin, uses a restricted environment,
discards helper output and bounds completion. `wl-copy` and `xclip` serve one
type per copy, so Linux copies cannot carry KDE's password-manager hint and
clipboard managers may record them. Clipboard ownership may outlive
the Keybay process. A failure after submission cannot prove the clipboard was
unchanged. No automatic clearing or clipboard-history erasure is claimed.

The repeatable core regression includes Fleury component tests, production-SDK
model tests, native PTY lifecycle tests and private clipboard round trips.
Linux uses isolated Xvfb; macOS uses a uniquely named pasteboard rather than the
user's clipboard. See [qualification status](cli-qualification-status.md) for
the exact configurations checked and the remaining release evidence.

The CLI is temporarily `publish_to: none` because Fleury is Git-pinned. Native
source/archive builds work; a reviewed hosted Fleury release is required before
pub publishing. Signed native packaging and installed upgrades are separate
gates in [release readiness](release-readiness.md). No SDK publication settings changed.

### Notification presentation

Fleury's `Toaster(maxToasts: 1)` displays one bordered notification at the bottom
right. Success is green and expires after three seconds; errors are red and
persistent. Notifications do not take focus or contain secret values. Repeated
Copy replaces the same toast, with no stack or queue. The action scope includes
the selected key for record reads/copies, so unrelated success or an idle
warning cannot erase a visible copy failure. Starting a retry leaves the error
visible; completing it successfully replaces the error with confirmation.

The presenter owns one opaque replacement ID and one `ToastHandle`. Its
`isActive` snapshot accounts for Escape and semantic dismissal. Fleury owns
expiry and lifecycle; Keybay has no second timer or notification queue. Model
message revisions fence deferred presentation and propagate clears, including
opening failures. Route changes clear their feedback. Idle Escape dismisses
the toast after disclosure hiding and filter clearing take precedence.

The synthetic render pass checks repeated-copy, persistent-error, focus and
viewport behavior at 40×24 and 80×20. The actual copy-error text wraps without
covering action buttons. This does not claim arbitrary unbounded messages can
never obscure an overlay's underlying content.

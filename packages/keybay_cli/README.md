# keybay CLI

The in-tree V2 CLI provides run-scoped secret injection and a foreground
Fleury vault with `keybay open` on ordinary macOS and Linux desktop. CLI 0.2.0
is not yet published; see [release readiness](../../doc/release-readiness.md)
for the native packaging and hosted-dependency gates. No account, Keybay server,
resident Keybay process, network access, or shell hook. Keybay writes no
plaintext secret file.

Keybay keeps non-secret configuration literal in a committed manifest and
stores secret values behind explicit `kb://` references:

```dotenv
API_URL=https://staging.example.com
LOG_LEVEL=debug
OPENAI_API_KEY=kb://acme-api/openai-api-key
```

```sh
keybay set acme-api/openai-api-key
keybay run -- npm start
```

The launched process receives ordinary environment variables and needs no
Keybay library. Keybay replaces itself with the child via `execve`; it never
invokes a shell or stays resident as a wrapper.

## Install

Use an official V2 native release when available. The CLI ships only as native
binaries through Homebrew and GitHub releases; it is not published to pub.dev.
A release's embedded application ID and stable packaging establish the intended
SDK identity and provider behavior. Hardened macOS distribution must qualify a
dedicated signed Dart AOT runtime and signed module; a local single-file build
below is a development artifact, not evidence that hardened distribution works.
Installing from source with `dart install` or Pub activation also gives a
development build, not a supported installation.

Contributors can build the in-tree executable from the repository root:

```sh
dart pub get
dart run keybay:keybay_compile packages/keybay_cli/bin/keybay.dart -o build/keybay
./build/keybay --version
```

The compiler wrapper validates the CLI package declaration and embeds
`keybay-cli` in the executable.

For a global command backed by this local checkout, run from the repository root:

```sh
dart pub global activate --source path packages/keybay_cli
keybay --version
keybay open
```

Put `$HOME/.pub-cache/bin` before an older Keybay installation in `PATH`.
Path activation follows this checkout, so keep it in place. It runs through the
shared Dart VM and resolves identity from the CLI package's own pubspec, including
inside this workspace. This is a local development installation; the signed
release distribution remains a separate qualification. On macOS, the Keychain
item it creates trusts the Dart VM rather than Keybay, so any program run with
`dart` can read the platform root without a prompt. Keep real secrets behind a
strong passphrase.

With Dart 3.12.2, local path activation prints Pub's dependency-resolution
messages before Keybay starts. Use the native executable for scripts or
dogfood checks that require exact CLI output.

### Verify a release download

Releases are produced locally by rk from maintainer-signed tags. Verify the tag
before trusting a download; do not infer GitHub-hosted build provenance or a
separate Keybay attestation unless that specific release actually provides it.
```sh
VERSION=X.Y.Z
git verify-tag "keybay_cli-v$VERSION"
```

Verifying the tag needs the maintainer's public signing key in an
allowed-signers file; it is published at
[github.com/danReynolds.keys](https://github.com/danReynolds.keys). Verification
establishes that the tag was signed by that maintainer-controlled key; no claim
about the private key's storage is required to perform the check.

The exact archive, signature, checksum, notarization, and Homebrew verification
commands will be documented from the first hardened rk release's actual public
artifacts rather than promised in advance.

On ordinary Linux desktop, Keybay requires a reachable, unlocked Secret
Service provider over the user D-Bus session. It does not shell out to
`secret-tool`. The SDK implements Flatpak through the Secret Portal, but Flatpak
CLI packaging and child-launch policy are not qualified or advertised here.
A missing provider never causes fallback to another store. Opening may invoke
trusted provider UI; there is no universal headless availability guarantee.

Under `dart run`, the shared Dart VM—not Keybay alone—is the macOS keychain
trust unit. Use a compiled, signed release when a stable Keychain trust unit is
required.

## Interactive vault

```sh
keybay open
```

Authenticate once, then browse a searchable list with key names on the left and
fixed-length masks on the right. Values stay
hidden until you choose Reveal, Copy or Edit. Search filters names only.

| Action | Key |
|---|---|
| Select a name | ↑ / ↓ |
| Search names | `/`, or ↑ from the first result |
| Reveal / hide | Space |
| Edit the selected key | Enter or `e` |
| Scroll a revealed value | → from the list, then ↑ / ↓ |
| Return to keys without hiding | ← from the value |
| Copy the selected value | `c` |
| New / edit / delete | `n` / `e` / `d` |
| Protection, clear and reset | `s` |
| Move focus / activate an action | Tab / Shift+Tab; Enter or Space |
| Hide or dismiss the current view | Esc |
| Exit | `q` from the vault, Ctrl+C or Ctrl+Z anywhere |

New and Edit use a compact, labeled Key/Value form. New has an editable Key;
Edit uses the existing key name as its title and focuses Value.
Enter validates New's Key before moving to Value; Enter in Value saves. Alt+Enter adds a line,
and multiline paste stays in the field until you save. A hint appears while
Value has focus to explain these keys. Tab and Shift+Tab move
between editable fields and the form actions; Escape cancels. **Ctrl+S saves**
from anywhere in the form;
**Ctrl+R reveals/hides** the value. Save, Reveal/Hide and Cancel use aligned
action cells with bracketed key hints, including Esc for Cancel. The same
layout aligns the vault's actions in four columns, or two in narrow terminals.
These shortcuts appear on the buttons and
also work when setting a passphrase; confirmation is still required. Unlock
uses Enter and Ctrl+R. Reset keeps its explicit typed confirmation.
Invalid or duplicate names keep the value masked for correction and focus Key.
Key renaming is outside the current scope. Cancel returns to the invoking screen;
Cancel at Unlock exits.
Plain letters typed into a field edit that field. Down or Enter from search, or a
click on a result, returns to the key list and its shortcuts. Values and
passphrases are masked. Reveal/Hide applies to both passphrase inputs together,
including confirmation. A field containing unsafe control or formatting
characters uses an escaped preview; ordinary printable Unicode stays readable.
Hide returns to editing without changing the draft.
Existing text and pasted bytes, including CRLF, are preserved in secret fields.
Values must be UTF-8
without NUL, up to 1 MiB; passphrases contain 1–1024 UTF-8 bytes and require an
exact confirmation when configured. An oversized draft is discarded.
Escape first hides a revealed value without changing the selected key or
search. With no reveal, Escape clears the search and returns to the selected
result, or to New key in an empty vault. Edit-save and cancellation keep the
filter; New clears it only when necessary to show the new key. An idle Escape
dismisses the latest notification. Footer instructions follow the focused
control. Disabled actions also disable their shortcuts.

Short terminals reserve more space for records and show a scrollbar when the
list can overflow. A 35-key store displays seven ordinary rows at 80×20 and nine
at 40×24; taller terminals retain more spacious layout.

Green marks primary actions and success; amber marks disclosure; red marks
destructive actions and errors. The focused field has a cyan border. Button
focus also uses inverse highlighting, and revealed fields are labeled, so
color is never the only cue. Field placeholders use muted grey; headings are
bold, and field labels and warning text use ordinary weight.

Reveal changes only the selected row, aligned to the right like its mask.
The value uses the space left beside its name and wraps only when needed;
Escape hides the value and returns focus to names.

Supporting terminals show hand pointers on actions and text pointers on fields.
Fleury negotiates this capability and restores the previous pointer on exit;
other terminals keep their normal pointer. macOS Terminal 2.15 does not
advertise this capability; hover underlining remains available.

Successful actions show a compact green, bordered toast at the bottom right for three seconds,
such as “Copied!” or “Saved!”. Repeated actions replace the same toast.
Errors remain until dismissed, left behind by navigation, or resolved by a
successful retry. An idle Esc dismisses feedback; hiding a revealed value and
clearing search take precedence. The Copy confirmation appears only after the
clipboard write completes.

Delete, Clear and Remove passphrase use compact centered confirmations.
Cancel has initial focus; Tab or arrow keys move to the confirming action.
An empty vault focuses New key. Clicking an action also gives it keyboard focus.

Settings keeps **Security** and **Data** in a left sidebar, with the selected
category’s content beside it. The filled highlight marks keyboard focus;
each list’s current row keeps its `›` marker when focus moves elsewhere.
Security shows passphrase
protection and the five-minute native idle-exit policy, and lets you add, change or
remove the passphrase. A mismatched confirmation keeps both entries masked,
marks the confirmation field red, and lets you correct it in place.
The idle timeout is not currently user-configurable. The browser UX preview
disables it and shows `Idle exit: Off`.
↑/↓ changes category in the sidebar. Enter or → moves into its actions;
← returns to the sidebar. Tab moves between panes and Back. Esc exits Settings. Shortcuts appear beside actions, with their effects explained below.
Data contains Clear and Reset. Clear deletes records while
keeping protection. Reset requires typing `RESET`, deletes the
managed store, and exits without creating a replacement. There is no passphrase
recovery. Unlock offers a neutral “Forgot passphrase?” link; reset is available
from that explanation, followed by the typed confirmation. Record changes from other processes follow the SDK's normal concurrent
write rules; reopen to refresh external changes.

The UI needs the foreground controlling terminal on both stdin and stdout.
Use at least 80×20 cells, or 40×24 for the narrow layout. Resizing or reported
terminal-window focus loss conceals values and retains masked form drafts.
If the terminal becomes too small, a resize prompt replaces the inputs until
they fit again. Returning never reveals a draft automatically. Drafts stay in
the active form's memory and are cleared on cancellation, accepted submission,
session invalidation or exit; there is no saved draft cache.
While the vault owns the terminal, SIGTSTP, SIGTTIN, SIGTTOU and SIGQUIT are
ignored, so it is never stopped or core-dumped with a value on screen; Ctrl+Z
and Ctrl+\ arrive as input in the vault's raw mode.
Five minutes without input exits the session. Submitted SDK operations are
settled before orderly exit; they may complete after dismissal. External
SIGSTOP/SIGKILL cannot guarantee immediate cleanup. Terminal captures and
immutable Dart strings cannot be reliably erased.

Copy is an explicit disclosure separate from Reveal. macOS uses a typed
pasteboard write restricted to this Mac, so Universal Clipboard does not send it
to your other devices, and marks it concealed and transient
([nspasteboard.org](http://nspasteboard.org) conventions that most clipboard
managers honor by not recording the item). Linux selects a fixed
`/usr/bin/wl-copy` (Wayland) or `/usr/bin/xclip` (X11) when available. Keybay
does not mark Linux copies sensitive (`xclip` cannot; `wl-copy` 2.3 and later
could, with `--sensitive`), so clipboard managers may record them. There is no PATH lookup or transport fallback. Clipboard
services, clipboard managers and other apps may retain copied values after exit;
Keybay does not promise clipboard erasure. Generic
field copy/cut never exports a secret. Native transport qualification is scoped
in the [qualification report](../../doc/cli-qualification-status.md).

The UI disables Fleury debug/hot reload and refuses `FLEURY_*` runtime settings
or an active Dart VM service before opening the SDK. Fleury currently uses an
exact Git revision; release builds wait for a reviewed hosted Fleury release.
Source and native archive builds remain supported.

### Local browser UX preview

The [website demo](https://danreynolds.github.io/keybay/#tui) runs the same TUI
screens entirely in the browser with temporary fake data. Reset or reload to
restore the samples. It does not connect to your Keybay store or demonstrate
native storage protection. See the [site build guide](../../site/README.md)
to run it from a checkout.

Run the same TUI widgets and model in Fleury's browser surface from the workspace
root:

```sh
dart run fleury:fleury serve --host=127.0.0.1 --port=5777 \
  --spawn dart run packages/keybay_cli/tool/tui_preview.dart
```

Open `http://127.0.0.1:5777` in the browser, including Codex's in-app browser for
visual feedback. Each connection gets an isolated in-memory store seeded with
synthetic records; refresh to reset it. Copy simulates successful delivery and
never changes the system clipboard. The preview stays open for review instead
of applying the native runner's idle timeout. The production CLI's foreground
and remote-output restrictions are unchanged.

Append `--empty`, `--locked` (passphrase: `preview`), or `--copy-fails` to the
preview command to inspect those states. This development-only entrypoint is
not included in release artifacts.

## Quickstart

The source checkout and native release archives include the same
language-neutral executable example. Use
`packages/keybay_cli/example/quickstart` in a source checkout or
`example/quickstart` in an extracted native archive. The
[repository examples guide](https://github.com/danReynolds/keybay/tree/main/packages/keybay_cli/example)
distinguishes an installed `keybay` from the current source checkout; choose
one before running these commands:

```sh
keybay run -- ./app.sh
keybay set acme-example/openai-api-key
keybay run -- ./app.sh
```

If the demo key is not set, the first `run` prints the required `set` command
without launching the app. Enter any disposable value at the hidden prompt.
The second `run` safely shows the literal URL and reports the secret as available without
printing its value. The included `.env` contains only a public literal
and a reference; projects can commit manifests like this so every developer
shares the contract but supplies their own value.

After this disposable example:

```sh
keybay rm acme-example/openai-api-key
```

## Commands

```text
keybay open
keybay run [-f FILE] -- COMMAND [ARGS...]
keybay set [--stdin] KEY
keybay get KEY
keybay rm KEY
keybay list
```

Keys are at most 120 ASCII characters. Simple names such as `x` or `api-token`
work everywhere, including `kb://x` manifest references. Namespacing is optional:
use `organization-project/name` to organize project values or
`organization-shared/name` for deliberate reuse. Each slash-separated segment
starts with a letter or digit and may also contain `.`, `_`, and `-`.
Identical full keys share a value across repositories; namespaces are not an
access control boundary.

`set` never accepts a value argument. Interactive input requires a TTY and is
hidden. Enter submits, Backspace edits, and Ctrl+U clears the draft. Bracketed
paste preserves the exact UTF-8 bytes, including CRLF and a trailing newline;
press Enter after pasting to submit. Hidden prompts support the full 1 MiB
record limit and 1024-byte passphrase limit, and restore the caller's terminal
modes on completion, EOF, or a handled interrupt.

`--stdin` reads strict UTF-8 through a pipe or redirection. The two modes never cross: `--stdin` at
a terminal is refused (typing there would echo the secret into scrollback), and
empty input is rejected rather than stored, so a silently failed producer in a
pipeline cannot replace a real credential with the empty string. Internal
newlines in piped input are preserved; at most one final LF or CRLF is removed. Partial producer
output is not detectable, so use `pipefail` or check producer status:

```sh
op read 'op://Engineering/OpenAI/credential' |
  keybay set --stdin acme-api/openai-api-key
```

`rm` is idempotent and silent. `list` prints sorted key names only,
one per line. A failed `run` lists every missing key and launches nothing.

`get` is the explicit human reveal path. Stdout must be the process's own
controlling foreground terminal. Keybay checks before opening the store and
again immediately before reveal; redirected/captured stdout, another terminal,
and background jobs are refused. Stdin is untouched and may be redirected.
Use `run` to provide a value to another program.
On success, `get` prints exactly the requested text value followed by a newline.
That value may remain in terminal scrollback, so reveal it only when needed:

```sh
keybay get acme-api/openai-api-key
```

Values containing anything `keybay open` would show escaped (control,
line-break, bidirectional, invisible or prepended characters, and selectors or
marks that would draw nothing) are refused rather than rendered, because the
terminal would not show them faithfully; view them escaped in `keybay open`, or
pass them to their consumer with `run`.

The TTY check prevents casual disclosure; it is not an access-control boundary.
A program launched with `run` necessarily receives its selected secrets and can
print or transmit them.

## Authentication and lifetime

Platform protection is always present. If the store also requires a passphrase,
`set`, `get`, `rm`, `list`, and a secret-referencing `run` each make one hidden
passphrase attempt through the controlling terminal. Wrong input exits; there
is no automatic retry, background unlock agent, or cache between commands.
A value pipe remains separate from the passphrase, and `run` leaves stdin for
the child. Help, version, and literal-only `run` never open Keybay.

Use a passphrase for high-value credentials on ordinary desktop hosts. Their
declared application namespace does not isolate the store from every other
program running as the same user. The passphrase adds protection even when
that program can obtain the platform root and encrypted file.

Before `run` reads any referenced value, the terminal shows the canonical
executable, arguments, and every manifest environment name. For a protected
store this precedes the passphrase prompt, which is the approval. Without a
passphrase the summary is shown whenever a terminal is attached, but nothing is
asked: it makes a launch visible, not approved. References show their key names;
literal values and secret values are omitted. Paths and arguments are quoted
with terminal controls escaped. Assignments that can make the program run other
code, such as `PATH`, `LD_*`, `DYLD_*`, `NODE_OPTIONS`, `BASH_ENV`, `PYTHON*`
and `GIT_*`, are marked; the marking is a review aid, not a complete list.

Without a passphrase, any program running as you can use `keybay list` and
`keybay run` to read every value, without a terminal or prompt. On macOS that
also bypasses the Keychain prompt an unrelated program would otherwise meet.
Add a passphrase in `keybay open` → Settings → Security when that matters.

Passphrase setup/change/removal is available in `keybay open` → Settings → Security;
these standalone commands do not add a second management interface. Opening the
SDK can also invoke trusted OS/provider UI, including without a terminal.
Record operations never invoke it.

A handled interrupt stops subsequent actions. Already-submitted SDK work is
allowed to settle, late results are cleared, and sessions close before exit or
launch. A submitted write may have committed even when interrupted or failed;
reopen to inspect its result before retrying. Keybay never automatically resets
a store. V2 does not read, migrate, or remove V1 stores; preserve old data when
upgrading from 0.1.x.

## Manifest

Keybay reads `./.env` from the current directory. Use `-f FILE` to select a
different file, such as `keybay run -f .env.production -- npm start`.
It reads exactly one file: no automatic loading of `.env.local` or other
variants, merging, fallback, or parent-directory search. A missing or invalid
selected file stops the command before launch. Keybay never writes a manifest.
The selected input must be a regular file (a symlink to one is accepted).
Devices, directories, and FIFOs are rejected without waiting for input. The
file is opened once, with 1 MiB total and 64 KiB physical-line limits.

The grammar is intentionally smaller than dotenv:

- strict UTF-8; LF or CRLF; one leading BOM tolerated
- `NAME=VALUE`, comments, and blank lines
- ASCII space/tab trimming around values
- no quotes, escapes, interpolation, `export`, continuations, or inline
  comments
- a value beginning `kb://` must be a valid key reference
- duplicate environment names are errors

Literals are committed plaintext. Keybay cannot determine whether a literal is
actually a secret; that classification remains visible in review.

Initial executable lookup uses the inherited `PATH`, before any manifest
overlay or secret access. Empty/relative PATH entries use the invocation's
working directory; an unset or unrepresentable PATH performs no search.
Commands containing `/` resolve directly. The canonical executable and original
arguments are retained through authentication, with no second search or launch
fallback. A manifest's environment can still affect interpreters, loaders, and
descendants. Path preparation cannot prevent another same-user program from
replacing the executable later.

## Security boundary

Keybay keeps referenced values out of repositories, argv, routine output, and
interactive shell state. Explicit `get` and TUI reveal actions show the
selected value; Copy sends it to the system clipboard. It preserves the parent
environment **byte-exact** —
variables the manifest does not name pass through from the raw process
`environ`, including values that are not valid UTF-8 — overlays only variables
named by the selected manifest, resolves all references before launch, and has
no network code. The launched command starts with shell-default signal state
(the Dart VM's ignored SIGPIPE and blocked job-control signals are reset at the
exec boundary), so pipelines behave as they would from a shell.

Every Keybay command disables its own core files, and on Linux makes its process
non-dumpable, so a crash cannot persist an open session's store key or a
revealed value. A command that cannot do so exits before opening the store. The
launched command gets the caller's original core-file limit back.

After injection, values are normal child environment variables. They can be
inherited by descendants and may be visible to same-user process inspection,
crash dumps, or the child itself. Running a manifest trusts both its references
and the launched code. Direct use of the `keybay` Dart library is preferable
when an application can avoid environment injection entirely.

The initial target profiles are ordinary macOS and Linux desktop. Signed
packaging and architecture-specific release evidence are separate
remaining gates. SDK mobile and sandboxed-platform receipts do not qualify
those CLI distributions.

## Regression checks

From the repository root:

```sh
./tool/test_cli.sh core         # unit, disposable SDK, native PTY/exec checks
./tool/test_cli.sh macos        # real Keychain, disposable application identity
./tool/test_cli.sh linux        # private Secret Service; Docker when on macOS
./tool/test_cli.sh all          # all three; requires a macOS host and Docker
```

No arguments selects `core`. Reports under `build/regression` record
`kind: cli-regression`, source digest, platform, ABI, and per-selection result.
A missing prerequisite is blocked (69), never a pass. The core archive/signature
checks establish structure only; final signed distribution and upgrade evidence
remain a separate release gate. Generic Dart installation is not qualified by
these checks.

## License

MIT.

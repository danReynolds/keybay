# RFC 0002: Keybay V2 CLI and foreground UI

- **Status:** Proposed
- **Date:** 2026-08-28
- **Depends on:** [RFC 0001: Cross-platform per-application stores](0001-per-application-stores.md)

## Summary

Keybay V2 keeps the command line interface small while adding an optional,
meaningful protection boundary. The Keybay CLI is one application and therefore
has exactly one encrypted application store. Users do not create, name, select,
lock, or unlock stores as separate objects.

The command surface is:

```text
keybay set [--stdin] KEY
keybay get KEY
keybay rm KEY
keybay list
keybay run [-f FILE] -- COMMAND [ARGS...]
keybay open
```

When the CLI store has passphrase protection enabled, every invocation that
accesses it asks for the passphrase. Authentication lasts only for that process:

- `set`, `get`, `rm`, `list`, and `run` prompt once per invocation.
- `open` prompts once and keeps access only while its foreground TUI is alive.
- A second command is a second prompt. There is no ambient unlocked state.

`keybay open` is a Fleury-based foreground TUI for browsing key names, setting,
revealing, and deleting individual values, and configuring passphrase
protection. Values and passphrases are hidden by default and can be shown only
through an explicit UI action.

`keybay run` reads one dotenv-format manifest, resolves every `kb://` reference
before launching the child, and injects the manifest's literals and referenced
secrets. It never returns or injects unrelated store entries; the SDK may
decrypt the store's sealed record-name manifest and only the referenced record
frames as specified by RFC 0001. Unreferenced record values remain ciphertext.
A protected store prompts once no matter how many references the manifest
contains.

The CLI uses the same Dart SDK and store implementation as every other Keybay
application. It does not implement a second storage format, crypto path, or
passphrase protocol.

## Status and relation to the current CLI

This is a V2 proposal, not documentation of the currently released behavior.

The released 0.1.1 CLI provides `set`, `rm`, `list`, `run`, and `doctor`. It has
neither direct retrieval, a store TUI, nor Keybay-level passphrase protection.
V2 retains the useful command grammar, adds `get` and `open`, routes every store
operation through the per-application model in RFC 0001, defines the
authentication rules in this document, and drops `doctor` rather than retaining
an inspection API solely for that command.

Until this RFC is implemented and released, current architecture and CLI
documentation remain authoritative for shipped behavior.

## Goals

- Preserve the small `set` / `get` / `run` workflow that makes Keybay useful as
  a developer tool.
- Give users a straightforward local store UI without introducing named stores
  or a password-manager command hierarchy.
- Make a passphrase a real additional unlock requirement: possessing the
  platform credential or reading the encrypted store file must not be enough to
  access a protected store.
- Minimize how long passphrase-derived material and an unwrapped store key stay
  resident.
- Keep secrets out of argv, shell history, ordinary diagnostics, and accidental
  pipelines.
- Support `.env`-style workflows while disclosing only the values a selected
  manifest references.
- Keep SDK access exact-key and bounded. The CLI's process-environment injection
  does not justify an unscoped SDK `readAll` primitive.
- Report platform limits honestly instead of implying that every operating
  system provides the same application isolation.

## Non-goals

- Multiple CLI stores, store selection, profiles, or `--vault`/`--store` flags.
- A noun hierarchy such as `keybay vault create` or `keybay store create`.
- `lock`, `unlock`, or session-management commands.
- A background daemon, agent, credential cache, sliding TTL, or system-tray
  process.
- Passing a Keybay passphrase through argv, environment variables, ordinary
  stdin, or a file.
- Fully unattended use of a passphrase-protected store.
- Injecting every value in the store into a child process.
- Cloud accounts, synchronization, sharing, browser integration, escrow, or
  recovery of data after a forgotten passphrase. Local reset can erase the
  inaccessible store but cannot recover it.
- Clipboard integration, automatic typing, password generation, or a full
  password-manager feature set in this revision.
- Additional unlock methods such as biometrics or hardware tokens in this RFC.
  The architecture may add them later without changing the one-store CLI
  grammar.

## Core decisions

### One CLI application, one store

The installed Keybay CLI has one stable application identity under RFC 0001.
Every command that requires store state resolves that identity's one store. A
literal-only `run` need not open it. The command parser exposes no application
ID or store selector.

This means:

- Keys such as `acme-api/openai-token` and `personal/email-password` are names
  inside the same CLI store.
- A slash in a key is organizational naming, not a separate store or access
  boundary.
- Source/development builds should use the identity rules from RFC 0001; they
  must not gain an ad hoc flag for reaching another application's store.
- Applications using the Keybay SDK have their own application store. They do
  not share the CLI store merely because they use the same package.

The absence of multiple stores is deliberate. Most applications need one
secure store, and the CLI does not need a second hierarchy to provide useful
namespacing.

### The SDK owns storage and cryptography

The CLI is an SDK client:

```text
command parser / Fleury TUI
              |
              v
       Keybay Dart SDK
              |
              v
 per-application store + platform provider
```

The SDK owns application identity, store discovery, envelope parsing,
passphrase derivation, authentication, store-key unwrapping, authenticated
storage, concurrency coordination, and atomic updates. The CLI owns only
terminal interaction, command policy, dotenv parsing, and child-process
execution.

There must not be a CLI-only encryption format or a second interpretation of
passphrase metadata. A security fix in the SDK must cover the CLI automatically.

The SDK remains an exact-key interface for ordinary applications. It does not
gain "read the whole store into the environment" merely to support `run`;
`run` parses its manifest and makes one bounded `getManyBytes` request for the
distinct referenced keys through one process-local `KeybaySession`. RFC 0001
requires that request to read one authenticated store generation and return no
unreferenced values. The SDK clears its decrypted record-name manifest and
selected-frame scratch before the operation settles; it never decrypts an
unreferenced record value.

`list` and the TUI may use an SDK operation that enumerates key names. That
operation returns names only. It is not a `readAll` API for values, and selecting
or injecting values still requires an explicit exact-key request.

### Per-invocation authentication

If passphrase protection is enabled, a store-accessing command obtains the
passphrase from the controlling terminal, asks the SDK to authenticate the
store, performs its bounded operation, and exits. The next invocation repeats
that process.

The command first attempts `Keybay.open()`. `AuthRequired` reveals no record
names or values; the CLI then prompts and reopens with
`PassphraseCredential`. A platform-only open succeeds directly. Every failed
open clears provider and key-package scratch material before returning.

The command owns an explicit SDK session:

```dart
final opening = Keybay.open(
  credential: PassphraseCredential(phrase: passphraseBytes),
);
passphraseBytes.fillRange(0, passphraseBytes.length, 0);

final session = await opening;

try {
  // One command's exact get/set/keys/delete operations.
} finally {
  await session.close();
}
```

The terminal adapter produces a mutable byte buffer. `PassphraseCredential` borrows
it without copying; the SDK operation synchronously snapshots it, after which
the CLI clears its original and the SDK owns and clears only its internal copy
on every success and failure path. RFC 0001 requires SDK entry failures to use
the returned future rather than escape synchronously, so the clear immediately
after the call also runs for invalid input or a closed session.
`Keybay.open()` never opens terminal UI itself. Opening retains the store key
and minimal authenticated metadata, not the record-name manifest or values.

There is no cross-process credential cache. In particular, V2 does not create:

- a socket or IPC service;
- a file containing an unlock token;
- a key in an environment variable;
- a resident agent holding the unwrapped store key; or
- a timestamp that lets later processes skip authentication.

This costs one prompt per command, but it gives the behavior a simple security
explanation: after an invocation ends, and while no `keybay open` process
remains, Keybay is not retaining a store key for the next command.

The TUI is the ergonomic escape hatch for a sequence of human operations. One
`keybay open` invocation authenticates once, and its process reuses that
`KeybaySession` until the TUI exits. That is not a system-wide unlock: no other
process can use it, and closing the foreground program clears its store key and
ends the access window.

### Conservative guidance, not a mandatory platform policy

Passphrase protection is optional on every platform. The CLI does not silently
enable it on Linux, nor does it pretend it is unnecessary everywhere else.

V2 does not add public platform inspection solely to customize this guidance.
After authentication, `session.auth.list().isEmpty` tells the CLI that the store
uses platform protection only. The CLI then recommends a passphrase as
additional protection and links to the platform-specific documentation. It does
not claim a stronger or weaker application boundary than the SDK has qualified.

Warnings are informational. Declining a passphrase must not select plaintext
storage: the platform-backed encrypted-store baseline in RFC 0001 still applies.

Every store-accessing invocation against a platform-only store emits one concise
warning outside machine-readable stdout and points to `keybay open` for adding a
passphrase. The warning is intentionally conservative on platforms with strong
application isolation. Repeating it makes an unexpected missing prompt visible
after a complete local-state substitution; it does not cryptographically
prevent substitution. Platform-only unattended workflows continue after
writing the warning to stderr. The warning is emitted after the session opens
and its authenticated method list is known, but before `set` accepts a value,
`get` requests its selected record frame, or `run` resolves references and
launches its child.

### CLI key and value contract

CLI keys use the RFC 0001 record-key grammar and require at least two segments,
for example `acme-api/openai-token`. They are 1 to 120 ASCII characters overall,
contain no empty segments or display-control characters, and are printed
exactly as stored. In `kb://KEY`, the suffix is that exact key: it is not URL
decoded and has no query or fragment syntax.

The SDK's default `get` and `set` methods use strings, but the V2 CLI uses the
byte variants internally to keep mutable plaintext where practical. The CLI
accepts UTF-8 text values only. Input uses the SDK's published per-value limit,
is additionally constrained by the total-store limit, and rejects NUL.
Interactive `set` reads one hidden line. `set --stdin` reads through EOF,
preserves internal newlines, and removes at most one producer line ending (`LF`
or `CRLF`); an empty result is rejected to catch the common case of a producer
that emits nothing. Keybay cannot observe an upstream process's exit status or
distinguish intentional partial output from a complete value. These framing
rules are part of the command contract, not an exact byte-export API.

`get` is deliberately human rendering. It preserves the stored text and adds a
final newline for terminal display; it is not a lossless serialization channel.
It refuses every embedded C0/C1 control and Unicode bidirectional control,
including tab, carriage return, and newline. Multiline or structured values are
shown only in the TUI's unmistakably framed, escaped value view. Programs
receive values through `run` or the SDK rather than by parsing `get` output.

### Absent store behavior

RFC 0001 defines `Keybay.open()` as open-or-initialize on total absence. A CLI
command that opens a session may therefore atomically initialize an empty
platform-only store before reporting that a requested key is absent. This keeps
the CLI on the same SDK path instead of adding a second creation protocol.

A literal-only `run` does not open Keybay. When a manifest contains
`kb://` references, `run` opens one session; if the store was absent, it reports
the missing referenced keys and launches nothing, although the empty encrypted
store may now exist. Partial, invalidated, migrating, or open-detectable
bootstrap/key-package corruption fails closed and is never treated as first
use. Manifest or frame corruption fails at the bounded record operation defined
by RFC 0001 rather than being falsely certified during `open()`.

### Exit status contract

CLI-originated statuses are stable across commands:

| Status | Meaning |
|---:|---|
| `0` | The requested Keybay operation completed. An empty list and idempotent removal of an absent key are successes. |
| `1` | Authentication, provider, integrity, state, I/O, or unexpected Keybay operation failure. |
| `2` | Invalid command grammar, key, value, manifest, or other caller input. |
| `3` | A requested key or one or more selected-manifest references were absent. |
| `4` | The required controlling-terminal, foreground, output-device, or explicit-interaction safety condition was unavailable. |
| `126` | The selected child was resolved but could not be invoked. |
| `127` | The selected child executable could not be resolved. |

For `run`, these statuses apply only before a child is created. After successful
creation, Keybay returns the child's status according to the qualified platform
adapter, even when it numerically equals a Keybay-originated status. Diagnostics
make clear whether launch occurred, without printing secret values. Platform
signal/control-event mapping is part of adapter qualification, not invented by
the generic CLI layer.

## Command behavior

### `keybay set [--stdin] KEY`

`set` creates or replaces one value.

Interactive mode reads the value from a hidden terminal prompt. A secret is
never accepted as a positional argument or option value:

```console
$ keybay set acme-api/openai-token
Keybay passphrase: ********
Value: ********
Stored acme-api/openai-token
```

The passphrase line is absent for a platform-only store. When present, it is
asked before the new value so authentication failure cannot leave the user
uncertain whether a replacement occurred.

`--stdin` reserves process stdin for the new value. It is intended for an
attended pipeline from another secret tool:

```console
$ op read 'op://Engineering/OpenAI/credential' | \
    keybay set --stdin acme-api/openai-token
Keybay passphrase: ********
Stored acme-api/openai-token
```

If the store is protected, the passphrase still comes from the controlling
terminal, not from the pipe. Without a controlling terminal the command fails
before modifying the store. `--stdin` never changes meaning to "read the
passphrase from stdin."

Interactive input requires a foreground terminal and disables echo. `--stdin`
requires an actual pipe or redirection and refuses a terminal, preventing an
operator from unknowingly typing an echoed value. Empty input is rejected so a
producer that emits nothing cannot erase a credential; callers still need
`pipefail` or explicit status handling because partial output is not detectable.
The CLI passes the validated mutable buffer to `session.setBytes()`, clears its
own copy as soon as the SDK has synchronously snapshotted it, and then awaits the
operation.

### `keybay get KEY`

`get` is the explicit human reveal path:

```console
$ keybay get acme-api/openai-token
Keybay passphrase: ********
sk-example-value
```

It requires a controlling foreground terminal. Standard output must resolve to
that same terminal device; a second PTY is not an equivalent destination. It
refuses pipes, redirection, non-TTY output, mismatched terminals, and background
process groups. On success it renders the requested text value directly to that
terminal followed by a newline.

After successful authentication, a missing key writes
`Key not found: KEY` to stderr, writes nothing to stdout, and exits with the
documented not-found status. It is never represented as an empty value. Before
authentication succeeds, Keybay does not reveal whether the key exists.

The CLI calls `session.getBytes()`, validates and renders the returned UTF-8
value, and clears the caller-owned buffer on every path. It does not create a
Dart string merely to call the SDK's convenience API.

The restriction prevents common accidental disclosure; it is not an
authorization boundary. A revealed value can remain in terminal scrollback and
can be observed by screen capture, shoulder surfing, or a compromised terminal.
Keybay cannot detect a PTY recorder, terminal logging, `script`, or multiplexer
capture, even though each presents a TTY.
Values containing terminal-control or bidirectional-control characters are not
rendered by `get`. Users use the framed TUI view for deliberate inspection or
provide a value to a program with `run`, not `get | program`.

### `keybay rm KEY`

`rm` removes one value and is idempotent:

```console
$ keybay rm acme-api/old-token
Keybay passphrase: ********
```

Authentication happens before the command reveals whether a protected store
contains the key. A wrong passphrase, unavailable platform provider, or
unauthenticated container causes no mutation.

### `keybay list`

`list` prints sorted key names, one per line. It never prints labels and values
on the same line, previews, lengths, or timestamps.

Key names must not contain secret material. Nevertheless, they are stored
inside the authenticated store and listing a protected store requires its
passphrase. Unlike `get`, name output may be redirected for ordinary developer
workflows.

### `keybay run [-f FILE] -- COMMAND [ARGS...]`

`run` launches one command with a dotenv-format manifest overlaid on its
environment:

```dotenv
API_URL=https://staging.example.com
LOG_LEVEL=debug
OPENAI_API_KEY=kb://acme-api/openai-token
DATABASE_PASSWORD=kb://acme-api/database-password
```

```console
$ keybay run -f .env -- npm start
Run: /usr/bin/npm start
Manifest: /work/acme/.env
Environment:
  API_URL (literal)
  LOG_LEVEL (literal)
  OPENAI_API_KEY <- acme-api/openai-token
  DATABASE_PASSWORD <- acme-api/database-password
Keybay passphrase: ********
```

The default manifest remains `./.secrets.env`; a conventional `.env` file is
selected explicitly with `-f .env`. Keybay reads exactly one selected file. It
does not search parent directories, merge implicit files, or write the
manifest.

The V2 manifest grammar is deliberately smaller than general dotenv:

- the file is valid UTF-8, optionally with one leading BOM, at most 1 MiB, with
  `LF` or `CRLF` endings and a 64 KiB limit per physical line;
- a blank line or a line whose first non-space/tab character is `#` is ignored;
- every other line is exactly `NAME=VALUE`, where `NAME` matches
  `[A-Za-z_][A-Za-z0-9_]*`, begins in column one, and appears only once under
  the target platform's environment-name equivalence;
- ASCII space and tab surrounding `VALUE` are removed; the remaining text is a
  literal, except that a whole value beginning `kb://` is always a reference;
- a reference's suffix must satisfy the CLI key grammar and is used verbatim,
  with no percent decoding or URI semantics; and
- quoting, escapes, inline comments, interpolation, shell evaluation, command
  substitution, multiline syntax, and an escape for literal `kb://...` values
  are not supported.

NUL, invalid UTF-8, unsupported carriage returns, oversize input, malformed
assignments, and duplicates reject the complete manifest without echoing its
contents. Keybay opens the selected path once, accepts only a regular-file
handle (including a symlink resolved to a regular file), reads it once through
that handle, and never reopens it between validation and execution.

Environment names are case-sensitive on POSIX and case-insensitive on Windows.
Thus `PATH` and `Path` are distinct on POSIX but a rejected duplicate on
Windows. Overlay construction uses the same equivalence against the inherited
environment and emits exactly one final entry per equivalent name, so the
approval summary and child environment cannot disagree through case folding.

POSIX executable resolution is deterministic and uses a working directory
captured when Keybay starts. An empty `COMMAND` is invalid input. If `COMMAND`
contains `/`, Keybay resolves an absolute path directly or a relative path
against that captured directory, follows symlinks to a canonical absolute
target, and requires an executable regular file. A missing/dangling target is
status `127`; a target that exists but is a directory, lacks execute permission,
or cannot be invoked is `126`.

If `COMMAND` contains no `/`, Keybay searches the inherited, pre-overlay `PATH`
from left to right. An unset `PATH` performs no implicit default search and
returns `127`. Empty or relative entries resolve against the captured working
directory. Keybay continues past non-executable candidates but remembers them:
if no executable target is found, at least one existing unusable candidate
produces `126`; otherwise the result is `127`. The canonical absolute target is
the path shown for approval and passed to `execve`. This does not prevent the
same-user replacement race disclosed below, but it prevents the manifest's
overlay and post-approval `PATH` changes from selecting another initial target.
Windows resolution, including `PATHEXT`, remains unavailable until its adapter
contract and fixtures are qualified.

`run` follows this transaction. Steps 4 through 7 apply only when the manifest
has at least one reference; a platform-only open skips steps 5 and 6.

1. Parse and validate the complete manifest without accessing secret values.
2. Resolve the requested executable to an absolute path using the inherited,
   pre-overlay environment. The manifest's `PATH` cannot change which initial
   executable Keybay launches, though it can affect that program's descendants.
3. Classify every manifest assignment as a literal or `kb://` reference, retain
   its environment-name mapping, and collect the distinct referenced-key set.
4. If references exist, first attempt `Keybay.open()` without a credential. A
   platform-only open succeeds, emits the conservative warning after
   `session.auth.list()` confirms no additional method, and retains that
   session. `AuthRequired` releases no record data and continues to the
   attended path below; every other failure launches nothing.
5. After `AuthRequired`, safely render the selected manifest,
   resolved executable and arguments, and every environment-variable name on
   the controlling terminal. References display as `ENV_NAME <- key-name`;
   literals display as `ENV_NAME (literal)` without echoing their values.
   Execution-affecting names such as `PATH`, `LD_PRELOAD`, and `DYLD_*` are
   highlighted. Untrusted path and argument text is escaped rather than
   interpreted as terminal controls.
6. Prompt once through that terminal and open one authenticated
   `KeybaySession`. Entering the passphrase approves release of the displayed
   references to this already-read manifest and launch request.
7. On whichever session step 4 or 6 produced, call
   `session.getManyBytes(distinctReferencedKeys)` once.
8. Confirm that every reference exists, strictly decode each value as UTF-8,
   and validate every resulting environment value.
9. If anything is missing or invalid, report names only, overwrite every
   returned byte buffer, close any session, and launch nothing.
10. Overlay every manifest entry—both literals and resolved references—on the
   inherited process environment.
11. Overwrite every returned byte buffer, await `session.close()` when a session
    exists, and close or mark close-on-exec every CLI-owned manifest and terminal
    descriptor. RFC 0001's close contract releases SDK-owned store keys, locks,
    and provider handles; operation-lived authentication buffers must already
    have been cleared.
12. Execute the resolved program directly, without a shell.

The phrase "the whole manifest" is important: every valid assignment in the
chosen file is injected, as users expect from a dotenv workflow. The phrase
"referenced keys" is equally important: entries in the CLI store that the
manifest does not reference are never copied into result buffers or given to the
child. `getManyBytes` decrypts the sealed record-name manifest and only the
referenced record frames, then clears SDK-owned scratch before it settles. All
referenced values come from the one authenticated generation selected by
`getManyBytes`; a concurrent commit may leave the operation with the prior
complete generation or make it fail, but cannot produce a mixed-generation
environment.

If the manifest contains no `kb://` references, `run` does not open the store
and does not request its passphrase. It acts only as a validated literal
environment overlay in that case.

A platform-only invocation has no additional Keybay approval step. Its selected
manifest and command are the caller's authority, including in an unattended
run. This is the automation-friendly mode's explicit trust boundary: on a
`namespaceOnly` platform, any same-user program able to invoke the CLI may be
able to request those references. Users who require attended authorization use
passphrase protection.

The approval summary binds secret release to the parsed manifest and launch
request, not to a cryptographic identity for the executable. Keybay does not
prevent a same-user attacker from replacing a binary after path resolution, and
it does not print literal values for inspection because a manifest may itself
contain plaintext secrets. The selected manifest is therefore trusted input;
the summary makes its authority legible without claiming to make it safe.

The passphrase prompt uses the controlling terminal, leaving process stdin
untouched for the child. After validation, Keybay replaces itself with the
child where the platform supports `execve`; it does not remain as an ambient
secret broker. Arguments are passed directly and are never reconstructed into
a shell command. `session.close()` completes before process replacement. The
environment values intentionally copied for the child remain caller-owned
plaintext, but Keybay's session key and caller-owned `getManyBytes` buffers do not.
On any validation or launch-preparation failure, every returned buffer is
overwritten, the same close path runs, and no child is launched. Every remaining
descriptor is closed or marked close-on-exec; only the child's intended
standard streams and explicitly requested inherited descriptors remain.

Where direct process replacement is unavailable, Keybay uses the platform's
direct process-creation API without a shell. It closes the session before
creation and passes arguments plus environment through the platform's native
launch representation. POSIX preserves the exact argv element boundaries. An
eventual Windows adapter must instead define and fixture-test its
`CreateProcessW` command-line encoding because Windows does not receive an argv
vector from the parent. Keybay clears its mutable launch buffers best-effort
immediately afterward, forwards termination/interrupt signals according to the
qualified platform contract, waits for the child, and exits with the child's
status. It never respawns the command or acts as a secret service. The parent
may remain as a minimal supervisor, but it retains no `Kstore` or Keybay record
plaintext beyond unavoidable immutable runtime copies.

The child receives ordinary environment variables. It and its descendants can
read, print, persist, or transmit them. Platform-permitted peer inspection may
also expose them—for example, Linux gates
[`/proc/PID/environ`](https://www.man7.org/linux/man-pages/man5/proc_pid_environ.5.html)
through its ptrace access checks rather than through Keybay. Running a manifest
therefore trusts the manifest, the launched executable, its descendants, and
the operating system's process-inspection boundary.

### `keybay open`

`open` starts the Fleury TUI on a foreground terminal:

```console
$ keybay open
```

If passphrase protection is enabled, the first screen asks for the passphrase.
The field is masked by default and has an explicit show/hide control. Failed
authentication does not reveal key names or open the main screen.

The main screen provides:

- a searchable, sorted list of key names;
- a detail view whose value is hidden by default;
- explicit show/hide for displayable values;
- set or replace with hidden entry and confirmation where appropriate;
- delete with confirmation;
- an unlock-method screen for enabling, changing, or removing the passphrase;
  and
- conservative platform-only guidance with a link to the qualified platform
  documentation.

The TUI does not display every value merely because the store is open. Selection
reveals metadata; revealing a value is a separate deliberate action. Unsafe
terminal text is never emitted as raw control bytes. A multiline or structured
value appears inside a bordered value view: line breaks are layout, tabs and
other controls are visibly escaped, and value text cannot draw outside that
frame or imitate a Keybay prompt. V2 does not put values on the clipboard or
invoke external commands.

The TUI fetches a value only for an explicit reveal or edit action and never
caches plaintext while browsing the key list. Hiding a value, navigating away,
committing or cancelling an edit, receiving `StaleSession`, and exiting all
overwrite the caller-owned source `Uint8List`, clear editable/passphrase
buffers, and erase sensitive screen regions best-effort. Flutter/Fleury and
terminal renderers may create immutable strings or platform copies that cannot
be proven zeroized; the UI minimizes their lifetime and does not claim
otherwise.

This UI-level selectivity matches the SDK storage boundary: browsing decrypts
record names from the sealed manifest, while an explicit reveal or edit
decrypts only the selected record frame under RFC 0001.

The TUI keeps one authenticated `KeybaySession` for its foreground lifetime. It
calls `session.close()` in its top-level `finally` path on normal exit,
cancellation, handled errors, and catchable signals. On a catchable job-control
event, or when it
detects that it no longer owns the foreground terminal, it clears sensitive
screen state, closes the session, and terminates before surrendering the
terminal where possible.
`SIGSTOP`, `SIGKILL`, power loss, and runtime crashes cannot be handled; after a
stop/resume that Keybay can observe, it must verify foreground ownership and
the store generation before rendering anything and otherwise clear and exit.
Those paths are best-effort limits, not a claim that every suspension can be
intercepted. There is no idle TTL: the process and its ownership of the
foreground PTY are the normal lifetime boundary.

Foreground PTY ownership does not prove physical visibility. A minimized
terminal window, or a detached `tmux`/`screen` session, can leave the TUI as the
foreground process of a PTY while no person can see it. In that state the
authenticated window remains open until the process exits. Users who need the
strongest boundary should exit `open` rather than detach it; an idle timeout or
terminal-session integration would require a later RFC.

The SDK binds the TUI session to a store key epoch and authenticated unlock
policy as specified by RFC 0001. Ordinary record commits are serialized and do
not invalidate it. If another process changes an unlock method and rotates
`Kstore`, the next operation returns `StaleSession` when the new epoch can be
authenticated, or a fail-closed authentication/state error when it cannot. The
TUI clears sensitive state and either reauthenticates through a new session or
exits. It never retries with stale key material.

The TUI begins with `Keybay.open()`. On `AuthRequired` it obtains a passphrase
and retries with
`Keybay.open(credential: PassphraseCredential(...))`. On total absence the
successful session reports `wasInitialized == true`; before accepting the first
record, the TUI explains the platform-only baseline and offers to add a
passphrase through that session. Declining continues with platform protection.
If state is partial or invalidated, the SDK returns a typed failure instead of
overwriting or repairing it. A direct `set` still opens and initializes a
baseline platform-only store, preserving unattended developer workflows.

`open` may offer its pre-session reset screen only when `Keybay.open()` fails
with `PlatformKeyInvalidated`, `StoreAuthenticationFailed`, or
`StoreStateConflict`. It identifies the target only as the current CLI store,
states that every value and protection method will be removed and cannot be
recovered by Keybay afterward, notes that external copies or storage remnants
may remain, and requires the user to type the case-sensitive phrase
`DELETE ALL KEYBAY DATA`. Only then does it call `Keybay.reset()`. Reset does
not reveal data or bypass authentication; it deliberately erases the current
application's state and initializes nothing.

No error-triggered reset screen or contextual reset suggestion follows
`AuthRequired`, `UnlockFailed`, `ProtectionMismatch`, `PlatformProtectorLocked`,
`PlatformInteractionRequired`, `PlatformProtectorUnavailable`,
`PlatformOperationFailed`, `StorageOperationFailed`, `StoreBusy`,
`UnsupportedStoreVersion`, `ApplicationIdentityUnavailable`, or other input,
lifecycle, resource, or transient failures. Those paths retain their specific
retry, unlock, upgrade, packaging, or operational guidance. Reset is never
automatic and is never presented as a remedy for a wrong credential.

`ResetIncomplete` states that cleanup may be partial and offers a deliberate
retry; every retry requires the same typed phrase again before another
`Keybay.reset()` call. Complete reset reports success and exits `open` without
initializing a replacement store. The next explicit store-accessing invocation
is first use.

Passphrase changes use the authenticated session's generic auth manager; the
TUI does not implement crypto or rewrite records itself:

```dart
final adding = session.auth.add(
  PassphraseCredential(phrase: confirmedNewPassphrase),
);
confirmedNewPassphrase.fillRange(0, confirmedNewPassphrase.length, 0);
await adding;

final updating = session.auth.update(
  PassphraseCredential(phrase: confirmedReplacementPassphrase),
);
confirmedReplacementPassphrase.fillRange(
  0,
  confirmedReplacementPassphrase.length,
  0,
);
await updating;

final passphrase =
    (await session.auth.list()).whereType<PassphraseMethod>().single;
await session.auth.remove(passphrase.id);
```

`add` fails if a passphrase already exists; `update` fails if none exists and
otherwise atomically replaces it. Remove is never used as the first half of an
update. The TUI explicitly confirms the protection reduction before removing
the final method.

The settings screen offers two deliberately different operations:

- **Clear all records** confirms once, calls authenticated
  `session.clearAll()`, preserves protection, and keeps the TUI session open.
- **Reset Keybay completely** requires the typed phrase above, calls
  `Keybay.reset()`, closes the session, and exits without creating replacement
  state.

For forgotten-passphrase recovery, the user may deliberately navigate from the
unauthenticated `open` UI to **Reset Keybay completely**. `AuthRequired` and
`UnlockFailed` never route there automatically, highlight it as a credential
remedy, or claim that a passphrase was forgotten rather than mistyped. The reset
screen states plainly that reset recovers usability only by deleting the
inaccessible data; it does not recover any value, and it still requires the full
typed phrase.

Interruption must leave either the old valid protection state or the new valid
state, never a half-updated store. Each successful change rotates `Kstore`,
invalidates peer sessions, and retains platform protection. Keybay has no
passphrase escrow or data-recovery path; the TUI must say so before enabling
protection.

## Passphrase input policy

Whenever a passphrase is required, the CLI reads it from the controlling
terminal rather than process stdin. Echo is disabled before the first byte is
read and restored on success, cancellation, EOF, error, and handled signals.
Before rendering approval text or reading any passphrase, the prompt adapter
verifies that Keybay's process group owns that same controlling terminal. This
check applies whenever `set --stdin`, `rm`, `list`, `run`, `set`, `get`, or
`open` needs a passphrase prompt. In that case missing or background terminal
ownership fails before any record value is read or mutated. It does not add a
TTY requirement to otherwise headless-compatible platform-only `set --stdin`
or `run`; `get` and `open` remain foreground interfaces in every mode.

The CLI must not support any of the following in V2:

```text
keybay list --passphrase PASSPHRASE
keybay list --passphrase-file FILE
KEYBAY_PASSPHRASE=PASSPHRASE keybay list
printf PASSPHRASE | keybay list
```

Argv is commonly retained in shell history or visible to process inspection;
environment variables propagate unexpectedly; files create a second secret to
protect; and ordinary stdin is already meaningful to `set --stdin` and the
child launched by `run`.

The CLI defines its own canonical mapping into the SDK's `Uint8List` input:
encode the final entered Unicode scalar sequence as UTF-8, exclude the
Enter/line terminator, and perform no trimming, case conversion, or Unicode
normalization. V2 CLI passphrases are 1 to 1024 encoded bytes. New passphrases
are confirmed by byte equality after this conversion. The terminal adapter
should accumulate mutable bytes without constructing an immutable Dart string
where its input stack permits. The SDK operation snapshots that input when
`PassphraseCredential` is passed to it; the CLI then overwrites its source
buffer, and the SDK clears its private copy after the operation. Unavoidable
renderer/runtime copies are cleared or released best-effort and documented. Policy and KDF
parameters remain in RFC 0001 and
the SDK so every caller derives the same key from the same bytes.

When no controlling terminal is available:

- a platform-only store can perform operations that otherwise support the
  execution context, including `set --stdin` and `run`, only when its provider
  can open non-interactively;
- a locked provider or one that would need UI returns a typed failure rather
  than displaying an implicit OS/keyring prompt;
- a passphrase-protected store fails with guidance before reading or mutating
  secret data; and
- `open` and `get` always fail because they are foreground-human interfaces.

This is a deliberate security/automation tradeoff. A future hardware-backed
unlock-method or agent protocol should be proposed independently rather than
smuggling a passphrase through an unsafe channel.

## Security model

### What this design improves

When passphrase protection is enabled under RFC 0001, a process that can copy
the encrypted store and retrieve its platform root still lacks the
passphrase-derived material needed to unwrap the store key. Merely invoking the
CLI is not enough: each process must obtain the passphrase from the user.

Per-invocation authentication also avoids a long-lived general-purpose agent
that any same-user process could ask to decrypt values. `open` is the only
longer-lived access window, and it is represented by a foreground PTY process
rather than an invisible timer. A minimized or detached terminal may hide that
process without ending the window.

The command rules additionally reduce routine disclosure:

- secret values and passphrases never enter argv;
- passphrases never enter environment variables or normal stdin;
- `get` refuses non-TTY output and non-foreground process groups;
- `run` returns only manifest-referenced values from one bounded SDK operation;
- all references resolve before a child is launched; and
- errors contain key names where useful, never values or passphrases.

### What this design does not protect against

The CLI and TUI are not a sandbox. This design does not defeat:

- root, kernel compromise, or an attacker with equivalent administrative
  control;
- same-user malware that can keylog the passphrase, capture the screen, attach
  to the Keybay process, or read its memory;
- a malicious terminal emulator or injected library;
- a program deliberately launched by `run`, which receives every secret its
  manifest references;
- total replacement of both store file and platform credential on a
  `namespaceOnly` platform; without an independent caller-held expectation, the
  CLI cannot preserve the fact that the replaced store previously required a
  passphrase;
- disclosure after `get` renders a value; or
- offline passphrase guessing after an attacker obtains both the encrypted
  store file and enough platform-root access or material to open its outer key
  package and copy the inner passphrase envelope. The SDK's memory-hard KDF
  raises that cost but cannot enforce an online lockout on an attacker holding
  those artifacts.

TTY checks prevent accidents, not hostile code running as the same user. The
bounded claim is that a dormant protected store resists a same-user attacker
who can reach the file and platform credential but cannot observe an authorized
operation or learn the passphrase. The RFC does not make the broader claim that
Keybay defeats malware active during use.

## Failure semantics

All operations fail closed:

- A cancelled or incorrect passphrase yields no value, mutation, or child
  process.
- Authentication failure must not disclose whether a requested key exists.
- After successful authentication, missing `get` writes no stdout, emits the
  caller-supplied key name on stderr, and returns status `3` rather than
  masquerading as an empty value.
- A wrong passphrase and unauthenticated-envelope failure may share a generic
  user-facing message; diagnostics must not turn authentication into an oracle.
- A missing `run` reference reports the missing key name because that name is
  already present in the selected manifest, but no resolved values are printed.
- A malformed or duplicate manifest entry prevents every lookup and prevents
  child launch.
- If one of several references fails, none are injected and the child is not
  launched.
- Provider failure, store authentication failure, and corrupt/tampered store
  data remain typed SDK failures, mapped to stable CLI exit categories without
  raw provider output.
- An unlock-method change is atomic. Recovery never deletes or reprovisions an
  unreadable store automatically.
- Terminal modes and screen state are restored best-effort on every handled exit
  path. Restoration failure must never cause a secret to be printed as part of
  an error.

## Examples

### Simple developer workflow

```console
$ keybay set acme-web/stripe-secret
Platform protection only. Run `keybay open` to add a passphrase.
Value: ********
Stored acme-web/stripe-secret

$ keybay run -f .env -- npm run dev
Platform protection only. Run `keybay open` to add a passphrase.
```

The absence of a passphrase prompt means this store currently relies on its
platform protection. It does not mean values are stored as plaintext.

### Add passphrase protection

On first use, `keybay open` has already created an empty platform-protected
store and offers the additional method before accepting a record. An
illustrative TUI interaction is:

```console
$ keybay open
First use
  Protection: platform only
  [Add passphrase]

New passphrase: ********
Confirm passphrase: ********
Passphrase protection enabled
```

The TUI calls `session.auth.add(PassphraseCredential(...))`; the SDK rotates the
empty store key and commits the protected generation before reporting success.
No value is stored during the temporary platform-only generation.

### The same workflow with additional protection

```console
$ keybay set acme-web/stripe-secret
Keybay passphrase: ********
Value: ********
Stored acme-web/stripe-secret

$ keybay run -f .env -- npm run dev
Run: /usr/bin/npm run dev
Manifest: /work/acme/.env
Environment:
  STRIPE_SECRET <- acme-web/stripe-secret
Keybay passphrase: ********

$ keybay list
Keybay passphrase: ********
acme-web/stripe-secret
```

These are three processes and therefore three passphrase prompts.

### Multiple references, one prompt

```dotenv
GITHUB_TOKEN=kb://acme-cli/github-token
SENTRY_DSN=kb://acme-cli/sentry-dsn
PUBLIC_ORIGIN=https://example.test
```

```console
$ keybay run -f .env -- dart run bin/server.dart
Run: /usr/bin/dart run bin/server.dart
Manifest: /work/acme/.env
Environment:
  GITHUB_TOKEN <- acme-cli/github-token
  SENTRY_DSN <- acme-cli/sentry-dsn
  PUBLIC_ORIGIN (literal)
Keybay passphrase: ********
```

The child receives all three manifest assignments. Keybay prompts once and
returns only the two referenced values. The SDK decrypts one record-name
manifest and those two record frames during that operation; other values remain
ciphertext.

### An attended pipeline

```console
$ security-tool export service-token | \
    keybay set --stdin acme-worker/service-token
Keybay passphrase: ********
Stored acme-worker/service-token
```

The pipe supplies the value; the terminal supplies the passphrase. Running the
same operation without a controlling terminal fails for a protected store.

## Implementation milestones

CLI work can begin against the RFC 0001 API after its M1 gate. Unit tests
assemble the production V2 engine with disposable boundary fakes; persistent
platform integration remains the final gate.

### C0 — Command contract

Freeze parsing, record-key validation, dotenv grammar, output framing, exit
categories, and command-policy tests without opening a store.

Exit gate: malformed input launches nothing; no grammar selects another
application or store; command and manifest fixtures define every accepted byte.

### C1 — SDK lifecycle

Integrate `KeybaySession`, including open-or-initialize,
`AuthRequired` retry with `PassphraseCredential`, conservative platform-only
guidance, bounded `getManyBytes`, auth-method CRUD, and every close/error path.
Tests inject a session opener at the CLI application boundary, backed by the
production engine and disposable file/protector fakes. Public constructors are
not added to sealed SDK output types, and production still calls the static
Keybay facade.

Exit gate: one prompt per protected invocation, zero prompts for platform-only
access, one session per command, no ambient credential, exact requested-key
disclosure, and unconditional close on every path.

### C2 — Terminal and process boundary

Implement controlling-terminal ownership, no-echo credential input, secure
restoration, direct process replacement, and supervised spawn without a shell.

Exit gate: terminal-loss and signal fixtures restore state; credentials never
enter argv, environment, ordinary stdin, or diagnostics; `run` closes and clears
SDK material before launch; child argv, environment, signals, and exit status
match the qualified native contract.

### C3 — Foreground Fleury UI

Build `keybay open` against fake records with masked values, explicit reveal and
edit actions, first-use guidance, auth add/update/remove, clear, reset, and stale
session handling.

Exit gate: no name appears before authentication; values remain hidden until an
explicit action; plaintext and terminal modes have bounded lifetimes; every
destructive or protection-reducing action receives the specified confirmation.

### C4 — Qualified SDK integration

Run the same command and TUI suites against each RFC 0001 profile only after its
M3–M7 format, transaction, passphrase, and platform gates pass.

Exit gate: packaging embeds the intended CLI identity; real-provider
platform-only and protected flows pass; release documentation and security
claims match retained evidence.

Real passphrase derivation, persistent rotation, and platform claims
remain owned by RFC 0001. The CLI does not wait for a public capability or
inspection API.

### Platform qualification still required

The POSIX terminal/process contract is specified by controlling terminals,
foreground process groups, argv, and `execve`. Windows support remains
unqualified until an adapter review defines equivalent Console/ConPTY ownership,
secure no-echo input, `CreateProcessW` command-line construction, environment
case folding, signal/control-event forwarding, and exit-status behavior. An
unqualified platform fails closed for `get`, `open`, protected prompts, and
`run`; it does not approximate these guarantees with shell invocation or an
unbound input stream.

## Validation criteria

Implementation is not complete until automated tests establish at least the
following.

### Command and identity boundaries

- Every command that requires store state reaches the CLI's one SDK-resolved
  application store; literal-only `run` does not open record state.
- No accepted argument can select an application ID or second store.
- `vault`, `store`, `--vault`, `--store`, `lock`, `unlock`, and the removed
  `doctor` command are rejected as unknown grammar.
- Source, development, and release identities follow RFC 0001 rather than
  silently sharing through a caller-provided runtime string.
- CLI keys enforce the two-segment subset and `kb://` suffixes use the exact
  canonical key with no decoding, query, fragment, or URI interpretation.

### Command I/O contract

- Interactive `set` and `set --stdin` enforce UTF-8, NUL, empty-result, line
  ending, framing, the SDK per-value limit, and the total-store limit exactly;
  stdin never becomes a passphrase channel.
- `get` requires the controlling foreground TTY, rejects redirection and
  background process groups, and never emits unframed control or bidirectional
  characters.
- A missing `get` result produces no stdout and status `3`; an empty value, if
  encountered through SDK-written state, remains distinguishable.
- `rm` is idempotent and authenticates before revealing whether a protected key
  existed.
- `list` emits only ASCII-sorted key names on stdout. Warnings and guidance use
  stderr and never corrupt machine-readable output.
- Every pre-child result maps to the documented `0`/`1`/`2`/`3`/`4`/`126`/`127`
  contract without exposing raw provider text or secret material; once a child
  starts, its status wins.
- Manifest tests cover the BOM, UTF-8, 1 MiB file, 64 KiB line, duplicate-name,
  malformed-line, whole-value-reference, and one-open-file-handle/TOCTOU rules.
- Environment overlay tests cover POSIX case sensitivity, Windows
  case-insensitive collisions such as `PATH`/`Path`, collisions with inherited
  entries, and exact agreement between approval summary and child environment.

### Authentication lifecycle

- Tests cover every RFC 0001 first-use/open state, including atomic
  initialization on total absence and failure on all partial, invalidated,
  malformed-bootstrap, and unauthenticated-key-package states. Manifest and
  frame corruption is tested at its RFC 0001 operation boundary.
- Each protected non-TUI command requests exactly one passphrase, even when
  `run` resolves several references.
- `run` makes exactly one bounded `getManyBytes` call for its distinct referenced
  keys; repeated references share that result and no unreferenced key is
  requested.
- `run` with no references never opens the store or requests a passphrase.
- Two separate invocations request it twice; no credential survives through a
  daemon, file, environment variable, or socket.
- A platform-only store does not show a passphrase prompt.
- Every platform-only access emits its conservative warning before accepting or
  releasing secret data, including after complete store substitution.
- Wrong input, cancellation, EOF, and provider failure cause no mutation and no
  child execution.
- Passphrase input never appears in argv, process environment, captured stdout,
  stderr, or structured errors.
- Passphrase conversion tests cover exact UTF-8 scalar encoding, no trimming or
  normalization, exclusion of the line terminator, the 1-to-1024-byte bound,
  and byte-equal confirmation.
- The CLI overwrites its passphrase input immediately after the SDK call returns
  its future, including invalid-input and closed-session failures; SDK tests
  prove those failures do not escape synchronously.
- `set --stdin` consumes the value pipe while passphrase entry uses the
  controlling terminal.
- `run` does not consume the child's stdin while asking for a passphrase.
- Every command closes its `KeybaySession` on success, cancellation, exception,
  terminal loss, and handled signal; `run` closes before `execve`.
- `run` overwrites every non-null `getManyBytes` result on success and on every
  missing-value, decoding, validation, and launch-preparation failure.
- `open()` decrypts no record values eagerly, calls after close fail with
  `SessionClosed`, and no operation remains in flight after close completes.
  Already-settled caller-owned results remain observable and are not revoked by
  close.
- Session-owned store keys are cleared by close and operation-owned derived-auth
  buffers are cleared when each authentication operation settles. Tests and
  documentation do not claim that close erases caller-owned values, immutable
  strings, or the child environment.

### TUI behavior

- The passphrase and value fields begin masked; show/hide is explicit.
- Opening a protected store reveals no key names before authentication.
- Values remain hidden when navigating the key list.
- `get` refuses every embedded control/bidirectional character, while the TUI
  renders multiline or structured values only in its framed escaped view.
- CRUD actions operate through the SDK's per-key API.
- Enabling, changing, and removing protection are atomic and preserve every
  value.
- Unsafe terminal text is never rendered as control sequences.
- Terminal echo, cursor, alternate-screen, and input modes are restored after
  success, cancellation, handled errors, and handled signals.
- Catchable suspension or backgrounding does not leave a hidden authenticated
  Keybay process; forced-stop and crash behavior is tested and documented as
  best effort.
- A stale TUI session cannot continue after an unlock-method rotation or
  ambiguous authentication/state failure without reopening; ordinary
  serialized record commits do not spuriously invalidate it.
- Passphrase add, update, and removal go through `session.auth`, rotate `Kstore`,
  preserve records atomically, and invalidate peer sessions.
- Complete reset requires the exact typed phrase, calls selector-free
  `Keybay.reset()`, handles `ResetIncomplete` with a deliberate retry, and exits
  without initializing a store.
- Authenticated `session.clearAll()` removes records while preserving protection
  and the open session; credential failures never trigger or recommend reset,
  while the user-invoked forgotten-passphrase reset path never claims to recover
  inaccessible data.

### `run` disclosure boundary

- Every literal and reference in the selected manifest reaches the child.
- Unreferenced values are not copied into result buffers and do not reach the
  child. The SDK decrypts the sealed record-name manifest and only referenced
  frames, then clears SDK-owned scratch before `getManyBytes` settles.
- A successful `run` selects all referenced values through one `getManyBytes`
  operation and therefore uses one authenticated store generation. A concurrent
  ordinary write or key rotation may make the operation fail but can never mix
  generations in the child environment.
- A protected run displays the resolved executable, escaped arguments, and
  every environment name with its literal/reference class before prompting.
- The initial executable is resolved before the manifest overlay; a manifest
  `PATH` cannot redirect that first launch.
- POSIX resolution fixtures cover absolute and slash-containing relative
  commands, captured working-directory behavior, unset/empty/relative `PATH`
  entries, search order including an unusable candidate before a later usable
  one, dangling symlinks, canonical approval paths, and the `126` versus `127`
  distinction.
- Missing references, duplicates, malformed input, authentication failure, and
  invalid environment values launch nothing.
- The child receives arguments directly without shell interpretation.
- Store, provider, lock, and prompt descriptors do not survive child launch.
- Both direct `execve` and supervised-spawn paths close the session before
  launch and propagate child status and relevant signals without retrying.
  POSIX preserves exact argv elements; other adapters preserve only the native
  representation proven by their platform qualification fixtures.
- Windows execution and terminal behavior is not advertised until its explicit
  Console/ConPTY and `CreateProcessW` qualification suite passes.
- Secret values are absent from argv and all Keybay diagnostics.
- The inherited environment is preserved except where the selected manifest
  explicitly overlays names.

### Platform and integration evidence

- Fake-SDK tests cover deterministic command and terminal state machines.
- Real-provider integration tests cover every supported platform path from RFC
  0001, including platform-only and passphrase-protected stores.
- Tests distinguish API-path evidence from physical hardware-backed evidence.
- Packaging tests prove that official CLI artifacts contain the intended stable
  application identity.

## Alternatives considered

### A login-style `keybay unlock`

An unlock command requires somewhere to retain authority for later processes:
an agent, socket, file token, environment change, or OS credential. That adds a
second access-control protocol and creates ambiguity about TTL, revocation,
terminal ownership, and which processes may use the unlocked state. V2 rejects
that complexity.

### A sliding-TTL agent

A TTL improves repeated-command ergonomics, but the expiry boundary is not
visible and every same-user client that can reach the agent becomes part of its
authorization design. It also introduces lifecycle, crash, suspend, IPC, and
upgrade concerns. The foreground TUI supplies batching with a much clearer
boundary.

### Passphrase flags or environment variables

They make automation easy by relocating the secret into history, process
metadata, inherited environments, or another file. V2 intentionally does not
support them. Unattended use should rely on an appropriately isolated platform
store or a separately designed non-passphrase unlock method.

### A `keybay vault ...` or `keybay store ...` hierarchy

The CLI owns exactly one store, so `store` would add a noun that never
disambiguates another command family. Flat verbs are shorter and match the
primary workflow.

### Inject the entire store with `run`

Bulk injection violates least disclosure and makes adding an unrelated key
silently expand every launched program's authority. The manifest is the
reviewable contract; only its references are read.

## Consequences

The normal workflow stays compact and a platform-only store remains automation
friendly. Users who choose a passphrase accept a prompt for every command and
lose fully unattended access in exchange for a real additional unlock
requirement and a short, obvious credential lifetime.

The Fleury TUI gives humans efficient multi-operation access without making
the SDK bulk-oriented or introducing an ambient agent. The cost is that an open
foreground TUI holds authenticated key material for longer than a single
command. Its process/foreground-PTY lifetime, hidden-by-default values, and
best-effort exit-on-background policy make that tradeoff explicit; detaching a
multiplexer does not close it.

Most importantly, the CLI has one security story: application identity and
cryptography come from the shared SDK; the terminal supplies a passphrase only
when the store requires one; each invocation gets only the authority needed for
its declared operation.

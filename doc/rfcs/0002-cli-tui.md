# RFC 0002: Keybay V2 CLI and foreground UI

- **Status:** C0–C3 implemented; C3 qualification and C4 release evidence tracked separately
- **Date:** 2026-08-28
- **Revised:** 2026-09-07 against the merged SDK 0.2.0 source
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

When the CLI store has passphrase protection enabled, each successful
store-accessing invocation authenticates with a passphrase. Authentication
lasts only for that process:

- `set`, `get`, `rm`, `list`, and a secret-referencing `run` make at most one
  passphrase attempt per invocation; a failed attempt exits.
- `open` authenticates one session and keeps access while its foreground TUI
  is alive. A failed attempt may be retried only by an explicit user action.
- A second command authenticates separately. There is no ambient unlocked state.

These are Keybay passphrase prompts. SDK opening, protection changes, and reset
may also invoke trusted OS/provider UI, even for a platform-only store.

`keybay open` is a Fleury-based foreground TUI for browsing key names, setting,
revealing, explicitly copying, and deleting individual values, and configuring passphrase
protection. Values and passphrases are hidden by default and can be shown only
through an explicit UI action.

`keybay run` reads one dotenv-format manifest, resolves every `kb://` reference
before launching the child, and injects the manifest's literals and referenced
secrets. It never returns or injects unrelated store entries; the SDK may
decrypt the store's sealed record-name manifest and only the referenced record
frames as specified by RFC 0001. Unreferenced record values remain ciphertext.
A protected run makes one Keybay passphrase attempt regardless of the number
of references; provider UI is a separate part of SDK opening.

The CLI uses the same Dart SDK and store implementation as every other Keybay
application. It does not implement a second storage format, crypto path, or
passphrase protocol.

## Status and relation to the current CLI

The baseline is the SDK 0.2.0 source merged by
[PR #66](https://github.com/danReynolds/keybay/pull/66), commit `0ca946d`.
The [SDK guide](../sdk.md) and exported
[public API](../../packages/keybay/lib/keybay.dart) are implemented dependencies,
not future work. SDK publication remains separate from this implementation plan.
The [scoped SDK qualification](../qualification-status.md#sdk-020-release-scope)
retains deferred physical lifecycle work and Argon2 performance acceptance;
RFC 2 neither reopens those gates nor calls them passed.

The published 0.1.1 CLI provides `set`, `rm`, `list`, `run`, and `doctor`.
The in-tree CLI uses V2 sessions and adds `get`. C0–C2 now implement the
standalone command contract and the selected foreground TUI; final release evidence remains ahead:

| Implemented | Remaining boundary |
|---|---|
| Command parsing, strict regular-file manifest input, exact-key SDK access, one passphrase attempt, session close | Release documentation must track the eventual TUI/packaging experience |
| Canonical target preparation from inherited `PATH`, protected-launch summary, one direct POSIX `execve`, raw inherited environment preservation | Final signed/installed artifact and upgrade qualification |
| Controlling-terminal checks, hidden input, handled interruption and late-result cleanup, native PTY tests | Foreground UI lifecycle in C3 |
| `core`, `macos`, `linux`, `all` regression selections and source/profile reports | Keep receipts scoped to their named host/ABI; C4 must qualify the distributed forms |
| `open` focused finder, SDK session owner, native terminal policy and exact Fleury pin | C3 regression and C4 distributed-artifact evidence |

The implementation replaces the former manifest-controlled executable lookup
and stdin-dependent `get` checks. Tests exercise actual command paths with the
production SDK engine over disposable boundaries, then real providers with
disposable identities. The earlier C0–C2 receipts do not qualify the TUI or
signed distribution. Current evidence is tracked in the
[CLI qualification status](../cli-qualification-status.md).

V2 does not read, migrate, or delete V1 stores. CLI upgrades need an explicit
compatibility notice; discovering or migrating old secrets is outside this RFC.
The in-tree README and examples must be reconciled before CLI publication;
version metadata `0.2.0` does not mean that CLI release has shipped.

### Initial release scope

The first CLI/TUI targets ordinary Linux desktop and unentitled macOS. Both
are POSIX terminal hosts and use the SDK's declared `keybay-cli` identity.
They are namespace-only profiles: invocation by another same-user program is
not an OS-enforced application authorization boundary.

SDK support for Android, iOS, entitled macOS, or Flatpak does not automatically
qualify a CLI artifact, its terminal, or child launch in that environment.
Flatpak CLI packaging and host/child execution policy are deferred, as are
mobile CLI distribution, Snap, and Windows. Any later packaged profile needs
its own identity, terminal, provider and launch evidence; it may never bypass
confinement or fall back to another SDK provider.

This revision preserves the flat command grammar, exact-key disclosure,
optional passphrase, foreground TUI and absence of a daemon. It removes the
unneeded supervised-launch implementation from the first release, keeps
passphrase management to the SDK's singleton method, and uses the current SDK
error/lifecycle contract without requesting new inspection or interaction APIs.

## Goals

- Preserve a small `set` / `get` / `run` workflow and a foreground UI for repeated
  human operations, using the same SDK and one application store.
- Make passphrases an additional cryptographic requirement, with short,
  explicit credential and session lifetimes.
- Keep values out of argv, history and diagnostics, and release to a child only
  the keys referenced by its selected manifest.
- Report actual platform and packaging limits without a capability framework
  or claims broader than the retained qualification evidence.

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
- Clipboard reading, synchronization, history, automatic typing, password
  generation, or a full password-manager feature set in this revision.
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
passphrase metadata. An SDK security fix must reach the CLI by updating its
reviewed dependency and rebuilding/releasing the CLI; an installed AOT artifact
does not update itself.

Use `session.listKeys()` for names and `getBytes`/`getManyBytes` for selected
values. A `run` uses one bounded batch for its distinct references, from one
authenticated generation; unrelated record values remain ciphertext. There is
no bulk-value export API added for the CLI. The shared SDK owns all format,
cryptographic and plaintext-scratch guarantees described in RFC 0001.

The implementation has three ownership boundaries:

| Owner | Responsibility |
|---|---|
| SDK | Identity, fixed paths/provider, authenticated record operations, passphrase derivation/rotation, locks, reset and key cleanup |
| CLI application code | Command ordering, manifest/launch preparation, one session lifetime, redacted error mapping and caller-owned byte cleanup |
| Terminal/Fleury adapter | Controlling-terminal checks, hidden input, safe rendering and restoring terminal state |

The TUI reuses the CLI's SDK session entry/cleanup and terminal safety rules.
It holds key names, selection and at most the active reveal/edit buffer; it
has no second repository, credential cache, SDK facade, or method-plugin layer.
Use Fleury for the screen and input lifecycle rather than building a second UI
framework. Review and pin its runtime closure in the CLI package; the core SDK
must not depend on Fleury. Only `open` starts the interactive screen.

### Per-invocation authentication

If passphrase protection is enabled, a store-accessing command obtains the
passphrase from the controlling terminal, asks the SDK to authenticate the
store, performs its bounded operation, and exits. The next invocation repeats
that process.

After command/manifest validation and any mandatory terminal checks, the command
attempts `Keybay.open()`. `authRequired` reveals no record names or values;
only that error triggers passphrase entry and a credential-bearing reopen.
A platform-only open needs no Keybay passphrase. Other failures retain their
specific operational guidance; they never trigger an automatic credential
retry or reset. The explicitly invoked reset UI has the narrow policy below.
Every failed open clears its SDK-owned scratch.

Each open attempt, including the initial credential-free attempt, may invoke
trusted OS/provider UI. The CLI cannot infer whether that UI will appear and
does not probe the provider, read SDK files, or add a public interaction flag.
Once a session is open, record operations and `auth.list()` are provider-free
and never prompt, including on failure. Passphrase management and reset may
invoke provider UI again. A Keybay passphrase always comes from the CLI's own
terminal input, never from provider UI.

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

This costs one Keybay passphrase entry per successful protected command.
After an invocation ends, and while no `keybay open` process remains, Keybay is
not retaining a store key for the next command.

The TUI supports a sequence of human operations through one `KeybaySession`.
It grants no access to other invocations. An invalid session is closed before
an explicit reauthentication attempt; no old passphrase is retained for retry.

`close()` rejects new work immediately and waits for accepted work to settle.
`isClosed` means that no new work is accepted; await `close()` for cleanup.
Closing does not cancel accepted operations or erase caller-owned results.
The SDK provides no cancellation token. Terminal cancellation stops further
CLI actions; if an SDK future is already pending, discard and clear late
results, await settlement/close on handled exit paths, and launch nothing.
A late successful open must also be closed. A submitted write or protection
change may have committed before an interruption or error is observed.

Device lock and provider lock do not revoke an already-open session's store
key. The TUI's explicit exit/foreground policy bounds that lifetime; this RFC
adds no device-lock watcher or claim of automatic revocation.

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
prevent substitution. Platform-only workflows whose provider opens successfully
continue after writing the warning to stderr; provider interaction can still
prevent unattended use. The warning is emitted after the session opens
and its authenticated method list is known, but before `set` accepts a value,
`get` requests its selected record frame, or `run` resolves references and
launches its child.

### CLI key and value contract

CLI keys use the RFC 0001 record-key grammar with optional namespacing,
for example `openai-token` or `acme-api/openai-token`. They are 1 to 120 ASCII
characters overall,
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
It refuses exactly what the TUI would escape (C0/C1 controls, line and
paragraph separators, bidirectional controls and other invisible format,
default-ignorable or prepended characters, stray variation selectors and marks
that would draw nothing) and the newline, including tab and carriage return. Multiline or structured values are
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
store may now exist. Partial or invalidated V2 state and open-detectable
bootstrap/key-package corruption fail closed and are never treated as first
use. A retained root without its complete file is `storeStateConflict`; it is
not proof of a fresh install or permission to create replacement state. V1 data
is not inspected. Manifest or frame corruption fails at its bounded record
operation rather than being falsely certified during `open()`.

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

For `run`, Keybay-originated statuses apply before successful process
replacement. After `execve` succeeds, the program runs in Keybay's place and
its own exit status/signals reach the caller, even when a status numerically
matches one above. Keybay never reports a child result before launch.

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
before submitting a record mutation. `--stdin` never changes meaning to "read the
passphrase from stdin."

Interactive input requires stdin to be the controlling foreground terminal and
disables echo. `--stdin` requires a pipe or redirection and refuses terminal
stdin. Check that mode before opening the SDK; do not consume the value pipe
until authentication and any platform-only warning have completed. Empty input is rejected so a
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
process groups. Check the controlling terminal and stdout before SDK opening
and immediately before rendering the value, including after provider UI.
Stdin need not be a terminal: `get` does not consume it or use it as proof of
controlling-terminal ownership. On success it renders the requested text value
to the verified stdout terminal followed by a newline.

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
$ keybay run -- npm start
Run: /usr/bin/npm start
Manifest: /work/acme/.env
Environment:
  API_URL (literal)
  LOG_LEVEL (literal)
  OPENAI_API_KEY <- acme-api/openai-token
  DATABASE_PASSWORD <- acme-api/database-password
Keybay passphrase: ********
```

The default manifest is `./.env` in the current directory. `-f FILE` selects
exactly one different file, for example `.env.production` or `.secrets.env`.
Keybay does not automatically load other variants, search parent directories,
merge files, or write the manifest. A missing or invalid selected file stops
the command before launch; there is no fallback to another file.

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
- no quote removal, escape processing, inline comments, interpolation, shell
  evaluation, command substitution or multiline syntax is performed. Quote,
  backslash and dollar characters in a literal are ordinary data; `export NAME`
  is an invalid name. There is no escape for a literal beginning `kb://`.

NUL, invalid UTF-8, unsupported carriage returns, oversize input, malformed
assignments, and duplicates reject the complete manifest without echoing its
contents. Keybay opens the selected path once, read-only, nonblocking,
close-on-exec and without acquiring a controlling terminal (`O_NOCTTY`). It
checks that the descriptor is a regular file before reading the bounded
content. A FIFO/device must not hang before its type can be rejected. Use the native
[open semantics](https://man7.org/linux/man-pages/man2/open.2.html) and verify
the corresponding macOS path in its harness. A symlink to a regular file is
accepted. The manifest is never reopened between validation and execution.

Environment names are case-sensitive on the initial POSIX targets. `PATH` and
`Path` are distinct. The native launch boundary preserves unoverlaid inherited
environment entries byte-for-byte, including values Dart cannot represent,
and replaces all exact-name matches for each manifest assignment. There is no
Windows case-folding layer in this release.

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
No second `PATH` search occurs after authentication or after an execution
failure. Keybay passes the original `COMMAND` as `argv[0]` and the remaining
arguments unchanged to `execve`; the canonical path is the execution target.
Scripts still follow the OS interpreter calling convention. An inherited
`PATH` that the Dart resolver cannot represent is treated as unavailable for
lookup; it is still preserved for the child unless overlaid.
Use an explicit executable path in that case.

`run` follows this transaction. Steps 4 through 7 apply only when the manifest
has at least one reference; a platform-only open skips steps 5 and 6.

1. Parse and validate the complete manifest without accessing secret values.
2. Resolve the requested executable to an absolute path using the inherited,
   pre-overlay environment. The manifest's `PATH` cannot change which initial
   file Keybay executes. The resulting environment can still affect script
   interpreters, dynamic loading and descendants; it is not a sandbox.
3. Classify every manifest assignment as a literal or `kb://` reference, retain
   its environment-name mapping, and collect the distinct referenced-key set.
4. If references exist, first attempt `Keybay.open()` without a credential. A
   platform-only open succeeds, emits the conservative warning after
   `session.auth.list()` confirms no additional method, shows the step 5
   summary on the controlling terminal when one is attached (best effort,
   without asking), and retains that session. `authRequired` releases no
   record data and continues to the attended path below; every other failure
   launches nothing.
5. After `authRequired`, safely render the selected manifest,
   resolved executable and arguments, and every environment-variable name on
   the controlling terminal. References display as `ENV_NAME <- key-name`;
   literals display as `ENV_NAME (literal)` without echoing their values.
   Execution-affecting names such as `PATH`, `LD_PRELOAD`, `DYLD_*`,
   `NODE_OPTIONS`, `BASH_ENV`, `PYTHON*` and `GIT_*` are highlighted; the list
   is a review aid, not a complete one. Untrusted path and argument text is escaped rather than
   interpreted as terminal controls.
6. Prompt once through that terminal and open one authenticated
   `KeybaySession`. Entering the passphrase approves release of the displayed
   references to this already-read manifest and launch request. Provider UI
   during either SDK open is separate and never substitutes for this approval.
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

Every valid manifest assignment reaches the child; unrelated store values do
not. All referenced values come from one authenticated `getManyBytes`
generation. A concurrent commit may leave the operation with the prior complete
generation or make it fail, but cannot produce a mixed-generation environment.

If the manifest contains no `kb://` references, `run` does not open the store
and does not request its passphrase. It acts only as a validated literal
environment overlay in that case.

A platform-only invocation has no additional Keybay approval step. Its selected
manifest and command are the caller's authority, including in an unattended
run. This is the automation-friendly mode's explicit trust boundary: on a
`namespaceOnly` platform, any same-user program can invoke the CLI to list
every name and request every value, without a terminal or prompt. On macOS
this also bypasses the Keychain prompt that an unrelated program reading the
item directly would meet. A terminal requirement would not change that, since a
program can supply its own pseudo-terminal. The summary shown on an attached
terminal makes a launch visible, not approved. Users who require attended
authorization use passphrase protection.

The approval summary binds secret release to the parsed manifest and launch
request, not to a cryptographic identity for the executable. Keybay does not
prevent a same-user attacker from replacing a binary after path resolution, and
it does not print literal values for inspection because a manifest may itself
contain plaintext secrets. The selected manifest is therefore trusted input;
the summary makes its authority legible without claiming to make it safe.

The controlling-terminal prompt leaves stdin untouched for the child.
`session.close()` completes before replacement, and arguments never pass
through shell interpolation by Keybay. Child environment values intentionally
remain plaintext; all mutable SDK result buffers are cleared. Validation and
prelaunch failures use the same close/clear path and create no child.
CLI-owned descriptors are closed or close-on-exec. Preserve the caller's
existing descriptor policy; add no descriptor-passing option and never pass
Keybay's provider, store, lock, manifest or prompt handles to the child.

Both initial targets use direct POSIX `execve`. No supervised-spawn fallback
is implemented or selected when resolution or execution fails. Successful
replacement leaves no Keybay parent; the child naturally owns its status and
signals. Failure restores the CLI's terminal/signal state where applicable,
clears mutable native launch buffers, and returns the specified failure status.
The Linux [execve contract](https://man7.org/linux/man-pages/man2/execve.2.html)
defines interpreter handling and close-on-exec behavior; native fixtures must
also establish the macOS behavior.
Native tests retain exact argv, byte-preserving environment overlay, descriptor
closure, SIGPIPE disposition and signal-mask behavior. A future non-POSIX
launch contract is separate work.

The child receives ordinary environment variables. It and its descendants can
read, print, persist, or transmit them. Platform-permitted peer inspection may
also expose them—for example, Linux gates
[`/proc/PID/environ`](https://www.man7.org/linux/man-pages/man5/proc_pid_environ.5.html)
through its ptrace access checks rather than through Keybay. Running a manifest
therefore trusts the manifest, the launched executable, its descendants, and
the operating system's process-inspection boundary.

### `keybay open`

`open` requires stdin and stdout to name the same controlling foreground
terminal, verified before SDK opening and before sensitive rendering. It starts
the Fleury TUI only after that terminal preflight:

```console
$ keybay open
```

If passphrase protection is enabled, the first screen asks for the passphrase.
The field is masked by default and has an explicit show/hide control. Failed
authentication does not reveal key names or open the main screen.

The main screen provides:

- a searchable, sorted list of key names;
- a constant masked value beside each key name;
- explicit show/hide for displayable values;
- an explicit Copy action for the selected text value, independent of Reveal,
  on a qualified clipboard path;
- set or replace with hidden entry and confirmation where appropriate;
- delete with confirmation;
- a small protection/settings view for the optional passphrase, clear and reset;
  and
- conservative platform-only guidance with a link to the qualified platform
  documentation.

#### Selected layout: focused finder with masked rows (C1)

The selected design is a centered searchable list with names on the left,
fixed-length masks on the right, and one shared action grid. It replaces the
earlier split view following the 2026-09-07 C1 prototype review. Fleury remains
the UI framework. The browser prototypes used fictional data and simulated
clipboard writes; qualification exercises the actual terminal implementation.

```text
keybay

  / Find a key…                                            6 keys
  ───────────────────────────────────────────────────────────────
    anthropic                                            ••••••••
    database-url                                         ••••••••
    github                                               ••••••••
  › openai                                               ••••••••
    staging/api-token                                    ••••••••
    x                                                    ••••••••

  ───────────────────────────────────────────────────────────────
  Space Reveal  c Copy  e Edit  d Delete

  n New key  s Settings  q Quit
  ↑↓ select · / search · Tab focus
```

The header shows the Keybay brand; protection details live in Security settings.
New, Settings and Quit remain
available beneath the shared selected-key actions.
Search filters names locally using a case-insensitive substring match; it
does not change the exact key passed to the SDK. A slash remains part of a
flat name, with no folder/tree navigation. Preserve selection by exact key
when filtering or refreshing names; if it disappears, select a remaining key
with its value hidden. The selected-row marker persists while search or an
action has focus. Masks are presentation constants, never value previews.

Selecting a row or focusing an action does not fetch its value. Hidden
placeholders do not encode the value's length. Reveal replaces only the
selected row's mask, left-aligned in the column beside the name so wrapped
lines start under one another; masks remain right-aligned. Long or multiline values
wrap in that row's bounded right column, which expands to at most six lines and
half the available list height; → focuses it for scrolling. Escape hides it and returns focus to
the key list. Unselected names use ellipsis when needed; the selected name
wraps within the row's height limit. New/edit, deletion confirmation and
protection settings use small, focused views over the same session. Opening those views clears a
revealed value. The action/status line never includes a value or passphrase.

New/Edit use a compact, labeled Key/Value form. New has an editable Key;
Edit uses the existing key name as its wrapping title, followed directly by
Value, which receives initial focus. There is no key input or redundant
read-only label. Renaming is outside scope.
Enter in New's Key focuses Value; Enter in Value saves. Use Fleury's existing
submit-oriented multiline keymap
so Alt+Enter (or reported Shift+Enter) adds a line and pasted line breaks stay
in the draft without submitting. The editor shows one to three lines, sized
to keep the nearby Save, Reveal/Hide and Cancel actions visible at the supported
minimum. The vault and forms share aligned action columns, with bracketed bold
shortcut hints and ordinary-weight labels. Vault actions use four columns when
they fit and two in narrow terminals; forms wrap as needed. Column positions
stay stable when Reveal changes to Hide. Each shortcut is separated from its
label by one space. Esc is shown beside form Cancel.
Validate record names and duplicates before transferring the value to a save.
A correctable name error retains the masked draft, focuses Key, and displays
feedback beside it. Form cancellation
returns to the invoking screen; cancelling Unlock exits. Use one explicit return
target instead of retaining previous views.

Reveal/Hide toggles Fleury's built-in field masking. When text requires terminal
escaping, Reveal instead replaces the field with a single escaped, read-only
preview; Hide restores editing without changing the draft. Pasting such text
into a shown field conceals it without interrupting the paste. Field placeholders
stay muted grey on focus, and the form omits shortcut-help lines.
Save and Reveal/Hide buttons display Ctrl+S and Ctrl+R respectively. Those chords
work throughout New/Edit and passphrase forms without consuming plain letters
or paste. Unlock supports Ctrl+R and Enter; reset has no accelerated submit.
Reveal/Hide applies to both passphrase inputs together, including confirmation.
Each field uses its own escaped preview when needed; toggling retains the
active field and exact draft. Validation errors, blur and resize conceal both.
Local missing-field or mismatch validation retains both drafts, conceals both
fields, focuses the field needing correction, and shows a specific inline
error and red border. Editing revalidates the error. Accepted submission,
cancellation, session invalidation and exit still clear the form and its history.

Use terminal palette colors consistently: green for primary actions/success,
amber for disclosure, cyan for the focused field border, and red for destructive
actions/errors. Retain inverse button focus, clear action labels and an explicit
revealed-field label so color is supplementary. Inactive field borders stay muted;
body text retains a readable terminal foreground and placeholders use muted grey.
Form headings are bold; field labels and warning text use ordinary weight.
Group the passphrase warning with the heading and separate it from the inputs
with a blank line. Add a gap between passphrase fields when height permits.

The dim footer describes the focused control. Search advertises Enter-to-results
and Escape-to-clear; results advertise selection/editing; a focused revealed
value advertises scrolling/hiding. Settings distinguishes category and action
navigation. New/Edit show Enter-to-save and Alt+Enter-to-add-a-line when Value
is focused, with scrolling/editing guidance for an escaped preview.
Successful actions show a compact bordered, green, three-second toast at the bottom right:
“Copied!”, “Saved!” or “Deleted!”. Replacement messages, a new operation,
navigation and exit cancel the previous message timer. Errors are persistent,
and an old success timer must never clear a newer error. These messages never
contain secret text. Copy confirms only after the selected transport completes.
Visibility is conveyed by masks and the Reveal/Hide action. The current Toaster
implementation still stacks notices and expires errors after fifteen seconds;
bounded replacement and persistent errors above await Fleury support.

At 24 terminal rows or fewer, use a one-row busy area and omit the gap above
the key list. Retain roomier spacing on taller terminals. Enable the existing
list scrollbar with a stable gutter when records or the expanded selected row
can exceed the viewport. Cap the finder at 80 columns and center it in wider terminals. Keep the same
two-column list at supported widths. Size the name to its content and give
the value the remaining space. If both cannot fit, cap the name at half the
available row and wrap the value. Reserve a
scroll gutter only when the value needs scrolling. A value that fits beside
its name must stay on one line;
there is no separate detail pane or saved layout preference. Validate the
minimum width and height with Fleury cell-layout tests. When controls and a
bounded value view cannot fit, clear the active disclosure and show a resize/quit screen;
resizing back must not reveal the value again automatically.
Keep the active form's controllers during this resize prompt; its inputs are
unmounted and cannot accept edits or submission until the terminal fits again.
Apply a received record paste within the 1 MiB limit as one editing transaction
before input unmounting, preserving its full accepted content.

Keyboard operation is complete without a mouse: arrows move through names,
`/` focuses search, Tab/Shift-Tab traverse controls, and Enter activates the
focused control. Clicking a key selects it; Enter opens its masked editor.
Space remains ordinary input inside text fields. Browse-mode shortcuts are Space Reveal/Hide, `c` Copy, Enter/`e` Edit,
`d` Delete, `n` New key, `s` Settings and `q` Quit. Escape dismisses the current
dialog or hides an active reveal; it never confirms a destructive operation.
Hiding preserves the selected key and filter. With no disclosure, Escape clears
the filter and returns to the current selection; an empty vault focuses New
key. With neither state active, it bubbles to notification dismissal. Edit-save
and cancellation retain the filter; New clears it only if necessary to show the
created key. Buttons and shortcuts share the same availability
checks, including empty results and pending operations.
While a text field owns focus, ordinary characters are input, not global
shortcuts. Pasted text never activates commands. Button labels and keyboard
bindings invoke the same action handlers.

Up from the first result focuses search. Down or Enter from search chooses
the first result; clicking a result focuses the list.
Bindings check focus when invoked so a search rebuild cannot leave shortcuts
disabled after focus moves. Search changes reset the result viewport.

Install Fleury's `FocusTraversalGroup` around the bare screen. Tab and
Shift+Tab traverse fields and actions in reading order; list edges bubble
arrows to the surrounding focus policy. Clicked actions take keyboard focus.
The empty vault focuses New key. Delete, Clear and Remove-passphrase
confirmations use centered, content-height panels with Cancel initially focused.
Escape returns to the invoking view. Forms and ordinary panels fit the minimum
terminal without scroll-container focus stops or a retained dialog stack.

#### Fleury composition and integration boundaries

Use Fleury's existing layout, focus, input and navigation primitives:

| UI piece | Fleury composition |
|---|---|
| Centered finder and masked rows | `StatefulWidget`, `LayoutBuilder`, `ConstrainedBox`, `Column`, `Row`, `Expanded` |
| Search and name selection | `TextInput`, `ListView`, `ListController`, stable item keys |
| Bounded revealed value column | `SizedBox`, safely escaped `Text`, a focused `ListView` with a scroll gutter |
| Actions and focused forms | `FocusTraversalGroup`, `KeyBindings`, `FocusNode`, semantic actions and one current view |
| Passphrase/value entry | Operation-owned `TextEditingController`, masked `TextInput` and `TextArea` |

Keep a small screen state owner for names, selected key, current view and
pending action. The invocation owns the SDK session and cleanup; child widgets
receive state and callbacks. Use ordinary widget state for presentation and
the existing CLI cancellation/error rules for operations. Add no application
repository layer, second storage model, reactive cache, route registry or
general-purpose form framework. Use standard Fleury controls where suitable;
review companion-package dependencies before adopting them just for chrome.

The implementation pins Fleury by full Git commit in the CLI pubspec and lock.
Only the core Fleury package is included; action chrome composes its focus,
keyboard and semantic primitives without a companion widget package. The
[integration review](../tui-integration.md) records the runtime closure and
upstream changes. Preserve these integration requirements when updating it:

- **Secret fields:** set `TextClipboardPolicy.redacted` explicitly even while
  Reveal is active. This keeps field copy/cut, cross-field kill-ring capture and
  semantic field values redacted independently of visual masking. Do not
  attach submission history or completion controllers. Use a fresh controller
  per operation. `TextEditingController.clear()` is an undoable edit, and
  `dispose()` alone does not replace its current text. Replace its editing
  value with an empty value, dispose it to release undo/redo/composition state,
  and release widget references when the operation ends. This remains
  best-effort release of immutable Dart strings, not guaranteed zeroization.
- **Local presentation:** explicitly select the native terminal path and
  disable hot reload and debug/inspection tooling. Reject developer capture
  or remote/serve configuration before SDK access if the pinned runtime
  cannot explicitly disable it. For example, the inspected `runApp` honors
  `FLEURY_ANSI_CAPTURE` independently of its debug flag. Debug-off alone is
  therefore not sufficient to prevent a durable copy of revealed values.
- **Terminal lifetime:** coordinate one terminal input/signal owner with the
  invocation's cleanup. Fleury's inspected POSIX driver consumes Ctrl+Z before
  widget dispatch and normally suspends/resumes the application. A widget
  shortcut cannot implement Keybay's exit-on-observed-suspension contract.
  Verify a driver-level policy/hook before connecting real store data; if
  missing, make the smallest upstream lifecycle change. Keep Keybay's
  foreground checks tied to the actual presenting terminal handle, including
  when Fleury redirects stdout for output capture.
- **Clipboard:** provide the explicit-copy boundary below. The inspected
  default `SystemClipboard` retains an in-process plaintext register, resolves
  helper commands by name, and falls back to an unacknowledged OSC 52 write.
  These defaults do not satisfy Keybay's copy contract unchanged.

These are C3 acceptance conditions, not reasons to build a new renderer or
fork Fleury. First prove the composed screen and lifecycle against disposable
fixtures, then connect the production SDK boundary and qualify the same screen.

#### Explicit copy

Copy is a deliberate disclosure of exactly the selected value, available
without first revealing it on screen. Check that a supported, qualified write
path exists before reading the value. Reuse the selected key's active revealed
buffer when present; otherwise fetch only that key. Check that the action
still belongs to the current selection/session and foreground terminal, write
once, and clear copy-only caller-owned bytes in `finally`. An already revealed
buffer retains its normal Hide/navigation cleanup. Hiding or navigating away
before disclosure discards the pending result. After a clipboard write has
begun, cancelling the UI cannot retract it.

The action copies valid UTF-8 text exactly, including line breaks, without
terminal-display escaping, truncation or added newlines. Reject unsupported
binary/NUL-containing values and transport size limits with specific guidance.
Copy leaves the on-screen value hidden unless it was already explicitly
revealed. It does not populate an in-process paste register or retain a
clipboard history. Secret input fields remain redacted; Copy belongs to the
selected stored value, not to a field's generic copy/cut shortcuts.

The terminal adapter owns one narrow, write-only clipboard operation. Select
and qualify its supported local OS/terminal transport during C3. It must not
resolve a helper through inherited `PATH`, invoke a shell, write a temporary
plaintext file, route to a remote Fleury surface, or silently retry through a
different transport after an uncertain write. An unsupported path reports
unavailability without reading the value. An unacknowledged terminal write
must not be reported as confirmed clipboard delivery. Do not use an
in-process-only fallback as a successful Copy.

On macOS the write is restricted to the current host
(`NSPasteboardContentsCurrentHostOnly`, so Universal Clipboard does not sync it)
and carries the nspasteboard.org concealed and transient marker types, which
clipboard managers commonly honor by not recording the item. `xclip` serves one
type per copy and cannot carry a sensitivity hint; `wl-copy` 2.3 and later can
(`--sensitive`), which Keybay does not use yet.

The CLI documentation explains that copied values leave Keybay and may remain
in the system clipboard or clipboard history after the TUI exits. There is no automatic
clipboard-clear timer or claim of remote erasure. This explicit action is the
only clipboard disclosure added to this RFC; it does not enable external
editors, automatic typing or arbitrary child commands inside the TUI.

#### Disclosure and session lifecycle

The TUI does not display every value merely because the store is open. Selection
reveals metadata; revealing a value is a separate deliberate action. Unsafe
terminal text is never emitted as raw control bytes. A multiline or structured
value appears inside a bounded value column: line breaks are layout; C0/C1
controls, DEL, line and paragraph separators, lone surrogates, and every
Unicode format, other default-ignorable or Prepend character (bidirectional
overrides and isolates, joiners, zero-width marks, prepended marks and letters,
tags and fillers) are visibly escaped, as are variation selectors that do not
choose an emoji's presentation and any other cluster text the renderer would
draw in zero cells, such as a stray combining mark; ordinary printable text,
including accented, CJK and emoji characters, renders as itself. Width is
measured in terminal cells through the framework's width resolver, under the
width policy the terminal is painted with, and wrapping never splits a grapheme
cluster, so a wide glyph cannot overflow its column or be clipped. Text is clipped or scrolled inside that view without
overwriting UI controls.
This is safe terminal rendering, not proof that arbitrary text cannot mislead
a reader. The explicit Copy action above is separate from terminal rendering;
ordinary selection, display and field editing never copy implicitly.

The TUI fetches a value only for an explicit reveal, copy or edit action and never
caches plaintext while browsing the key list. Hiding a value, navigating away,
committing or cancelling an edit, receiving `staleSession`, and exiting all
overwrite the caller-owned source `Uint8List`, clear editable/passphrase
buffers, and erase sensitive screen regions best-effort. Fleury and terminal
renderers may create immutable strings or platform copies that cannot be proven
zeroized. Secret fields must not retain undo/history buffers after their
operation ends; release renderer/controller state as well as the source bytes.
Review this behavior before selecting Fleury input components. Do not promise
stronger memory erasure than the component/runtime permits.

Accept one SDK action at a time; show a pending state and disable conflicting
mutation/protection actions. Hiding, navigating away, or exiting must never let
a late read redraw a secret into a newer screen. Discard/clear abandoned results
and close late-opened sessions using the same cleanup owner. Cancelling an edit
before submission changes nothing; after submission it cannot undo the SDK
operation. No background polling, file watcher, or value prefetch is needed.

This UI-level selectivity matches the SDK storage boundary: browsing decrypts
record names from the sealed manifest, while an explicit reveal or edit
decrypts only the selected record frame under RFC 0001.

The TUI keeps one authenticated `KeybaySession` for its foreground lifetime. It
calls `session.close()` in its top-level `finally` path on normal exit,
cancellation, handled errors, and the signals Dart can observe (SIGINT,
SIGTERM and SIGHUP). Dart cannot run code for SIGTSTP, SIGTTIN, SIGTTOU or
SIGQUIT, so while the TUI owns the terminal it ignores them: an external stop
request or quit signal can neither suspend it with a value on screen nor
core-dump it. In raw mode Ctrl+Z and Ctrl+\ arrive as input, and Ctrl+Z
closes the session. When it detects that it no longer owns the foreground
terminal, it clears sensitive screen state, closes the session, and terminates
before surrendering the terminal where possible.
`SIGSTOP`, `SIGKILL`, power loss, and runtime crashes cannot be handled. Every
command disables its own core files, and on Linux makes its process
non-dumpable, so a crash does not persist the session's store key or a revealed
value; a command that cannot do so exits before opening the store, and `run`
restores the caller's core-file limit for the launched program.
On an observed resume after suspension, clear sensitive state and exit through
the close path instead of resuming the old authenticated screen. This avoids a
second resume/epoch protocol or SDK inspection API. Terminal restoration and
screen clearing are best effort when ownership has already been lost; never
redraw a secret to perform cleanup. An unobservable stop/resume cannot be
claimed as detected. The process exits after five minutes without input, announcing the pending
close thirty seconds beforehand without extending it. This
fixed inactivity limit belongs to the foreground UI; it adds no shared
authentication cache or daemon. Submitted operations settle before orderly exit.

Foreground PTY ownership does not prove physical visibility. A minimized
terminal window, or a detached `tmux`/`screen` session, can leave the TUI as the
foreground process of a PTY while no person can see it. In that state the
authenticated window can remain open until the inactivity limit expires.
Reported terminal-window focus loss conceals revealed fields and values, while
retaining the active form's masked draft. Ordinary resize does the same. This
policy intentionally retains draft plaintext in the form's process memory until
submission, cancellation, invalidation or exit; it adds no persisted drafts.
Concealing a form does not cancel an accepted SDK write. Users
who need immediate closure should exit `open` before detaching it.

Ordinary record commits do not invalidate the SDK session. Known local
invalidation reports `staleSession`; rotation in another process/isolate may
instead report `storeAuthenticationFailed`, just like tamper or replacement.
An already-pinned read may still finish against the prior valid generation.
The CLI cannot distinguish these causes by querying the provider or reading
an epoch; neither capability is public.

On `staleSession`, `storeAuthenticationFailed`, or `storeStateConflict` during
an authenticated action, clear sensitive UI state and close the session.
Offer an explicit fresh open or exit without diagnosing the cause or suggesting
reset from that operation failure. A failed reopen follows the narrow
pre-session error policy below. Refresh names through `listKeys()` on entry
and after mutations; a missing selected key is ordinary concurrent deletion,
not an integrity failure.

The TUI begins with `Keybay.open()`. On `authRequired` it obtains a passphrase
and retries with
`Keybay.open(credential: PassphraseCredential(...))`. On total absence the
successful session reports `wasInitialized == true`; before accepting the first
record, the TUI explains the platform-only baseline and offers to add a
passphrase through that session. Declining continues with platform protection.
If state is partial or invalidated, the SDK returns a typed failure instead of
overwriting or repairing it. A direct `set` still opens and initializes a
baseline platform-only store; unattended `set --stdin` also depends on provider
availability and interaction as specified below.

`open` may offer an error-triggered pre-session reset screen only when
`Keybay.open()` fails
with `platformKeyInvalidated`, `storeAuthenticationFailed`, or
`storeStateConflict`. It identifies the target only as the current CLI store,
states that every value and protection method will be removed and cannot be
recovered by Keybay afterward, and requires the user to type the case-sensitive
word `RESET`. Only then does it call `Keybay.reset()`. Reset does not reveal
data or bypass authentication; it deliberately erases the current application's
state and initializes nothing. External copies or storage remnants may still
remain; reset is not a secure-erasure guarantee.

No error-triggered reset screen or contextual reset suggestion follows
`authRequired`, `unlockFailed`, `protectionMismatch`, `platformProtectorLocked`,
`platformInteractionRequired`, `platformProtectorUnavailable`,
`platformOperationFailed`, `storageOperationFailed`, `storeBusy`,
`unsupportedStoreVersion`, `applicationIdentityUnavailable`, or other input,
lifecycle, resource, or transient failures. Those paths retain their specific
retry, unlock, upgrade, packaging, or operational guidance. Reset is never
automatic and is never presented as a remedy for a wrong credential.

`resetIncomplete` states that cleanup may be partial and offers a deliberate
retry; every retry requires the same typed phrase again before another
`Keybay.reset()` call. Complete reset reports success and exits `open` without
initializing a replacement store. A later explicit open initializes only when the SDK's absence rules permit.
Reset retains nonsecret coordination locks and, on an applicable future Flatpak
CLI profile, the portal-owned secret. An older complete encrypted snapshot can
restore access under retained protection; reset is not rollback resistance or
guaranteed erasure of external copies.

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
the singleton passphrase. Its current method ID comes from `auth.list()` or
an auth operation result; `update` retains that ID. There is no UI for arbitrary
method types or a collection of future hardware credentials.

Settings uses a left sidebar (Security and Data) with the active category’s
content beside it. Sidebar arrows change categories without invoking actions;
Enter or → focuses content, ← returns to the sidebar, and Tab traverses panes
and Back. Escape/Back exits Settings; cancelling a form returns to its category.
Security contains passphrase state, the fixed five-minute idle-exit policy,
Add/Change (p) and Remove passphrase (x). Data contains Clear (c) and Reset (r).
Category shortcuts apply only to visible actions and retain all confirmations.
Focus uses a row background and marker; destructive actions use red. Buttons
and rows have hover feedback that neither activates nor steals keyboard focus.
Mouse motion alone does not keep the vault unlocked beyond its idle timeout.

The settings screen offers two deliberately different data operations:

- **Clear all records** confirms once, calls authenticated
  `session.clearAll()`, preserves protection, and keeps the TUI session open.
- **Reset Keybay** requires the typed phrase above, clears sensitive
  UI state and awaits session closure, then calls selector-free `Keybay.reset()`.
  It exits without creating replacement state. Its provider UI and partial
  cleanup behavior are the same as the pre-session reset path.

For forgotten-passphrase recovery, the user may deliberately navigate from the
unauthenticated `open` UI through a neutral **Forgot passphrase?** link to an
explanation, then choose **Reset Keybay**. `authRequired` and
`unlockFailed` never route there automatically, highlight it as a credential
remedy, or claim that a passphrase was forgotten rather than mistyped. The reset
screen states plainly that reset recovers usability only by deleting the
inaccessible data; it does not recover any value, and it still requires the full
typed confirmation.

The SDK owns atomic protection changes: a successful change rotates `Kstore`,
updates the committing session, and makes peers fail closed against the new
state. The stable platform root is retained. A failed/interrupted call does not
prove that the old policy remains current; preserve the store, close and require
an explicit authenticated reopen before further work. Do not automatically
retry an add/update/remove or claim that cancelling the UI rolled it back.
Keybay has no passphrase escrow or data-recovery path; the TUI must say so before
enabling protection.

## Passphrase input policy

Whenever a passphrase is required, the CLI reads it from the controlling
terminal rather than process stdin. Echo is disabled before the first byte is
read and restored on success, cancellation, EOF, error, and handled signals.
Before rendering approval text or reading any passphrase, the prompt adapter
verifies that Keybay's process group owns that same controlling terminal. This
check applies whenever `set --stdin`, `rm`, `list`, `run`, `set`, `get`, or
`open` needs a passphrase prompt. In that case missing or background terminal
ownership fails before any record value is read or mutated. It does not add a
TTY requirement to platform-only `set --stdin` or `run`; provider availability
and interaction remain separate constraints. `get` and `open` remain foreground
interfaces in every mode.

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
renderer/runtime copies are cleared or released best-effort and documented.
Policy and KDF parameters remain in RFC 0001 and the SDK so every caller derives
the same key from the same bytes.

When no controlling terminal is available:

- `open`, `get` and interactive `set` fail their terminal preconditions before
  SDK access. `set --stdin` rejects terminal stdin before SDK access, but may
  use a pipe while a separate controlling terminal supplies the passphrase.
- `list`, `rm`, `set --stdin` and a secret-referencing `run` may attempt the
  ordinary `Keybay.open()`. That SDK call permits OS/provider UI regardless of
  whether this process has a controlling terminal. The CLI cannot suppress it
  or promise a prompt-free startup. Provider failures remain typed failures.
- On `authRequired`, the CLI fails with status `4` before reading record data
  or submitting a record mutation. It never reads a passphrase from stdin.
- A literal-only `run` never opens the SDK or invokes a Keybay/provider prompt.

Platform-only automation is usable in a configured environment where provider
opening succeeds without interaction. There is no general unattended/headless
availability guarantee. This limitation follows the fixed SDK contract; no
provider preflight, fallback, or public noninteractive option is added.

This is a deliberate security/automation tradeoff. A future hardware-backed
unlock-method or agent protocol should be proposed independently rather than
smuggling a passphrase through an unsafe channel.

## Security model

### What this design improves

A protected store requires both platform access and the passphrase. Each
invocation authenticates separately; only the foreground TUI deliberately holds
a longer-lived session. There is no agent accepting requests from other
processes. Exact-key SDK access, bounded manifests, controlled terminal output
and prelaunch cleanup reduce routine disclosure while preserving the platform
and runtime limits below.

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

- A cancelled or incorrect passphrase yields no record value, submitted record
  mutation, or child process. Cancellation before submitting an operation is
  distinct from interruption after submission; `open()` can already have
  initialized previously absent state.
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
- A failed write/protection/reset call may have crossed its commit boundary.
  Never report success without acknowledgment, infer unchanged state from an
  error, or retry mutations automatically. Preserve the store and use explicit
  reopen/recovery; `resetIncomplete` requires a deliberately reconfirmed reset.
- `storeBusy` is bounded contention, not data loss. The SDK uses a one-second
  acquisition deadline. Commands report it and exit; the TUI permits a user
  retry after the pending action settles, with no spin or background retry loop.
- Input failures and operational failures keep distinct guidance. In particular,
  `protectionMismatch` is not always a wrong passphrase, and `resetIncomplete`
  never triggers an automatic reset. Error text is redacted; branch on
  `KeybayException.code`, not message strings.
- Terminal modes and screen state are restored best-effort on every handled exit
  path. Restoration failure must never cause a secret to be printed as part of
  an error.

## Examples

A developer stores a value, then passes only its reference to a child:

```console
$ keybay set acme-web/stripe-secret
Platform protection only. Run `keybay open` to add a passphrase.
Value: ********
Stored acme-web/stripe-secret
```

```dotenv
PUBLIC_ORIGIN=https://example.test
STRIPE_SECRET=kb://acme-web/stripe-secret
```

After adding a passphrase through `keybay open`, each new invocation
reauthenticates. A protected run displays the target and selected references
before accepting that passphrase:

```console
$ keybay run -f .env -- npm run dev
Run: /usr/bin/npm run dev
Manifest: /work/acme/.env
Environment:
  PUBLIC_ORIGIN (literal)
  STRIPE_SECRET <- acme-web/stripe-secret
Keybay passphrase: ********

$ keybay list
Keybay passphrase: ********
acme-web/stripe-secret
```

`/usr/bin/npm` is illustrative; display the actual resolved canonical target.
Several references in the same manifest still use one passphrase attempt and
one `getManyBytes` operation. A manifest with only literals opens no SDK session.
Provider UI, if needed, is separate from these terminal examples. The earlier
`set --stdin` example uses the pipe for the value and the controlling terminal
for its passphrase.

## Implementation milestones

The SDK dependency is implemented and merged. C0–C2 are implemented. Retain
their regression gates while implementing C3, then qualify the combined product
at C4. Existing SDK receipts apply
only to their recorded source/profile; they do not certify terminal behavior,
Fleury, child launch, packaging or a new dependency closure.

### C0 — Command contract

Retain the parser, manifest grammar and exit categories. Complete nonblocking,
descriptor-validated regular-file manifest input with no controlling-terminal
acquisition; preflight command/value-channel requirements before opening a
store; correct tests that preserve old behavior.
Keep help/version/literal-only `run` independent of SDK availability.

Exit gate: invalid command/manifest/channel input performs no SDK access and
launches nothing; fixtures define every accepted byte and `0/1/2/3/4/126/127`
result. Invalid value bytes discovered after opening submit no record mutation;
initialization on absent state remains possible.

### C1 — SDK lifecycle

Reuse the existing session opener, `authRequired` credential retry,
`getManyBytes` and close ownership. Apply the SDK's exact error codes, distinguish
Keybay passphrase prompts from provider UI, and complete cancellation/late-result
cleanup. Refresh platform-only guidance when the `open` command is available.

Tests inject the opener at the CLI application boundary using the production
engine with disposable file/protector fakes. No SDK identity override, public
backend constructor, sealed-type constructor, credential cache, or inspection
API is added. Test seams remain internal to the CLI/test harness.

Exit gate: at most one passphrase attempt and one successful session for a
non-TUI command, no passphrase attempt for platform-only access, provider UI
allowed only through SDK lifecycle operations, and close/byte cleanup on all
handled paths. Pending operations are settled, not described as cancelled.

### C2 — Terminal and process boundary

Separate launch preparation from execution within the existing process adapter:
resolve the canonical target using inherited `PATH` before secret access;
freeze the selected manifest/target/arguments; show the protected-launch summary
before requesting its passphrase; call `getManyBytes` once; clean up, then
perform one direct `execve`. Never search again or launch a fallback afterward.

Complete same-controlling-terminal checks and one ownership path for no-echo
input, terminal restoration, descriptor closure and handled signals. Keep the
native environment and signal behavior already covered by the existing harness.
No supervisor abstraction or unimplemented platform adapter is required.

Exit gate: real PTY and child-process fixtures establish safe input/output,
exact selected-secret release, correct target/argv/environment and no SDK or
prompt handles at launch. Provider failures and cleanup failures before launch
create no child. Neither redirected output nor a second PTY can receive `get`.

### C3 — Foreground Fleury UI

Implement the selected focused finder and a small protection/settings view
using the Fleury composition and integration boundaries above. Includes masked
entry, explicit reveal/copy/edit, search over names, delete, singleton
passphrase management, clear and reset.
Keep one session owner, one pending SDK action and at most the active plaintext
buffer. No auto-refresh, background unlock or generic authentication framework.

Before accepting a Fleury dependency, inspect its input/render lifecycle and
pin/review the added runtime closure in `keybay_cli`. Verify hidden input,
undo/history disposal, late-result handling, control escaping, bounded layout,
clipboard disclosure/retention, capture/debug configuration, driver suspension
policy and release of secret-bearing UI state. Use component tests plus a real PTY;
render snapshots alone do not prove terminal restoration or plaintext lifetime.

Exit gate: explicit user actions govern every reveal, mutation and protection
reduction; stale/integrity failures close the session; observed suspension exits;
pending results cannot repopulate a dismissed view; reset is deliberate and
never initializes a replacement. The initial TUI is qualified through the real
SDK boundary, not a second persistent fake implementation.

### C4 — Qualified CLI integration and packaging

Qualify ordinary Linux desktop and unentitled macOS for each advertised
architecture and distribution form. Reuse disposable identities/accounts and
SDK provider runners where practical. Do not run reset or destructive fixtures
against the developer's real CLI store. A test-only reset entrypoint must not
be compiled into release artifacts.

Retain the repeatable `tool/test_cli.sh` entrypoint and its existing
PTY/exec/storage/quickstart harnesses. Its implemented `core`, `macos`, `linux`,
and `all` selections produce source/profile/status reports using the shared SDK
runner; no arguments selects core. Extend them with TUI and final-package checks. Missing prerequisites are blocked rather than
passed/skipped qualification. Keep SDK and CLI results distinguishable and
reuse the same commands in CI; no test registry or new assurance framework.

Packaging is part of this gate:

- Resolve `keybay-cli` from its owning pubspec in development or embed it using
  `keybay_compile`. Verify the exact installed artifact from another working
  directory; `--help`/`--version` alone do not exercise SDK identity or storage.
- For hardened macOS, start with the SDK-qualified dedicated signed
  `dartaotruntime` plus signed AOT module. A launcher must use its packaged
  runtime/module locations, never caller-controlled `PATH` to select them.
  Retain stable identity/signing continuity across an actual package upgrade.
  The known single-file hardened-executable startup limitation is unresolved;
  do not solve it by weakening signing or library validation.
- Prove native startup, real provider access, platform-only and passphrase flows,
  TUI cleanup and `run` in the final package. Notarization and installer/archive
  claims require receipts for the actual distributed artifacts. Do not ship a
  silently substituted build form when qualification fails.
- Reconcile CLI README/examples/install guidance and exact dependency/version
  checks. Generic hosted Dart installation and alternative packaging forms are
  advertised only after their identity and runtime/provider behavior pass.
  No SDK crypto, format or API change is presumed for packaging.

Exit gate: command/TUI behavior, package identity, provider access, upgrade
continuity, dependency checks and publish/archive validation pass for each
advertised configuration. Preserve the V1 incompatibility notice and scoped
SDK evidence gaps. Signed tags, publication and distribution are separate
release actions after this evidence exists.

## Validation criteria

These fixtures qualify the CLI boundary. Retain existing SDK format, crypto,
rotation and hostile-input tests rather than copying them into a second suite.
Use the real engine over disposable boundaries for application tests and real
providers for the advertised deployment configurations.

- **Grammar and identity:** Exact command grammar and two-segment keys; no
  store/provider/identity selector; removed commands rejected; literal-only runs and
  help/version never open the SDK; source/installed/AOT identities established without
  public overrides

- **Value input:** UTF-8, NUL, empty-result, 1 MiB value bound, producer newline rules;
  stdin pipe versus hidden input; passphrase always separate from value/child stdin; no
  mutation on invalid value bytes

- **Manifest input:** BOM, UTF-8, CRLF, 1 MiB file/64 KiB physical line, duplicates,
  malformed names/references, literal syntax; one nonblocking regular-file handle;
  FIFO/device/directory refusal, symlink-to-file acceptance, descriptor closure and no
  reread after approval

- **Terminal ownership:** Missing terminal, background process group, redirected/captured
  output, a different foreground PTY and foreground loss while awaiting input/provider/SDK
  work; check before input/reveal and recheck immediately before output

- **Display:** No names before authentication; list emits only sorted names; `get` missing
  status versus empty stored value; controls and invisible format characters rejected by `get` and
  escaped/confined in TUI; no raw provider/manifest/value text in failures

- **Authentication:** `authRequired` alone triggers retry; one passphrase attempt per
  command; explicit TUI retry; wrong credential, protection mismatch and
  unavailable/locked provider remain distinct guidance; provider UI may occur on either
  open attempt

- **Ownership and cancellation:** Caller input cleared after SDK snapshot, returned
  buffers cleared on every path, no cross-invocation cache; late-open session closed and
  late-read bytes cleared after cancellation; accepted writes may settle; close rejects
  new work and is awaited before exit/launch

- **Concurrent state:** Ordinary writes preserve session usability; local `staleSession`
  and cross-runtime `storeAuthenticationFailed` close the TUI session without diagnosing
  the cause; prior pinned results remain valid but cannot redraw abandoned UI; concurrent
  deletion reports missing normally

- **Passphrase management:** Byte-exact confirmation, no trimming/normalization, 1–1024
  bytes; add/update/remove through `session.auth`; stable ID on update; explicit removal
  confirmation; unsuccessful/uncertain changes never trigger automatic retry or record
  loss

- **Reset and clear:** `clearAll` preserves protection/session; exact typed reset phrase
  on every attempt; session closes before authenticated reset; allowed pre-session error
  cases only; user-navigated forgotten-passphrase erase path; `resetIncomplete` and
  retained roots/locks disclosed; success exits without reopening

- **TUI lifetime:** Masked initial fields; explicit reveal/edit only; hide/navigation/edit
  completion release bytes/controllers/history; one pending action; no late redraw after
  exit; restoration on handled exits/signals; observed resume exits; forced-stop/kill and
  detached-PTY limits documented

- **Launch preparation:** Inherited pre-overlay `PATH`; absolute/relative/canonical
  targets; captured cwd, missing/empty/relative PATH entries, unusable candidates,
  dangling symlinks, directories and `126/127`; approval target equals execution target;
  no post-auth search or fallback

- **Launch disclosure:** Summary precedes passphrase/secret read (platform-only: shown
  when a terminal is attached, without approval); every
  environment name/class shown without literal values; one `getManyBytes` for distinct
  referenced keys; all-or-nothing reference resolution from one generation; no child on
  missing/invalid data, authentication/cancellation/prelaunch failure

- **Native process:** Exact argv; raw inherited environment preservation and exact-name
  overlay; unrepresentable PATH handling; session closed and CLI descriptors closed/close-
  on-exec; SIGPIPE and signal-mask behavior; direct exec status propagation and launch
  failure cleanup; child stdin unconsumed

- **Platform/package:** Real-provider protected/platform-only command and TUI flows;
  missing/locked provider and reset cleanup; final artifact identity, signed macOS
  runtime/module startup and upgrade continuity; architecture/provider-scoped receipts; no
  production test hooks

Publication requires passing results for the advertised CLI configurations.
Deferred SDK device/performance cases remain deferred, and unsupported CLI
platforms gain no claim from a generic unit test or SDK provider receipt.

## Alternatives considered

- **Unlock command or TTL agent:** would add IPC authority, revocation, expiry
  and background lifecycle. One foreground TUI session supplies repeated human
  access without that protocol.
- **Passphrase flags, files or environment variables:** relocate authentication
  into history, inherited state or another persistent secret. Keep the terminal
  contract; platform-only automation depends on provider availability.
- **Multiple stores or a vault command hierarchy:** add selectors to a product
  with one application store. Slash-separated names provide organization only.
- **Inject every stored value:** makes unrelated records silently expand a
  child's authority. The chosen manifest and exact referenced keys remain the
  disclosure boundary.
- **Supervisor, resume protocol or generic method UI now:** add states for
  unshipped platforms/features. Use POSIX replacement, exit after observed
  suspension, and implement only the singleton passphrase the SDK supports.

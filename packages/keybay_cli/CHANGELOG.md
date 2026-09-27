# Changelog

## 0.2.0

Unreleased. The CLI ships only as native binaries through Homebrew and GitHub
releases; it is not published to pub.dev. Native distribution qualification and
publication remain separate from source integration.

- Adapt existing commands to the single-application V2 SDK and session API.
  Existing V1 stores are not migrated automatically.

- Disable core files for every command and make the process non-dumpable on
  Linux, so a crash cannot persist an open session's store key or a revealed
  value. A command that cannot do so exits before opening the store. `run`
  restores the caller's core-file limit for the launched program.
- Ignore SIGTSTP, SIGTTIN, SIGTTOU and SIGQUIT while the vault owns the
  terminal, so it is never stopped or core-dumped with a value on screen.
- Fix hidden input on macOS, which ignored SIGCHLD instead of SIGTSTP: Dart's
  `ProcessSignal` numbers use Linux numbering, so the prompt now passes native
  signal numbers to libc.
- Copy on macOS stays on this Mac (no Universal Clipboard) and is marked
  concealed and transient for clipboard managers.
- Escape every Unicode format, default-ignorable and Prepend character,
  variation selectors that do not choose an emoji's presentation, and any text
  that would be drawn in zero cells, in revealed values; `get` refuses exactly
  the same set. Revealed values wrap under the terminal's measured width policy,
  so ambiguous-width letters on a CJK-configured terminal are not clipped.
- A launch summary or prompt larger than the terminal's output buffer is
  written whole instead of failing partway.
- Show a platform-only `run` its launch summary on an attached terminal, flag
  more execution-affecting variables, and state plainly that without a
  passphrase any program running as you can read every value.

- Add `keybay get KEY` as an explicit human reveal path. Stdout must be the
  foreground controlling terminal; stdin is untouched and may be redirected.
  Refuse captured or background output before opening the store and check the
  output channel again immediately before revealing a value.

- Add `keybay open`: a searchable interactive vault with explicit reveal/copy,
  key editing, passphrase settings and reset recovery. Unlock stays within the
  TUI; blur and resize hide disclosed values, and five minutes of inactivity
  closes the session.
- Preserve accepted text, selection and undo history when name, search or reset
  input is rejected, using the upstream Fleury editing policy.
- Preserve exact secret-field text, including CRLF; render printable Unicode
  normally and escape unsafe controls. Exclude revealed values and escaped
  previews from semantics and accessibility output.
- Own hidden CLI input through terminal cleanup, preserve bracketed-paste bytes,
  support bounded input without canonical-line truncation, and restore caller
  terminal modes after EOF, cancellation and handled signals.
- Accept simple key names as well as slash-separated names. Resolve globally
  activated workspace identity from the CLI package's own declaration.
- Read `.env` in the working directory by default. `-f` selects one replacement
  file; no parent search, fallback or implicit layering occurs. Ship ready-to-use
  reference-only manifests with all four examples.
- Resolve child executables from the inherited PATH before applying manifest
  values. Preserve exact environment bytes and await accepted storage work on
  interruption before closing the session.

## 0.1.1

- Require Dart 3.11 or newer so the Dart-native install path uses the patched
  pub archive extractor; the minimum-SDK CI lane now enforces the lockfile.
- Refuse interactive secret input from a background process group before
  changing terminal echo, with SIGTTIN/SIGTTOU race protection and a real PTY
  regression test.
- Refresh the shipped Rails example to patched Rails, JSON, Loofah, and
  rails-html-sanitizer releases and include its lockfile in advisory scanning.

## 0.1.0

- Initial five-command CLI: `run`, `set`, `rm`, `list`, and `doctor`.
- Strict mixed manifests with literal values and qualified `kb://` references.
- Run-scoped POSIX `execve` injection with no shell or resident wrapper. The
  parent environment passes through byte-exact from raw `environ` (variables
  Dart cannot represent are preserved, not dropped), and the child starts with
  shell-default signal state (SIGPIPE disposition and the thread signal mask
  are reset at the exec boundary).
- Hidden TTY input and strict `--stdin` handling: the modes never cross
  (`--stdin` refuses a terminal so a typed secret is never echoed), and empty
  input is rejected rather than stored.
- macOS login-Keychain and Linux Secret Service-backed storage through
  `package:keybay`.

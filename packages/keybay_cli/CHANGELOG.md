# Changelog

## Unreleased

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

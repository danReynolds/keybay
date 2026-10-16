# Changelog

## 0.3.1

- When the terminal UI meets a vault this version can never open, such as a
  0.2.0 vault with a passphrase or hardware key, it no longer offers Reopen,
  which failed the same way. It says the vault was preserved, shows the upgrade
  steps, and offers Quit.
- Built on Keybay SDK 0.3.1. The vault format is unchanged from 0.3.0.
- Release tags are signed again; the 0.3.0 tags were not.

## 0.3.0

- Confirm the vault on every passphrase or hardware-key unlock (Keybay SDK
  0.3.0). Previously a program that could read the platform root could swap in a
  vault your genuine passphrase or key would open, and read what you saved next.
- **Upgrading a protected vault:** vaults protected by a passphrase or hardware
  key under 0.2.0 do not open in 0.3.0 and are left untouched. Before upgrading,
  open `keybay open` → Settings → Security with 0.2.0 and remove every method.
  After upgrading, add them back. If you already upgraded, reinstall 0.2.0 from
  the [keybay_cli-v0.2.0 release](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.2.0)
  first. Vaults without a passphrase or key upgrade as is.
- Reject retired V2 singleton-passphrase stores without changing them. Keep the
  old installation to transfer needed secrets.
- Keep focused and invalid input borders clean: high-contrast and error text
  underlines no longer draw extra lines through field outlines.

## 0.2.0

Keybay 0.2.0 adds an interactive terminal vault, passphrase protection, and
hardware passkey protection using compatible FIDO2 security keys.

**Upgrading from 0.1.x:** this release uses the V2 store format. It does not read
or automatically migrate V1 stores. Existing V1 data remains accessible with
the old binary; retain access to that installation and transfer any required
secrets before switching to 0.2.0. Do not treat an empty V2 vault as proof that
your old data was deleted or migrated.

### Interactive vault and protection

- Run `keybay open` to browse, search, add, edit, reveal, and copy secrets.
  Values stay masked until explicitly revealed. Blur and resize hide disclosed
  values, and five minutes of inactivity closes the session.
- Add or remove a passphrase or hardware key in Settings → Security. Hardware
  unlock also works with `get`, `set`, `list`, `rm`, and secret-referencing
  `run`. Hardware keys must support the encryption capability required by
  Keypass; ordinary passkey storage alone is insufficient.
- The TUI remembers your last successful unlock method. Selecting a hardware
  key starts the unlock flow immediately, with PIN entry and touch handled
  through the controlling terminal. Cancellation does not consume piped input
  or automatically retry a rejected PIN.
- Center the vault in a framed layout on larger terminals and customize its
  appearance in Settings. Small terminals retain access to the available
  actions.

### Commands and terminal handling

- Add `keybay get KEY` as an explicit reveal command. It requires foreground
  terminal output and refuses captured or background output before opening the
  store; redirected stdin is left untouched.
- Read `.env` in the current directory by default. `-f` selects one replacement
  manifest, without parent-directory searches or implicit layering.
- Resolve child executables from the inherited PATH before applying manifest
  values. Preserve exact environment bytes and replace Keybay with the child
  process through `execve`.
- Preserve secret-field text and multiline paste, restore terminal modes on
  cancellation and handled signals, and escape unsafe control and formatting
  characters when displaying values.

### Native distribution and security

- Ship native archives for macOS ARM64, Linux ARM64, and Linux x64 through
  GitHub releases and Homebrew. No Dart SDK is required at runtime. The CLI is
  not distributed through pub.dev.
- Bundle the hardware adapter and its native dependencies with their license
  notices. macOS uses a Developer ID signed and notarized runtime/module bundle
  with constrained library loading. Linux builders target glibc 2.35.
- Disable core dumps while Keybay owns the vault; restore the caller's core
  limit for launched programs. Protect terminal ownership during secret input
  and disclosure.
- Keep macOS clipboard copies local to the device and mark them concealed and
  transient. Do not include revealed secret values in accessibility output.

Linux requires an available Secret Service provider over the user's D-Bus
session. Windows, Intel macOS, mobile CLI distribution, and Flatpak CLI
packaging are outside this release. CLI hardware-key support does not claim
system-stored passkeys for unsigned terminal programs.

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

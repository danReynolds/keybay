# Keybay CLI

An encrypted local vault and run-scoped secret injection for macOS ARM64 and
ordinary Linux ARM64/x64 desktop. No account, Keybay server, daemon or shell hook.

Commit references in `.env`, not secret values:

```dotenv
API_URL=https://staging.example.com
API_KEY=kb://my-app/api-key
```

```sh
keybay set my-app/api-key
keybay run -- ./app
```

The child receives ordinary environment variables and needs no Keybay library.
Keybay replaces itself with that process; it does not invoke a shell.

## Install

```sh
brew install danReynolds/tap/keybay
keybay --version
keybay open
```

Update with `brew update` and `brew upgrade keybay`.
[Release 0.3.0 archives](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.3.0)
need no Dart SDK. Keep the entire extracted directory: launch `./keybay` on
macOS or `./bin/keybay` on Linux. Companion files are required.

Linux needs glibc 2.35+ and a reachable, unlocked Secret Service provider on the
user D-Bus session. Provider UI may appear; headless availability is not guaranteed.
The macOS bundle is Developer ID signed and notarized. Exact hashes and observed
installation checks are in the [publication record](../../doc/reviews/2026-10-11-cli-publication.md).

**Upgrading:** V1 stores are not migrated, and 0.3.0 rejects retired V2
singleton-passphrase stores. If your 0.2.0 vault has a passphrase or hardware
key, open `keybay open` → Settings → Security with 0.2.0 and remove every
method before upgrading, then add them back. If you already upgraded, reinstall
0.2.0 from the [keybay_cli-v0.2.0 release](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.2.0)
first. Vaults without one upgrade as is.
See the [CLI changelog](CHANGELOG.md#030).

### Development builds

From the repository root:

```sh
dart pub get
dart run keybay:keybay_compile packages/keybay_cli/bin/keybay.dart -o build/keybay
./build/keybay --version
```

The wrapper embeds the CLI's `keybay-cli` application namespace. Desktop builds
need [Keypass's native prerequisites](https://github.com/danReynolds/keypass/blob/main/doc/build-hooks.md).
For a global command following this checkout:

```sh
dart pub global activate --source path packages/keybay_cli
```

Keep the checkout and put `$HOME/.pub-cache/bin` before older installations in
`PATH`. With RK, use `rk use local -p keybay_cli` from the repo.

Source/Pub activation is a development installation. On macOS it trusts the
shared Dart VM for Keychain access, so another Dart program can read the platform
root. Use an additional credential for real secrets. Activation may also print
Pub resolution messages; use the native build when exact CLI output matters.

### Verify a release download

Releases are produced locally by rk from tags signed with the maintainer's
release key; the 0.3.0 tags are the exception and were published unsigned. CLI
releases since 0.1.1 are immutable GitHub releases, so a quick check confirms
that a download is exactly the file attached to the release:

```sh
gh release verify-asset keybay_cli-v0.2.0 keybay-0.2.0-macos-arm64.tar.gz --repo danReynolds/keybay
```

That trusts GitHub's release record; it is not build provenance. 0.3.0 has no
signed tag to check, though on macOS the codesign check below still applies. To
verify independently of that record, check the tag with the maintainer's release key
from [SECURITY.md](../../SECURITY.md#verifying-releases), saved as an
allowed-signers file, in a clone of this repository:

```sh
git -c gpg.ssh.allowedSignersFile=keybay-allowed-signers verify-tag keybay_cli-v0.2.0
```

The tag's `release-manifest-sha256` line binds the release's
`release-manifest.json`, which lists each archive's SHA-256 and the Homebrew
formula's. Compare them (on Linux, use `sha256sum` for `shasum -a 256`):

```sh
git cat-file tag keybay_cli-v0.2.0 | grep '^release-manifest-sha256:'
shasum -a 256 release-manifest.json keybay-0.2.0-macos-arm64.tar.gz
```

The [publication record](../../doc/reviews/2026-10-11-cli-publication.md)
records the exact digests. The
[CLI release audit](../../.github/workflows/audit-cli-release.yml) repeats this
chain for each release and daily for the newest release and its published
Homebrew formula.

On macOS, after extracting the archive, verify the signed runtime:

```sh
codesign --verify --strict --check-notarization lib/keybay/bin/dartaotruntime
codesign -d -r- lib/keybay/bin/dartaotruntime
```

The runtime identity is `io.github.danreynolds.keybay.cli`, signed by
Developer ID Application: Pollyn Inc (`5AHFA9FUZG`). All code companions must
remain present; the release verification checks their signatures as well.

## Interactive vault

Run `keybay open`. Authenticate once, then browse masked values and search names.

| Action | Key |
| --- | --- |
| Select / search | ↑ / ↓; `/` |
| Reveal / hide | Space |
| New / edit / delete | `n` / `e` or Enter / `d` |
| Copy selected value | `c` |
| Scroll revealed value / return to names | → then ↑ / ↓; ← |
| Settings | `s` |
| Move focus / activate | Tab / Shift+Tab; Enter or Space |
| Hide / dismiss | Esc |
| Exit | `q` from vault; Ctrl+C or Ctrl+Z anywhere |

In forms, Enter advances from Key to Value, then saves. Alt+Enter adds a line;
Ctrl+S saves, Ctrl+R reveals/hides and Esc cancels. Multiline paste, including
CRLF, is preserved until submission. Values must be UTF-8 without NUL, up to
1 MiB; passphrases are 1–1024 UTF-8 bytes with exact confirmation. Oversized
drafts are discarded. Key renaming is not supported.

Settings has three sections:

- **Security:** add/remove passphrases and hardware keys.
- **Data:** Clear deletes records but keeps protection. Reset requires typing
  `RESET`, deletes the managed store and exits. There is no passphrase recovery.
- **Appearance:** Green/Cyan/Blue/Magenta accent and Normal/High contrast.
  `NO_COLOR=1 keybay` removes color while retaining focus and validation cues.

Appearance and the last successful unlock-method ID are nonsecret local
preferences, separate from the vault. Missing preferences use defaults.

The UI requires foreground controlling-terminal stdin/stdout and at least
80×20 cells or 40×24 for the narrow layout. Resize and reported focus loss hide
values. Drafts remain only in memory and are cleared on cancellation, accepted
submission, invalidation or exit. Five minutes without input exits; this is not
configurable. Orderly exit settles submitted work, which may already have
committed. SIGSTOP/SIGKILL and terminal captures cannot guarantee cleanup.

Copy deliberately releases a value to the clipboard. macOS restricts it to the
current host and marks it sensitive/transient. Linux uses fixed `wl-copy` or
`xclip` paths without a sensitivity hint. Clipboard managers may retain values;
Keybay cannot erase their history. Generic field copy/cut never exports secrets.

### Hardware keys in the TUI

1. Open Settings → Security → **Add hardware key**.
2. Connect one compatible FIDO2 key, optionally label it, and choose Add.
3. Touch when prompted. If requested, enter the key's existing PIN.

Rejected PINs are never retried automatically. Cancel waits for cleanup.
On reopening, the last successful method starts directly. Without a preference,
a sole usable method starts; several methods show a choice. Hardware unlock
starts immediately, with explicit Retry after failure and **Other methods** to
cancel and switch. Connection attempts can take up to two minutes.

A store supports one passphrase and multiple passkeys, eight methods total.
They are alternatives on top of mandatory platform protection. Removing the
last method leaves platform-only protection; removal does not delete the key's
credential or revoke older vault snapshots. Passphrase changes use separate
remove/add operations, leaving platform-only protection if it was the last
method and adding fails.

The CLI uses a stable hardware RP namespace and needs no website. System
passkeys are reserved for supported native app hosts. Standalone commands can
unlock with enrolled methods; enrollment/removal lives in the TUI.

For disposable attended testing from source:

```sh
./tool/build_cli_hardware_test.sh
open 'build/hardware-tui-test/Start hardware test.command'
```

Reopen to verify recovery in a fresh process. The companion
`Test command unlock.command` checks standalone command authentication.

### Local browser UX preview

The [website demo](../../site/README.md) and local preview use fake records;
they cannot access or protect a real vault. From the repo root:

```sh
dart run fleury:fleury serve --host=127.0.0.1 --port=5777 \
  --spawn dart run packages/keybay_cli/tool/tui_preview.dart
```

Preview flags include `--empty`, `--locked` and `--copy-fails`. Each connection
gets fresh fake state and a simulated clipboard; idle exit is disabled.
Production disables Fleury debug/hot reload and rejects `FLEURY_*` runtime
settings or an active Dart VM service before opening the store.

## Quickstart

Run the included example from `packages/keybay_cli/example/quickstart` in the
checkout or `example/quickstart` in a release archive:

```sh
keybay run -- ./app.sh
keybay set acme-example/openai-api-key
keybay run -- ./app.sh
keybay rm acme-example/openai-api-key
```

The first run reports the missing key without launching. Set a disposable value;
the second run confirms availability without printing it. See the
[examples guide](example/README.md) to select installed versus source execution.

## Commands

| Command | Purpose |
| --- | --- |
| `keybay open` | Interactive vault and protection settings. |
| `keybay run [-f FILE] -- COMMAND [ARGS...]` | Resolve the manifest and replace Keybay with the child. |
| `keybay set [--stdin] KEY` | Store a value from hidden input or a pipe. No value argument. |
| `keybay get KEY` | Explicit reveal to the controlling foreground terminal. |
| `keybay rm KEY` | Delete; idempotent and silent. |
| `keybay list` | Sorted names, one per line. |

Keys are 1–120 ASCII characters. Each slash-separated segment starts with a
letter/digit and may contain `.`, `_` and `-`. Names such as `my-app/api-key`
organize one shared CLI store; they do not isolate repositories.

Interactive `set` hides input. Enter submits, Backspace edits and Ctrl+U clears.
Bracketed paste preserves exact UTF-8 bytes, including CRLF and trailing newline;
press Enter to submit. Terminal modes are restored on completion or handled exit.

`--stdin` requires a pipe/redirection, refuses empty input and accepts strict
UTF-8. It preserves internal newlines and removes at most one final LF/CRLF.
Partial producer output cannot be detected; use `pipefail` or check its status:

```sh
op read 'op://Engineering/OpenAI/credential' |
  keybay set --stdin my-app/api-key
```

`get` checks stdout before opening and again before reveal. Captured/redirected
output, another terminal and background jobs are refused; stdin is untouched.
It prints the value and a newline, which may remain in scrollback. Values with
control/line-break or unsafe Unicode formatting characters are refused; view
them escaped in the TUI or deliver them with `run`.

The terminal guard prevents accidental disclosure, not access by another program.
A child launched with `run` can print or transmit its selected secrets.

## Authentication and lifetime

Platform protection is mandatory. With additional methods enrolled, commands
select and authenticate one method per invocation; no credential is cached.
PINs are requested only when required, with no automatic retry. Ctrl+C cancels
and waits for provider cleanup. Authentication uses the controlling terminal,
leaving value pipes and child stdin separate. Help, version and literal-only
`run` do not open the store.

**Ordinary desktop namespaces do not isolate same-user programs.** Without an
additional method, a program running as you can use `list` and `run` to read
values without a terminal or prompt. Add a passphrase or hardware key when
platform/file access alone should be insufficient.

Before a secret-referencing `run`, the terminal shows the canonical executable,
arguments, manifest variable names and referenced keys; it omits literal/secret
values. Code-affecting assignments such as `PATH`, `LD_*`, `DYLD_*` and
`NODE_OPTIONS` are marked as a review aid. For protected stores this precedes
authentication. For platform-only stores it is informational, not an approval.
All missing references are reported together and nothing launches.

Handled interrupts stop subsequent actions and settle submitted work. A write
may have committed even when interrupted or failed; reopen and inspect before
retrying. Keybay never automatically resets a store.

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

Secrets stay out of repositories, argv, routine output and interactive shell
state. Explicit Reveal, Copy and `get` disclose selected values. `run` preserves
unmentioned parent environment bytes, overlays manifest entries and resolves
all references before launch. It restores shell-default signal behavior for
the child.

Keybay disables its core files and becomes non-dumpable on Linux before opening
the store; failure stops the command. The child receives the caller's original
core-file limit. Injected values are ordinary child environment variables:
child code, descendants, process inspection and dumps may expose them. Trust
the manifest and launched code. Prefer the Dart SDK when you can avoid injection.

See the [security policy](../../SECURITY.md) and
[external review guide](../../doc/external-review.md) for guarantees and open work.
Flatpak CLI packaging, Windows, Snap and mobile CLI distribution are outside the
published release scope.

## Regression checks

From the repo root:

```sh
./tool/test_cli.sh core   # unit, disposable SDK, native PTY/exec checks
./tool/test_cli.sh macos  # real Keychain, disposable application identity
./tool/test_cli.sh linux  # private Secret Service; Docker on macOS
./tool/test_cli.sh all    # requires macOS and Docker
```

No argument selects `core`. Reports in `build/regression` identify source,
platform, ABI and results; missing prerequisites block rather than pass.
Fake-provider terminal tests and native bundle relocation checks do not replace
attended hardware or installed-release qualification. See
[native packaging](../../doc/cli-hardware-packaging.md) and
[qualification](../../doc/cli-qualification-status.md).

## License

MIT.

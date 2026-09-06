# keybay CLI

Five commands for local, run-scoped secret injection on macOS and Linux
desktop. No account, Keybay server, resident Keybay process, network access,
or shell hook. Keybay writes no plaintext secret file.

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

Use an official V2 native release when available. Its embedded application ID
and, on macOS, stable code signature are part of the store identity. Generic
`dart install keybay_cli` is intentionally deferred: Dart does not currently
carry the package's `keybay.application_id` declaration into that AOT build.

Contributors can build the in-tree executable from the repository root:

```sh
dart pub get
dart run keybay:keybay_compile packages/keybay_cli/bin/keybay.dart -o build/keybay
./build/keybay --version
```

The compiler wrapper validates the CLI package declaration and embeds
`keybay-cli` in the executable. For repeated source runs without changing
global state, use the repository runner documented in the
[examples guide](example/README.md).

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
`secret-tool`. Flatpak is detected and currently fails closed until the Secret
portal lifecycle is implemented; it never silently downgrades to direct Secret
Service access. Headless deployment is unsupported.

Under `dart run`, the shared Dart VM—not Keybay alone—is the macOS keychain
trust unit. Use a compiled, signed release when a stable Keychain trust unit is
required.

## Quickstart

The source checkout and native release archives include the same
language-neutral executable example. Use
`packages/keybay_cli/example/quickstart` in a source checkout or
`example/quickstart` in an extracted native archive. The
[repository examples guide](https://github.com/danReynolds/keybay/tree/main/packages/keybay_cli/example)
distinguishes an installed `keybay` from the current source checkout; choose
one before running these commands:

```sh
cp secrets.env.example .secrets.env
keybay run -- ./app.sh
keybay set acme-example/openai-api-key
keybay run -- ./app.sh
```

The first `run` fails closed and prints the required `set` command without
launching the app. Enter any disposable value at the hidden prompt. The second
`run` safely shows the literal URL and reports the secret as available without
printing its value. The generated `.secrets.env` contains only a public literal
and a reference; real projects should commit manifests like this so every
developer shares the contract but supplies their own value.

After this disposable example:

```sh
keybay rm acme-example/openai-api-key
rm .secrets.env
```

## Commands

```text
keybay run [-f FILE] -- COMMAND [ARGS...]
keybay set [--stdin] KEY
keybay get KEY
keybay rm KEY
keybay list
```

Every key is qualified and at most 120 ASCII characters:
`organization-project/name` for project-local values or
`organization-shared/name` for deliberate reuse. Identical full keys share a
value across repositories; namespaces organize identity but are not an access
control boundary.

`set` never accepts a value argument. Interactive input requires a TTY and is
hidden; automation pipes strict UTF-8. The two modes never cross: `--stdin` at
a terminal is refused (typing there would echo the secret into scrollback), and
empty input is rejected rather than stored, so a silently failed producer in a
pipeline cannot replace a real credential with the empty string:

```sh
op read 'op://Engineering/OpenAI/credential' |
  keybay set --stdin acme-api/openai-api-key
```

`rm` is idempotent and silent. `list` prints sorted qualified names only,
one per line. A failed `run` lists every missing key and launches nothing.

`get` is the explicit human reveal path. It requires both stdin and stdout to
be the foreground interactive TTY and checks that boundary before opening the
store or decrypting a value. Redirected input, pipes, captured output, and
background jobs are refused; use `run` to provide a value to another program.
On success, `get` prints exactly the requested text value followed by a newline.
That value may remain in terminal scrollback, so reveal it only when needed:

```sh
keybay get acme-api/openai-api-key
```

Values containing terminal control or bidirectional-control characters are
refused rather than rendered; pass those values to their consumer with `run`.

The TTY check prevents casual disclosure; it is not an access-control boundary.
A program launched with `run` necessarily receives its selected secrets and can
print or transmit them.

## Manifest

Keybay reads exactly one file: `./.secrets.env`, or the file selected by
`-f`. It never searches parent directories and never writes a manifest.

The grammar is intentionally smaller than dotenv:

- strict UTF-8; LF or CRLF; one leading BOM tolerated
- `NAME=VALUE`, comments, and blank lines
- ASCII space/tab trimming around values
- no quotes, escapes, interpolation, `export`, continuations, or inline
  comments
- a value beginning `kb://` must be a valid qualified reference
- duplicate environment names are errors

Literals are committed plaintext. Keybay cannot determine whether a literal is
actually a secret; that classification remains visible in review.

## Security boundary

Keybay keeps referenced values out of repositories, argv, routine output, and
interactive shell state. The deliberately requested, foreground-only `get`
command is the sole direct-output exception. It preserves the parent
environment **byte-exact** —
variables the manifest does not name pass through from the raw process
`environ`, including values that are not valid UTF-8 — overlays only variables
named by the selected manifest, resolves all references before launch, and has
no network code. The launched command starts with shell-default signal state
(the Dart VM's ignored SIGPIPE and blocked job-control signals are reset at the
exec boundary), so pipelines behave as they would from a shell.

After injection, values are normal child environment variables. They can be
inherited by descendants and may be visible to same-user process inspection,
crash dumps, or the child itself. Running a manifest trusts both its references
and the launched code. Direct use of the `keybay` Dart library is preferable
when an application can avoid environment injection entirely.

macOS and Linux desktop are supported. Headless/CI environments have no
supported availability contract; use the CI platform's secret store there.

## License

MIT.

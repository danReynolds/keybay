# Keybay CLI examples

These are all examples of the CLI process boundary:

- [`quickstart`](quickstart): the packaged language-neutral acceptance path
- [`flutter`](flutter): launch a macOS Flutter app with injected configuration
- [`rails`](rails): boot a Rails web app on the loopback interface
- [`node`](node): start a Node web app on the loopback interface

Each example includes a ready-to-use `.env` with public configuration
and `kb://` references only. Every developer supplies their own values through
the local Keybay store. The examples use separate namespaces so each demo has
its own disposable values.

The three visual app examples intentionally render the injected value so you
can see the complete process boundary working. Use a disposable value only:
the value can appear on screen, in screenshots, or in browser tooling. The
language-neutral quickstart keeps its terminal output redacted.

## Choose the executable first

Use an official V2 native release when available. Generic `dart install` is
deferred because it does not yet embed Keybay's declared application identity.

For this source checkout, activate the CLI once from the repository root:

```sh
dart pub global activate --source path packages/keybay_cli
keybay --version
```

Put `$HOME/.pub-cache/bin` before any older Keybay installation in `PATH`.
The command should report `0.2.0`. Path activation follows this checkout, so
keep the checkout in place; no alias or shell function is needed.

With Dart 3.12.2, local path activation prints Pub's dependency-resolution
messages before Keybay starts. For checks that require exact CLI output, use
the native build instead.

Then enter any example directory and use the same command name:

```sh
cd packages/keybay_cli/example/node
keybay set keybay-node/openai-api-key
keybay run -- npm start
```

Path activation runs through the shared Dart VM, which is the Keychain trust
unit on macOS in this development mode. To test the embedded AOT identity,
use the native build described in the
[CLI installation guide](../README.md#install).
The signed release distribution remains a separate qualification.

Now follow the selected README. Run every command from that example directory;
Keybay deliberately reads only its manifest and never searches parents.
Remove the disposable value with the documented `keybay rm` command when
finished.

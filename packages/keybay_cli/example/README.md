# Keybay CLI examples

These are all examples of the CLI process boundary:

- [`quickstart`](quickstart): the packaged language-neutral acceptance path
- [`flutter`](flutter): launch a macOS Flutter app with injected configuration
- [`rails`](rails): boot a Rails web app on the loopback interface
- [`node`](node): start a Node web app on the loopback interface

Each example contains a manifest template with public configuration and
`kb://` references only. Copy it to `.secrets.env` as instructed; every
developer supplies their own values through the local Keybay store. The
examples use different qualified namespaces, so their disposable values do
not bleed into one another.

The three visual app examples intentionally render the injected value so you
can see the complete process boundary working. Use a disposable value only:
the value can appear on screen, in screenshots, or in browser tooling. The
language-neutral quickstart keeps its terminal output redacted.

## Choose the executable first

Use an official V2 native release when available. Generic `dart install` is
deferred because it does not yet embed Keybay's declared application identity.

For the current source checkout, resolve the workspace and either compile the
CLI or define the source runner from the repository root:

```sh
dart pub get
dart run keybay:keybay_compile packages/keybay_cli/bin/keybay.dart -o build/keybay
alias keybay="$PWD/tool/keybay-dev"
```

Then enter any example directory and use the same command name:

```sh
cd packages/keybay_cli/example/flutter
keybay --version
```

`keybay-dev` runs the current source with the root package configuration while
preserving the example directory as the manifest directory. On macOS, the
shared Dart VM is the Keychain trust unit for this source mode; only the
promoted Developer ID-signed archive promises the frozen release identity. The
runner is contributor tooling, not a sixth CLI command and not part of a
release archive. Use `build/keybay` instead when testing the embedded AOT
identity itself.

Now follow the selected README. Run every command from that example directory;
Keybay deliberately reads only its manifest and never searches parents.
Remove the disposable value with the documented `keybay rm` command when
finished.

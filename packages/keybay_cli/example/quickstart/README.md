# Quickstart example

This language-neutral example proves both halves of a mixed Keybay manifest:
the literal `API_URL` and the referenced `OPENAI_API_KEY` reach exactly one
child process.

These commands require `keybay` on `PATH`. Source contributors can choose the
local path activation in the
[examples guide](https://github.com/danReynolds/keybay/tree/main/packages/keybay_cli/example).
Then, from this directory:

```sh
keybay run -- ./app.sh
keybay set acme-example/openai-api-key
keybay run -- ./app.sh
```

The included `.env` contains only a public URL and a `kb://` reference.
It is checked in so the configuration is shared while each developer supplies
their own value. There is nothing to copy or edit.

If the demo key is not set, the first `run` prints the `set` command without
launching the app. Enter any disposable value at the hidden prompt. The second
`run` shows the literal URL and confirms that the secret reached the app
without printing its value:

```text
Keybay example app started.
  API_URL: https://staging.example.com
  OPENAI_API_KEY: available (value not printed)
```

Remove the disposable example value when finished:

```sh
keybay rm acme-example/openai-api-key
```

`keybay rm` is silent and succeeds even if the value is already absent.

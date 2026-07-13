# Quickstart example

This language-neutral example proves both halves of a mixed Keyway manifest:
the literal `API_URL` and the referenced `OPENAI_API_KEY` reach exactly one
child process.

From this directory:

```sh
cp secrets.env.example .secrets.env
keyway run -- ./app.sh
keyway set acme-example/openai-api-key
keyway run -- ./app.sh
```

The first `run` fails closed and prints the `set` command without launching the
app. Enter any disposable value at the hidden prompt. The second `run` shows
the literal URL and confirms that the secret reached the app without printing
its value:

```text
Keyway example app started.
  API_URL: https://staging.example.com
  OPENAI_API_KEY: available (value not printed)
```

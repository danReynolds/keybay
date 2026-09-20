# CLI dogfood

Use disposable values in your usual interactive terminal. If your store has a
passphrase, each command that accesses it asks for that passphrase separately.
The value prompt for `set` is also hidden.

Use the `keybay` command from the [local installation guide](../packages/keybay_cli/README.md#install):

```sh
keybay --version
```

The version should be `0.2.0`. Dart 3.12.2 path activation prints Pub dependency
messages before Keybay starts. For exact-output checks, build the native
executable using that guide, then prepend this checkout's `build` directory to
`PATH` in your terminal. No shell function is needed.

Use a fresh namespace for this run:

```sh
dogfood_key="dogfood-$(date +%s)/api-token"
```

1. **Set a key interactively.** Run the command, enter `demo-token-one`, then
   press Enter. Check that typing stays hidden and the result is clear.

   ```sh
   keybay set "$dogfood_key"
   ```

2. **List and reveal.** The list should show names only. `get` should print
   exactly the disposable value.

   ```sh
   keybay list
   keybay get "$dogfood_key"
   ```

3. **Update through stdin.** Check that the existing key is replaced and the
   piped value does not interfere with a passphrase prompt.

   ```sh
   printf 'demo-token-two\n' | keybay set --stdin "$dogfood_key"
   keybay get "$dogfood_key"
   ```

4. **Try error and cancellation paths.** The first two should give clear errors.
   At the final command's first prompt, press Ctrl+C; the terminal should return
   normally and the saved value should remain `demo-token-two`.

   ```sh
   keybay get "${dogfood_key}-missing"
   keybay set 'bad key'
   keybay set "$dogfood_key"
   keybay get "$dogfood_key"
   ```

5. **Inject into a process.** Create a temporary manifest containing a reference
   and a public literal. Expect `Environment: dogfood` and `Token available`,
   without printing the value.

   ```sh
   dogfood_dir=$(mktemp -d)
   printf 'APP_ENV=dogfood\nAPI_TOKEN=kb://%s\n' "$dogfood_key" > "$dogfood_dir/.env"
   keybay run -f "$dogfood_dir/.env" -- /bin/sh -c 'printf "Environment: %s\n" "$APP_ENV"; test -n "$API_TOKEN" && echo "Token available"'
   ```

6. **Delete and clean up.** `rm` should succeed silently, a second removal should
   also succeed, and `get` should report the missing key.

   ```sh
   keybay rm "$dogfood_key"
   keybay rm "$dogfood_key"
   keybay get "$dogfood_key"
   rm "$dogfood_dir/.env"
   rmdir "$dogfood_dir"
   ```

Look for confusing wording, unnecessary output, awkward passphrase prompts,
and terminal state left behind after cancellation.

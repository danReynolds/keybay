# Node service example

This dependency-free Node service demonstrates the common `npm start` path.
It inherits configuration from Keyway, exposes only a safe status response,
and never prints or returns the credential.

First choose an installed or source-checkout executable as described in the
[examples guide](../README.md). Then, from this directory:

```sh
cp secrets.env.example .secrets.env
keyway run -- npm run check --silent
keyway set keyway-node/openai-api-key
keyway run -- npm run check --silent
keyway run -- npm start
```

The first command fails closed before npm starts. Enter any disposable value
at the hidden prompt. The one-shot check then succeeds, and `npm start` listens
on `http://127.0.0.1:4242`. In another terminal:

```sh
curl http://127.0.0.1:4242/
```

The response reports only that OpenAI is configured. Stop the service with
Control-C, then remove the disposable value:

```sh
keyway rm keyway-node/openai-api-key
rm .secrets.env
```

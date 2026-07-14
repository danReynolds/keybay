# Node service demo

This dependency-free Node service demonstrates the common `npm start` path.
It inherits configuration from Keyway, exposes only a safe status response,
and never prints or returns the credential.

From this directory:

```sh
keyway run -- npm run check --silent
keyway set demo-node/openai-api-key
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
keyway rm demo-node/openai-api-key
```

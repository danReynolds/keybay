# Rails runner example

This minimal Rails application runs ordinary application code with a
development-only Stripe credential supplied by Keyway. It prints the Rails
version, the public endpoint, and a safe availability status—not the secret.

Rails 8.1 requires Ruby 3.2 or newer. Activate a current Ruby with your usual
version manager. On a Homebrew installation:

```sh
export PATH="$(brew --prefix ruby)/bin:$PATH"
```

Then choose an installed or source-checkout executable as described in the
[examples guide](../README.md). From this directory:

```sh
bundle install
cp secrets.env.example .secrets.env
keyway run -- bin/rails runner script/check_configuration.rb
keyway set keyway-rails/stripe-secret-key
keyway run -- bin/rails runner script/check_configuration.rb
```

The first run fails closed before Rails boots. Enter any disposable value at
the hidden prompt. The second run prints:

```text
Keyway Rails example booted on Rails 8.1.3.
  PAYMENTS_API_URL: https://payments.example.com
  STRIPE_SECRET_KEY: available (value not printed)
```

After the example:

```sh
keyway rm keyway-rails/stripe-secret-key
rm .secrets.env
```

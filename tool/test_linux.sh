#!/usr/bin/env bash
# Run the Linux integration tier locally on ANY machine with Docker (e.g. a
# macOS dev box) — the same tier CI runs: the Secret Service backend against a
# real gnome-keyring under a throwaway D-Bus session. Verified in-repo.
#
#   ./tool/test_linux.sh
#
# The repo is mounted read-only. Only source and test inputs are copied into
# the container, so host build products and caches cannot bloat the disposable
# Linux workspace or be rewritten with container paths.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec docker run --rm -i -v "$REPO":/src:ro dart:stable bash -s <<'INNER'
set -euo pipefail
apt-get update -qq
apt-get install -y -qq libsecret-tools gnome-keyring dbus python3 >/dev/null
mkdir -p /build/packages/keybay_cli/example
cp /src/pubspec.yaml /src/pubspec.lock /src/analysis_options.yaml \
  /src/dart_test.yaml /build/
cp -R /src/lib /src/test /src/tool /build/
cp /src/packages/keybay_cli/pubspec.yaml \
  /src/packages/keybay_cli/analysis_options.yaml \
  /src/packages/keybay_cli/LICENSE \
  /src/packages/keybay_cli/README.md \
  /src/packages/keybay_cli/CHANGELOG.md \
  /build/packages/keybay_cli/
cp -R /src/packages/keybay_cli/bin \
  /src/packages/keybay_cli/lib \
  /src/packages/keybay_cli/test \
  /src/packages/keybay_cli/tool \
  /build/packages/keybay_cli/
cp -R /src/packages/keybay_cli/example/quickstart \
  /build/packages/keybay_cli/example/
cd /build
dart pub get >/dev/null

# Secret Service via secret-tool, under a throwaway D-Bus session + keyring.
# NB: we deliberately do NOT pre-create ~/.local/share — a bare container lacks
# it, so this exercises the clean-account path where the library creates the
# missing XDG data hierarchy itself (0700).
dbus-run-session -- bash -c '
  set -euo pipefail
  eval "$(printf itest | gnome-keyring-daemon --daemonize --unlock --components=secrets)"
  export GNOME_KEYRING_CONTROL
  (cd packages/keybay && KEYBAY_INTEGRATION=1 dart test test/secret_service_integration_test.dart)
  ./tool/test_cli_storage.sh
  CI=true KEYBAY_QUICKSTART=1 ./tool/test_cli_quickstart.sh
  KEYBAY_BENCHMARK=1 KEYBAY_BENCHMARK_ITERATIONS=100 \
    ./tool/benchmark_cli.sh
'

# The locked-collection tier, in its OWN session (it locks the login collection
# and can't unlock it again) — the same second step CI runs. The container is
# exactly the throwaway session KEYBAY_LOCKED_TEST demands.
dbus-run-session -- bash -c '
  set -euo pipefail
  eval "$(printf itest | gnome-keyring-daemon --daemonize --unlock --components=secrets)"
  export GNOME_KEYRING_CONTROL
  (cd packages/keybay && KEYBAY_INTEGRATION=1 KEYBAY_LOCKED_TEST=1 dart test test/secret_service_locked_integration_test.dart)
'

# The CLI guidance is a separate contract from the library's raw API behavior.
# It also locks the collection, so give it a third disposable session.
dbus-run-session -- bash -c '
  set -euo pipefail
  eval "$(printf itest | gnome-keyring-daemon --daemonize --unlock --components=secrets)"
  export GNOME_KEYRING_CONTROL
  KEYBAY_LOCKED_TEST=1 ./tool/test_cli_locked_storage.sh
'
INNER

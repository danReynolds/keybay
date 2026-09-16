#!/usr/bin/env bash
# Real provider regression; never the developer's fixed CLI store.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
case "${1:-}" in
  macos)
    [[ "$(uname -s)" == Darwin ]] || exit 69
    exec bash tool/test_cli_storage.sh
    ;;
  linux)
    if [[ "$(uname -s)" != Linux ]]; then
      exec bash tool/test_linux_docker.sh cli
    fi
    for program in dart dbus-run-session gnome-keyring-daemon gdbus; do
      command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
    done
    # A private provider session, data/config roots and runtime directory.
    # shellcheck disable=SC2016
    exec dbus-run-session -- bash -c '
      set -euo pipefail
      umask 077
      work="$(mktemp -d)"
      trap '\''rm -rf -- "$work"'\'' EXIT
      mkdir "$work/data" "$work/config" "$work/runtime" "$work/keyring"
      export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_RUNTIME_DIR="$work/runtime"
      printf itest | gnome-keyring-daemon --foreground --unlock --components=secrets \
        --control-directory="$work/keyring" > "$work/keyring.log" 2>&1 &
      keyring_pid=$!
      trap '\''kill "$keyring_pid" 2>/dev/null || true; wait "$keyring_pid" || true; rm -rf -- "$work"'\'' EXIT
      gdbus wait --session --timeout 15 org.freedesktop.secrets
      bash tool/test_cli_storage.sh
      KEYBAY_LOCKED_TEST=1 bash tool/test_cli_locked_storage.sh
    '
    ;;
  *) echo 'usage: test_cli_platform.sh macos|linux' >&2; exit 64 ;;
esac

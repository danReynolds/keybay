#!/usr/bin/env bash
# Run the packaged quickstart and benchmark in a private Secret Service session.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "$(uname -s)" == Linux ]] || exit 69
for program in dbus-run-session gnome-keyring-daemon gdbus secret-tool; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done

# Variables expand in the separate disposable session shell.
# shellcheck disable=SC2016
exec dbus-run-session -- bash -c '
  set -euo pipefail
  umask 077
  work="$(mktemp -d)"
  keyring_pid=""
  cleanup() {
    local result=$?
    trap - EXIT
    if [[ -n "$keyring_pid" ]]; then
      kill "$keyring_pid" 2>/dev/null || true
      wait "$keyring_pid" || true
    fi
    rm -rf -- "$work" || result=1
    exit "$result"
  }
  trap cleanup EXIT
  trap "exit 130" INT
  trap "exit 143" TERM
  mkdir "$work/data" "$work/config" "$work/runtime" "$work/keyring"
  export XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_RUNTIME_DIR="$work/runtime"
  printf itest | gnome-keyring-daemon --foreground --unlock --components=secrets \
    --control-directory="$work/keyring" > "$work/keyring.log" 2>&1 &
  keyring_pid=$!
  gdbus wait --session --timeout 15 org.freedesktop.secrets
  kill -0 "$keyring_pid"
  KEYBAY_QUICKSTART=1 bash tool/test_cli_quickstart.sh
  KEYBAY_BENCHMARK=1 KEYBAY_BENCHMARK_ITERATIONS="${KEYBAY_BENCHMARK_ITERATIONS:-100}" \
    bash tool/benchmark_cli.sh
'

#!/usr/bin/env bash
# SDK Secret Service regression against two private disposable keyrings.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != Linux ]]; then
  exec bash "$repo/tool/test_linux_docker.sh" linux
fi
for program in dart dbus-run-session gnome-keyring-daemon gdbus; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done
cd "$repo/packages/keybay"
dart test test/v2_posix_store_files_test.dart --name 'uses ABI-correct directory and no-follow flags'
dart test test/v2_linux_desktop_host_platform_test.dart --name 'securely prepares a missing clean-account data hierarchy'
for test_file in v2_linux_secret_service_integration_test.dart v2_linux_secret_service_locked_integration_test.dart; do
  # Variables expand in the separate disposable session shell.
  # shellcheck disable=SC2016
  dbus-run-session -- bash -c '
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
    KEYBAY_INTEGRATION=1 KEYBAY_LOCKED_TEST=1 dart test "test/$1"
  ' keybay-linux "$test_file"
done

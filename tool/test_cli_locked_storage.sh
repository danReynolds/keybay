#!/usr/bin/env bash
# Exercise the CLI's honest Linux failure path when Secret Service hides a
# stored item behind a locked collection. This deliberately locks the login
# collection and therefore belongs only in a disposable dbus-run-session.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() {
  echo "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "CLI locked-store check is Linux-only; skipped"
  exit 0
fi

if [[ "${KEYBAY_LOCKED_TEST:-}" != "1" ]]; then
  echo "refusing to lock a real login keyring" >&2
  echo "run only in a disposable dbus-run-session with KEYBAY_LOCKED_TEST=1" >&2
  exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-cli-locked.XXXXXX")"
app_id="keybay-cli-locked-itest-${GITHUB_RUN_ID:-$$}"
cleanup() {
  rm -rf "$tmp"
  rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/$app_id"
}
trap cleanup EXIT

dart compile exe -Dkeybay.application_id="$app_id" \
  packages/keybay_cli/tool/integration_harness.dart \
  -o "$tmp/keybay-integration"

sentinel="keybay-locked-value-${GITHUB_RUN_ID:-$$}"
printf '%s' "$sentinel" | \
  "$tmp/keybay-integration" set --stdin keybay-itest/token

dbus-send \
  --session \
  --print-reply \
  --dest=org.freedesktop.secrets \
  /org/freedesktop/secrets \
  org.freedesktop.Secret.Service.Lock \
  array:objpath:/org/freedesktop/secrets/collection/login >/dev/null

set +e
output="$("$tmp/keybay-integration" list 2>&1)"
rc=$?
set -e

[[ $rc -eq 1 ]] || fail "locked-store list exited $rc, expected 1"
[[ "$output" == *"platform protection is locked"* ]] || \
  fail "locked-store output omitted the observed failure"
[[ "$output" == *"Unlock the platform key store and retry"* ]] || \
  fail "locked-store output omitted unlock guidance"
[[ "$output" != *"$sentinel"* ]] || \
  fail "locked-store output leaked the secret sentinel"

echo "CLI locked-store guidance passed"

#!/usr/bin/env bash
# Real Security.framework tests using only a disposable file Keychain.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required' >&2; exit 69; }
for program in dart clang; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d /private/tmp/keybay-native-XXXXXXXX)"
keychain="$fixture/account/Library/Keychains/login.keychain-db"
created=0
cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$created" == 1 ]]; then
    # Deleting our disposable Keychain works while locked. An unnecessary
    # unlock can fail independently and obscure the SDK test outcome.
    if ! "$fixture/keychain-fixture" delete "$keychain"; then
      echo "Temporary Keychain cleanup failed: $fixture" >&2
      exit 1
    fi
  fi
  rm -rf -- "$fixture"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$fixture/account/Library/Keychains"
chmod 700 "$fixture/account"
clang -Wno-deprecated-declarations -framework Security -framework CoreFoundation \
  "$repo/tool/macos_test_keychain.c" -o "$fixture/keychain-fixture"
"$fixture/keychain-fixture" create "$keychain"
created=1
export KEYBAY_INTEGRATION=1
export KEYBAY_TEST_KEYCHAIN_HOME="$fixture/account"
export KEYBAY_TEST_KEYCHAIN_HELPER="$fixture/keychain-fixture"
cd "$repo/packages/keybay"
dart test --reporter expanded --concurrency=1 \
  test/keychain_integration_test.dart \
  test/v2_macos_login_keychain_integration_test.dart \
  test/v2_macos_unentitled_integration_test.dart \
  test/v2_macos_locked_integration_test.dart \
  --name '^(bounded|unsigned|create|V2 read|real login|locked classic)'

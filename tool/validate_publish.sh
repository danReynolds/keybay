#!/usr/bin/env bash
# Pub warns about exact dependency constraints. Those pins are a deliberate
# supply-chain contract, so accept exactly the named warnings while still
# failing on validation errors, dirty package files, or any new warning.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ $# -lt 2 ]]; then
  echo "usage: $0 PACKAGE_DIRECTORY EXACT_PIN_DEPENDENCY [...]" >&2
  exit 2
fi

package_directory="$1"
shift
expected_warning_count="$#"
output="$(mktemp "${TMPDIR:-/tmp}/keybay-publish.XXXXXX")"
cleanup() {
  rm -f "$output"
}
trap cleanup EXIT

# Both packages publish directly from their own workspace directory
# (packages/keybay, packages/keybay_cli) — no staging.
dart pub -C "$package_directory" publish --dry-run --ignore-warnings \
  2>&1 | tee "$output"

warning_count="$(grep -c '^\* ' "$output" || true)"
if [[ "$warning_count" != "$expected_warning_count" ]]; then
  echo "publish validation reported $warning_count warnings, expected $expected_warning_count exact-pin warnings" >&2
  exit 1
fi
for dependency in "$@"; do
  expected="* Your dependency on \"$dependency\" should allow more than one version. For example:"
  if ! grep -Fxq "$expected" "$output"; then
    echo "publish validation omitted the expected $dependency exact-pin warning" >&2
    exit 1
  fi
done

warning_noun="warnings"
if [[ "$expected_warning_count" == "1" ]]; then
  warning_noun="warning"
fi
if ! grep -Fxq "Package has $expected_warning_count $warning_noun." "$output"; then
  echo "publish validation warning summary changed unexpectedly" >&2
  exit 1
fi

echo "Publish archive passed with only the intentional exact-pin warnings"

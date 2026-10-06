#!/usr/bin/env bash
# Verify the frozen code-identity contract. Strict mode is the release gate;
# KEYBAY_ALLOW_ADHOC=1 exists only so the structural checks can run locally.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 KEYBAY_BINARY [EXPECTED_TEAM_ID]" >&2
  exit 2
fi

binary="$(python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve(strict=True))
PY
)"
expected_team="${2:-}"
details="$(codesign -dvvv "$binary" 2>&1)"

codesign --verify --strict --verbose=2 "$binary"
if [[ "$details" != *$'\nIdentifier=io.github.danreynolds.keybay.cli\n'* ]]; then
  echo "release binary does not use identifier io.github.danreynolds.keybay.cli" >&2
  exit 1
fi
if ! grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$details"; then
  echo "release binary does not enable the hardened runtime" >&2
  exit 1
fi

entitlements="$(mktemp "${TMPDIR:-/tmp}/keybay-entitlements.XXXXXX")"
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements - "$binary" >"$entitlements" 2>/dev/null
if [[ -s "$entitlements" ]]; then
  echo "release binary unexpectedly carries entitlements" >&2
  cat "$entitlements" >&2
  exit 1
fi

if [[ "${KEYBAY_ALLOW_ADHOC:-}" != "1" ]]; then
  if [[ -z "$expected_team" ]]; then
    echo "strict release verification requires the frozen Apple Team ID" >&2
    exit 2
  fi
  if [[ ! "$expected_team" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "expected Apple Team ID must be 10 uppercase letters or digits" >&2
    exit 2
  fi
  if [[ "$details" != *$'\nAuthority=Developer ID Application:'* ]]; then
    echo "release binary is not signed by a Developer ID Application" >&2
    exit 1
  fi
  if [[ "$details" != *$'\nTimestamp='* ]]; then
    echo "release binary does not carry a secure timestamp" >&2
    exit 1
  fi
  team="$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p')"
  if [[ -z "$team" || "$team" == "not set" ]]; then
    echo "release binary does not carry a signing team identifier" >&2
    exit 1
  fi
  if [[ "$team" != "$expected_team" ]]; then
    echo "release binary team was '$team', expected '$expected_team'" >&2
    exit 1
  fi

  requirement="$(codesign -d -r- "$binary" 2>&1 | sed -n '/^designated =>/p')"
  expected_requirement="designated => identifier \"io.github.danreynolds.keybay.cli\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \"$team\""
  if [[ "$requirement" != "$expected_requirement" ]]; then
    echo "release binary designated requirement changed" >&2
    echo "actual:   $requirement" >&2
    echo "expected: $expected_requirement" >&2
    exit 1
  fi
fi

bundle="$(dirname "$binary")"
if [[ -f "$bundle/hardware.json" ]]; then
  python3 "$(dirname "${BASH_SOURCE[0]}")/cli_hardware_bundle.py" verify "$bundle"
  if [[ "${KEYBAY_ALLOW_ADHOC:-}" != "1" ]]; then
    python3 "$(dirname "${BASH_SOURCE[0]}")/cli_macos_constraint.py" verify "$bundle"
    runtime_requirement="$(codesign -d -r- "$bundle/keybay-runtime" 2>&1 | sed -n '/^designated =>/p')"
    if [[ "$runtime_requirement" != "$expected_requirement" ]]; then
      echo 'dedicated runtime does not preserve the frozen CLI identity' >&2; exit 1
    fi
  fi
  for companion in keybay-runtime keybay.aot; do
    codesign --verify --strict "$bundle/$companion"
    companion_details="$(codesign -dvvv "$bundle/$companion" 2>&1)"
    if ! grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$companion_details"; then
      echo "missing hardened runtime: $companion" >&2; exit 1
    fi
  done
  for library in "$bundle"/*.dylib "$bundle/keybay-runtime" "$bundle/keybay.aot"; do
    codesign --verify --strict "$library"
    codesign -d --entitlements - "$library" >"$entitlements" 2>/dev/null
    if [[ -s "$entitlements" ]]; then
      echo "companion unexpectedly carries entitlements: $library" >&2; exit 1
    fi
    if [[ "${KEYBAY_ALLOW_ADHOC:-}" != "1" ]]; then
      library_details="$(codesign -dvvv "$library" 2>&1)"
      if [[ "$library_details" != *$'\nTeamIdentifier='"$expected_team"$'\n'* ||
            "$library_details" != *$'\nAuthority=Developer ID Application:'* ||
            "$library_details" != *$'\nTimestamp='* ]]; then
        echo "hardware library must have a timestamped Developer ID signature from $expected_team: $library" >&2
        exit 1
      fi
    fi
  done
fi

echo "macOS release identity passed"

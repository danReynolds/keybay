#!/usr/bin/env bash
# Promote only a passing schema-v2 receipt and its sanitized structured result.
set -euo pipefail
umask 077

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO"

if [[ $# != 1 ]]; then
  echo "usage: $0 RUN_DIRECTORY" >&2
  exit 64
fi
command -v jq >/dev/null 2>&1 || {
  echo "promote-device-receipt: jq is required" >&2
  exit 64
}
run="$(cd "$1" 2>/dev/null && pwd -P)" || {
  echo "promote-device-receipt: run directory does not exist" >&2
  exit 64
}
case "$run" in
  "$REPO"/build/device-security/*) ;;
  *)
    echo "promote-device-receipt: run must be under build/device-security" >&2
    exit 64
    ;;
esac
receipt="$run/receipt.json"
[[ -f "$receipt" && ! -L "$receipt" ]] || {
  echo "promote-device-receipt: missing regular receipt.json" >&2
  exit 64
}

subject="$(jq -er '
  select(.schema == "keybay.device-security-receipt") |
  select(.schema_version == 2) |
  select(.status == "pass") |
  select(.suite.clean == true) |
  .subject.sha256 |
  select(test("^[0-9a-f]{64}$"))
' "$receipt")" || {
  echo "promote-device-receipt: receipt is not an eligible pass" >&2
  exit 64
}
selection="$(jq -er '.selection | select(test("^[a-z0-9-]+$"))' \
  "$receipt")"
evidence_name="$(jq -er '
  select(.evidence | length == 1) |
  .evidence[0].path |
  select(test("^[a-z0-9-]+[.]results[.]json$"))
' "$receipt")" || {
  echo "promote-device-receipt: unexpected retained-evidence shape" >&2
  exit 64
}
[[ "$evidence_name" == "$selection.results.json" ]] || {
  echo "promote-device-receipt: selection/evidence mismatch" >&2
  exit 64
}
evidence="$run/$evidence_name"
[[ -f "$evidence" && ! -L "$evidence" ]] || {
  echo "promote-device-receipt: retained evidence is missing" >&2
  exit 64
}
expected="$(jq -er '.evidence[0].sha256' "$receipt")"
actual="$(shasum -a 256 -- "$evidence" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || {
  echo "promote-device-receipt: retained evidence digest mismatch" >&2
  exit 64
}

# A candidate subject accumulates one receipt per selection (baseline, a
# change-triggered tamper run, macos, ...); only the same selection may not be
# promoted twice — receipts are immutable, corrections come from a new run.
destination="$REPO/doc/device-security-receipts/$subject"
receipt_dest="$destination/$selection.receipt.json"
evidence_dest="$destination/$evidence_name"
for existing in "$receipt_dest" "$evidence_dest"; do
  [[ ! -e "$existing" && ! -L "$existing" ]] || {
    echo "promote-device-receipt: $selection is already promoted for this" \
      "subject" >&2
    exit 64
  }
done
mkdir -p -- "$destination"
temporary="$(mktemp -d "$REPO/doc/device-security-receipts/.promote.XXXXXX")"
cleanup() {
  [[ ! -d "$temporary" ]] || rm -rf -- "$temporary"
}
trap cleanup EXIT
cp -- "$receipt" "$temporary/$selection.receipt.json"
cp -- "$evidence" "$temporary/$evidence_name"
chmod 0644 "$temporary"/*
mv -- "$temporary/$selection.receipt.json" "$receipt_dest"
mv -- "$temporary/$evidence_name" "$evidence_dest"
trap - EXIT
cleanup
echo "$destination"

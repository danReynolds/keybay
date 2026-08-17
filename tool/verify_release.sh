#!/usr/bin/env bash
# Verify a published keybay core release from public sources only.
#
# Downloads the archive pub.dev actually serves, recomputes its canonical
# package-content identity, verifies the GitHub release-assurance attestation
# against that identity, and prints what the release's signed statement
# verified — and what it declared as gaps.
#
# This is the same code path CI runs after publication; a consumer needs only
# curl, python3, and an authenticated `gh` CLI.
#
# usage: tool/verify_release.sh keybay VERSION [--source-ref REF]
#          [--work-dir DIR]
#
# With --work-dir, the downloaded archive, recomputed identity, and the raw
# `gh attestation verify --format json` output are retained there for callers
# (CI compares them against the run's own artifacts).
set -euo pipefail
umask 077

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  echo "usage: $0 keybay VERSION [--source-ref REF] [--work-dir DIR]" >&2
  exit 64
}

[[ $# -ge 2 ]] || usage
package="$1"
version="$2"
shift 2
[[ "$package" == keybay ]] || {
  echo "verify-release: only the core 'keybay' package is verifiable here;" \
    "CLI archives are verified per-asset on their GitHub Release" >&2
  exit 64
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

source_ref=""
work_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-ref)
      [[ $# -ge 2 ]] || usage
      source_ref="$2"
      shift 2
      ;;
    --work-dir)
      [[ $# -ge 2 ]] || usage
      work_dir="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

for dependency in curl python3 gh; do
  command -v "$dependency" >/dev/null 2>&1 || {
    echo "verify-release: '$dependency' is required" >&2
    exit 69
  }
done

if [[ -z "$work_dir" ]]; then
  work_dir="$(mktemp -d)"
  trap 'rm -rf -- "$work_dir"' EXIT
else
  mkdir -p -- "$work_dir"
fi

hosted="$work_dir/keybay-$version.hosted.tar.gz"
identity="$work_dir/keybay-$version.canonical-content"
verified="$work_dir/verified-assurance.json"

if ! curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  --output "$hosted" "https://pub.dev/api/archives/keybay-$version.tar.gz"; then
  echo "verify-release: keybay $version was not found on pub.dev" >&2
  exit 1
fi

python3 "$REPO/tool/compare_pub_archives.py" --identity "$hosted" "$identity"
# The canonical digest is by definition sha256 of the identity file's bytes;
# hash those instead of parsing the whole archive a second time.
digest="$(python3 -c \
  'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' \
  "$identity")"

verify_args=(
  --repo danReynolds/keybay
  --signer-workflow danReynolds/keybay/.github/workflows/publish.yml
  --predicate-type https://keybay.dev/attestations/release-assurance/v1
  --deny-self-hosted-runners
  --format json
)
[[ -z "$source_ref" ]] || verify_args+=(--source-ref "$source_ref")

if ! gh attestation verify "$identity" "${verify_args[@]}" > "$verified"; then
  echo "verify-release: no valid release-assurance attestation matched" \
    "keybay $version (content sha256 $digest)." >&2
  echo "Releases before 0.1.1 predate signed release statements; for those," \
    "absence of an attestation is a declared gap, not a verification." >&2
  exit 1
fi

python3 - "$verified" "$digest" "$version" <<'PY'
import json
import sys

verified_path, digest, version = sys.argv[1:4]
with open(verified_path, encoding="utf-8") as handle:
    results = json.load(handle)
if not isinstance(results, list) or not results:
    sys.exit("verify-release: unexpected gh attestation output shape")
predicate = results[0]["verificationResult"]["statement"]["predicate"]

if predicate.get("version") != version:
    sys.exit(
        "verify-release: attestation is for version "
        f"{predicate.get('version')!r}, not {version!r}"
    )

print(f"subject: {predicate.get('subject')} {predicate.get('version')}")
print(f"canonical content sha256: {digest}")
print("attestation: VERIFIED "
      "(danReynolds/keybay .github/workflows/publish.yml)")
receipts = predicate.get("qualification_receipts") or []
print("qualification receipts:" if receipts else "qualification receipts: none")
for receipt in receipts:
    print(
        f"  - {receipt.get('selection')} "
        f"({receipt.get('platform')}, {receipt.get('execution_class')})"
    )
gaps = predicate.get("unqualified_configurations") or []
print("declared gaps:" if gaps else "declared gaps: none")
for gap in gaps:
    print(f"  - {gap}")
for limitation in predicate.get("canonical_limitations") or []:
    print(f"limitations: {limitation}")
PY

#!/usr/bin/env bash
# Build the exact core publication subject and its release-assurance manifest.
# Run this before creating a release tag; the tag workflow runs it again.
set -euo pipefail
umask 077

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO"

if [[ $# != 2 ]]; then
  echo "usage: $0 OUTPUT_DIRECTORY CI_RUN_ID" >&2
  exit 64
fi
output="$1"
ci_run_id="$2"
[[ "$ci_run_id" =~ ^[1-9][0-9]*$ ]] || {
  echo "CI_RUN_ID must be a positive integer" >&2
  exit 64
}
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
  echo "core assurance requires a clean checkout" >&2
  exit 1
}
[[ ! -e "$output" && ! -L "$output" ]] || {
  echo "refusing an existing assurance output path: $output" >&2
  exit 1
}
mkdir -p "$(dirname "$output")"
mkdir -m 700 "$output"

version="$(awk '$1 == "version:" { print $2; exit }' packages/keybay/pubspec.yaml)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
archive="$output/keybay-$version.tar.gz"
identity="$output/keybay-$version.canonical-content"
dart pub -C packages/keybay publish --to-archive="$archive"
python3 tool/compare_pub_archives.py --identity "$archive" "$identity"

# Receipts live in a digest-named directory per candidate subject. Only the
# current candidate's directory feeds this manifest; prior subjects' receipt
# directories are immutable history and are deliberately ignored here.
subject_digest="$(python3 tool/compare_pub_archives.py --digest "$archive")"
[[ "$subject_digest" =~ ^[0-9a-f]{64}$ ]]

shopt -s nullglob
receipt_args=()
android_receipt=false
for receipt in "doc/device-security-receipts/$subject_digest"/*.receipt.json; do
  receipt_args+=(--receipt "$receipt")
  case "$(basename "$receipt")" in
    android-*) android_receipt=true ;;
  esac
done

# Qualification policy (doc/device-security-suite.md): a minor/major release
# (x.y.0) requires the non-destructive Android baseline for this exact
# candidate. A patch release may ship without re-running it, but then the
# manifest must say so — the gate enforces honesty, not ceremony. Destructive
# scenarios are change-triggered; when a tamper receipt is present it also
# satisfies the baseline requirement, but it is never demanded here.
patch_component="${version##*.}"
policy_args=()
if [[ "$patch_component" == 0 ]]; then
  policy_args+=(--require-selection android-baseline)
elif [[ "$android_receipt" == false ]]; then
  policy_args+=(--unqualified \
    "Android device qualification was not re-run for this patch release")
fi

repository="${GITHUB_REPOSITORY:-danReynolds/keybay}"
commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
dart run tool/security_assurance/manifest.dart \
  --output "$output/release-assurance.json" \
  --subject core \
  --version "$version" \
  --ci-run-id "$ci_run_id" \
  --artifact "keybay-$version.tar.gz=$archive" \
  "${policy_args[@]}" \
  --unqualified "Physical iOS Keychain qualification has not been performed" \
  --unqualified "Entitled macOS Data Protection Keychain qualification has not been performed" \
  --unqualified "No independent third-party assessment has been completed" \
  --limitation "https://github.com/$repository/blob/$commit/doc/platforms/ios.md" \
  --limitation "https://github.com/$repository/blob/$commit/doc/platforms/macos.md" \
  "${receipt_args[@]}"

echo "Core assurance payload: $output"

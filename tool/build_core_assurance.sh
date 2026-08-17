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
# directories are immutable history and are deliberately ignored here. The
# canonical digest is by definition sha256 of the identity file just written,
# so hash those bytes rather than re-parsing the whole archive.
subject_digest="$(python3 -c \
  'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' \
  "$identity")"
[[ "$subject_digest" =~ ^[0-9a-f]{64}$ ]]

shopt -s nullglob
receipt_args=()
android_receipt=false
macos_receipt=false
for receipt in "doc/device-security-receipts/$subject_digest"/*.receipt.json; do
  receipt_args+=(--receipt "$receipt")
  # Platform coverage is judged from the receipt's own validated `selection`
  # field, never from a filename convention.
  selection="$(python3 -c \
    'import json,sys;print(json.load(open(sys.argv[1])).get("selection",""))' \
    "$receipt")"
  case "$selection" in
    android-*) android_receipt=true ;;
    macos-*) macos_receipt=true ;;
  esac
done

# Qualification policy (doc/device-security-suite.md): a minor/major release
# (x.y.0) requires the non-destructive Android baseline for this exact
# candidate; a patch release may ship with the gap declared instead. Every
# claimed configuration without a receipt gets a declared gap. The manifest
# validator enforces these same rules independently — this wrapper only
# assembles the arguments.
patch_component="${version##*.}"
policy_args=()
if [[ "$patch_component" == 0 ]]; then
  policy_args+=(--require-selection android-baseline)
elif [[ "$android_receipt" == false ]]; then
  policy_args+=(--unqualified \
    "Android device qualification was not re-run for this patch release")
fi
if [[ "$macos_receipt" == false ]]; then
  policy_args+=(--unqualified \
    "macOS native-host qualification was not re-run for this release")
fi

repository="${GITHUB_REPOSITORY:-danReynolds/keybay}"
commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
dart run tool/security_assurance/manifest.dart \
  --output "$output/release-assurance.json" \
  --subject core \
  --version "$version" \
  --ci-run-id "$ci_run_id" \
  --artifact "keybay-$version.tar.gz=$archive" \
  ${policy_args[@]+"${policy_args[@]}"} \
  --unqualified "Physical iOS Keychain qualification has not been performed" \
  --unqualified "Entitled macOS Data Protection Keychain qualification has not been performed" \
  --unqualified "No independent third-party assessment has been completed" \
  --limitation "https://github.com/$repository/blob/$commit/doc/platforms/ios.md" \
  --limitation "https://github.com/$repository/blob/$commit/doc/platforms/macos.md" \
  ${receipt_args[@]+"${receipt_args[@]}"}

echo "Core assurance payload: $output"

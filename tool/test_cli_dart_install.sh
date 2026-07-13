#!/usr/bin/env bash
# Hermetic smoke for Dart 3.10's `dart install` product channel. The core is
# still unpublished during development, so the disposable package copy points
# its exact dependency at this checkout; the final hosted-resolution proof is
# a Phase 3 external gate after first publication.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/keyway-dart-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cp -R "$repo/packages/keyway_cli" "$tmp/keyway_cli"
rm -rf "$tmp/keyway_cli/.dart_tool"

awk -v root="$repo" '
  $0 == "  keyway: 0.1.0" {
    print "  keyway:"
    print "    path: " root
    next
  }
  { print }
' "$tmp/keyway_cli/pubspec.yaml" > "$tmp/pubspec.yaml"
mv "$tmp/pubspec.yaml" "$tmp/keyway_cli/pubspec.yaml"

home="$tmp/home"
mkdir -p "$home"
HOME="$home" dart install \
  "keyway_cli@{path: $tmp/keyway_cli}"

installed="$(
  find "$home" \( -type f -o -type l \) \
    -path '*/Dart/install/bin/keyway' -perm -u+x -print -quit
)"
if [[ -z "$installed" ]]; then
  echo "dart install did not create a keyway executable under disposable HOME" >&2
  exit 1
fi
actual_version="$("$installed" --version)"
if [[ "$actual_version" != "0.1.0" ]]; then
  echo "installed keyway version was '$actual_version', expected '0.1.0'" >&2
  exit 1
fi
help_lines="$("$installed" --help | wc -l | tr -d ' ')"
if ((help_lines > 24)); then
  echo "installed keyway help used $help_lines lines, expected at most 24" >&2
  exit 1
fi

HOME="$home" dart uninstall keyway_cli
if [[ -e "$installed" ]]; then
  echo "dart uninstall left the keyway executable installed" >&2
  exit 1
fi
echo "CLI hermetic dart install passed"

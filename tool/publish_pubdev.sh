#!/usr/bin/env bash
# Publish one package through pub.dev OIDC, or reconcile an ambiguous prior
# success by proving the already-hosted archive has the exact tagged contents.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# != 1 ]]; then
  echo "usage: $0 PACKAGE_DIRECTORY" >&2
  exit 2
fi
package_directory="$1"
pubspec="$package_directory/pubspec.yaml"
if [[ ! -f "$pubspec" ]]; then
  echo "missing package pubspec: $pubspec" >&2
  exit 2
fi

package_name="$(awk '$1 == "name:" { print $2; exit }' "$pubspec")"
package_version="$(awk '$1 == "version:" { print $2; exit }' "$pubspec")"
[[ "$package_name" =~ ^[a-z][a-z0-9_]*$ ]]
[[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/keybay-pub.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT
expected="$tmp/$package_name-$package_version.expected.tar.gz"
hosted="$tmp/$package_name-$package_version.hosted.tar.gz"

# The pinned release SDK supports these hidden pub flags. Building once and
# uploading that same file removes any source/archive race.
dart pub -C "$package_directory" publish --to-archive="$expected"

archive_url="https://pub.dev/api/archives/$package_name-$package_version.tar.gz"
if ! status="$(curl --proto '=https' --tlsv1.2 --location --silent --show-error \
  --output "$hosted" --write-out '%{http_code}' "$archive_url")"; then
  echo "could not determine whether $package_name $package_version is hosted" >&2
  exit 1
fi

case "$status" in
  200)
    python3 "$repo_root/tool/compare_pub_archives.py" "$expected" "$hosted"
    echo "$package_name $package_version was already published exactly; nothing to upload"
    ;;
  404)
    dart pub -C "$package_directory" publish \
      --from-archive="$expected" --force
    ;;
  *)
    echo "pub.dev archive lookup returned HTTP $status" >&2
    exit 1
    ;;
esac

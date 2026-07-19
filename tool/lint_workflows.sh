#!/usr/bin/env bash
# Lint GitHub workflows with a checksum-pinned actionlint binary. actionlint
# delegates every embedded shell fragment to the runner's ShellCheck.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

version=1.7.12
case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    platform=linux_amd64
    checksum=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
    hash_program=sha256sum
    ;;
  Darwin:arm64)
    platform=darwin_arm64
    checksum=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f
    hash_program=shasum
    ;;
  Darwin:x86_64)
    platform=darwin_amd64
    checksum=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644
    hash_program=shasum
    ;;
  *)
    echo "unsupported actionlint platform: $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac
shellcheck_path="$(command -v shellcheck || true)"
if [[ -z "$shellcheck_path" ]]; then
  echo "ShellCheck is required so workflow shell fragments are linted" >&2
  exit 1
fi

tmp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/keybay-actionlint.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT
archive="$tmp/actionlint.tar.gz"
curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  --output "$archive" \
  "https://github.com/rhysd/actionlint/releases/download/v$version/actionlint_${version}_${platform}.tar.gz"
if [[ "$hash_program" = sha256sum ]]; then
  actual="$(sha256sum "$archive" | awk '{ print $1 }')"
else
  actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
fi
if [[ "$actual" != "$checksum" ]]; then
  echo "actionlint archive checksum mismatch" >&2
  exit 1
fi
tar -xzf "$archive" -C "$tmp" actionlint
"$tmp/actionlint" -shellcheck="$shellcheck_path"

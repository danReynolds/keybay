#!/usr/bin/env bash
# Load only ABI metadata from a relocated bundle; never enumerate a device.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# == 1 ]] || { echo "usage: $0 HARDWARE_BUNDLE_DIR" >&2; exit 2; }
bundle="$1"
python3 tool/cli_hardware_bundle.py verify "$bundle"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-hardware-load.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/relocated bundle" "$tmp/bin"
python3 - "$bundle" "$tmp/relocated bundle" <<'PY'
import sys, shutil
from pathlib import Path
sys.path.insert(0, 'tool')
from cli_hardware_bundle import verify
source, target = map(Path, sys.argv[1:])
for name in ['hardware.json', *verify(source)]: shutil.copy2(source/name, target/name)
PY
dart --suppress-analytics compile exe tool/probe_cli_hardware.dart -o "$tmp/relocated bundle/probe"
ln -s "$tmp/relocated bundle/probe" "$tmp/bin/probe"
env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH "$tmp/bin/probe"
case "$(uname -s)" in
  Darwin) crypto=libcrypto.3.dylib ;;
  Linux) crypto=libcrypto.so.3 ;;
  *) exit 69 ;;
esac
# A missing required member must be rejected without trying to load anything.
mv "$tmp/relocated bundle/$crypto" "$tmp/$crypto"
if python3 tool/cli_hardware_bundle.py verify "$tmp/relocated bundle"; then
  echo 'Incomplete native bundle was accepted' >&2; exit 1
fi
echo 'Relocated hardware bundle passed (no device access).'

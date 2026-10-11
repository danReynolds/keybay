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
# Simulate a previously valid bundle with a different libcbor soname. A rebuild
# must replace managed members instead of leaving a stale native companion.
python3 - "$bundle" "$tmp/rebuild/bundle" <<'PYTEST'
import json, sys
from pathlib import Path
sys.path.insert(0, 'tool')
from cli_hardware_bundle import install, verify
source, target = map(Path, sys.argv[1:])
install(source, target)
manifest = target / 'hardware.json'
receipt = json.loads(manifest.read_text())
old = next(name for name in receipt['files'] if name.startswith('libcbor.'))
renamed = 'libcbor.999.dylib' if old.endswith('.dylib') else 'libcbor.so.999'
(target / old).rename(target / renamed)
receipt['files'][renamed] = receipt['files'].pop(old)
manifest.write_text(json.dumps(receipt))
verify(target)
PYTEST
bash tool/build_cli_hardware.sh "$tmp/rebuild"
python3 tool/cli_hardware_bundle.py verify "$tmp/rebuild/bundle"
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

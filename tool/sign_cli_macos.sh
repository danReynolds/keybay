#!/usr/bin/env bash
# Sign a built bundle without relaxing hardened-runtime library validation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# == 3 ]] || { echo "usage: $0 BINARY DEVELOPER_ID_IDENTITY TEAM_ID" >&2; exit 2; }
binary="$1"
identity="$2"
team="$3"
bundle="$(dirname "$binary")"
python3 tool/cli_hardware_bundle.py verify "$bundle"
for library in "$bundle"/*.dylib; do
  codesign --force --sign "$identity" --timestamp "$library"
done
codesign --force --sign "$identity" --timestamp --options runtime \
  --identifier io.github.danreynolds.keybay.cli.module "$bundle/keybay.aot"
constraint="$(mktemp "${TMPDIR:-/tmp}/keybay-library-constraint.XXXXXX")"
trap 'rm -f "$constraint"' EXIT
python3 tool/cli_macos_constraint.py write "$bundle" "$constraint"
codesign --force --sign "$identity" --timestamp --options runtime \
  --enforce-constraint-validity --library-constraint "$constraint" \
  --identifier io.github.danreynolds.keybay.cli "$bundle/keybay-runtime"
codesign --force --sign "$identity" --timestamp --options runtime \
  --identifier io.github.danreynolds.keybay.cli "$binary"
# Signing changes Mach-O bytes; record their final signed digests.
python3 - "$bundle" <<'PY'
import hashlib, json, sys
from pathlib import Path
p = Path(sys.argv[1]) / 'hardware.json'
item = json.loads(p.read_text())
item['files'] = {n: hashlib.sha256((p.parent/n).read_bytes()).hexdigest() for n in item['files']}
p.write_text(json.dumps(item, indent=2) + '\n')
PY
bash tool/verify_macos_release.sh "$binary" "$team"

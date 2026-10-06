#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 KEYBAY_BINARY OUTPUT.tar.gz [HARDWARE_BUNDLE_DIR]" >&2
  exit 2
fi

binary="$1"
output="$2"
bundle="${3:-build/cli-hardware/bundle}"
if [[ ! -x "$binary" ]]; then
  echo "not an executable Keybay binary: $binary" >&2
  exit 2
fi
if [[ $# -ne 3 ]]; then
  bash tool/build_cli_hardware.sh
fi
python3 tool/cli_hardware_bundle.py verify "$bundle"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-cli-package.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cp "$binary" "$tmp/keybay"
chmod 0755 "$tmp/keybay"
cp packages/keybay_cli/LICENSE "$tmp/LICENSE"
cp packages/keybay_cli/README.md "$tmp/README.md"
python3 - "$bundle" "$tmp" <<'PY'
import sys, shutil
from pathlib import Path
sys.path.insert(0, 'tool')
from cli_hardware_bundle import verify, MANIFEST
source, target = map(Path, sys.argv[1:])
for name in [MANIFEST, *verify(source)]:
    shutil.copyfile(source / name, target / name)
PY
mkdir -p "$tmp/example/quickstart"
cp packages/keybay_cli/example/quickstart/README.md \
  "$tmp/example/quickstart/README.md"
cp packages/keybay_cli/example/quickstart/.env \
  "$tmp/example/quickstart/.env"
cp packages/keybay_cli/example/quickstart/app.sh \
  "$tmp/example/quickstart/app.sh"
chmod 0755 "$tmp/example/quickstart/app.sh"

mkdir -p "$(dirname "$output")"
python3 - "$bundle" "$binary" "$tmp" "$output" <<'PY'
import json, shutil, sys, tarfile
from pathlib import Path
bundle, binary, stage, output = map(Path, sys.argv[1:])
metadata = json.loads((bundle/'hardware.json').read_text())
names = ['keybay', 'LICENSE', 'README.md', 'example', 'hardware.json', *metadata['files']]
if metadata['platform'] == 'macos':
    for name in ('keybay-runtime', 'keybay.aot', 'LICENSE.dart'):
        source = binary.parent/name
        if source.is_symlink() or not source.is_file():
            raise SystemExit('macOS archives require the split runtime bundle; use tool/build_cli_release.sh')
        shutil.copy2(source, stage/name)
        names.append(name)
with tarfile.open(output, 'w:gz', format=tarfile.PAX_FORMAT) as archive:
    for name in names: archive.add(stage/name, arcname=name)
PY

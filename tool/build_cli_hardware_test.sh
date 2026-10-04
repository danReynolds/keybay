#!/usr/bin/env bash
# Build only: no device ceremony and no production vault access.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'This attended test build currently targets macOS.' >&2; exit 69; }
repo="$PWD"
output="$repo/build/hardware-tui-test"
mkdir -p "$output"
chmod 700 "$output"
keypass_source="$(python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import urljoin, urlparse, unquote
p = Path('.dart_tool/package_config.json').resolve()
package = next(x for x in json.loads(p.read_text())['packages'] if x['name'] == 'keypass')
print(unquote(urlparse(urljoin(p.as_uri(), package['rootUri'])).path))
PY
)"
revision=78cbf68a52b9e11f22434059fcde8069a97b2bad
[[ "$(git -C "$keypass_source" rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected Keypass revision' >&2; exit 1; }
[[ -z "$(git -C "$keypass_source" status --porcelain -- native/hardware)" ]] || { echo 'Modified Keypass native source' >&2; exit 1; }
cmake -S "$keypass_source/native/hardware" -B "$output/native" -DCMAKE_BUILD_TYPE=Release
cmake --build "$output/native" --parallel 4
ctest --test-dir "$output/native" --output-on-failure
cp "$output/native/libkeypass_hardware.dylib" "$output/libkeypass_hardware.dylib"
if [[ ! -f "$output/application-id" ]]; then
  python3 - "$output/application-id" <<'PY'
from pathlib import Path
import sys, uuid
Path(sys.argv[1]).write_text('keybay-cli-hardware-test-' + uuid.uuid4().hex)
PY
fi
application_id="$(cat "$output/application-id")"
[[ "$application_id" == keybay-cli-hardware-test-* ]] || exit 1
hardware_rp=io.github.danreynolds.keybay.cli.test
dart compile exe \
  -Dkeybay.application_id="$application_id" \
  -Dkeybay.hardware_rp_id="$hardware_rp" \
  packages/keybay_cli/tool/hardware_tui_harness.dart -o "$output/keybay-hardware-test"
cat > "$output/Start hardware test.command" <<'LAUNCH'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./keybay-hardware-test open
LAUNCH
chmod 700 "$output/Start hardware test.command"
python3 - "$output" "$revision" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
out=Path(sys.argv[1])
receipt={
 'keybayRevision': subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
 'keypassRevision': sys.argv[2],
 'keybayTrackedChanges': bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=no'], text=True).strip()),
 'applicationId': (out/'application-id').read_text(),
 'files': {name: hashlib.sha256((out/name).read_bytes()).hexdigest() for name in ['keybay-hardware-test','libkeypass_hardware.dylib']},
 'scope': 'Local macOS test with installed libfido2/OpenSSL; not a portable release',
}
(out/'build-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
PY
printf 'Ready: %s\n' "$output/Start hardware test.command"

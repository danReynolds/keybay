#!/usr/bin/env bash
# Build only: no device ceremony and no production vault access.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'This attended test build currently targets macOS.' >&2; exit 69; }
repo="$PWD"
output="$repo/build/hardware-tui-test"
mkdir -p "$output"
chmod 700 "$output"
revision="$(python3 -c 'import sys; sys.path.insert(0, "tool"); from cli_hardware_bundle import REVISION; print(REVISION)')"
bash tool/build_cli_hardware.sh "$output/hardware-build"
python3 tool/cli_hardware_bundle.py install "$output/hardware-build/bundle" "$output"
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
  packages/keybay_cli/tool/hardware_tui_harness.dart -o "$output/.keybay-hardware-test.build"
mv -f "$output/.keybay-hardware-test.build" "$output/keybay-hardware-test"
cat > "$output/Start hardware test.command" <<'LAUNCH'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./keybay-hardware-test open
LAUNCH
cat > "$output/Test command unlock.command" <<'LAUNCH'
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./keybay-hardware-test list
printf '\nPress Enter to close.'
read -r _
LAUNCH
chmod 700 "$output/Start hardware test.command" "$output/Test command unlock.command"
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
 'scope': 'Disposable macOS hardware test with bundled native dependencies; no device ceremony performed by this build',
 'hardwareBundle': json.loads((out/'hardware.json').read_text()),
}
(out/'build-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
PY
printf 'Ready: %s\n' "$output/Start hardware test.command"

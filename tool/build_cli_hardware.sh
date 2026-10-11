#!/usr/bin/env bash
# Builds the reviewed Keypass adapter and its relocatable dependency bundle.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
output="${1:-build/cli-hardware}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
for program in cmake pkg-config python3; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done
pkg-config --atleast-version=1.16 libfido2 || {
  echo 'libfido2 >= 1.16 is required; see doc/cli-hardware-packaging.md.' >&2; exit 69;
}
source="$(python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import urljoin, urlparse, unquote
p = Path('.dart_tool/package_config.json').resolve()
package = next(x for x in json.loads(p.read_text())['packages'] if x['name'] == 'keypass')
print(unquote(urlparse(urljoin(p.as_uri(), package['rootUri'])).path))
PY
)"
revision="$(python3 -c 'import sys; sys.path.insert(0, "tool"); from cli_hardware_bundle import REVISION; print(REVISION)')"
python3 tool/verify_keypass_source.py "$source"
native="$output/native-$revision"
cmp -s "$source/LICENSE" tool/licenses/keypass.txt || { echo 'Keypass license notice differs from the pinned source' >&2; exit 1; }
cmake -S "$source/native/hardware" -B "$native" -DCMAKE_BUILD_TYPE=Release
cmake --build "$native" --parallel 4
ctest --test-dir "$native" --output-on-failure
python3 tool/sync_cli_notices.py --check
cp packages/keybay_cli/THIRD_PARTY_NOTICES.txt "$output/notices.txt"
case "$(uname -s)" in
  Darwin) library=libkeypass_hardware.dylib ;;
  Linux) library=libkeypass_hardware.so ;;
  *) echo 'Hardware CLI bundling supports macOS and Linux.' >&2; exit 69 ;;
esac
# Reuse the dependency package's bundler; do not maintain a second native loader
# layout in Keybay. The pinned-source gate covers this script as well.
stage="$(mktemp -d "$output/.bundle.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
python3 "$source/hook/bundle.py" "$native/$library" "$stage/bundle" > "$stage/code-assets.json"
cp "$output/notices.txt" "$stage/bundle/THIRD_PARTY_NOTICES.txt"
python3 - "$stage" "$revision" <<'MANIFEST'
import hashlib, json, platform, sys
from pathlib import Path
output = Path(sys.argv[1])
names = json.loads((output/'code-assets.json').read_text())['libraries']
names.append('THIRD_PARTY_NOTICES.txt')
manifest = {'schema': 1, 'keypassRevision': sys.argv[2],
 'platform': 'macos' if sys.platform == 'darwin' else 'linux',
 'architecture': 'arm64' if platform.machine() in ('arm64', 'aarch64') else 'x64',
 'files': {name: hashlib.sha256((output/'bundle'/name).read_bytes()).hexdigest() for name in names}}
(output/'bundle/hardware.json').write_text(json.dumps(manifest, indent=2)+'\n')
MANIFEST
# Install only after verification; retire prior managed library names.
python3 tool/cli_hardware_bundle.py install "$stage/bundle" "$output/bundle"
mv "$stage/code-assets.json" "$output/code-assets.json"
python3 - "$output/hardware-build.json" <<'PY'
import json, platform, subprocess, sys
versions = {p: subprocess.check_output(['pkg-config', '--modversion', p], text=True).strip() for p in ('libfido2', 'libcbor', 'libcrypto')}
versions['nlohmann-json'] = '3.12.0'
versions['host'] = platform.platform()
versions['libc'] = platform.libc_ver()
with open(sys.argv[1], 'w') as f: json.dump(versions, f, indent=2); f.write('\n')
from pathlib import Path
p = Path(sys.argv[1]).parent / 'bundle/hardware.json'
item = json.loads(p.read_text()); item['build'] = versions
p.write_text(json.dumps(item, indent=2) + '\n')
PY
echo "Hardware bundle ready: $output/bundle"

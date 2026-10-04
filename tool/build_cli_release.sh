#!/usr/bin/env bash
# Local native release candidate. Signing/publication are separate operations.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $# == 1 ]] || { echo "usage: $0 OUTPUT_DIRECTORY" >&2; exit 2; }
mkdir -p "$1"
output="$(cd "$1" && pwd)"
bash tool/build_cli_hardware.sh "$output/hardware-build"
python3 tool/cli_hardware_bundle.py install "$output/hardware-build/bundle" "$output"
stage="$(mktemp -d "$output/.app-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
if [[ "$(uname -s)" == Darwin ]]; then
  dart run keybay:keybay_compile --aot-snapshot packages/keybay_cli/bin/keybay.dart -o "$stage/keybay.aot"
  install_name_tool -id @rpath/keybay.aot "$stage/keybay.aot"
  codesign --force --sign - "$stage/keybay.aot"
  sdk="$(dart --disable-dart-dev tool/dart_sdk_path.dart)"
  cp "$sdk/bin/dartaotruntime" "$stage/keybay-runtime"
  cp "$sdk/LICENSE" "$stage/LICENSE.dart"
  chmod 755 "$stage/keybay-runtime"
  clang -Wall -Wextra -Werror -O2 tool/cli_macos_launcher.c -o "$stage/keybay"
else
  dart run keybay:keybay_compile packages/keybay_cli/bin/keybay.dart -o "$stage/keybay"
fi
for file in "$stage"/*; do mv -f "$file" "$output/"; done
python3 - "$output/keybay" <<'SMOKE'
import subprocess, sys
subprocess.run([sys.argv[1], '--version'], check=True, timeout=20)
SMOKE
echo "Unsigned CLI candidate ready: $output"

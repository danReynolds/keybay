#!/usr/bin/env bash
# Only environment setup belongs here; the same SDK tests run natively in CI.
set -euo pipefail
lane="${1:-}"
[[ "$lane" == linux || "$lane" == flatpak ]] || exit 64
for program in docker python3 git; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done
docker info >/dev/null 2>&1 || { echo 'Docker is not running.' >&2; exit 69; }
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/keybay-linux-docker.XXXXXXXX")"
container=""
# Invoked by the EXIT trap; ShellCheck's nested-shell analysis misses it.
# shellcheck disable=SC2329
cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "$container" ]]; then
    docker rm -f "$container" >/dev/null || result=1
  fi
  rm -rf -- "$work" || result=1
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Copy only source inputs, including uncommitted work. Git excludes build
# products and caches; missing tracked files represent deliberate deletions.
python3 - "$repo" "$work/source" <<'PY'
from pathlib import Path
import shutil
import subprocess
import sys
root, target = map(Path, sys.argv[1:])
names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-co', '--exclude-standard', '-z', '--', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'tool', 'packages/keybay', 'packages/keybay_cli'])
for name in set(names.decode().split('\0')) - {''}:
    source = root / name
    if source.is_symlink():
        raise SystemExit(f'Source symlink is unsupported: {name}')
    if source.is_file():
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
PY
# No repository context is sent to the image builder.
docker build -t keybay-linux-regression:local - < "$repo/tool/linux_test.Dockerfile"
options=(--init)
if [[ "$lane" == flatpak ]]; then
  options+=(--security-opt seccomp=unconfined --security-opt systempaths=unconfined)
fi
container="$(docker create "${options[@]}" \
  --mount "type=bind,src=$work/source,dst=/src,readonly" \
  keybay-linux-regression:local bash -c '
    set -euo pipefail
    mkdir /build
    cp -R /src/. /build/
    chown -R keybay-test:keybay-test /build
    if [[ "$1" == flatpak ]]; then
      mkdir -p /run/dbus
      dbus-daemon --system --fork --nopidfile
    fi
    exec runuser -u keybay-test -- env KEYBAY_FLATPAK_REPORT=/build/flatpak.json bash -c '\''
      set -euo pipefail
      cd /build
      dart pub get --enforce-lockfile
      exec bash "tool/test_$1.sh"
    '\'' keybay-inner "$1"
  ' keybay-container "$lane")"
result=0
docker start -a "$container" || result=$?
if [[ "$lane" == flatpak && -n "${KEYBAY_REGRESSION_DIR:-}" ]]; then
  docker cp "$container:/build/flatpak.json" "$KEYBAY_REGRESSION_DIR/flatpak.json" || result=1
fi
exit "$result"

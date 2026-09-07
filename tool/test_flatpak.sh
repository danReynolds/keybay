#!/usr/bin/env bash
# Linux Flatpak qualification: the real sandbox, filtered bus, portal frontend,
# and Secret backend establish two installed applications' identities together.
# Nested Docker needs outer namespace/mount permissions; the checks below
# verify that each inner Flatpak still enforces its own sandbox.
#
# Ubuntu 24.04 prerequisites: flatpak, xdg-desktop-portal, gnome-keyring,
# dbus, libglib2.0-bin, python3, and a resolved Dart workspace. Requires sudo
# to create and remove a disposable OS account; never uses a personal keyring.
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
  exec bash "$(dirname "${BASH_SOURCE[0]}")/test_linux_docker.sh" flatpak
fi
if [[ -n "${KEYBAY_REGRESSION_DIR:-}" && -z "${KEYBAY_FLATPAK_REPORT:-}" ]]; then
  export KEYBAY_FLATPAK_REPORT="$KEYBAY_REGRESSION_DIR/flatpak.json"
fi

if [[ "${1:-}" == --session ]]; then
  work="${2:?missing disposable workspace}"
  app_a=dev.keybay.FlatpakQualificationA
  app_b=dev.keybay.FlatpakQualificationB
  runtime=org.freedesktop.Platform
  runtime_branch=25.08
  arch="$(flatpak --default-arch)"
  umask 077

  # Only the disposable provider receives this display. Neither sandboxed app
  # gets an X11 socket or access to the developer's desktop.
  Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp 3> "$work/display" > "$work/xvfb.log" 2>&1 &
  for (( attempt=0; attempt<50; attempt++ )); do
    [[ -s "$work/display" ]] && break
    sleep 0.1
  done
  [[ -s "$work/display" ]] || exit 69
  DISPLAY=":$(cat "$work/display")"
  export DISPLAY GDK_BACKEND=x11
  dbus-update-activation-environment DISPLAY GDK_BACKEND

  # This config selects a real backend without requiring a desktop shell.
  # The unlocked disposable keyring needs no visible authentication dialog.
  mkdir -p "$XDG_CONFIG_HOME/xdg-desktop-portal" "$work/keyring"
  cat > "$XDG_CONFIG_HOME/xdg-desktop-portal/portals.conf" <<'PORTALS'
[preferred]
default=none
org.freedesktop.impl.portal.Secret=gnome-keyring
PORTALS
  start_keyring() {
    printf '%s' keybay-disposable-ci-password | \
      gnome-keyring-daemon --foreground --unlock --components=secrets \
        --control-directory="$work/keyring" >> "$work/keyring.log" 2>&1 &
    keyring_pid=$!
    gdbus wait --session --timeout 15 org.freedesktop.secrets
  }
  start_portal() {
    /usr/libexec/xdg-desktop-portal >> "$work/portal.log" 2>&1 &
    portal_pid=$!
    gdbus wait --session --timeout 15 org.freedesktop.portal.Desktop
  }
  start_keyring
  start_portal

  flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user --noninteractive --assumeyes --no-related \
    flathub "$runtime//$runtime_branch"

  # AOT compilation already happened against the reviewed workspace. Package
  # that identical executable twice; neither app gets host files, the raw
  # Secret Service name, network, or an unfiltered session-bus socket.
  for app in "$app_a" "$app_b"; do
    build="$work/$app"
    mkdir -p "$build/files/bin"
    install -m 0755 "$work/flatpak-harness" "$build/files/bin/keybay-harness"
    cat > "$build/metadata" <<METADATA
[Application]
name=$app
runtime=$runtime/$arch/$runtime_branch
command=keybay-harness
METADATA
    flatpak build-finish --command=keybay-harness "$build"
    flatpak build-export "$work/repo" "$build" stable
  done
  flatpak remote-add --user --no-gpg-verify keybay-qualification "$work/repo"
  flatpak install --user --noninteractive --assumeyes --no-related --no-deps \
    keybay-qualification "$app_a//stable" "$app_b//stable"

  python3 - "$work" "$app_a" "$app_b" "$runtime" "$runtime_branch" <<'PY'
import json
import os
import re
import secrets
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

work, app_a, app_b, runtime, branch = sys.argv[1:]

def run(app, command, *args, environment=None):
    if environment:
        # Set these inside the established sandbox: Flatpak must not sanitize
        # the attempted forgery before the process being tested sees it.
        invocation = ['flatpak', 'run', '--user', '--command=/usr/bin/env', app,
                      *[f'{key}={value}' for key, value in environment.items()],
                      '/app/bin/keybay-harness', command, *args]
    else:
        invocation = ['flatpak', 'run', '--user', app, command, *args]
    try:
        result = subprocess.run(
            invocation,
            capture_output=True, text=True, timeout=90,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit(f'{command}: timed out') from None
    if result.returncode != 0:
        # Never echo harness output: portal challenge responses are sensitive.
        raise SystemExit(f'{command}: failed with status {result.returncode}')
    return result.stdout.strip()

def forged_environment(peer):
    return {
        'FLATPAK_ID': peer,
        'HOME': '/tmp/keybay-forged-home',
        'XDG_DATA_HOME': '/tmp/keybay-forged-data',
    }

sandbox_states = {app: json.loads(run(app, 'sandbox-state')) for app in (app_a, app_b)}
for state in sandbox_states.values():
    if (state['effective_uid'] != os.geteuid() or os.geteuid() == 0
            or int(state['effective_capabilities'], 16) != 0
            or state['no_new_privs'] != 1 or state['seccomp_mode'] != 2):
        raise SystemExit('inner sandbox: unexpected identity, capabilities, or syscall restrictions')
    for field, name in (('mount_namespace', 'mnt'), ('pid_namespace', 'pid')):
        if (not re.fullmatch(rf'{name}:\[[0-9]+\]', state[field])
                or state[field] == os.readlink(f'/proc/self/ns/{name}')):
            raise SystemExit('inner sandbox: namespace isolation missing')
print('PASS: inner Flatpak namespaces, syscall filter, and unprivileged identity')

nonce = secrets.token_hex(32)
def first_challenges(app):
    # No earlier request has provisioned this fresh application's secret.
    # Separate Flatpak processes must converge on the same retained value.
    with ThreadPoolExecutor(max_workers=4) as pool:
        values = list(pool.map(lambda _: run(app, 'portal-challenge', nonce), range(4)))
    if not all(re.fullmatch(r'[0-9a-f]{64}', value) for value in values):
        raise SystemExit('portal first use: malformed challenge result')
    if len(set(values)) != 1:
        raise SystemExit('portal first use: concurrent requests returned different secrets')
    return values[0]

first = first_challenges(app_a)
other = first_challenges(app_b)
again = run(app_a, 'portal-challenge', nonce)
forged = run(app_b, 'portal-challenge', nonce, environment=forged_environment(app_a))
if not all(re.fullmatch(r'[0-9a-f]{64}', value) for value in (first, again, other, forged)):
    raise SystemExit('portal challenge: malformed result')
if first != again or first == other or other != forged:
    raise SystemExit('portal challenge: continuity or per-application isolation failed')
del first, again, other, forged, nonce
print('PASS: portal secret continuity, distinct application secrets, and forged identity rejection')

run(app_a, 'exercise')
run(app_a, 'reopen')
run(app_b, 'exercise')
run(app_b, 'reopen')
root_a = run(app_a, 'file-root')
root_b = run(app_b, 'file-root')
if root_a == root_b or not all(path.startswith('/') for path in (root_a, root_b)):
    raise SystemExit('private file roots: malformed or equal')
run(app_b, 'verify-peer', root_a)
run(app_a, 'verify-peer', root_b)
run(app_a, 'verify-environment', app_a, app_b, root_a,
    environment=forged_environment(app_b))
run(app_b, 'verify-environment', app_b, app_a, root_b,
    environment=forged_environment(app_a))
# These routing probes establish manifest-level denial while the host Secret
# Service is running. The separate unavailable check below exercises Keybay's
# failure path after portal removal; neither probe reads any provider secret.
run(app_a, 'raw-service-denied')
run(app_b, 'raw-service-denied')
print('PASS: SDK lifecycle, reset/backup policy, and peer file isolation')
print('PASS: forged environment cannot select a store; raw Secret Service routing is denied')

def output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()

receipt = {
    'profile': 'linux.flatpak.secret-portal-file.v1',
    'application_ids': [app_a, app_b],
    'flatpak': output('flatpak', '--version'),
    'packages': output('dpkg-query', '-W', '-f=${Package} ${Version}\n',
                       'xdg-desktop-portal', 'gnome-keyring'),
    'runtime': f'{runtime}//{branch}',
    'runtime_commit': output('flatpak', 'info', '--user', '--show-commit', f'{runtime}//{branch}'),
    'permissions': {
        app: output('flatpak', 'info', '--user', '--show-permissions', app)
        for app in (app_a, app_b)
    },
    'portal_secret_continuity': True,
    'concurrent_first_portal_secret_continuity': True,
    'distinct_portal_secrets': True,
    'private_file_isolation': True,
    'forged_environment_ignored': True,
    'direct_secret_service_denied': True,
    'sdk_lifecycle_and_reset_backup_policy': True,
    'inner_sandbox_verified': True,
    'sandbox_states': sandbox_states,
}
with open(f'{work}/receipt.json', 'w', encoding='utf-8') as target:
    json.dump(receipt, target, indent=2)
    target.write('\n')
PY

  python3 "$work/flatpak_prompt_checks.py" "$work" "$app_a" "$app_b"

  # Reopen existing stores after restarting the actual provider processes.
  # This proves continuity from persisted keyring state, beyond daemon memory.
  kill "$portal_pid"
  wait "$portal_pid" || true
  kill "$keyring_pid"
  wait "$keyring_pid" || true
  start_keyring
  start_portal
  python3 - "$app_a" "$app_b" <<'PY'
import subprocess
import sys

for app in sys.argv[1:]:
    try:
        result = subprocess.run(
            ['flatpak', 'run', '--user', app, 'reopen'],
            capture_output=True, timeout=90,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit('provider restart continuity check timed out') from None
    if result.returncode != 0:
        raise SystemExit('provider restart continuity check failed')
print('PASS: both stores reopen after portal and keyring restart')
PY

  # The higher-precedence D-Bus service file deliberately disables reactivation
  # after this explicit frontend exits. The real Secret Service stays alive.
  kill "$portal_pid"
  wait "$portal_pid" || true
  # Confirm the alternative provider is still reachable on the host bus.
  # This is a credential-free routing check and produces no report payload.
  gdbus call --session --dest org.freedesktop.secrets \
    --object-path /org/freedesktop/secrets \
    --method org.freedesktop.DBus.Peer.Ping > /dev/null
  python3 - "$work/receipt.json" "$app_a" <<'PY'
import json
import subprocess
import sys
try:
    result = subprocess.run(
        ['flatpak', 'run', '--user', sys.argv[2], 'unavailable'],
        capture_output=True, timeout=90,
    )
except subprocess.TimeoutExpired:
    raise SystemExit('unavailable portal check timed out') from None
if result.returncode != 0:
    raise SystemExit('unavailable portal check failed')
with open(sys.argv[1], encoding='utf-8') as source:
    receipt = json.load(source)
receipt['provider_restart_continuity'] = True
receipt['portal_unavailable_no_fallback'] = True
with open(sys.argv[1], 'w', encoding='utf-8') as target:
    json.dump(receipt, target, indent=2)
    target.write('\n')
print('PASS: unavailable portal fails without Secret Service fallback')
PY
  exit 0
fi

for program in dart flatpak dbus-run-session gnome-keyring-daemon gdbus python3 sudo pkill pgrep Xvfb xdotool dbus-update-activation-environment; do
  command -v "$program" > /dev/null || {
    echo "missing prerequisite: $program" >&2
    exit 69
  }
done
[[ -x /usr/libexec/xdg-desktop-portal ]] || {
  echo 'expected Ubuntu portal frontend at /usr/libexec/xdg-desktop-portal' >&2
  exit 69
}
sudo -n true || { echo 'Flatpak tests need passwordless sudo for a disposable account.' >&2; exit 69; }

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
(cd "$repo/packages/keybay" && dart test test/v2_linux_secret_portal_test.dart test/v2_linux_secret_portal_dbus_test.dart)
work="$(mktemp -d /tmp/keybay-flatpak.XXXXXXXX)"
test_user="keybay-flatpak-$$"
test_uid=
cleanup() {
  local failed=0 remaining=0 status=0 attempt
  if [[ -n "$test_uid" ]]; then
    sudo -n pkill -TERM -u "$test_uid" 2>/dev/null || true
    sudo -n pkill -KILL -u "$test_uid" 2>/dev/null || true
    # Signal delivery is asynchronous. Bound the wait before removing the
    # account, and distinguish "no processes" from an inspection failure.
    for (( attempt=0; attempt<50; attempt++ )); do
      if sudo -n pgrep -u "$test_uid" > /dev/null; then
        remaining=1
        sleep 0.1
      else
        status=$?
        [[ "$status" == 1 ]] || failed=1
        remaining=0
        break
      fi
    done
    [[ "$remaining" == 0 ]] || failed=1
    if id "$test_user" > /dev/null 2>&1; then
      sudo -n userdel "$test_user" 2>/dev/null || failed=1
    fi
    if id "$test_user" > /dev/null 2>&1; then
      failed=1
    fi
  fi
  sudo -n rm -rf -- "$work" || failed=1
  [[ ! -e "$work" ]] || failed=1
  if [[ "$failed" != 0 ]]; then
    echo 'Flatpak qualification cleanup could not be verified.' >&2
  fi
  return "$failed"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
dart compile exe "$repo/packages/keybay/test/support/flatpak_native_harness.dart" \
  -o "$work/flatpak-harness"
cp "${BASH_SOURCE[0]}" "$work/run.sh"
cp "$repo/tool/flatpak_prompt_checks.py" "$work/flatpak_prompt_checks.py"
sudo -n useradd --create-home --home-dir "$work/home" --shell /bin/bash "$test_user"
test_uid="$(id -u "$test_user")"
sudo -n chown -R "$test_user:$test_user" "$work"
sudo -n -H -u "$test_user" mkdir -p -m 0700 \
  "$work/data" "$work/config" "$work/runtime" "$work/cache"
sudo -n -H -u "$test_user" mkdir -p "$work/data/dbus-1/services"
sudo -n -H -u "$test_user" tee "$work/data/dbus-1/services/org.freedesktop.portal.Desktop.service" > /dev/null <<'SERVICE'
[D-BUS Service]
Name=org.freedesktop.portal.Desktop
Exec=/bin/false
SERVICE
sudo -n -H -u "$test_user" env \
  XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" \
  XDG_CACHE_HOME="$work/cache" XDG_RUNTIME_DIR="$work/runtime" \
  XDG_CURRENT_DESKTOP=KeybayQualification \
  dbus-run-session -- bash "$work/run.sh" --session "$work"
# Hold only the public receipt while removing the account, processes and data.
# A failed cleanup must never produce a passing qualification artifact.
receipt="$(sudo -n cat "$work/receipt.json")"
cleanup
trap - EXIT
if [[ -n "${KEYBAY_FLATPAK_REPORT:-}" ]]; then
  printf '%s\n' "$receipt" | python3 -c '
import json, sys
receipt = json.load(sys.stdin)
receipt["cleanup_verified"] = True
json.dump(receipt, sys.stdout, indent=2)
print()
' > "$KEYBAY_FLATPAK_REPORT"
fi
python3 -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1]).get("prompted_cancellation_recovery") is True else 1)' "$receipt"

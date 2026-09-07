#!/usr/bin/env bash
# Opt-in signed SDK lifecycle and continuity across development builds.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 69
for program in flutter xcodebuild codesign python3; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done
[[ "${KEYBAY_APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || {
  echo 'Set KEYBAY_APPLE_TEAM_ID for the opt-in signing lane.' >&2
  exit 69
}
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$REPO/example_flutter"
HARNESS_BUNDLE_ID=dev.keybay.securityharness
XCCONFIG="$HARNESS/macos/Runner/Configs/AppInfo.xcconfig"
ENTITLEMENTS="$HARNESS/macos/Runner/DebugProfile.entitlements"
OVERLAY_BACKUP=""
mkdir -p "$REPO/build"
EVIDENCE="${KEYBAY_REGRESSION_DIR:-$(mktemp -d "$REPO/build/macos-signed.XXXXXXXX")}"
echo "Signed macOS evidence: $EVIDENCE"

apply_entitled_overlay() {
  local team="$KEYBAY_APPLE_TEAM_ID" backup
  backup=$(mktemp -d "${TMPDIR:-/tmp}/keybay-macos-overlay.XXXXXXXX")
  if ! cp "$XCCONFIG" "$ENTITLEMENTS" "$backup/"; then
    rm -rf -- "$backup"
    return 1
  fi
  OVERLAY_BACKUP="$backup"
  printf '\nDEVELOPMENT_TEAM = %s\nCODE_SIGN_IDENTITY = Apple Development\n' \
    "$team" >>"$XCCONFIG"
  python3 - "$ENTITLEMENTS" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    values = plistlib.load(source)
values['keychain-access-groups'] = ['$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)']
with open(path, 'wb') as target:
    plistlib.dump(values, target)
PY
  # Regenerate Flutter's ephemeral xcode inputs, then provision (idempotent;
  # creates the managed profile on first run — needs the account's PLA signed).
  (cd "$HARNESS" && flutter build macos --debug --config-only >/dev/null) &&
    (cd "$HARNESS/macos" && xcodebuild build -workspace Runner.xcworkspace \
      -scheme Runner -configuration Debug -destination 'platform=macOS' \
      -derivedDataPath "$HARNESS/build/macos" \
      -allowProvisioningUpdates -quiet) &&
    verify_entitled_build "$team" provisioned
}

verify_entitled_build() {
  local team="$1"
  local app="$HARNESS/build/macos/Build/Products/Debug/example_flutter.app"
  codesign --verify --deep --strict \
    -R "=anchor apple generic and identifier \"$HARNESS_BUNDLE_ID\" and certificate leaf[subject.OU] = \"$team\"" \
    "$app" || return 1
  python3 - "$app" "$team.$HARNESS_BUNDLE_ID" "$EVIDENCE/$2-signature.json" <<'PY'
import hashlib, json, pathlib, plistlib, subprocess, sys
app, expected, output = sys.argv[1:]
values = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', app], stderr=subprocess.DEVNULL))
if (values.get("com.apple.application-identifier") != expected or
    values.get("keychain-access-groups") != [expected] or
    values.get("com.apple.security.app-sandbox") is not True):
    raise SystemExit("signed macOS entitlement verification failed")
details = subprocess.run(['codesign', '-dv', '--verbose=4', app], capture_output=True, text=True, check=True)
fields = dict(line.split('=', 1) for line in (details.stdout + details.stderr).splitlines() if '=' in line)
if not fields.get('CDHash'):
    raise SystemExit('missing signed code-directory hash')
with open(pathlib.Path(app, 'Contents/Info.plist'), 'rb') as source:
    info = plistlib.load(source)
binary = pathlib.Path(app, 'Contents/MacOS', info['CFBundleExecutable'])
with open(output, 'w') as target:
    json.dump({'strict_apple_signature_verified': True, 'application_identifier': expected,
               'keychain_access_groups': values['keychain-access-groups'], 'sandboxed': True,
               'cdhash': fields['CDHash'], 'build_number': str(info['CFBundleVersion']),
               'executable_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}, target, indent=2)
    target.write('\n')
PY
}

restore_entitled_overlay() {
  [[ -n "$OVERLAY_BACKUP" ]] || return 0
  local failed=0
  cp "$OVERLAY_BACKUP/AppInfo.xcconfig" "$XCCONFIG" || failed=1
  cp "$OVERLAY_BACKUP/DebugProfile.entitlements" "$ENTITLEMENTS" || failed=1
  if [[ $failed -ne 0 ]]; then
    echo "Could not restore signing configuration; backup retained at $OVERLAY_BACKUP" >&2
    return 1
  fi
  rm -rf -- "$OVERLAY_BACKUP" || return 1
  OVERLAY_BACKUP=""
}


cleanup() {
  local result=$?
  trap - EXIT
  restore_entitled_overlay || result=1
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
apply_entitled_overlay
run_test() {
  local phase="$1" target="$2"
  shift 2
  (cd "$HARNESS" && flutter test "$target" -d macos --reporter expanded \
    --file-reporter "json:$EVIDENCE/$phase-tests.jsonl" "$@")
  # Flutter test rebuilds. Verify the actual tested app after every phase.
  verify_entitled_build "$KEYBAY_APPLE_TEAM_ID" "$phase"
}
run_test baseline integration_test/keybay_v2_macos_entitled_test.dart
for phase in seed reopen; do
  number=101
  [[ "$phase" == seed ]] || number=102
  printf '\nFLUTTER_BUILD_NUMBER = %s\n' "$number" >> "$XCCONFIG"
  run_test "$phase" integration_test/keybay_v2_macos_continuity_test.dart \
    "--dart-define=KEYBAY_MACOS_CONTINUITY_PHASE=$phase"
done
python3 - "$EVIDENCE" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
seed, reopen = [json.loads((root / (phase + '-signature.json')).read_text()) for phase in ('seed', 'reopen')]
if seed['build_number'] != '101' or reopen['build_number'] != '102' or seed['cdhash'] == reopen['cdhash']:
    raise SystemExit('continuity requires distinct signed builds 101 and 102')
for phase in ('baseline', 'seed', 'reopen'):
    events = [json.loads(line) for line in (root / (phase + '-tests.jsonl')).read_text().splitlines() if line.strip()]
    expected = ('entitled macOS V2 profile is isolated and resettable' if phase == 'baseline' else
                'signed macOS ' + phase + ' phase preserves its V2 store across replacement')
    ids = {event['test']['id'] for event in events if event.get('type') == 'testStart' and event['test']['name'].endswith(expected)}
    completed = [event for event in events if event.get('type') == 'testDone' and event.get('testID') in ids]
    if (len(ids) != 1 or len(completed) != 1 or any(event.get('result') != 'success' or event.get('skipped') for event in completed)
        or not any(event.get('type') == 'done' and event.get('success') is True for event in events)):
        raise SystemExit('missing, skipped or failed signed test results: ' + phase)
print('PASS: signed baseline, distinct-build passphrase continuity, and reset cleanup')
PY

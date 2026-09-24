#!/usr/bin/env bash
# Builds Keybay Demo and installs it for dogfooding. The app's identity stays
# fixed, so its store survives reinstalls and upgrades on the same device.
#
#   KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/install.sh ios [DEVICE]
#   ./tool/install.sh android [SERIAL]
#   KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/install.sh macos
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

usage() {
  sed -n '5,7p' "$0" | sed 's/^# //' >&2
  exit 64
}

# Apple signing comes from the environment, never from committed files.
use_apple_team() {
  [[ "${KEYBAY_APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || {
    echo 'Set KEYBAY_APPLE_TEAM_ID to your 10-character Apple team ID.' >&2
    exit 64
  }
  signing="$(mktemp "${TMPDIR:-/tmp}/keybay-demo-signing.XXXXXX")"
  trap 'rm -f "$signing"' EXIT
  printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\nCODE_SIGN_IDENTITY = Apple Development\n' \
    "$KEYBAY_APPLE_TEAM_ID" >"$signing"
  export XCODE_XCCONFIG_FILE="$signing"
}

# The one connected physical iOS device, unless a device was named.
ios_device() {
  local listing
  listing="$(mktemp "${TMPDIR:-/tmp}/keybay-demo-devices.XXXXXX")"
  xcrun devicectl list devices --json-output "$listing" >/dev/null
  trap 'rm -f "$listing"; trap - RETURN' RETURN
  python3 - "$listing" <<'PY'
import json, sys
devices = [d for d in json.load(open(sys.argv[1]))['result']['devices']
           if d.get('hardwareProperties', {}).get('platform') == 'iOS'
           and d.get('connectionProperties', {}).get('pairingState') == 'paired'
           and d.get('deviceProperties', {}).get('bootState') == 'booted']
if len(devices) != 1:
    names = ', '.join(d['deviceProperties']['name'] for d in devices) or 'none'
    sys.exit(f'Name one iOS device to install on (found: {names}).')
print(devices[0]['identifier'])
PY
}

platform="${1:-}"
device="${2:-}"
[[ -n "$platform" ]] || usage
flutter pub get --enforce-lockfile >/dev/null

case "$platform" in
  ios)
    use_apple_team
    [[ -n "$device" ]] || device="$(ios_device)"
    flutter build ios --release
    xcrun devicectl device install app --device "$device" \
      build/ios/iphoneos/Runner.app
    ;;
  android)
    flutter build apk --release
    adb ${device:+-s "$device"} install -r \
      build/app/outputs/flutter-apk/app-release.apk
    ;;
  macos)
    use_apple_team
    # The Keychain group entitlement needs a provisioning profile, which
    # xcodebuild can create; flutter build macos cannot.
    flutter build macos --release --config-only
    xcodebuild build -workspace macos/Runner.xcworkspace -scheme Runner \
      -configuration Release -destination 'platform=macOS' \
      -derivedDataPath build/macos -allowProvisioningUpdates -quiet
    mkdir -p "$HOME/Applications"
    ditto "build/macos/Build/Products/Release/Keybay Demo.app" \
      "$HOME/Applications/Keybay Demo.app"
    open "$HOME/Applications/Keybay Demo.app"
    ;;
  *)
    usage
    ;;
esac

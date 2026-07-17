#!/usr/bin/env bash
# The FULL end-to-end matrix, one command: every supported platform exercised
# against its REAL keystore (simulator/emulator for mobile), repeatably.
#
#   ./tool/test_e2e.sh              # all legs except entitled-macOS
#   ./tool/test_e2e.sh --entitled   # + the DP-success leg (needs a signing
#                                   #   identity; temporarily applies the
#                                   #   Keychain Sharing overlay, restores it)
#
# Legs (each = the real platform, not a mock):
#   unit        hermetic tier: crypto vectors, container fuzz, resolver fakes
#   macos-cli   real login Keychain via SecItem (dart test, this machine)
#   linux       real gnome-keyring under D-Bus (Docker)
#   macos-app   file scheme inside a real sandboxed .app (Flutter harness)
#   ios         native DP items on an iPhone simulator (Flutter harness)
#   android     hardware-Keystore-wrapped file scheme on an emulator (harness)
#   entitled    (--entitled) native DP items in a signed, entitled macOS app
#
# Requires: macOS dev box with Xcode (+ an iPhone simulator runtime), the
# Android SDK (+ one AVD), Flutter, Docker.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$REPO/example_flutter"
ANDROID_SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_SDK/platform-tools/adb"
ENTITLED=0
[[ "${1:-}" == "--entitled" ]] && ENTITLED=1

declare -a RESULTS=()
STARTED_EMULATOR=0
ANDROID_SERIAL=""
INTERRUPTED=0
INTERRUPT_SIGNAL=""

note() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
record() { RESULTS+=("$1|$2"); }

handle_interrupt() {
  INTERRUPTED=1
  INTERRUPT_SIGNAL="$1"
}
trap 'handle_interrupt INT' INT
trap 'handle_interrupt TERM' TERM

run_leg() { # name, command...
  local name="$1" rc=0; shift
  note "$name"
  INTERRUPTED=0
  INTERRUPT_SIGNAL=""
  "$@" || rc=$?
  if [[ $INTERRUPTED -eq 1 || $rc -eq 130 || $rc -eq 143 ]]; then
    record "$name" "INTERRUPTED"
    printf '\nInterrupted during %s (%s); no pass result was recorded.\n' \
      "$name" "${INTERRUPT_SIGNAL:-exit $rc}" >&2
    exit 130
  fi
  if [[ $rc -eq 0 ]]; then record "$name" "PASS"; else record "$name" "FAIL"; fi
}

# --- device lifecycle ----------------------------------------------------------

boot_ios_sim() {
  IOS_UDID=$(xcrun simctl list devices available | grep -m1 -E "iPhone" \
    | grep -oE '[0-9A-F-]{36}' || true)
  [[ -z "$IOS_UDID" ]] && return 1
  xcrun simctl boot "$IOS_UDID" 2>/dev/null || true # already booted is fine
  local waited=0
  until xcrun simctl list devices booted | grep -q "$IOS_UDID"; do
    sleep 2; waited=$((waited + 2)); [[ $waited -ge 120 ]] && return 1
  done
}

boot_android_emu() {
  local emu_pid=""
  ANDROID_SERIAL=$("$ADB" devices | awk '/^emulator-/ && $2 == "device" {print $1; exit}')
  if [[ -z "$ANDROID_SERIAL" ]]; then
    local avd
    avd=$("$ANDROID_SDK/emulator/emulator" -list-avds | head -1)
    [[ -z "$avd" ]] && { echo "no AVD found"; return 1; }
    # Reset a possibly-stale adb server (e.g. left over from a prior leg that
    # killed its emulator) so the fresh instance is seen.
    "$ADB" kill-server >/dev/null 2>&1 || true
    "$ADB" start-server >/dev/null 2>&1 || true
    "$ANDROID_SDK/emulator/emulator" -avd "$avd" -no-window -no-snapshot \
      -no-audio -no-boot-anim -gpu swiftshader_indirect \
      >/tmp/e2e-emulator.log 2>&1 &
    emu_pid=$!
    STARTED_EMULATOR=$emu_pid
    disown "$emu_pid" 2>/dev/null || true
  fi
  local waited=0
  until [[ -n "$ANDROID_SERIAL" ]] &&
    [[ "$("$ADB" -s "$ANDROID_SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]] &&
    "$ADB" -s "$ANDROID_SERIAL" shell pm path android >/dev/null 2>&1; do
    # Fail fast if an emulator we launched died before booting, instead of
    # waiting out the full timeout.
    if [[ -n "$emu_pid" ]] && ! kill -0 "$emu_pid" 2>/dev/null; then
      echo "emulator exited before boot (see /tmp/e2e-emulator.log)"
      return 1
    fi
    sleep 3
    waited=$((waited + 3))
    [[ $waited -ge 420 ]] && { echo "emulator boot timed out"; return 1; }
    ANDROID_SERIAL=$("$ADB" devices | awk '/^emulator-/ && $2 == "device" {print $1; exit}')
  done
  local flutter_devices
  flutter_devices=$(flutter devices --machine --device-timeout 30) || return 1
  if [[ "$flutter_devices" != *"$ANDROID_SERIAL"* ]]; then
    echo "Flutter did not discover $ANDROID_SERIAL after Android boot"
    return 1
  fi
}

# --- entitled-macOS overlay (applied temporarily, always restored) --------------

XCCONFIG="$HARNESS/macos/Runner/Configs/AppInfo.xcconfig"
ENTITLEMENTS="$HARNESS/macos/Runner/DebugProfile.entitlements"
OVERLAY_BACKUP=""

apply_entitled_overlay() {
  local team
  team=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | grep -oE 'OU=[A-Z0-9]{10}' | head -1 | cut -d= -f2)
  [[ -z "$team" ]] && { echo "no Apple Development identity/team found"; return 1; }
  OVERLAY_BACKUP=$(mktemp -d)
  cp "$XCCONFIG" "$ENTITLEMENTS" "$OVERLAY_BACKUP/" \
    || { echo "overlay backup copy failed; leaving configs untouched"; return 1; }
  printf '\nDEVELOPMENT_TEAM = %s\nCODE_SIGN_IDENTITY = Apple Development\n' \
    "$team" >>"$XCCONFIG"
  /usr/bin/sed -i '' \
    's|<key>com.apple.security.network.server</key>|<key>keychain-access-groups</key><array><string>$(AppIdentifierPrefix)com.example.exampleFlutter</string></array><key>com.apple.security.network.server</key>|' \
    "$ENTITLEMENTS"
  # Regenerate Flutter's ephemeral xcode inputs, then provision (idempotent;
  # creates the managed profile on first run — needs the account's PLA signed).
  (cd "$HARNESS" && flutter build macos --debug --config-only >/dev/null) &&
    (cd "$HARNESS/macos" && xcodebuild build -workspace Runner.xcworkspace \
      -scheme Runner -configuration Debug -destination 'platform=macOS' \
      -allowProvisioningUpdates -quiet)
}

restore_entitled_overlay() {
  [[ -n "$OVERLAY_BACKUP" ]] || return 0
  local failed=0
  cp "$OVERLAY_BACKUP/AppInfo.xcconfig" "$XCCONFIG" || failed=1
  cp "$OVERLAY_BACKUP/DebugProfile.entitlements" "$ENTITLEMENTS" || failed=1
  [[ $failed -eq 0 ]] && rm -rf "$OVERLAY_BACKUP" # keep the backup on failure
  OVERLAY_BACKUP=""
}

cleanup_e2e() {
  restore_entitled_overlay
  if [[ "$STARTED_EMULATOR" != "0" ]]; then
    if [[ -n "$ANDROID_SERIAL" ]]; then
      "$ADB" -s "$ANDROID_SERIAL" emu kill >/dev/null 2>&1 || true
    fi
    kill "$STARTED_EMULATOR" >/dev/null 2>&1 || true
    wait "$STARTED_EMULATOR" >/dev/null 2>&1 || true
  fi
}
trap cleanup_e2e EXIT

# --- the legs -------------------------------------------------------------------

leg_unit() {
  cd "$REPO" && dart format --output=none --set-exit-if-changed . &&
    dart analyze --fatal-infos &&
    (cd packages/keybay && dart test -x integration) &&
    (cd packages/keybay_cli && dart test -x integration) && ./tool/test_cli.sh
}
leg_macos_cli() {
  cd "$REPO" &&
    (cd packages/keybay &&
      KEYBAY_INTEGRATION=1 dart test test/keychain_integration_test.dart) &&
    ./tool/test_cli_storage.sh
}
leg_linux() { cd "$REPO" && ./tool/test_linux.sh; }
leg_macos_app() {
  # Ad-hoc signing gives each rebuild a different Keychain trust identity. A
  # persisted key from an earlier harness build can therefore require an ACL
  # prompt and hang a non-interactive run. This fixed com.example store is test
  # data, so remove both halves before and after the leg to keep it repeatable.
  local app_id="com.example.keybayHarness.file"
  local app_dir="$HOME/Library/Containers/com.example.exampleFlutter/Data/Library/Application Support/$app_id"
  security delete-generic-password -s "$app_id" -a store-key \
    >/dev/null 2>&1 || true
  rm -rf -- "$app_dir"
  local rc=0
  # Distinct APP_ID from the entitled leg — same machine, different scheme, so
  # they must not share an app-support dir (the migration guard would fire).
  cd "$HARNESS" && flutter test integration_test/keybay_test.dart \
    -d macos --dart-define=APP_ID="$app_id" \
    --dart-define=EXPECT_SCHEME=file --dart-define=EXPECT_LEVEL=login || rc=$?
  security delete-generic-password -s "$app_id" -a store-key \
    >/dev/null 2>&1 || true
  rm -rf -- "$app_dir"
  return "$rc"
}
leg_ios() {
  boot_ios_sim || return 1
  # Apple native items deliberately report no hardware level: Keybay exercises
  # the real API path without claiming simulator or per-item hardware backing.
  cd "$HARNESS" && flutter test integration_test/keybay_test.dart \
    -d "$IOS_UDID" --dart-define=EXPECT_SCHEME=native
}
leg_android() {
  boot_android_emu || return 1
  # Level is measured from the KEK (asserted in the dedicated test after a
  # write); leave EXPECT_LEVEL unset here.
  cd "$HARNESS" && flutter test integration_test/keybay_test.dart \
    -d "$ANDROID_SERIAL" \
    --dart-define=EXPECT_SCHEME=file
}
leg_entitled() {
  apply_entitled_overlay || return 1
  # The signed leg proves native-item selection and round-trip behavior. Apple
  # native items deliberately report no inferred hardware level.
  local rc=0
  (cd "$HARNESS" && flutter test integration_test/keybay_test.dart \
    -d macos --dart-define=EXPECT_SCHEME=native \
    --dart-define=APP_ID=com.example.keybayHarness.native) || rc=1
  restore_entitled_overlay
  return $rc
}

run_leg "unit + analyze"          leg_unit
run_leg "macOS CLI (login Keychain)" leg_macos_cli
run_leg "Linux (gnome-keyring, Docker)" leg_linux
run_leg "macOS .app (file scheme)" leg_macos_app
run_leg "iOS simulator (DP native items)" leg_ios
run_leg "Android emulator (Keystore-wrapped)" leg_android
if [[ $ENTITLED -eq 1 ]]; then
  run_leg "macOS entitled (DP success)" leg_entitled
else
  record "macOS entitled (DP success)" "SKIP (--entitled to run; needs signing identity)"
fi

note "e2e matrix"
FAILED=0
for r in "${RESULTS[@]}"; do
  printf '  %-38s %s\n' "${r%%|*}" "${r##*|}"
  [[ "${r##*|}" == "FAIL" ]] && FAILED=1
done
exit $FAILED

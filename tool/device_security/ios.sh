#!/usr/bin/env bash

ios_usage() {
  cat <<'USAGE'
iOS options:
  --device UDID       Required for run; must identify a connected physical iOS device.
                     Runs the non-disruptive Keychain/API baseline.

Reboot, before-first-unlock, restore, and multi-access-group procedures are
separately authorized qualification work; the baseline performs none of them.
USAGE
}

device_security_main() {
  local action="$1"
  shift
  ds_require flutter

  local device=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) [[ $# -ge 2 ]] || ds_die "--device needs a value"; device="$2"; shift 2 ;;
      -h|--help) ios_usage; return 0 ;;
      *) ds_die "unknown iOS option: $1" ;;
    esac
  done
  if [[ "$action" == "doctor" ]]; then
    flutter devices
    echo
    echo "For a physical run, pass the connected device UDID explicitly."
    return 0
  fi
  [[ -n "$device" ]] || ds_die "iOS run requires --device UDID"
  ds_require dart
  local device_inventory device_model device_os_version
  device_inventory="$(flutter devices --machine |
    dart run "$DEVICE_SECURITY_REPO/tool/device_security/flutter_device.dart" \
      "$device")" ||
    ds_die "the selected target is not one exact connected physical iOS device"
  IFS=$'\t' read -r device_model device_os_version <<<"$device_inventory"

  local selection="ios-baseline"
  ds_new_run_dir ios "$selection"
  ds_prepare_source
  local challenge_log="$DEVICE_SECURITY_RUN_DIR/security-challenge.log"
  local results="$DEVICE_SECURITY_RUN_DIR/$selection.results.json"
  local challenge_rc=0

  set +e
  ds_flutter_security_test "$device" "$selection" "$challenge_log" "$results" \
    --dart-define=APP_ID=com.example.keybayHarness.security.ios \
    --dart-define=EXPECT_SCHEME=native
  challenge_rc=$?
  set -e
  local command_status="pass"
  [[ "$challenge_rc" -eq 0 ]] || command_status="fail"
  ds_write_report "$DEVICE_SECURITY_RUN_DIR/report.json" ios "$selection" \
    physical-device "$results" "$command_status" not-required \
    --field "model=$device_model" \
    --field "osVersion=$device_os_version" \
    --limitation "Development-signed physical run; no reboot, restore, access-group transition, or installed-app archive identity was exercised."
  echo "Device-security report: $DEVICE_SECURITY_RUN_DIR/report.json"
  return "$challenge_rc"
}

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
  local ios_sdk
  ios_sdk="$(flutter devices --machine |
    dart run "$DEVICE_SECURITY_REPO/tool/device_security/flutter_device.dart" \
      "$device")" ||
    ds_die "the selected target is not one exact connected physical iOS device"

  ds_new_run_dir ios ios-baseline
  local baseline_log="$DEVICE_SECURITY_RUN_DIR/baseline.log"
  local challenge_log="$DEVICE_SECURITY_RUN_DIR/security-challenge.log"
  local baseline_rc=0 challenge_rc=0 rc=0

  set +e
  ds_flutter_test "$device" integration_test/keybay_test.dart "$baseline_log" \
    --dart-define=APP_ID=com.example.keybayHarness.security.ios \
    --dart-define=EXPECT_SCHEME=native
  baseline_rc=$?
  if [[ "$baseline_rc" -eq 0 ]]; then
    ds_flutter_test "$device" integration_test/device_security_test.dart \
      "$challenge_log" \
      --dart-define=APP_ID=com.example.keybayHarness.security.ios \
      --dart-define=EXPECT_SCHEME=native
    challenge_rc=$?
  else
    printf 'Not run because the baseline failed.\n' >"$challenge_log"
    challenge_rc=1
  fi
  set -e
  [[ "$baseline_rc" -eq 0 && "$challenge_rc" -eq 0 ]] || rc=1

  local status="pass" scenario_status="pass"
  if [[ "$rc" -ne 0 ]]; then status="inconclusive"; scenario_status="inconclusive"; fi
  ds_write_receipt "$DEVICE_SECURITY_RUN_DIR/receipt.json" ios ios-baseline \
    physical-device "$status" \
    --field "osVersion=$ios_sdk" \
    --scenario "KB-IOS-001=pass" \
    --scenario "KB-IOS-010=$scenario_status" \
    --scenario "KB-IOS-020=$scenario_status" \
    --evidence "$baseline_log" \
    --evidence "$challenge_log"
  echo "Device-security receipt: $DEVICE_SECURITY_RUN_DIR/receipt.json"
  return "$rc"
}

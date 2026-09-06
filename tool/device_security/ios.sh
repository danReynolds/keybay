#!/usr/bin/env bash

ios_usage() {
  cat <<'USAGE'
iOS options:
  --device UDID       Required for run; must identify a connected physical iOS device.
                     Runs the non-disruptive Keychain/API baseline.
  --lifecycle         Instead, build Profile/AOT and verify separate-process
                     seed/reopen. Requires KEYBAY_APPLE_TEAM_ID for signing.
  --upgrade           Instead, verify a passphrase store across signed builds 101/102.
  --crash             Instead, SIGKILL after seed and during writes, then recover.

Reboot, before-first-unlock, restore, and multi-access-group procedures are
separately authorized qualification work; the baseline performs none of them.
USAGE
}

device_security_main() {
  local action="$1"
  shift
  ds_require flutter

  local device="" lifecycle=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) [[ $# -ge 2 ]] || ds_die "--device needs a value"; device="$2"; shift 2 ;;
      --lifecycle|--upgrade|--crash) [[ -z "$lifecycle" ]] || ds_die "select one lifecycle mode"; lifecycle="${1#--}"; shift ;;
      -h|--help) ios_usage; return 0 ;;
      *) ds_die "unknown iOS option: $1" ;;
    esac
  done
  ds_require xcrun
  ds_require dart
  local flutter_inventory apple_inventory
  if [[ "$action" == "run" ]]; then
    flutter_inventory="$(flutter devices --machine --device-connection attached)"
  else
    flutter_inventory="$(flutter devices --machine)"
  fi
  apple_inventory="$(xcrun xcdevice list)"
  if [[ "$action" == "doctor" ]]; then
    printf '{"flutter":%s,"apple":%s}\n' "$flutter_inventory" "$apple_inventory" |
      dart run "$DEVICE_SECURITY_REPO/tool/device_security/flutter_device.dart" --list
    echo
    echo "For a physical run, pass the connected device UDID explicitly."
    return 0
  fi
  [[ -n "$device" ]] || ds_die "iOS run requires --device UDID"
  local device_inventory device_model device_os_version
  device_inventory="$(printf '{"flutter":%s,"apple":%s}\n' "$flutter_inventory" "$apple_inventory" |
    dart run "$DEVICE_SECURITY_REPO/tool/device_security/flutter_device.dart" \
      "$device")" ||
    ds_die "the selected target must be one supported physical iOS device connected over USB"
  IFS=$'\t' read -r device_model device_os_version <<<"$device_inventory"

  local selection="ios-baseline"
  if [[ -n "$lifecycle" ]]; then
    ds_require python3
    [[ "${KEYBAY_APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] ||
      ds_die "--lifecycle requires KEYBAY_APPLE_TEAM_ID"
    selection="ios-$lifecycle"
  fi
  ds_new_run_dir ios "$selection"
  ds_prepare_source
  if [[ -n "$lifecycle" ]]; then
    [[ "$lifecycle" != "lifecycle" ]] || lifecycle="process"
    python3 "$DEVICE_SECURITY_REPO/tool/device_security/ios_lifecycle.py" \
      "$device" "$device_model" "$device_os_version" "$lifecycle"
    return $?
  fi
  local challenge_log="$DEVICE_SECURITY_RUN_DIR/security-challenge.log"
  local results="$DEVICE_SECURITY_RUN_DIR/$selection.results.json"
  local challenge_rc=0

  set +e
  ds_flutter_security_test "$device" "$selection" "$challenge_log" "$results"
  challenge_rc=$?
  set -e
  local command_status="pass"
  [[ "$challenge_rc" -eq 0 ]] || command_status="fail"
  ds_write_report "$DEVICE_SECURITY_RUN_DIR/report.json" ios "$selection" \
    physical-device "$results" "$command_status" not-required \
    --field "model=$device_model" \
    --field "osVersion=$device_os_version" \
    --limitation "Development-signed physical run; no force-stop/relaunch, reboot, restore, access-group transition, or installed-app archive identity was exercised."
  echo "Device-security report: $DEVICE_SECURITY_RUN_DIR/report.json"
  return "$challenge_rc"
}

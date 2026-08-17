#!/usr/bin/env bash

ios_usage() {
  cat <<'USAGE'
iOS options:
  --device UDID       Required for run; must identify a connected physical iOS device.
                     Runs the non-disruptive Keychain/API baseline.
  --core-archive PATH Exact candidate package archive to exercise.

Reboot, before-first-unlock, restore, and multi-access-group procedures are
separately authorized qualification work; the baseline performs none of them.
USAGE
}

device_security_main() {
  local action="$1"
  shift
  ds_require flutter

  local device="" core_archive=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) [[ $# -ge 2 ]] || ds_die "--device needs a value"; device="$2"; shift 2 ;;
      --core-archive) [[ $# -ge 2 ]] || ds_die "--core-archive needs a value"; core_archive="$2"; shift 2 ;;
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
  flutter devices --machine |
    dart run "$DEVICE_SECURITY_REPO/tool/device_security/flutter_device.dart" \
      "$device" >/dev/null ||
    ds_die "the selected target is not one exact connected physical iOS device"

  local selection="ios-baseline"
  ds_new_run_dir ios "$selection"
  ds_prepare_core_subject "$core_archive"
  local challenge_log="$DEVICE_SECURITY_RUN_DIR/security-challenge.log"
  local results="$DEVICE_SECURITY_RUN_DIR/$selection.results.json"
  local challenge_rc=0

  set +e
  ds_flutter_security_test "$device" "$selection" "$challenge_log" "$results" \
    --dart-define=APP_ID=com.example.keybayHarness.security.ios \
    --dart-define=EXPECT_SCHEME=native
  challenge_rc=$?
  set -e
  echo "Apple development results: $results"
  echo "No release receipt was issued; installed IPA/app identity and physical Apple qualification remain unavailable."
  return "$challenge_rc"
}

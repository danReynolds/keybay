#!/usr/bin/env bash

MACOS_STORE_APP_ID="com.example.keybayHarness.security.file"
MACOS_BUNDLE_ID="dev.keybay.securityharness"
MACOS_STORE_APP_IDS=(
  "$MACOS_STORE_APP_ID"
  "$MACOS_STORE_APP_ID.isolate0"
  "$MACOS_STORE_APP_ID.isolate1"
  "$MACOS_STORE_APP_ID.isolate2"
  "$MACOS_STORE_APP_ID.isolate3"
)

macos_usage() {
  cat <<'USAGE'
macOS options:
  --tamper            Add self-restoring encrypted-container corruption.
  --core-archive PATH Exact candidate package archive to qualify.

The signed Data Protection Keychain and entitlement-transition procedures are
separately gated because they require a real development identity and
provisioning changes.
USAGE
}

_macos_store_dir() {
  local app_id="$1"
  printf '%s/Library/Containers/%s/Data/Library/Application Support/%s\n' \
    "$MACOS_HOME" "$MACOS_BUNDLE_ID" "$app_id"
}

_macos_init_home() {
  [[ "$(id -u)" != "0" ]] || ds_die "never run the device suite as root"
  local account_home actual_home
  account_home="$(id -P "$(id -un)" | awk -F: '{print $(NF-1)}')"
  [[ -n "$account_home" && -d "$account_home" ]] ||
    ds_die "could not derive the current account home"
  MACOS_HOME="$(cd "$account_home" && pwd -P)"
  actual_home="$(cd "$HOME" && pwd -P)" ||
    ds_die "HOME is not an accessible directory"
  [[ "$actual_home" == "$MACOS_HOME" ]] ||
    ds_die "HOME does not match the current account; refusing cleanup"
}

_macos_remove_store_dir() {
  local app_id="$1" dir candidate
  case "$app_id" in
    "$MACOS_STORE_APP_ID"|"$MACOS_STORE_APP_ID".isolate[0-3]) ;;
    *) echo "device-security: refusing unknown macOS appId: $app_id" >&2; return 1 ;;
  esac
  dir="$(_macos_store_dir "$app_id")"
  case "$dir" in
    "$MACOS_HOME/Library/Containers/$MACOS_BUNDLE_ID/Data/Library/Application Support/"*) ;;
    *) echo "device-security: refusing unexpected macOS cleanup target: $dir" >&2; return 1 ;;
  esac
  for candidate in \
    "$MACOS_HOME/Library" \
    "$MACOS_HOME/Library/Containers" \
    "$MACOS_HOME/Library/Containers/$MACOS_BUNDLE_ID" \
    "$MACOS_HOME/Library/Containers/$MACOS_BUNDLE_ID/Data" \
    "$MACOS_HOME/Library/Containers/$MACOS_BUNDLE_ID/Data/Library" \
    "$MACOS_HOME/Library/Containers/$MACOS_BUNDLE_ID/Data/Library/Application Support" \
    "$dir"; do
    if [[ -L "$candidate" ]]; then
      echo "device-security: refusing symlinked cleanup component: $candidate" >&2
      return 1
    fi
  done
  rm -rf -- "$dir" || return 1
  [[ ! -e "$dir" && ! -L "$dir" ]]
}

_macos_delete_store_key() {
  local app_id="$1" rc
  if security delete-generic-password -s "$app_id" -a store-key \
    >/dev/null 2>&1; then
    return 0
  else
    rc=$?
  fi
  [[ "$rc" -eq 44 ]] || {
    echo "device-security: could not delete Keychain key for $app_id" >&2
    return 1
  }
}

_macos_cleanup() {
  local app_id rc=0
  for app_id in "${MACOS_STORE_APP_IDS[@]}"; do
    _macos_delete_store_key "$app_id" || rc=1
    _macos_remove_store_dir "$app_id" || rc=1
  done
  return "$rc"
}

_macos_signing_mode() {
  local app="$DEVICE_SECURITY_HARNESS/build/macos/Build/Products/Debug/example_flutter.app"
  local details
  details="$(codesign -dv --verbose=4 -- "$app" 2>&1)" || return 1
  grep -q '^Signature=adhoc$' <<<"$details" || return 1
  printf 'ad-hoc\n'
}

device_security_main() {
  local action="$1"
  shift
  local tamper="0" core_archive=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tamper) tamper="1"; shift ;;
      --core-archive) [[ $# -ge 2 ]] || ds_die "--core-archive needs a value"; core_archive="$2"; shift 2 ;;
      -h|--help) macos_usage; return 0 ;;
      *) ds_die "unknown macOS option: $1" ;;
    esac
  done
  _macos_init_home

  if [[ "$action" == "doctor" ]]; then
    sw_vers
    printf 'architecture: %s\n' "$(uname -m)"
    printf 'development identities: '
    security find-identity -v -p codesigning 2>/dev/null |
      awk '/valid identities found/ {print $1; found=1} END {if (!found) print "unknown"}'
    return 0
  fi

  _macos_cleanup || ds_die "could not clean the dedicated macOS harness state"
  trap '_macos_cleanup >/dev/null 2>&1 || true' EXIT
  trap '_macos_cleanup >/dev/null 2>&1 || true; exit 130' INT
  trap '_macos_cleanup >/dev/null 2>&1 || true; exit 143' TERM
  local selection="macos-baseline" security_mode="baseline"
  if [[ "$tamper" == "1" ]]; then
    selection="macos-tamper"
    security_mode="tamper"
  fi
  ds_new_run_dir macos "$selection"
  ds_prepare_core_subject "$core_archive"
  local challenge_log="$DEVICE_SECURITY_RUN_DIR/security-challenge.log"
  local results="$DEVICE_SECURITY_RUN_DIR/$selection.results.json"
  local challenge_rc=0 rc=0

  set +e
  ds_flutter_security_test macos "$selection" "$challenge_log" "$results" \
    --dart-define=APP_ID="$MACOS_STORE_APP_ID" \
    --dart-define=EXPECT_SCHEME=file \
    --dart-define=EXPECT_LEVEL=login \
    --dart-define=SECURITY_MODE="$security_mode"
  challenge_rc=$?
  set -e
  [[ "$challenge_rc" -eq 0 ]] || rc=1

  local signing_mode="unverified" cleanup_rc=0
  signing_mode="$(_macos_signing_mode)" || {
    signing_mode="unverified"
    rc=1
  }
  local installer="$DEVICE_SECURITY_HARNESS/build/macos/Build/Products/Debug/example_flutter.app"
  local install_status="pass"
  [[ -d "$installer" && ! -L "$installer" ]] || install_status="fail"
  if [[ "$install_status" == "pass" ]]; then
    [[ "$(defaults read "$installer/Contents/Info.plist" CFBundleIdentifier)" == \
      "$MACOS_BUNDLE_ID" ]] || install_status="fail"
  fi
  [[ "$install_status" == "pass" ]] || rc=1
  _macos_cleanup || cleanup_rc=1
  [[ "$cleanup_rc" -eq 0 ]] || rc=1
  local cleanup_status="pass"
  [[ "$cleanup_rc" -eq 0 ]] || cleanup_status="fail"

  local receipt_args=(
    --field "model=$(sysctl -n hw.model 2>/dev/null || true)"
    --field "osVersion=$(sw_vers -productVersion)"
    --field "architecture=$(uname -m)"
    --field "storageScheme=encryptedFile"
    --field "signingIdentity=$signing_mode"
    --field "protectionLevel=loginBound"
  )
  ds_write_receipt "$DEVICE_SECURITY_RUN_DIR/receipt.json" macos "$selection" \
    native-host "$results" app-tree-sha256 "$installer" "$install_status" \
    "$cleanup_status" "${receipt_args[@]}"
  trap - EXIT INT TERM
  echo "Device-security receipt: $DEVICE_SECURITY_RUN_DIR/receipt.json"
  return "$rc"
}

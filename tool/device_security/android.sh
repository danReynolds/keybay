#!/usr/bin/env bash

ANDROID_HARNESS_PACKAGE="dev.keybay.securityharness"
ANDROID_STORE_APP_ID="com.example.keybayHarness"

android_usage() {
  cat <<'USAGE'
Android options:
  --device SERIAL              Target one connected physical device.
  --device-user ID             Android user/profile (default: 0).
  --tamper                     Add artifact corruption and a dedicated
                               harness-only missing-KEK challenge.
  --expect-level LEVEL         hardware or software (default: hardware).
  --allow-package-reset        Permit removing a pre-existing dedicated
                               harness package for the selected user first.
  --core-archive PATH          Exact candidate package archive to qualify.

The baseline never reboots, changes the screen credential, changes backup
transport, alters biometric enrollment, or touches another application.
USAGE
}

_android_prop() {
  adb -s "$ANDROID_DEVICE" shell getprop "$1" | tr -d '\r'
}

_android_pick_device() {
  if [[ -n "$ANDROID_DEVICE" ]]; then
    adb -s "$ANDROID_DEVICE" get-state >/dev/null 2>&1 ||
      ds_die "Android device is not connected/authorized: $ANDROID_DEVICE"
    return
  fi
  local candidates
  candidates="$(adb devices | awk '$2 == "device" {print $1}')"
  local count
  count="$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]] ||
    ds_die "expected exactly one authorized Android device; pass --device SERIAL"
  ANDROID_DEVICE="$candidates"
}

_android_inventory() {
  ANDROID_MODEL="$(_android_prop ro.product.model)"
  ANDROID_MANUFACTURER="$(_android_prop ro.product.manufacturer)"
  ANDROID_DEVICE_NAME="$(_android_prop ro.product.device)"
  ANDROID_RELEASE="$(_android_prop ro.build.version.release)"
  ANDROID_API="$(_android_prop ro.build.version.sdk)"
  ANDROID_PATCH="$(_android_prop ro.build.version.security_patch)"
  ANDROID_FINGERPRINT="$(_android_prop ro.build.fingerprint)"
  ANDROID_QEMU="$(_android_prop ro.kernel.qemu)"
  ANDROID_AVB="$(_android_prop ro.boot.verifiedbootstate)"
  ANDROID_BOOT_STATE="$(_android_prop ro.boot.vbmeta.device_state)"
  ANDROID_LOCKED="$(_android_prop ro.boot.flash.locked)"
  ANDROID_CURRENT_USER="$(adb -s "$ANDROID_DEVICE" shell am get-current-user | tr -d '\r')"
  ANDROID_SELINUX="$(adb -s "$ANDROID_DEVICE" shell getenforce | tr -d '\r')"
  ANDROID_FBE="$(adb -s "$ANDROID_DEVICE" shell sm get-fbe-mode 2>/dev/null | tr -d '\r' || true)"

  [[ "$ANDROID_QEMU" != "1" ]] ||
    ds_die "device-security requires physical hardware; $ANDROID_DEVICE is an emulator"
  [[ "$ANDROID_API" =~ ^[0-9]+$ ]] && [[ "$ANDROID_API" -ge 31 ]] ||
    ds_die "Keybay requires Android API 31+; target reports '$ANDROID_API'"
  [[ "$ANDROID_CURRENT_USER" == "$ANDROID_USER" ]] ||
    ds_die "active Android user is $ANDROID_CURRENT_USER, expected $ANDROID_USER"
}

_android_print_inventory() {
  cat <<EOF
Android physical-device preflight
  model:          $ANDROID_MANUFACTURER $ANDROID_MODEL ($ANDROID_DEVICE_NAME)
  release/API:    Android $ANDROID_RELEASE / API $ANDROID_API
  patch:          $ANDROID_PATCH
  build:          $ANDROID_FINGERPRINT
  user/profile:   $ANDROID_CURRENT_USER
  verified boot:  $ANDROID_AVB; vbmeta=$ANDROID_BOOT_STATE; flash-locked=$ANDROID_LOCKED
  SELinux/FBE:    $ANDROID_SELINUX / ${ANDROID_FBE:-unreported}
  harness package:$ANDROID_HARNESS_PACKAGE
EOF
  adb -s "$ANDROID_DEVICE" shell pm list features |
    tr -d '\r' | grep -E 'hardware_keystore|strongbox_keystore|keystore.app_attest_key' || true
}

_android_package_present_for_user() {
  local user="$1" output
  output="$(adb -s "$ANDROID_DEVICE" shell pm list packages --user "$user" \
    "$ANDROID_HARNESS_PACKAGE" 2>/dev/null)" || return 2
  output="${output//$'\r'/}"
  if grep -Fxq "package:$ANDROID_HARNESS_PACKAGE" <<<"$output"; then
    return 0
  fi
  [[ -z "$output" ]] && return 1
  return 2
}

_android_package_present() {
  _android_package_present_for_user "$ANDROID_USER"
}

# Controlled install with installed-bytes verification. This must run BEFORE
# the challenge: `flutter test` uninstalls the harness when it exits, so
# package identity is provable only while the retained APK is demonstrably
# what the device holds. The pulled copy closes the loop: built bytes ==
# installed bytes, then the nonce-bound results prove that package ran.
_android_controlled_install() {
  local installer="$1"
  (
    cd "$DEVICE_SECURITY_HARNESS"
    flutter build apk --debug
  ) || return 1
  [[ -f "$installer" && ! -L "$installer" ]] || return 1
  ds_require apkanalyzer
  [[ "$(apkanalyzer manifest application-id "$installer")" == \
    "$ANDROID_HARNESS_PACKAGE" ]] || return 1
  adb -s "$ANDROID_DEVICE" install -r --user "$ANDROID_USER" "$installer" \
    >/dev/null || return 1
  local device_path
  device_path="$(adb -s "$ANDROID_DEVICE" shell pm path --user "$ANDROID_USER" \
    "$ANDROID_HARNESS_PACKAGE" 2>/dev/null | tr -d '\r' |
    sed -n 's/^package://p' | head -n 1)"
  [[ -n "$device_path" ]] || return 1
  local pulled="$DEVICE_SECURITY_RUN_DIR/installed-base.apk"
  adb -s "$ANDROID_DEVICE" pull "$device_path" "$pulled" >/dev/null || return 1
  local built_digest installed_digest
  built_digest="$(_android_file_sha256 "$installer")"
  installed_digest="$(_android_file_sha256 "$pulled")"
  rm -f -- "$pulled"
  [[ -n "$built_digest" && "$built_digest" == "$installed_digest" ]]
}

_android_file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    sha256sum -- "$1" | awk '{print $1}'
  fi
}

_android_users_with_package() {
  local user users package_state parsed=0
  users="$(adb -s "$ANDROID_DEVICE" shell pm list users | tr -d '\r')" ||
    ds_die "could not inventory Android users"
  while IFS= read -r user; do
    parsed=1
    if _android_package_present_for_user "$user"; then
      printf '%s\n' "$user"
    else
      package_state=$?
      [[ "$package_state" -eq 1 ]] || return 2
    fi
  done < <(printf '%s\n' "$users" |
    sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p')
  [[ "$parsed" == "1" ]] || ds_die "could not parse Android user inventory"
}

_android_cleanup_harness() {
  local package_state
  if _android_package_present; then
    adb -s "$ANDROID_DEVICE" uninstall --user "$ANDROID_USER" \
      "$ANDROID_HARNESS_PACKAGE" >/dev/null || return 1
  else
    package_state=$?
    [[ "$package_state" -eq 1 ]] || return 1
  fi
  local remaining
  remaining="$(_android_users_with_package)" || return 1
  [[ -z "$remaining" ]]
}

_android_run_selection() {
  local installed_users user
  installed_users="$(_android_users_with_package)"
  if [[ -n "$installed_users" ]]; then
    while IFS= read -r user; do
      [[ "$user" == "$ANDROID_USER" ]] ||
        ds_die "$ANDROID_HARNESS_PACKAGE is installed for Android user $user; refusing a run that could affect another profile"
    done <<<"$installed_users"
    [[ "$ANDROID_ALLOW_PACKAGE_RESET" == "1" ]] ||
      ds_die "$ANDROID_HARNESS_PACKAGE is already installed; rerun with --allow-package-reset to remove only that dedicated harness for user $ANDROID_USER"
    _android_cleanup_harness ||
      ds_die "could not remove the pre-existing dedicated harness"
  fi

  local selection="android-baseline" security_mode="baseline"
  if [[ "$ANDROID_TAMPER" == "1" ]]; then
    selection="android-tamper"
    security_mode="tamper"
  fi
  ds_new_run_dir android "$selection"
  ds_prepare_core_subject "$ANDROID_CORE_ARCHIVE"
  local challenge_log="$DEVICE_SECURITY_RUN_DIR/security-challenge.log"
  local results="$DEVICE_SECURITY_RUN_DIR/$selection.results.json"
  local rc=0 challenge_rc=0

  # Flutter may leave its dedicated test application behind. The trap is a
  # best-effort interruption guard; the normal path verifies cleanup before it
  # can issue a pass receipt.
  trap '_android_cleanup_harness >/dev/null 2>&1 || true' EXIT
  trap '_android_cleanup_harness >/dev/null 2>&1 || true; exit 130' INT
  trap '_android_cleanup_harness >/dev/null 2>&1 || true; exit 143' TERM

  local installer="$DEVICE_SECURITY_HARNESS/build/app/outputs/flutter-apk/app-debug.apk"
  local install_status="pass"
  _android_controlled_install "$installer" || install_status="fail"
  [[ "$install_status" == "pass" ]] || rc=1

  set +e
  ds_flutter_security_test "$ANDROID_DEVICE" "$selection" \
    "$challenge_log" "$results" \
    --device-user "$ANDROID_USER" \
    --dart-define=APP_ID="$ANDROID_STORE_APP_ID" \
    --dart-define=EXPECT_SCHEME=file \
    --dart-define=EXPECT_ANDROID_LEVEL="$ANDROID_EXPECT_LEVEL" \
    --dart-define=SECURITY_MODE="$security_mode"
  challenge_rc=$?
  set -e
  [[ "$challenge_rc" -eq 0 ]] || rc=1

  local cleanup_rc=0
  _android_cleanup_harness || cleanup_rc=1
  [[ "$cleanup_rc" -eq 0 ]] || rc=1
  local cleanup_status="pass"
  [[ "$cleanup_rc" -eq 0 ]] || cleanup_status="fail"

  local receipt_args=(
    --field "model=$ANDROID_MANUFACTURER $ANDROID_MODEL"
    --field "osVersion=$ANDROID_RELEASE"
    --field "apiLevel=$ANDROID_API"
    --field "securityPatch=$ANDROID_PATCH"
    --field "buildFingerprint=$ANDROID_FINGERPRINT"
    --field "verifiedBoot=$ANDROID_AVB; vbmeta=$ANDROID_BOOT_STATE; flash-locked=$ANDROID_LOCKED"
    --field "selinux=$ANDROID_SELINUX"
    --field "fbe=${ANDROID_FBE:-unreported}"
  )
  ds_write_receipt "$DEVICE_SECURITY_RUN_DIR/receipt.json" android \
    "$selection" physical-device "$results" apk-sha256 "$installer" \
    "$install_status" "$cleanup_status" "${receipt_args[@]}"

  trap - EXIT INT TERM
  echo "Device-security receipt: $DEVICE_SECURITY_RUN_DIR/receipt.json"
  return "$rc"
}

device_security_main() {
  local action="$1"
  shift
  ds_require adb

  ANDROID_DEVICE=""
  ANDROID_USER="0"
  ANDROID_TAMPER="0"
  ANDROID_EXPECT_LEVEL="hardware"
  ANDROID_ALLOW_PACKAGE_RESET="0"
  ANDROID_CORE_ARCHIVE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) [[ $# -ge 2 ]] || ds_die "--device needs a value"; ANDROID_DEVICE="$2"; shift 2 ;;
      --device-user) [[ $# -ge 2 ]] || ds_die "--device-user needs a value"; ANDROID_USER="$2"; shift 2 ;;
      --tamper) ANDROID_TAMPER="1"; shift ;;
      --expect-level) [[ $# -ge 2 ]] || ds_die "--expect-level needs a value"; ANDROID_EXPECT_LEVEL="$2"; shift 2 ;;
      --allow-package-reset) ANDROID_ALLOW_PACKAGE_RESET="1"; shift ;;
      --core-archive) [[ $# -ge 2 ]] || ds_die "--core-archive needs a value"; ANDROID_CORE_ARCHIVE="$2"; shift 2 ;;
      -h|--help) android_usage; return 0 ;;
      *) ds_die "unknown Android option: $1" ;;
    esac
  done

  case "$ANDROID_EXPECT_LEVEL" in hardware|software) ;; *) ds_die "--expect-level must be hardware or software" ;; esac
  [[ "$ANDROID_USER" =~ ^[0-9]+$ ]] ||
    ds_die "--device-user must be a non-negative integer"

  _android_pick_device
  _android_inventory
  _android_print_inventory
  [[ "$action" == "doctor" ]] && return 0
  _android_run_selection
}

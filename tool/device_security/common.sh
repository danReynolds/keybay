#!/usr/bin/env bash
# Shared helpers for tool/device_security/*.sh. Sourced, never executed.

DEVICE_SECURITY_REPO="${REPO:?device_security.sh must set REPO}"
DEVICE_SECURITY_HARNESS="$DEVICE_SECURITY_REPO/example_flutter"
DEVICE_SECURITY_OUT="$DEVICE_SECURITY_REPO/build/device-security"

ds_die() {
  echo "device-security: $*" >&2
  exit 64
}

ds_require() {
  command -v "$1" >/dev/null 2>&1 || ds_die "required command not found: $1"
}

ds_timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

ds_new_run_dir() {
  local platform="$1" selection="$2" stamp
  stamp="$(ds_timestamp)"
  [[ ! -L "$DEVICE_SECURITY_REPO/build" ]] ||
    ds_die "refusing symlinked build directory"
  mkdir -p "$DEVICE_SECURITY_OUT"
  [[ -d "$DEVICE_SECURITY_OUT" && ! -L "$DEVICE_SECURITY_OUT" ]] ||
    ds_die "device-security output root must be a real directory"
  local actual_out
  actual_out="$(cd "$DEVICE_SECURITY_OUT" && pwd -P)"
  [[ "$actual_out" == "$DEVICE_SECURITY_REPO/build/device-security" ]] ||
    ds_die "device-security output root escaped the repository"
  DEVICE_SECURITY_RUN_DIR="$(mktemp -d \
    "$DEVICE_SECURITY_OUT/$stamp-$platform-$selection.XXXXXX")"
  chmod 700 "$DEVICE_SECURITY_RUN_DIR"
  export DEVICE_SECURITY_RUN_DIR
}

ds_write_receipt() {
  local output="$1" platform="$2" selection="$3" execution_class="$4" status="$5"
  shift 5
  ds_require dart
  dart run "$DEVICE_SECURITY_REPO/tool/device_security/receipt.dart" \
    --output "$output" \
    --platform "$platform" \
    --selection "$selection" \
    --execution-class "$execution_class" \
    --status "$status" \
    "$@"
}

ds_flutter_test() {
  local device="$1" test_file="$2" log="$3"
  shift 3
  ds_require flutter
  (
    cd "$DEVICE_SECURITY_HARNESS"
    flutter test "$test_file" -d "$device" "$@"
  ) 2>&1 | tee "$log"
  local command_rc="${PIPESTATUS[0]}" tee_rc="${PIPESTATUS[1]}"
  if [[ "$tee_rc" -ne 0 ]]; then
    echo "device-security: evidence logger failed with exit $tee_rc" >&2
    return 74
  fi
  return "$command_rc"
}

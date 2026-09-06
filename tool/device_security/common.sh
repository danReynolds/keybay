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
  DEVICE_SECURITY_NONCE="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  [[ "$DEVICE_SECURITY_NONCE" =~ ^[0-9a-f]{64}$ ]] ||
    ds_die "could not generate a qualification nonce"
  export DEVICE_SECURITY_RUN_DIR
  export DEVICE_SECURITY_NONCE
}

ds_prepare_source() {
  local commit
  [[ -z "$(git -C "$DEVICE_SECURITY_REPO" status --porcelain --untracked-files=all)" ]] ||
    ds_die "device reports require a clean source checkout"
  commit="$(git -C "$DEVICE_SECURITY_REPO" rev-parse HEAD)"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] ||
    ds_die "source commit was malformed"
  DEVICE_SECURITY_SOURCE_IDENTITY="git-commit:$commit"
  export DEVICE_SECURITY_SOURCE_IDENTITY
  (
    cd "$DEVICE_SECURITY_HARNESS" || exit 1
    flutter pub get --enforce-lockfile
  )
  [[ -z "$(git -C "$DEVICE_SECURITY_REPO" status --porcelain --untracked-files=all)" ]] ||
    ds_die "dependency preparation changed the qualified source checkout"
}

ds_write_report() {
  local output="$1" platform="$2" selection="$3" execution_class="$4"
  local results="$5" command_status="$6" cleanup_status="$7"
  shift 7
  ds_require dart
  dart run "$DEVICE_SECURITY_REPO/tool/device_security/report.dart" \
    --output "$output" \
    --platform "$platform" \
    --selection "$selection" \
    --execution-class "$execution_class" \
    --nonce "$DEVICE_SECURITY_NONCE" \
    --results "$results" \
    --command-status "$command_status" \
    --cleanup-status "$cleanup_status" \
    "$@"
}

ds_flutter_security_test() {
  local device="$1" selection="$2" log="$3" results="$4" test_file
  shift 4
  case "$selection" in
    android-baseline|android-tamper)
      test_file="integration_test/keybay_v2_android_test.dart" ;;
    ios-baseline) test_file="integration_test/keybay_v2_ios_test.dart" ;;
    *) ds_die "this device-security selection has not yet been ported to Keybay V2" ;;
  esac
  local reporter="${results%.json}.flutter.jsonl" command_rc=0 parser_rc=0
  ds_require flutter
  ds_require dart
  # Flutter build output is not JSON and can contain device identifiers. Keep
  # it private; parse only the dedicated test reporter, never console text.
  (
    cd "$DEVICE_SECURITY_HARNESS" || exit 1
    flutter test "$test_file" -d "$device" \
      --file-reporter "json:$reporter" \
      --dart-define="KEYBAY_SECURITY_NONCE=$DEVICE_SECURITY_NONCE" \
      --dart-define="KEYBAY_SECURITY_SUBJECT=$DEVICE_SECURITY_SOURCE_IDENTITY" \
      "$@"
  ) >"$log" 2>&1 || command_rc=$?
  dart run "$DEVICE_SECURITY_REPO/tool/device_security/result.dart" \
    --input "$reporter" --output "$results" --selection "$selection" \
    --nonce "$DEVICE_SECURITY_NONCE" \
    --subject "$DEVICE_SECURITY_SOURCE_IDENTITY" >/dev/null || parser_rc=$?
  [[ "$parser_rc" -eq 0 ]] || return "$parser_rc"
  return "$command_rc"
}

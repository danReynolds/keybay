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

ds_prepare_core_subject() {
  local archive="$1" source_dir source_name copied digest workspace
  [[ -n "$archive" ]] || ds_die "run requires --core-archive PATH"
  [[ -f "$archive" && ! -L "$archive" ]] ||
    ds_die "core subject must be a regular, non-symlink archive"
  [[ -z "$(git -C "$DEVICE_SECURITY_REPO" status --porcelain --untracked-files=all)" ]] ||
    ds_die "release qualification requires a clean suite checkout"
  source_dir="$(cd "$(dirname "$archive")" && pwd -P)"
  source_name="$(basename "$archive")"
  archive="$source_dir/$source_name"
  copied="$DEVICE_SECURITY_RUN_DIR/core-subject.tar.gz"
  cp -- "$archive" "$copied"
  digest="$(python3 "$DEVICE_SECURITY_REPO/tool/compare_pub_archives.py" \
    --digest "$copied")" || ds_die "core subject archive is invalid"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] ||
    ds_die "core subject digest was malformed"

  workspace="$DEVICE_SECURITY_RUN_DIR/workspace"
  mkdir -p "$workspace/packages/keybay"
  git -C "$DEVICE_SECURITY_REPO" archive HEAD example_flutter |
    tar -x -C "$workspace"
  tar -xzf "$copied" -C "$workspace/packages/keybay"
  DEVICE_SECURITY_HARNESS="$workspace/example_flutter"
  DEVICE_SECURITY_SUBJECT_ARCHIVE="$copied"
  DEVICE_SECURITY_SUBJECT_IDENTITY="core-pub-content-sha256:$digest"
  export DEVICE_SECURITY_HARNESS DEVICE_SECURITY_SUBJECT_ARCHIVE
  export DEVICE_SECURITY_SUBJECT_IDENTITY
  (
    cd "$DEVICE_SECURITY_HARNESS"
    flutter pub get --enforce-lockfile
  )
}

ds_write_receipt() {
  local output="$1" platform="$2" selection="$3" execution_class="$4"
  local results="$5" installer_kind="$6" installer_path="$7"
  local install_status="$8" cleanup_status="$9"
  shift 9
  ds_require dart
  dart run "$DEVICE_SECURITY_REPO/tool/device_security/receipt.dart" \
    --output "$output" \
    --platform "$platform" \
    --selection "$selection" \
    --execution-class "$execution_class" \
    --nonce "$DEVICE_SECURITY_NONCE" \
    --subject-archive "$DEVICE_SECURITY_SUBJECT_ARCHIVE" \
    --results "$results" \
    --cleanup-status "$cleanup_status" \
    --installer-kind "$installer_kind" \
    --installer-path "$installer_path" \
    --package-id dev.keybay.securityharness \
    --install-command flutter-test-controlled \
    --install-status "$install_status" \
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

ds_flutter_security_test() {
  local device="$1" selection="$2" log="$3" results="$4"
  shift 4
  local raw="$DEVICE_SECURITY_RUN_DIR/flutter-report.jsonl"
  local had_errexit=0
  [[ $- == *e* ]] && had_errexit=1
  ds_require flutter
  set +e
  (
    cd "$DEVICE_SECURITY_HARNESS"
    flutter test integration_test/device_security_test.dart \
      -d "$device" \
      --file-reporter "json:$raw" \
      --dart-define=SECURITY_RUN_NONCE="$DEVICE_SECURITY_NONCE" \
      --dart-define=SECURITY_SUBJECT_IDENTITY="$DEVICE_SECURITY_SUBJECT_IDENTITY" \
      "$@"
  ) 2>&1 | tee "$log"
  local command_rc="${PIPESTATUS[0]}" tee_rc="${PIPESTATUS[1]}"
  local result_rc=0
  dart run "$DEVICE_SECURITY_REPO/tool/device_security/result.dart" \
    --input "$raw" \
    --output "$results" \
    --selection "$selection" \
    --nonce "$DEVICE_SECURITY_NONCE" \
    --subject "$DEVICE_SECURITY_SUBJECT_IDENTITY"
  result_rc=$?
  rm -f -- "$raw"
  if [[ "$had_errexit" == "1" ]]; then set -e; else set +e; fi
  [[ "$tee_rc" -eq 0 ]] || return 74
  [[ "$result_rc" -eq 0 ]] || return "$result_rc"
  return "$command_rc"
}

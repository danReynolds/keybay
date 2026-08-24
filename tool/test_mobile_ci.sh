#!/usr/bin/env bash
# One mobile integration leg for CI. The physical qualification runner is
# deliberately separate: this script proves genuine platform API paths on
# disposable virtual targets and emits no physical qualification report.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$REPO/example_flutter"
PLATFORM="${1:-}"

case "$PLATFORM" in
  android)
    serials="$(adb devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1}')"
    count="$(printf '%s\n' "$serials" | awk 'NF {n++} END {print n + 0}')"
    [[ "$count" -eq 1 ]] || {
      echo "expected exactly one ready Android emulator, found $count" >&2
      exit 2
    }
    serial="$(printf '%s\n' "$serials" | awk 'NF {print; exit}')"
    (
      cd "$HARNESS"
      flutter test integration_test/keybay_test.dart \
        -d "$serial" \
        --dart-define=APP_ID=com.example.keybayHarness.ci \
        --dart-define=EXPECT_SCHEME=file
    )
    ;;
  ios)
    udid="$({ xcrun simctl list devices available -j || exit 1; } | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("no available iPhone simulator")
')"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b
    (
      cd "$HARNESS"
      # Generate an XCTest-hosted integration app, then let XCTest launch it
      # and read the plugin's in-process result map. `flutter test` instead
      # discovers the VM service by scraping `simctl log stream`; that
      # discovery can wait forever after an otherwise successful build.
      flutter build ios --config-only --simulator --debug \
        integration_test/keybay_test.dart \
        --dart-define=APP_ID=com.example.keybayHarness.ci \
        --dart-define=EXPECT_SCHEME=native
      result_root="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
      result_bundle="$result_root/keybay-ios-$$.xcresult"
      xcode_log="$result_root/keybay-ios-$$.log"
      if xcodebuild test \
        -workspace ios/Runner.xcworkspace \
        -scheme Runner \
        -configuration Debug \
        -destination "id=$udid" \
        -parallel-testing-enabled NO \
        -resultBundlePath "$result_bundle" >"$xcode_log" 2>&1; then
        tail -n 100 "$xcode_log"
      else
        status=$?
        tail -n 500 "$xcode_log" >&2
        exit "$status"
      fi
    )
    ;;
  *)
    echo "usage: $0 android|ios" >&2
    exit 64
    ;;
esac

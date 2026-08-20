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
      flutter test integration_test/keybay_test.dart \
        -d "$udid" \
        --dart-define=APP_ID=com.example.keybayHarness.ci \
        --dart-define=EXPECT_SCHEME=native
    )
    ;;
  *)
    echo "usage: $0 android|ios" >&2
    exit 64
    ;;
esac

#!/usr/bin/env bash
# Repeatable native/device security qualification for Keybay.
#
# The stable security contract and scenario catalogue live in
# doc/device-security-suite.md. This entrypoint deliberately stays small:
# platform adapters own device mechanics while the Flutter harness owns the
# shared in-app assertions.
set -euo pipefail
umask 077

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO"

usage() {
  cat <<'USAGE'
Usage:
  ./tool/device_security.sh doctor <android|ios|macos|linux> [options]
  ./tool/device_security.sh run    <android|ios> [options]

Examples:
  ./tool/device_security.sh doctor android
  ./tool/device_security.sh run android --device SERIAL
  ./tool/device_security.sh run android --device SERIAL --lifecycle
  ./tool/device_security.sh run android --device SERIAL --upgrade
  ./tool/device_security.sh run android --device SERIAL --crash
  ./tool/device_security.sh run android --device SERIAL --tamper \
    --allow-package-reset
  ./tool/device_security.sh doctor ios
  ./tool/device_security.sh run ios --device UDID
  KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/device_security.sh run ios --device UDID --lifecycle
  KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/device_security.sh run ios --device UDID --upgrade
  KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/device_security.sh run ios --device UDID --crash
  ./tool/device_security.sh doctor macos

Baseline qualification changes only the dedicated Keybay security-harness app
and its one V2 store. `--tamper` adds self-restoring artifact corruption and a
missing-KEK challenge that deletes only a dedicated harness key. Reboot,
credential changes, or real backup/transfer require separate procedures and
are never implied here.
USAGE
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi
[[ $# -ge 2 ]] || { usage >&2; exit 64; }
ACTION="$1"
PLATFORM="$2"
shift 2

case "$ACTION" in
  doctor|run) ;;
  *) echo "unknown action: $ACTION" >&2; usage >&2; exit 64 ;;
esac

case "$PLATFORM" in
  android|ios|macos|linux)
    ADAPTER="$REPO/tool/device_security/$PLATFORM.sh"
    ;;
  *)
    echo "unsupported platform: $PLATFORM" >&2
    usage >&2
    exit 64
    ;;
esac

# shellcheck source=tool/device_security/common.sh
source "$REPO/tool/device_security/common.sh"
# shellcheck source=/dev/null
source "$ADAPTER"

device_security_main "$ACTION" "$@"

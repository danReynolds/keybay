#!/usr/bin/env bash

device_security_main() {
  local action="$1"
  shift
  case "$action" in
    doctor)
      echo "Linux desktop qualification is not implemented."
      echo "The current GNOME Keyring integration remains available via ./tool/test_linux.sh."
      ;;
    run)
      ds_die "Linux is not yet an implemented device-security target; see doc/device-security-suite.md"
      ;;
  esac
}

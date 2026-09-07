#!/usr/bin/env bash

# Native V2 provider tests and the signed Flutter harness are separate lanes.
# The obsolete device runner must never perform its V1 namespace cleanup.
device_security_main() {
  local action="$1"
  shift
  [[ $# -eq 0 ]] || ds_die "macOS device-security accepts no options"
  if [[ "$action" != "doctor" ]]; then
    ds_die "the macOS device-security report adapter has not been ported to Keybay V2; use the native provider and signed harness lanes"
  fi
  sw_vers
  printf 'architecture: %s\n' "$(uname -m)"
  printf 'development identities visible in this execution context: '
  security find-identity -v -p codesigning 2>/dev/null |
    awk '/valid identities found/ {print $1; found=1} END {if (!found) print "unknown"}'
}

#!/usr/bin/env bash
# Opt-in SDK qualification with genuine login-Keychain state and signed AOT.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 69
exec python3 "$(dirname "${BASH_SOURCE[0]}")/device_security/macos_developer_id.py"

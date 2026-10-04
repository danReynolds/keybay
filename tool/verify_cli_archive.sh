#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "usage: $0 ARCHIVE.tar.gz" >&2
  exit 2
fi
# Never extract or execute a release candidate during structural verification.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/verify_cli_archive.py" "$1"

#!/usr/bin/env bash
# SDK regression selector. Platform mechanics stay in their own runners.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec dart tool/platform_regression.dart "$@"

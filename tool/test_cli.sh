#!/usr/bin/env bash
# CLI selector; shares report handling with the SDK regression runner.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec dart tool/platform_regression.dart --cli "$@"

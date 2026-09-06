#!/usr/bin/env bash
# Hermetic SDK tests, including every platform's contract tests over fakes.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../packages/keybay"
exec dart test -x integration

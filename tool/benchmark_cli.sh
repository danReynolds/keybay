#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ "${KEYBAY_BENCHMARK:-}" != "1" ]]; then
  echo "Set KEYBAY_BENCHMARK=1 and run on a disposable release test account." >&2
  exit 2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-cli-bench.XXXXXX")"
app_id="${KEYBAY_BENCHMARK_APP_ID:-keybay-cli-benchmark-${GITHUB_RUN_ID:-$$}}"
cleanup() {
  if [[ -x "$tmp/keybay-benchmark" ]]; then
    "$tmp/keybay-benchmark" --test-reset >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

dart compile exe -Dkeybay.application_id="$app_id" \
  packages/keybay_cli/tool/integration_harness.dart \
  -o "$tmp/keybay-benchmark"

iterations="${KEYBAY_BENCHMARK_ITERATIONS:-50}"
one="$tmp/one.env"
ten="$tmp/ten.env"
python="python3"
if [[ "$(uname -s)" == "Darwin" ]]; then
  python="/usr/bin/python3"
fi

for index in $(seq 1 10); do
  key="benchmark/key-$index"
  printf 'benchmark-value-%s' "$index" | \
    "$tmp/keybay-benchmark" set --stdin "$key"
  printf 'KEY_%s=kb://%s\n' "$index" "$key" >>"$ten"
  if [[ $index -eq 1 ]]; then
    printf 'KEY_1=kb://%s\n' "$key" >"$one"
  fi
done

one_result="$("$python" tool/benchmark_cli.py \
  "$tmp/keybay-benchmark" "$one" "$iterations")"
ten_result="$("$python" tool/benchmark_cli.py \
  "$tmp/keybay-benchmark" "$ten" "$iterations")"
printf 'one reference: %s\n' "$one_result"
printf 'ten references: %s\n' "$ten_result"

if [[ -n "${KEYBAY_BENCHMARK_OUTPUT:-}" ]]; then
  mkdir -p "$(dirname "$KEYBAY_BENCHMARK_OUTPUT")"
  printf '{"one_reference":%s,"ten_references":%s}\n' \
    "$one_result" \
    "$ten_result" > "$KEYBAY_BENCHMARK_OUTPUT"
fi

for index in $(seq 1 10); do
  "$tmp/keybay-benchmark" rm "benchmark/key-$index"
done

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-cli-storage.XXXXXX")"
binary="$tmp/keybay-integration"
application_id="keybay-cli-itest-${GITHUB_RUN_ID:-$$}"
writer_pids=()

fail() {
  echo "$1" >&2
  exit 1
}

cleanup() {
  if [[ -n "${writer_pids[*]-}" ]]; then
    for writer_pid in "${writer_pids[@]}"; do
      kill "$writer_pid" 2>/dev/null || true
      wait "$writer_pid" 2>/dev/null || true
    done
  fi
  if [[ -x "$binary" ]]; then
    "$binary" --test-reset >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

dart compile exe \
  -Dkeybay.application_id="$application_id" \
  packages/keybay_cli/tool/integration_harness.dart \
  -o "$binary"

key="keybay-itest/token"
sentinel="keybay-integration-value-${GITHUB_RUN_ID:-$$}"
manifest="$tmp/.secrets.env"
printf 'LITERAL=from-manifest\nSECRET=kb://%s\n' "$key" >"$manifest"

concurrent_writers=8
concurrent_names=()
concurrent_gate="$tmp/concurrent-writer-gate"
for writer in $(seq 0 $((concurrent_writers - 1))); do
  suffix="$(printf '%02d' "$writer")"
  concurrent_names+=("CONCURRENT_$suffix")
  printf 'CONCURRENT_%s=kb://keybay-itest/concurrent-%s\n' \
    "$suffix" "$suffix" >>"$manifest"
  (
    touch "$tmp/concurrent-writer-ready-$suffix"
    while [[ ! -e "$concurrent_gate" ]]; do
      sleep 0.01
    done
    printf 'concurrent-%s' "$suffix" | \
      "$binary" set --stdin "keybay-itest/concurrent-$suffix"
  ) &
  writer_pids+=("$!")
done

ready_count=0
for _ in $(seq 1 200); do
  ready_count="$(
    find "$tmp" -name 'concurrent-writer-ready-*' -type f | \
      wc -l | tr -d ' '
  )"
  [[ "$ready_count" == "$concurrent_writers" ]] && break
  sleep 0.01
done
[[ "$ready_count" == "$concurrent_writers" ]] || \
  fail "concurrent writers did not reach the start gate"
touch "$concurrent_gate"
writer_failed=0
for writer_pid in "${writer_pids[@]}"; do
  if ! wait "$writer_pid"; then
    writer_failed=1
  fi
done
writer_pids=()
((writer_failed == 0)) || fail "a concurrent writer failed"

set_output="$(printf '%s' "$sentinel" | "$binary" set --stdin "$key")"
[[ -z "$set_output" ]] || fail "set --stdin wrote unexpected stdout"

# A captured get refuses before opening the store or decrypting the value.
set +e
captured_get="$("$binary" get "$key" 2>&1)"
captured_get_status=$?
set -e
[[ $captured_get_status -eq 4 ]] || \
  fail "captured get exited $captured_get_status, expected 4"
[[ "$captured_get" == *"captured output is refused"* ]] || \
  fail "captured get omitted its TTY guidance"
[[ "$captured_get" != *"$sentinel"* ]] || \
  fail "captured get disclosed the stored value"

python3 tool/test_cli_get.py "$binary" "$key" "$sentinel"

list_output="$("$binary" list)"
expected_list="$(
  for writer in $(seq 0 $((concurrent_writers - 1))); do
    printf 'keybay-itest/concurrent-%02d\n' "$writer"
  done
  printf 'keybay-itest/token'
)"
[[ "$list_output" == "$expected_list" ]] || \
  fail "list output did not contain the sorted test keys"

concurrent_values="$(
  "$binary" run -f "$manifest" -- \
    /bin/sh -c 'for name do /usr/bin/printenv "$name"; done' \
      keybay-concurrent-values "${concurrent_names[@]}"
)"
expected_values="$(
  for writer in $(seq 0 $((concurrent_writers - 1))); do
    printf 'concurrent-%02d\n' "$writer"
  done
)"
[[ "$concurrent_values" == "$expected_values" ]] || \
  fail "concurrent writes did not preserve every value"

resolved="$("$binary" run -f "$manifest" -- /usr/bin/printenv SECRET)"
[[ "$resolved" == "$sentinel" ]] || fail "run did not resolve the stored value"

literal="$("$binary" run -f "$manifest" -- /usr/bin/printenv LITERAL)"
[[ "$literal" == "from-manifest" ]] || \
  fail "run did not overlay the manifest literal"

"$binary" rm "$key"
"$binary" rm "$key"
for writer in $(seq 0 $((concurrent_writers - 1))); do
  "$binary" rm "keybay-itest/concurrent-$(printf '%02d' "$writer")"
done

set +e
missing_output="$("$binary" run -f "$manifest" -- /usr/bin/true 2>&1)"
missing_status=$?
set -e
[[ $missing_status -eq 3 ]] || \
  fail "missing-reference run exited $missing_status, expected 3"
[[ "$missing_output" == *"keybay set $key"* ]] || \
  fail "missing-reference output omitted set remediation"
[[ "$missing_output" == *"Nothing was launched."* ]] || \
  fail "missing-reference output omitted atomicity notice"

"$binary" --test-reset
echo "CLI V2 real-store round trip passed"

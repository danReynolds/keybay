#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-cli-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
repo="$PWD"
for program in dart python3 ruby; do
  command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 69; }
done
dart analyze --fatal-infos packages/keybay_cli
(cd packages/keybay_cli && dart test test)

# The source runner must ignore a caller package config and keep the caller's
# directory as the manifest boundary.
mkdir -p "$tmp/dev-project/.dart_tool"
printf '{"configVersion":2,"packages":[]}\n' > \
  "$tmp/dev-project/.dart_tool/package_config.json"
printf 'KEYBAY_DEV_MARKER=from-example\n' > \
  "$tmp/dev-project/.env"
dev_output="$(
  cd "$tmp/dev-project"
  "$repo/tool/keybay-dev" run -- /usr/bin/printenv KEYBAY_DEV_MARKER
)"
[[ "$dev_output" == "from-example" ]] || {
  echo "keybay-dev did not preserve the caller manifest directory" >&2
  exit 1
}

dart run keybay:keybay_compile \
  packages/keybay_cli/bin/keybay.dart -o "$tmp/keybay"
dart compile exe packages/keybay_cli/tool/prompt_harness.dart \
  -o "$tmp/prompt_harness"
dart compile exe packages/keybay_cli/tool/passphrase_prompt_harness.dart \
  -o "$tmp/passphrase_prompt_harness"
dart compile exe packages/keybay_cli/tool/command_harness.dart \
  -o "$tmp/command_harness"
dart compile exe packages/keybay_cli/tool/clipboard_harness.dart \
  -o "$tmp/clipboard_harness"
python3 tool/test_cli_commands.py "$tmp/command_harness"
python3 tool/test_cli_tui.py "$tmp/command_harness"
python3 tool/test_cli_exec.py "$tmp/keybay"
python3 tool/test_cli_pty.py "$tmp/prompt_harness"
python3 tool/test_cli_passphrase.py "$tmp/passphrase_prompt_harness"
python3 tool/test_cli_hidden_input.py "$tmp/prompt_harness" "$tmp/passphrase_prompt_harness"
python3 tool/test_cli_archive.py
python3 tool/test_homebrew_formula.py
if [[ "$(uname -s)" == "Darwin" ]]; then
  python3 tool/test_cli_clipboard.py "$tmp/clipboard_harness"
  # A local ad-hoc hardened-runtime signature is structurally inspectable but
  # not launchable like the Developer-ID release signature. Keep the executable
  # archive smoke on the original binary and use the copy only for identity
  # verifier coverage.
  cp "$tmp/keybay" "$tmp/keybay-identity"
  codesign --force --sign - --identifier io.github.danreynolds.keybay.cli --options runtime \
    "$tmp/keybay-identity"
  KEYBAY_ALLOW_ADHOC=1 ./tool/verify_macos_release.sh "$tmp/keybay-identity"

  mkdir "$tmp/runtime-in-path"
  cp "$tmp/keybay" "$tmp/runtime-in-path/keybay"
  codesign --force --sign - --identifier io.github.danreynolds.keybay.cli \
    "$tmp/runtime-in-path/keybay"
  if KEYBAY_ALLOW_ADHOC=1 \
      ./tool/verify_macos_release.sh "$tmp/runtime-in-path/keybay"; then
    echo "macOS identity verifier accepted a binary without hardened runtime" >&2
    exit 1
  fi
fi
if [[ "$(uname -s)" == "Linux" ]]; then
  if ! command -v xvfb-run >/dev/null || ! command -v xclip >/dev/null; then
    echo 'Linux CLI qualification needs xvfb-run and xclip.' >&2; exit 69;
  fi
  env -u WAYLAND_DISPLAY KEYBAY_TEST_X11=1 xvfb-run -a \
    python3 tool/test_cli_clipboard.py "$tmp/clipboard_harness"
fi
version="$(awk '$1 == "version:" { print $2 }' packages/keybay_cli/pubspec.yaml)"
archive="$tmp/keybay-$version-test.tar.gz"
./tool/package_cli_release.sh "$tmp/keybay" "$archive"
./tool/verify_cli_archive.sh "$archive"
./tool/verify_cli_binary.sh "$tmp/keybay" "$version"

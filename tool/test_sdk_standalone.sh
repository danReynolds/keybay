#!/usr/bin/env bash
# Qualify the SDK independently of the CLI's workspace constraints. Run after
# workspace pub get --enforce-lockfile has fetched the reviewed dependencies.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

sdk_package="$(mktemp -d "${TMPDIR:-/tmp}/keybay-sdk-standalone.XXXXXX")"
trap 'rm -rf "$sdk_package"' EXIT
cp -R packages/keybay/lib packages/keybay/bin packages/keybay/test "$sdk_package/"
cp packages/keybay/analysis_options.yaml packages/keybay/dart_test.yaml \
  pubspec.lock "$sdk_package/"
sed '/^resolution: workspace$/d' packages/keybay/pubspec.yaml \
  > "$sdk_package/pubspec.yaml"

cd "$sdk_package"
# Removing the workspace changes direct/dev dependency labels and prunes
# workspace-only packages, so its lock cannot be enforced verbatim. Offline
# resolution fetches nothing; the closure test verifies the runtime versions
# and hosted sources still match the reviewed set.
dart pub get --offline
dart analyze --fatal-infos lib bin test
dart test -x integration --concurrency=2

#!/usr/bin/env bash
# CI/build hosts only. Does not modify the end user's machine at CLI runtime.
set -euo pipefail

# Builds the pinned libfido2 where the distribution's is too old.
build_libfido2() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-libfido2.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  curl --fail --location --retry 3 https://github.com/Yubico/libfido2/archive/refs/tags/1.17.0.tar.gz -o "$tmp/fido.tar.gz"
  printf '%s  %s\n' ace062d14a482ff9325410ff63d06c8b5fe87e79ebc18dda07add2bc0188c77f "$tmp/fido.tar.gz" | shasum -a 256 -c -
  tar -xzf "$tmp/fido.tar.gz" -C "$tmp"
  cmake -S "$tmp/libfido2-1.17.0" -B "$tmp/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_MANPAGES=OFF
  cmake --build "$tmp/build" --parallel 4
  sudo cmake --install "$tmp/build"
}

if [[ "$(uname -s)" == Darwin ]]; then
  # Homebrew's libfido2 brings the OpenSSL it links; Keypass bundles that one.
  # Refresh first so a runner's cached metadata does not pick an older build.
  brew update --quiet
  brew install cmake pkg-config libfido2
  otool -L "$(brew --prefix libfido2)/lib/libfido2.1.dylib" | grep libcrypto
  exit
fi
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config libssl-dev libudev-dev libcbor-dev zlib1g-dev curl ca-certificates patchelf
if pkg-config --atleast-version=1.16 libfido2; then exit; fi
build_libfido2
sudo ldconfig

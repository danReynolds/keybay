#!/usr/bin/env bash
# CI/build hosts only. Does not modify the end user's machine at CLI runtime.
set -euo pipefail

# Builds the pinned libfido2 into /usr/local, which pkg-config searches by
# default. Keypass's build hook cannot be pointed elsewhere: Dart build hooks
# drop PKG_CONFIG_PATH from their environment.
build_libfido2() {
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/keybay-libfido2.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  curl --fail --location --retry 3 https://github.com/Yubico/libfido2/archive/refs/tags/1.17.0.tar.gz -o "$tmp/fido.tar.gz"
  printf '%s  %s\n' ace062d14a482ff9325410ff63d06c8b5fe87e79ebc18dda07add2bc0188c77f "$tmp/fido.tar.gz" | shasum -a 256 -c -
  tar -xzf "$tmp/fido.tar.gz" -C "$tmp"
  cmake -S "$tmp/libfido2-1.17.0" -B "$tmp/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_MANPAGES=OFF "$@"
  cmake --build "$tmp/build" --parallel 4
  sudo cmake --install "$tmp/build"
}

if [[ "$(uname -s)" == Darwin ]]; then
  brew install cmake pkg-config libcbor openssl@3
  # Keypass 0.1.0-dev.2 bundles OpenSSL 3, but Homebrew's libfido2 now links
  # OpenSSL 4. Keep an installed libfido2 only while it links OpenSSL 3.
  if pkg-config --atleast-version=1.16 libfido2; then
    if otool -L "$(pkg-config --variable=libdir libfido2)/libfido2.1.dylib" | grep -q 'libcrypto\.3\.dylib'; then exit; fi
    echo "The installed libfido2 does not link OpenSSL 3, which Keypass bundles; uninstall it first." >&2
    exit 1
  fi
  openssl="$(brew --prefix openssl@3)"
  PKG_CONFIG_PATH="$openssl/lib/pkgconfig" build_libfido2 -DCMAKE_PREFIX_PATH="$openssl;$(brew --prefix libcbor)"
  exit
fi
sudo apt-get update
sudo apt-get install -y build-essential cmake pkg-config libssl-dev libudev-dev libcbor-dev zlib1g-dev curl ca-certificates patchelf
if pkg-config --atleast-version=1.16 libfido2; then exit; fi
build_libfido2
sudo ldconfig

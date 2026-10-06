# Native CLI hardware builds

The hardware route uses the exact hosted Keypass prerelease, libfido2 >= 1.16,
OpenSSL 3 and CBOR. `tool/build_cli_hardware.sh` resolves the source from Dart's
package configuration and verifies native inputs against `tool/keypass-source.json`,
which records the reviewed release commit, registry archive hash and file hashes.
It rejects modified, missing, additional or linked native inputs,
runs its native tests, and creates a relocatable bundle. It does not access a
device or vault.

## Local build and verification

Install build dependencies on a development/CI host with
`bash tool/install_cli_hardware_build_deps.sh`. This uses Homebrew on macOS;
on Linux it installs development packages and, when necessary, builds
checksum-pinned libfido2 1.17.0. End users do not run this script.

```sh
bash tool/build_cli_release.sh build/cli-candidate
bash tool/test_cli_hardware_bundle.sh build/cli-candidate
# macOS only; use the intended Developer ID and Team ID:
bash tool/sign_cli_macos.sh build/cli-candidate/keybay "$SIGNING_IDENTITY" "$TEAM_ID"
bash tool/package_cli_release.sh build/cli-candidate/keybay \
  build/keybay-candidate.tar.gz build/cli-candidate
bash tool/verify_cli_archive.sh build/keybay-candidate.tar.gz
```

The archive includes the CLI, four native libraries, dependency license notices,
`hardware.json`, and the existing quickstart files. The manifest records native
file hashes, Keypass revision, architecture and dependency versions. Hashes
detect inconsistent packaging; release checksums/signatures establish provenance.
Archive validation reads metadata and bytes without extracting or executing a
candidate. Its exact allowlist rejects missing libraries, unexpected files,
links, traversal, duplicate members and changed digests.

On macOS the CLI is a native launcher, a dedicated matching Dart runtime and
an AOT module, plus the Dart license. It resolves installed companions through
the executable's real path, including a Homebrew-style symlink. Single-file
`dart compile exe` remains useful for development but is not the hardened
release format. Build stages replace executable files by rename to avoid stale
kernel signature caches from overwriting previously executed Mach-O files.

The hardware libraries use relative dependency paths and `@rpath` install IDs.
Signing includes all libraries and the module before the runtime. The runtime
keeps the CLI's frozen signing identity, enables hardened runtime, carries no
entitlement exceptions, and admits only the exact signed code hashes of its
module and native libraries. macOS system libraries remain available. Verification
checks the signatures, Team ID, timestamps and the exact load constraint.

The local Homebrew renderer installs companions together in `libexec`, links the
launcher into `bin`, and preserves rpath names so Homebrew does not rewrite and
invalidate their signatures. This renderer is not an end-to-end release-kit
publication qualification. Release-kit's existing Dart runtime/module layout
still needs to carry the hardware companions through its staging/signing and
publication path before releasing this feature.

On Linux the CLI remains a native Dart executable. Its adapter and bundled
libfido2/OpenSSL/CBOR libraries use `$ORIGIN` for resolution. The OS still supplies
glibc, libstdc++, libgcc, libudev, zlib and (when the OpenSSL build uses it) zstd.
The bundle is specific to its build architecture and libc baseline; it is not
a claim of compatibility with every Linux distribution. A release lane must
build against the supported baseline and test the installed artifact there.
Ordinary users also need their distribution's FIDO USB HID access rules. Do not
run Keybay as root to work around missing device access.

## Source execution

Keypass now owns a Dart code-assets hook. `dart run` and `dart test` prepare the
adapter and its dependency closure on a matching desktop build host. `dart
build cli` produces a relocatable `bin`/`lib` bundle. The consumer no longer
needs a native-library path in ordinary source execution. The native development
prerequisites above still apply.

The custom signed-runtime build in this document explicitly uses Keypass's
manual-bundle compatibility mode. It retains the tested signing/layout contract
until the release builder can consume code assets in that format. This is
separate from automatic local hook preparation; do not switch the signed release
to the SDK's single-file executable without requalifying its hardened launch.

Dart 3.12's hook discovery is sensitive to invocation cwd. A generic rk local
bootstrap prepares hooks in the owning project and then launches the original
entrypoint with the caller cwd. A previously prepared cache alone is insufficient
proof; qualification covers cold launch and native source edits from another cwd.

## Physical test handoff

`bash tool/build_cli_hardware_test.sh` preserves a unique disposable application
identity in `build/hardware-tui-test/application-id`, uses a separate test RP,
and bundles the native libraries. It never opens the ordinary CLI vault.

1. Open `Start hardware test.command`. In Settings → Security, add the key.
   Enter its existing PIN only if asked, then touch it when it flashes.
2. Quit and reopen the launcher. Unlock the selected method and confirm the
   seeded `hardware-test/marker` is present.
3. Open `Test command unlock.command` to authenticate a fresh `list` command.
4. Exercise cancellation and removal in the TUI. Removal changes local vault
   protection; it does not delete the passkey from the physical authenticator.

Build and operation receipts record revisions, file hashes, process IDs and
outcomes. They omit PINs, PRF material, vault keys and credential records.
Fake-provider PTY tests and no-device ABI probes do not qualify these ceremonies.
OS enumeration cannot be forcibly interrupted inside libfido2; cancellation is
forwarded immediately, but completion still waits for that OS call to return.
Physical latency, disconnection and credential capability checks remain attended
tests. Notarization and installed upgrades are
separate release gates, tracked in [release readiness](release-readiness.md).

# Native CLI hardware builds

The hardware route uses the exact hosted Keypass prerelease, libfido2 >= 1.16,
OpenSSL 3 or 4 (whichever libfido2 links) and CBOR. `tool/build_cli_hardware.sh` resolves the source from Dart's
package configuration and verifies native inputs against `tool/keypass-source.json`,
which records the reviewed release commit, registry archive hash and file hashes.
It rejects modified, missing, additional or linked native inputs,
runs its native tests, and invokes Keypass's bundler for local qualification.
It does not access a device or vault.

## Build and verification

Install development dependencies with
`bash tool/install_cli_hardware_build_deps.sh`. End users install the finished
CLI and do not need compilers or native development libraries.

Keypass owns native dependency discovery and relocation in `hook/bundle.py`.
RK owns release builds, code-asset layout, signing, notarization, archives,
checksums and Homebrew publication, configured in `release.toml`. Stage the
release with `rk stage keybay_cli` and publish with `rk release keybay_cli`.
The release archive declares its layout in `rk-artifact.json`.

For local qualification on the supported Dart SDK floor:

```sh
bash tool/build_cli_test_bundle.sh build/cli-test
bash tool/test_cli_hardware_bundle.sh build/cli-test
```

This is a disposable test bundle, not a second release format. Its `hardware.json`
is a local file-integrity receipt; it is never used by RK publication. Native
source inputs, including Keypass's bundler, are checked against the pinned hosted
package. The test bundle verifies relocation without a device ceremony.

The narrow `keybay_compile` helper and explicit native-host loading remain
necessary because stock Dart cannot yet pass compile-time declarations through
`dart build cli` or emit the separate AOT module used by hardened macOS hosts.
RK provides these capabilities through its hook-aware build helper for releases.
There is no retry through the manual loader when a code asset fails.

On macOS releases contain a launcher, a dedicated matching Dart runtime, an
AOT module and native code assets. RK signs the complete bundle, constrains
runtime library loading to the signed companions, and preserves the frozen
CLI signing identity through installation. Local ad-hoc tests do not establish
Developer ID, notarization or installed-release qualification.

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


## RK release environment

Native Linux releases target **glibc 2.35 or newer**, built on Ubuntu 22.04 for
x64 and ARM64. The native build tools are confined to release builders. Runtime
systems must still supply libstdc++, libgcc, libudev, zlib and any system
libraries required by the bundled OpenSSL build. Alpine/musl is not supported.
A source build uses its host's ABI and does not establish this release baseline.

Build the two images from the repository root:

```sh
docker build --platform linux/arm64 -f tool/linux_release.Dockerfile -t keybay-release:arm64 .
docker build --platform linux/amd64 -f tool/linux_release.Dockerfile -t keybay-release:amd64 .
export RK_DART_BUILD_IMAGE='keybay-release:{arch}'
```

The Dockerfile pins the Ubuntu image, Dart 3.13.5 archives, libfido2 1.17.0 and
RK's temporary native-build helper source. It rebuilds the helper inside each
target architecture. The Ubuntu package repositories supply build prerequisites;
the resulting image ID should be recorded with release qualification.

On macOS, select the matching stock Dart 3.13.5 SDK on PATH and set
`RK_DART_BUILD_TOOL` to the verified macOS helper from
[RK's preview release](https://github.com/danReynolds/release-kit/releases/tag/dart-build-patch-3.13.5-1).
Use an RK version with native bundle support and third-party notice support.
The normal workflow is then `rk stage keybay_cli --timings` followed by
`rk release keybay_cli`. Installed upgrade and actual hardware authentication
remain required application checks before publication.

`packages/keybay_cli/THIRD_PARTY_NOTICES.txt` is included by RK without a library
list or plugin. Regenerate it after updating `tool/licenses`:

```sh
python3 tool/sync_cli_notices.py
python3 tool/sync_cli_notices.py --check
```

Both the manual packager and RK use this same notice text. CI checks it remains
in sync. For baseline qualification, test native calls from the extracted
release on Ubuntu 22.04, Debian 12 and Ubuntu 24.04 with development library
paths unavailable; `--version` alone does not load the hardware adapter.

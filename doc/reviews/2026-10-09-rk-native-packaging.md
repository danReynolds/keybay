# RK native packaging qualification — October 9, 2026

The fixes in [RK #118](https://github.com/danReynolds/release-kit/pull/118) and
[Keybay #96](https://github.com/danReynolds/keybay/pull/96) close the observed
compiled-Local, missing-notice and Linux ABI failures. They have not published a
CLI release or changed the active installation.

## Candidate and results

- RK source: `3a984cbf1d8c2a4c706c2a09c600e6d2088f2e42`.
- Keybay staged source: `df377aaec87f50d1ce833003ebc12849bbf77722`.
- Stage: `586a22cc7f0b55b70b83017d9bbc0ab825371fc97ac6e48a8305a8ca4acc7fa3`.
- Default `rk use local` compiled real Keybay with its application ID and all
  four native libraries. Its isolated launcher returned 0.2.0 without Dart on PATH.
- The source-execution option is now `rk use local --clean`. It runs source on
  each launch; it does not delete caches. A regression observes an edit made
  after selection.
- All three release archives include the exact generated third-party notices.
- macOS ARM64: all seven code signatures verified; the existing published
  signing requirement and application ID were preserved. Apple accepted
  notarization, submission `e3e6d24d-d11c-4076-8aa2-673070d986a5`.
- A relocated macOS symlink launched help/version and its native worker loaded
  with source, Pub cache and Homebrew paths denied by the macOS sandbox.
- Linux ARM64 and x64: help/version and native worker loading passed in minimal
  Ubuntu 22.04, Debian 12 and Ubuntu 24.04 containers, without network or mounted
  development libraries. x64 was emulated on the ARM64 host.
- Removing bundled libfido2 caused the native probe to fail on every runtime.

The Linux builder now uses Ubuntu 22.04/glibc 2.35. Previously, an adapter built
on Debian trixie failed to load on Debian 12 because it required GLIBC_2.38.
The new candidate passes that previously failing runtime on both architectures.

| Archive | SHA-256 |
| --- | --- |
| macos-arm64 | `b835901293822a676957db8750f5941ac0dcf91174a05589acec548de2a5923c` |
| linux-arm64 | `e9ce4b360dcf13e8b6dc6fd0f7d66de31e4ddf9c6cf6360e25b4257fe8e9b5a6` |
| linux-x64 | `120c39ae5f97d9f3a10bbacc0a162c9e6d5e78436c571025132cb99a596cee0b` |

Local receipts and probe source are retained in
`build/qualification/rk-native-fixes-20261009/`; these are local evidence, not
public downloads. Builder and minimal-runtime image IDs are in `results.json`.
The [packaging guide](../cli-hardware-packaging.md#rk-release-environment)
records the release environment.

## Remaining boundary

The native probe checks ABI 1 and the worker response to an invalid operation;
it does not authenticate with a physical device or access a vault. Private
staging and accepted notarization do not establish installed upgrades,
protected-store continuity, downloaded quarantine launch or public distribution.
Those checks remain in [release readiness](../release-readiness.md).
Any source change requires a fresh release stage; these hashes describe the
exact candidate above, before this documentation-only follow-up.

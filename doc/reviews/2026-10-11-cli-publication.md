# CLI 0.2.0 publication, October 11, 2026

[Keybay CLI 0.2.0](https://github.com/danReynolds/keybay/releases/tag/keybay_cli-v0.2.0) is published for macOS ARM64,
Linux ARM64 and Linux x64. GitHub and the public Homebrew formula were verified
after publication. The SDK and CLI remain independent release units.

## Provenance and public artifacts

- Source: `607b070d75c3d9facee9a4b10064cfac55fb837b`, documentation PR #98 merged after all applicable checks passed.
- Full exact-commit [release CI](https://github.com/danReynolds/keybay/actions/runs/38159342058) passed every required lane.
- Signed tag: `keybay_cli-v0.2.0`; local SSH signature verification passed.
- Stage: `c5772f9b74e6187040b8c41ca26436ca1d703a49c68b6f0281b0a5b1ab03bf8e`; RK source `8e1b480d5dc1019fc1dadecedf2a079a7b02991b`.
- `rk release keybay_cli --yes --timings --json` completed with no problems. The tag, GitHub release and Homebrew targets reconciled as exact.
- Published at `2026-10-11T17:35:09Z`. All three archives and `release-manifest.json` were independently downloaded and matched the stage byte for byte.
- Manifest SHA-256: `15267fe64d8e16e46e15ea775bd6cb66793631b233121b2bbf02213c9d009c3f`. The signed tag annotation binds this digest and names the source commit above.

| Public archive | SHA-256 |
| --- | --- |
| keybay-0.2.0-linux-arm64.tar.gz | `e9ce4b360dcf13e8b6dc6fd0f7d66de31e4ddf9c6cf6360e25b4257fe8e9b5a6` |
| keybay-0.2.0-linux-x64.tar.gz | `120c39ae5f97d9f3a10bbacc0a162c9e6d5e78436c571025132cb99a596cee0b` |
| keybay-0.2.0-macos-arm64.tar.gz | `4918209f8c79a765c9e4da3a72f19ef38a74657c1b46a074cc9181ecee5cd930` |

## Installed public distribution

The actual `danReynolds/tap` formula upgraded this Mac's Homebrew installation
from 0.1.1 to 0.2.0. `brew test` and the installed version check passed. Every
archive file matched the installed bytes; Homebrew places README and LICENSE
at the keg root and keeps the remaining files in `libexec`. The public formula
matched the generated staged formula exactly.

All seven macOS code signatures and notarization tickets verified. The installed
hardware adapter loaded and passed its ABI/worker probe. No personal vault was
opened for this public-channel check. The old Homebrew keg was retained.

RK's GitHub route also installed the public 0.2.0 archive and its generated
launcher passed version/help checks, using an isolated `XDG_DATA_HOME`. The
maintainer's ordinary RK source selection was not changed. Its launcher can
shadow the Homebrew command; selecting Homebrew through RK is a separate user
preference from installing the public formula.

## Relationship to attended and Linux checks

The [candidate record](2026-10-11-cli-release-candidate.md) records the two
successful fresh-process YubiKey unlocks, confirmed by the user. The release
source differs from that candidate only in the changelog and release documents.
Linux archives are byte-for-byte identical to that candidate, retaining its
installed-product checks on ARM64 and emulated x64, and runtime load checks on
Ubuntu 22.04, Debian 12 and Ubuntu 24.04.

The macOS release was rebuilt and notarized after the documentation commit.
Its native payloads are identical after removing signatures; the Dart snapshot
embeds a different temporary build path and derived private-name hash. It
passed fresh signature/notarization, isolated launch, native-adapter loading,
and missing-library failure checks, plus the public Homebrew installation.
The earlier attended test is not represented as a new physical ceremony on the
rebuilt archive. Physical Linux hardware, fresh enrollment on this installed
candidate, and a fresh-machine Mac launch remain outside that evidence.

## SDK package verification

The latest declared versions were already published:

- [Keybay 0.2.0](https://pub.dev/packages/keybay/versions/0.2.0), published October 7. Served archive SHA-256: `f45c2df4b7e027d1555036caf6a01cfa58661a1acf924b01ce5c8bffa05ba61d`.
- [Keypass 0.1.0-dev.2](https://pub.dev/packages/keypass/versions/0.1.0-dev.2), published October 6. Served archive SHA-256: `9c46f2bb0413b4f891d5e7eddce46830d2fa4c5c83ebad08b14333efe051c1ec`.

Both registry checksums and served archives were reverified on October 11
against the intended sources. All Keybay files matched exactly; Keypass's only
difference was CRLF normalization of `native/android/gradlew.bat`, whose
normalized contents match. Neither version was republished or overwritten.
Keypass remains a prerelease; this CLI release does not promote it to stable.

## Upgrade scope and retained evidence

**V2 does not read or automatically migrate V1 stores.** Existing V1 data was
preserved in installed-product tests and remained readable with the old binary.
Keep access to the previous installation and transfer required secrets before
switching; an empty V2 vault is not a migration result.

Receipts, downloaded archives, final source CI, runtime comparisons and the
public Homebrew/RK results are retained locally under
`build/qualification/cli-production-20261010/`. The dated candidate evidence
retains its scope; publication adds no new lifecycle, rollback, transfer or
Argon2 performance guarantees.

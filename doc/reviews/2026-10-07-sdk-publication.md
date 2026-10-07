# SDK 0.2.0 publication, October 7, 2026

The SDK adds system and hardware passkey protection through exact-pinned
Keypass 0.1.0-dev.2. Credentials remain data-only; `Keybay.open(credential: ...)`
authenticates an enrolled method, while `session.auth.add` enrolls and
`session.auth.remove` removes one. A store permits zero or one passphrase and
multiple passkeys. Enrolled methods are alternatives; each still requires the
platform-protected root. Removing a method does not revoke old file snapshots.

## Publication provenance

- Signed tag: [v0.2.0](https://github.com/danReynolds/keybay/tree/v0.2.0),
  source `6d2add6a95fa42ef4775e458e4635c045f2cb99c`. Local SSH signature verification passed.
- Final full main CI: [37658108194](https://github.com/danReynolds/keybay/actions/runs/37658108194),
  all applicable jobs passed on the tagged commit.
- Release-kit private stage: `4537a15a5f27ce079cb4a6d2fec688a763f92ec9f7d06b9354a10184ad19526e`.
  Validation passed with only the four deliberate exact-dependency-pin warnings.
  Local stage/archive receipts are retained in
  `build/qualification/sdk-release-20261007/`.
- `rk release keybay --yes --json` completed successfully with no problems;
  both tag and registry targets verified as exact. Its receipt is retained as
  `build/qualification/sdk-release-20261007/sdk-release.json`.
- Registry publication: [keybay 0.2.0](https://pub.dev/packages/keybay/versions/0.2.0),
  `2026-10-07T17:47:06.265296Z`. The served archive matches the staged archive byte for byte.
- Registry archive SHA-256:
  `f45c2df4b7e027d1555036caf6a01cfa58661a1acf924b01ce5c8bffa05ba61d`.
- Canonical package-content digest:
  `56b4819537ed0ba9cb2f1f29d14bcb6b777f5990ea0e97a8fba02b44a2cff30b`.
- Independent [release audit 37661738639](https://github.com/danReynolds/keybay/actions/runs/37661738639)
  passed: signed source tag, exact main-commit CI and the package contents served
  by pub.dev all verified.

## Reviewed changes and qualification boundaries

PR #88 integrated Keypass. PR #91 completed hosted dependency closure,
updated security discovery and fixed test-worker startup orchestration.
PR #92 made the monitoring tools run directly in the Dart VM,
without triggering application-native build hooks.
PR #93 merged the completed all-source monitoring assessment. Its scan
[37651745087](https://github.com/danReynolds/keybay/actions/runs/37651745087)
ran successfully on `afcd3e298f249e469455191782f80e2119a82d70`;
raw report blob `7476c185b91c0fc45a14a938bed30756155d5880` records
39 signals, including eight new and one updated. The assessment established
no new blocking runtime finding; issues #75 and #76 remain bounded follow-ups.
The monitoring-health workflow also passed after the assessment merged.

PR #94 merged as `6d2add6a95fa42ef4775e458e4635c045f2cb99c` after
all applicable checks passed in run `37654416511`, attempt 2. Android API 36
needed a targeted retry: the first attempt exhausted its ten-minute job limit
during app compilation after slow dependency installation; no test failure was
reported before cancellation. The retry passed without changing code or checks.

PR #94 isolates the Linux packaged quickstart's data/config/runtime directories
and owns its Secret Service process. The previous main run inherited a malformed
runner keyring, and correctly failed closed. A local disposable Linux ARM64
Docker run passed the real packaged quickstart and benchmark even with an
intentionally invalid ambient keyring, whose bytes remained unchanged.

Retained failed main CI runs:

- `37649549606`: Intel macOS hit the cryptography dependency's ten-second
  Argon2 segment deadline during passphrase enrollment. The store failed closed.
  No KDF parameters or runtime deadline changed; the subsequent full run passed
  that lane. This is not accepted Argon2 latency/memory qualification.
- `37651739398`: all other lanes passed, but Linux's packaged quickstart
  inherited the invalid ambient keyring described above. PR #94 repairs the
  test fixture without weakening provider requirements.

The scoped pre-1.0 release retains the existing physical-device evidence and
its deferred lifecycle/performance work. This publication adds no new physical
passkey, lock/reboot, transfer, StrongBox, or Wayland qualification claim.
SDK 0.2.0 replaces the API and encrypted format from 0.1.x; it neither reads,
migrates nor removes V1 stores.

## CLI remains unpublished

Apple notarization access was restored after the developer agreement was
accepted, confirmed by a successful authenticated `notarytool history` query.
Release-kit staging then failed on all three configured CLI targets because
its binary builder invokes `dart compile`, which rejects Keypass build hooks.
No CLI artifact was published by that attempt.

Release-kit must carry the native hardware libraries through its build,
archive, signing, notarization and Homebrew paths. The existing macOS signed
runtime/module layout and library validation must be preserved. Local Keybay
manual-bundle checks do not substitute for qualification of the actual installed
release packages and upgrades on macOS ARM64, Linux x64 and Linux ARM64.

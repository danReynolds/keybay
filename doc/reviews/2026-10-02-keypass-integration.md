# Keypass integration engineering review

## Consumer contract follow-up — October 3, 2026

Following the API discussion, `open(credential:)` now only authenticates existing
protection, for passphrases and both passkey routes. A missing live file without
staging returns `storeNotFound` before root acquisition, derivation, or passkey
enrollment. Credential-free first use still creates an empty platform-only store;
`auth.add` explicitly enrolls protection before protected records are written.
The initialization helper no longer accepts a credential. Existing encrypted
formats, migration, rotation, and credential-record selection are unchanged.

The guide now shows reusable app-owned RP configuration and documents singleton
passphrase versus multiple alternative passkeys. This adds no global domain,
ambient configuration, or automatic system/hardware fallback.

Current local checks: SDK 585 passed / three D-Bus skips on Dart 3.12.2;
standalone SDK 583 passed / five host/SDK skips on Dart 3.11.0; 36 affected CLI
tests, seven Flutter demo tests, and 45 repository tests passed. The full CLI
run passed its 220 unaffected tests; all four old implicit-enrollment fixtures
were corrected and passed in the affected-suite rerun. SDK/CLI source and test
analysis, Flutter analysis, and changed-file formatting passed. No native-device
ceremony was rerun. The earlier review and native receipts below remain scoped
to their recorded revision; the dependency distribution blocker remains.

## Original integration review

Date: October 2, 2026. Scope: the Keybay SDK integration branch, based on
`d71eb38`, consuming Keypass commit
`78cbf68a52b9e11f22434059fcde8069a97b2bad`.

Keypass's consumer SDK was reviewed, cleaned up, and merged in
[Keypass PR 1](https://github.com/danReynolds/keypass/pull/1). Its ten CI jobs
passed. This record covers the subsequent Keybay integration, not a claim that
the new vault format has been qualified on physical devices.

## Design and review findings

The API uses `PasskeyCredential.system` and `.hardware` through the existing
`Keybay.open` and `session.auth` surface. Temporary Keypass results remain inside
Keybay. The protocol is specified in [RFC 0003](../rfcs/0003-passkey-methods.md).
Multiple methods are alternatives in addition to the mandatory platform root.

DX, security/ownership, format/migration, and dependency work received separate
agent reviews and regression checks. These are internal AI-assisted engineering
reviews, not an independent cryptographic or human security audit.

Final disposition: DX and security/ownership reviewers approved the scoped
implementation after remediation. A separate read-only format review approved
the metadata-capacity amendment. No implementation blocker remained for a draft
PR; dependency distribution and publication remain merge/release blockers.

The review identified and resolved these issues:

- **Surviving credentials during removal.** Persisting reusable method secrets
  under the old store key would undermine revocation. Each credential instead
  derives its own X25519 private key; only public keys and RFC 9180 HPKE store-key
  envelopes are saved. Rotation rewraps survivors without asking for them.
- **Counterless unlock races.** An unchanged passkey record still requires the
  final exact-prefix comparison. A concurrent auth change now prevents a stale
  opening operation from publishing its session, including across engines.
- **Interactive lock ownership.** Authentication preparation runs outside the
  exclusive file transaction. Commit checks the original authenticated prefix
  and rotates the latest records, preserving ordinary writes that completed
  while the prompt was pending.
- **Callback reentrancy.** A callback awaiting its own session operation could
  deadlock. Operations invoked from a live Keypass callback now fail promptly
  with `storeBusy`; normal outer callers remain queued. The guard expires when
  the credential ceremony settles.
- **Full-store metadata growth.** Legacy upgrade and growing verification
  counters require additional metadata bytes. Suite 2 reserves a bounded key
  package allowance outside the content budget; suite 1 and aggregate read
  bounds remain unchanged.
- **Late cancellation and cleanup.** Cancellation checks bracket provider
  creation, metadata persistence and open-resource cleanup. Failed opens clear
  provisional keys; owned Keypass results and derivation scratch are disposed.
- **Malformed input and method directories.** Invalid UTF-16 labels fail before
  a ceremony. Decoded records must match the method kind and have unique stable
  credential identities. Full manifest authentication precedes use of directory
  public keys for mutation.
- **Existing passphrase-only UI.** The CLI and mobile demo now reject
  passkey-only unlock with explicit unsupported-UI guidance. Mixed stores keep
  passphrase access. No passkey UI or automatic fallback is implied.

## Dependency review

The Git checkout and lockfile agree on the exact Keypass commit above. Keypass
is MIT licensed and adds PointyCastle 4.0.0 alongside the already present `ffi`.
The hosted PointyCastle SHA-256 is
`92aa3841d083cc4b0f4709b5c74fd6409a3e6ba833ffc7dc6a8fee096366acf5`.
Its use is concrete SHA-256 hashing and P-256 public-signature verification;
Keybay's vault encryption and HPKE use the existing pinned `cryptography`.
The workspace closure additionally contains `convert` 3.1.2. SDK and CLI
closure firewalls were updated, including the exact Keypass source and SHA.
The hosted dependency watcher now covers PointyCastle.

Forty-two Keypass WebAuthn/hardware verifier tests, using independent
Node/OpenSSL fixtures, passed against Keybay's resolved closure. Native
libfido2/OpenSSL/AndroidX and Apple host builds remain outside the Pub closure
and retain their own build/notices/device qualification obligations.

## Validation boundary

The new tests cover both credential routes with the real Keypass facade and a
fake provider boundary, mixed-method rotations, exact selection, persisted
verification state, corruption, wrong secrets, cancellation, buffer ownership,
cross-engine conflicts, callback reentrancy, legacy migration and failed
commits. HPKE has published RFC 9180 and independent Python fixtures, byte-wise
tampering, context and low-order-point checks. Existing store, KDF, POSIX,
process-crash and CLI suites remain part of validation.

Final local checks on macOS ARM64:

| Check | Result |
| --- | --- |
| SDK core, Dart 3.13.5 (`tool/test_e2e.sh core`) | 578 passed, three D-Bus-daemon skips; receipt `build/regression/run-Hpd8BT/report.json`. |
| SDK standalone, Dart 3.11.0 (`tool/test_sdk_standalone.sh`) | Analysis clean; 576 passed, five host/SDK-specific skips. |
| CLI unit/SDK-boundary/TUI tests | 224 passed. |
| CLI core runner, native builds, terminal/exec/clipboard/archive checks | Passed; receipt `build/regression/run-Gc5Acd/report.json`. |
| Flutter demo | Full analysis clean; seven tests passed. |
| Repository tooling | 45 tests passed. |
| Dart source analysis and formatting | Passed on the changed SDK, CLI and demo sources. |

The initial restricted-sandbox run could not use the fixture pipe descriptors
or update Dart's cache. The unrestricted disposable-fixture run above passed;
those environment failures were not suppressed by changing assertions. The
reports identify an uncommitted integration tree atop the named base, rather
than claiming the tests ran on that base commit alone.

The dependency remains a development Git pin. Keypass is private and unpublished
at review time. Public CI/consumer resolution and a hosted Keypass release are
required before merging a publishable Keybay change. Source analysis passes;
whole-package analysis and the unchanged publication gate correctly flag the
Git dependency. No publication warning or gate was suppressed.

Native passkey-host setup, CLI/demo passkey UI, and end-to-end physical-device
Keybay vault qualification remain separate work. Existing Keypass device probes
are not promoted to vault qualification. Managed-runtime erasure limits,
complete-snapshot rollback, and provider credential leftovers after failed
local enrollment remain explicit in RFC 0003.

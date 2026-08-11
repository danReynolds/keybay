# Platform e2e receipts

Dated records of `tool/test_e2e.sh` runs against platform keystore APIs,
including simulator/emulator paths where named. Each entry names the exact
commit, host, and per-leg result so downstream consumers can distinguish local,
CI, skipped, and unexecuted evidence. CI covers the unit, macOS-CLI, and Linux
legs on every push; the mobile legs run on a developer machine and are recorded
here.

## 2026-08-10 — platform matrix attempt, commit e1313c3

- **Host:** macOS (Darwin 25.2.0, Apple Silicon), Flutter 3.44.4, Xcode with
  iPhone 17 Pro simulator runtime, Android SDK with AVD `Keybay_API_33`
  (pixel_6, arm64-v8a, API 33 default image), CocoaPods 1.17.0.
- **Code identity:** `packages/keybay/lib` at this commit is byte-identical
  to the published `keybay 0.1.0` (`diff -rq` against the pub cache), so the
  exercised Keybay runtime library is the code that pinning consumers resolve.
  The Flutter harness and matrix tooling are repository-only test code.
- **Command:** `./tool/test_e2e.sh` (without `--entitled`).

| Leg | Result | Notes |
| --- | --- | --- |
| unit + analyze | FAIL (environmental) | The leg's leading `dart format --set-exit-if-changed` reformats under this host's newer SDK formatter, so the chain stopped before the tests. Re-run directly: `packages/keybay` 146 tests pass, `packages/keybay_cli` 67 tests pass. No code failure. |
| macOS CLI (login Keychain) | PASS | Real `SecItem` login-Keychain round trip. |
| Linux (gnome-keyring, Docker) | NOT RUN locally | Docker daemon unavailable on the host at run time. This leg runs against a real unlocked gnome-keyring in CI (`integration-linux`) on every push. |
| macOS .app (file scheme) | PASS | Sandboxed harness app, file scheme, login-Keychain root key. |
| iOS simulator (DP native items) | **PASS** | Real Data Protection Keychain API path on the iPhone 17 Pro simulator. |
| Android emulator (Keystore-wrapped) | **PASS** | Real Android Keystore KEK wrap on arm64 API 33; the suite asserts ciphertext plus the wrapped-key blob at the derived path and measures the security level from the KEK. |
| macOS entitled (DP success) | SKIP | Requires a signing identity (`--entitled`); the unsigned refusal/no-silent-downgrade branch is covered by CI unit tests. |

**Residuals this run does not cover:** the entitled-macOS Data Protection
success path (run `--entitled` on a machine with an Apple Development
identity); hardware StrongBox and OEM Keystore variance (simulator/emulator
images exercise the software Keystore/Keychain implementations — a thin
physical-device pass remains the final tier); and per-item hardware backing
on Apple platforms, which Keybay deliberately does not claim.

**Durable upgrade:** the Android leg is automatable on free CI runners
(e.g. `reactivecircus/android-emulator-runner` booting an API 31+ x86_64
image and running `example_flutter/integration_test/keybay_test.dart`), and
Android is the highest-risk backend. An emulator CI job would convert this
recorded receipt into a per-push guarantee. The format-check drift also
suggests pinning the Dart SDK for the `unit + analyze` leg (or scoping the
format gate to CI) so newer local toolchains do not produce false FAILs.

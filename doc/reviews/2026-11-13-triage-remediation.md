# Open-issue remediation plan — 2026-11-13

Baseline: `6eed3ebfa4e90785985fe87665c616fd6e0361cf`; working branch
`codex/triage-remediation`. This record tracks engineering work, not release
qualification. No SDK/CLI publication is planned. The coordinating chat owns
integration; workers have disjoint dependency, identity, and Android scopes.

## Priority and acceptance gates

1. **Restore the supply-chain gate (#120; dependency PRs #122–125).** Update
   Guava with verified Gradle metadata, and update Rails and its coupled gems
   together, including Crass, Rack, Nokogiri, and Loofah security fixes. Preserve
   lockfile integrity and scan policy. Validate examples and rerun the scan.
2. **Repair identity discovery (CI on #125).** Reproduce path activation and
   installed-executable failures on the affected SDK/platform. Preserve bounded
   identity discovery and owner validation. Require focused regressions,
   analysis, and macOS/Linux CI before accepting the repair.
3. **Complete monitoring backlog (#82, #121).** Review November 2 then
   November 9, preserving immutable raw reports. Publish with the verified
   assessment helper only, review exact heads, and merge only with green CI.
   Recheck health after publication; do not manually race the health issue writer.
4. **Harden Android first creation (#117).** Require definite absence before
   generating the fixed alias; preserve adopted-root conflict and non-mutating
   live-store failures. Review AOSP error semantics, add regressions, and retain
   physical Android qualification as a separate required gate.
5. **Renew Apple qualification (#76).** Record patched-host requirements and
   inspect available hosts. Run lifecycle/reset tests only on explicitly selected
   disposable test identities on an applicable patched physical host. This
   machine currently reports macOS 26.2 (25C56), so it cannot substantiate the
   patched October boundary. Do not update the host OS or touch real vaults.
6. **Refresh Go reference maintenance (#75).** Update compatible x/crypto,
   preserve reference vectors, and retain import-level disposition of unreachable
   advisories without module-wide suppression. This isolated work may run while
   higher-priority checks are in progress.
7. **Revisit remaining PRs.** Refresh/review the Actions dependency PR #119 after
   the shared gate clears. PR #116 requires review of its final fixes and fresh
   checks against current main; historical green checks are insufficient.

## Integration policy

Review stable diffs independently, fix findings, then run affected checks. Keep
security gates intact and document unavailable device evidence. Do not close
issues solely because code exists. Preserve the four pre-existing untracked
September review files. No private keys, real vault reset, or release publication
are authorized by this plan.

## Progress

- Confirmed the five open issues and seven PRs against GitHub.
- Confirmed November 2 and November 9 assessment publication is overdue.
- Dependency repair complete locally: Rails 8.1.4.1, Crass 1.0.8, Rack 3.2.8,
  Loofah 2.25.3, Nokogiri 1.19.7, sanitizer 1.7.2; Guava 33.7.2-android with
  refreshed checksum catalogs. Frozen Rails tests: 2 tests / 8 assertions.
  Gradle strict checkDebugAarMetadata passed; added checksums independently
  matched Maven Central artifacts and published SHA512.
- Go x/crypto v0.56.0 requires Go 1.26.0 and x/sys v0.47.0. All nine reference
  outputs remain unchanged; module verification and go test passed. Actual
  imports omit SSH/OpenPGP. GO-2026-5932 remains visible, with called:false;
  no module suppression was added. Host Go toolchain warnings are separate.
- CI-pinned OSV scanner and reporter v2.6.0 scanned all seven manifest locks
  (286 package records), with exit 0 from both, including fail-on-vuln=true.
  No Ruby/Guava findings remain. Native macOS builds of the pinned tools were
  used; the exact Linux action container and SARIF upload remain CI checks.
- Identity repair supports Linux Dart 3.14 installed split AOT images while
  retaining canonical runtime/bundle ownership and retained-metadata checks.
  Actual SDK probes established source-vs-snapshot activation behavior; tests
  now assert the actual evidence source without relaxing identity ownership.
  Sixty focused tests passed on Dart 3.12.2 and 3.14.0; Linux live mode needs CI.
- Android creation probes getKey before containsAlias, adopts existing AES
  roots and propagates lookup errors without generation. Observable non-key
  alias conflicts fail closed. Thirty-four provider/store tests passed.
  Public getKey can also return null for pure certificates: this is a bounded
  AES-root repair, not universal KEY_NOT_FOUND proof. Physical qualification
  remains outstanding and #117 must stay open.
- Independent reviews of the stable Android and identity changes found no
  actionable issues. Synthetic tests are not native-device qualification.
- Repository tests: 49 passed. SDK core: 614 passed, 3 existing skips.
  Repository analysis passed. Watcher format/analysis, 28 Dart tests,
  19 Python tests, and workflow lint passed.
- The local Homebrew libfido2 links OpenSSL 3 while default CMake/pkg-config
  selected OpenSSL 4. Tests used a temporary CMake wrapper consistently
  selecting OpenSSL 3. No system libraries or tracked build settings changed.
- Apple qualification remains blocked on an explicitly selected patched
  physical host. Existing receipts are not broadened. The maintained-patched-OS
  policy is already present in SECURITY.md.

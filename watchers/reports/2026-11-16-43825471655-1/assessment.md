<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-43825471655-1","status":"needs_attention","summary":"No new Keybay finding; existing Apple and Android provider qualification remains outstanding.","actions":[{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"},{"label":"Android provider qualification and alias assurance","url":"https://github.com/danReynolds/keybay/issues/117"}]} -->

# Assessment

Assessed November 16, 2026 against current main
`9967891254c48477edfad92bbcb5c09d73c9c221`, also the report's source.
Status: **needs attention** only for the two retained provider-qualification
actions. All three watchers completed. No new Keybay vulnerability, public
repair, private investigation, or physical-device trigger was established.
Raw blob: `b63c787cff932b9631d1febb52b6bcc5e6e5f14a` (unchanged).

## Delta and reuse

The 69 signals comprise **12 new, 3 updated, and 54 exact repeats** compared
with November 9: dependencies 0/0/3, platforms 4/0/7, and peers 8/3/44. The
three updated markers are the same peer items with changed update timestamps.

Reuse was checked against the implementation changes since the November 9 raw
report. The November 13 follow-up in that report already reassessed the merged
dependency, Android provider, Go-reference, and identity changes. Android now
uses `KeyStore.getKey` before `containsAlias`, while #117 remains open for
physical-provider qualification and residual alias-type assurance. The Go
reference now pins x/crypto 0.56.0 but still imports only ChaCha20-Poly1305.
The later process-hardening merge runs before `Keybay.open`; it does not change
provider selection, provider addresses, migration, synchronization, root
creation, reset, or crypto formats. Apple queries, Linux Secret Service/Portal
transport, and the relevant provider tests are otherwise unchanged. Exact
repeats therefore retain their prior dispositions on this updated basis.

## Dependencies — no new reachable finding

- **GO-2026-5932 — not applicable to reachable imports.** The advisory affects
  x/crypto OpenPGP. The nonshipping Go reference imports
  `chacha20poly1305`, and its dependency graph contains no OpenPGP or SSH
  package. Keep the module-level warning visible; it is not a shipped Keybay
  vulnerability or a reason to suppress full-graph scanning.
- **dbus 0.8.0 — no finding.** Its published changes add anonymous client
  authentication and record-shaped generated returns. Keybay remains exactly
  pinned to pure-Dart dbus 0.7.15 and uses a narrow typed call surface. The
  release does not identify a security fix required by Keybay.
- **Keypass 0.1.0-dev.3 — no finding; already adopted.** Current main is
  exactly pinned to dev.3. The signal does not establish a newer dependency or
  a new Keybay defect.

Sources examined include the OSV and Go records for
[GO-2026-5932](https://osv.dev/vulnerability/GO-2026-5932), the
[dbus changelog](https://pub.dev/packages/dbus/changelog), the
[Keypass changelog](https://pub.dev/packages/keypass/changelog), current lock
files, the Go import graph, and the prior assessment.

## Platforms — existing Apple action retained

- **Android September, October, and November bulletins — no Keybay-specific
  finding.** The published platform vulnerabilities do not identify Keybay's
  fixed AES Keystore root or establish a change to its fail-closed provider
  contract. Maintained patched hosts remain required. #117 independently
  retains Android JNI/physical-provider qualification; these repeated
  bulletins do not add a new device claim or repair.
- **Apple September 14 and October 26 — actionable public work already tracked
  by #76.** The published Keychain authorization, credential-deletion, System
  Keychain, and permissions changes touch the custody assumptions behind
  Keybay's Apple profiles. They do not establish access to Keybay's exact
  login-Keychain item or signed Data Protection access group. Qualification
  remains scoped to selected patched physical configurations. September 28
  adds no separate provider finding.
- **Apple November 9 — no finding.** All six release pages were reviewed. Their
  listed repairs concern AirPlay, Bluetooth, CoreUtils/rapportd, Messages,
  brotli, App Intents, and an older-iOS MediaRemote pairing issue. No published
  Keychain access-group, root-custody, synchronization, or provider-operation
  change broadens #76 or triggers additional physical qualification.
- **CVE-2026-120749 — no Keybay repair.** This repeated native dbus-daemon
  privileged-monitor abort is an OS availability issue. Keybay is not a
  monitor, never falls back on service failure, and bounds provider calls.
- **CVE-2026-128885 — not applicable to the reviewed configuration.** The
  native dbus `select()` fallback defect requires the intentionally compiled
  `BROKEN_POLL` path; Debian records normal Linux builds as unaffected. Keybay
  neither ships native libdbus nor selects that build configuration.
- **CVE-2026-128886 and CVE-2026-128987 — no Keybay repair.** These concern a
  native nonce-tcp accept/authentication stall and a native libdbus
  broken-pipe retry loop. Keybay is a pure-Dart session-bus client, not a
  nonce-tcp listener, and its Secret Service calls have total deadlines,
  connection teardown, typed unavailable failures, and no weaker fallback.
  Hosts should consume distribution fixes, but the records establish no
  Keybay confidentiality, integrity, or provider-transition defect.

The Android and Apple release pages, all four OSV distro records, Debian's
three new CVE records, Keybay's security invariants, provider source, tests,
and open issues #76/#117 were examined. The watcher succeeded, so no
watcher-health issue is warranted.

## Peers — mechanisms do not transfer

- Flutter Secure Storage #1309 repairs cached cipher selection after automatic
  migration when per-operation biometrics are requested. Keybay has neither
  that migration/cache path nor a per-operation biometric promise; its fixed
  Android AES root deliberately does not require user authentication, while
  optional Keybay methods recover cryptographic material separately.
- Flutter Secure Storage #1308 reports legacy-schema secrets returning after
  delete-all. Keybay never probes or migrates peer/V1 schemas, addresses one
  fixed V2 provider root, rejects retired encodings, and makes reset revalidate
  the prepared root, delete it, and verify absence. There is no matching
  resurrection path.
- Flutter Secure Storage #1310/#1292 are workflow/simulator updates and #1295
  is example build dependency maintenance. Python keyring #783 is test-fixture
  documentation, while #784 is a missing macOS credential-discovery API.
  Keybay imports none of those mechanisms and reads one derived Apple address.
- React Native Keychain #836 concerns AndroidX biometric availability on
  Android 10 and older. Keybay requires Android 12/API 31+, uses direct JNI
  Keystore operations, and does not use that AndroidX path.
- Go keyring #160 updates godbus. Keybay's production Linux client is Dart
  dbus, and its nonshipping Go reference does not import godbus. Rust keyring
  #379/#380 are dependency-lock and CI-action updates to libraries Keybay does
  not import.

The complete bodies and relevant diffs of all 11 new/updated peer items were
reviewed. Exact-repeat peer items retain the November 9 mechanism-specific
dispositions after the changed-boundary review above. No plausible
undisclosed Keybay vulnerability, public issue, private advisory, or new
physical-device qualification was warranted.

## Validation and limits

Focused current-source validation passed 86 Android, Apple, macOS Keychain,
and Linux Secret Service provider tests, plus `go test ./...` for the
nonshipping reference. The local Keypass hook initially rejected the host's
mixed OpenSSL 3/4 closure; tests passed through an isolated temporary wrapper
that selected Homebrew OpenSSL 3 consistently with libfido2, without changing
the repository or Homebrew installation.

Watcher formatting and analysis passed, as did 28 Dart watcher tests, 19
Python publication tests, workflow lint, diff checking, and raw-blob
verification. The publication helper's read-only plan verified Actions
provenance, current-main reconstruction, exact report scope, and the immutable
raw blob. This assessment is monitoring evidence, not a release certificate;
#76 and #117 remain qualification limits rather than evidence of a new defect.

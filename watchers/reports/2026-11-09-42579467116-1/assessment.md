<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-42579467116-1","status":"needs_attention","summary":"Merged dependency and identity remediation verified; Apple and Android provider qualification remain outstanding, with the unreachable residual Go warning retained.","actions":[{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"},{"label":"Android provider qualification and alias assurance","url":"https://github.com/danReynolds/keybay/issues/117"}]} -->

# Assessment

> Historical assessment and dated follow-up. The original assessment below
> retains its `6eed3eb` source basis, dispositions and validation. Its references
> to “current main,” open maintenance issues or watcher health describe that
> baseline. The November 13 follow-up records verified merged remediation and
> the remaining qualification limits; report publication and health recovery
> remain separate checks.

Assessed November 13, 2026 against main
`6eed3ebfa4e90785985fe87665c616fd6e0361cf`, also the report's source.
Status: **needs attention** for the four retained public follow-ups. All three
watchers completed. Monitoring health remains unhealthy until the November 2
and November 9 assessments reach main; collection success is not completion.
Raw blob: `111367817bfa028aa8bdbdc4f88a50ee655635fd` (unchanged).

## Delta and reuse

The 80 signals comprise **41 new, 8 updated, and 31 exact repeats** compared
with November 2: dependencies 0/0/8, platforms 2/0/5, peers 39/8/18.
An updated peer has the same repository/item and a changed update timestamp.
The prior assessment and this report use identical main source. Provider,
identity, storage, crypto, lockfiles, and security assumptions are unchanged
there, so exact repeats retain their prior disposition. Unmerged remediation
work is not credited as a completed fix or qualification in this assessment.

## Dependencies — actionable public maintenance

All eight markers repeat November 2. Guava and Crass example maintenance is
tracked in #120; four Go reference advisories in #75 remain outside the tool's
actual SSH/OpenPGP import graph. The dbus and Keypass release notifications do
not themselves establish a required security update. These are not findings
of a reachable vulnerability in the shipped Keybay SDK/CLI.

The newer November 12 PR scan also identifies Rails/Rack example updates.
Those findings postdate this immutable report and are included in the current
coordinated dependency repair, not silently inserted into raw discovery.
The gate must pass after refreshed locks; do not suppress module findings or
merge stale individual updates to bypass the full graph check.

## Platforms — maintained-host policy; existing Apple action retained

- The new [November Android bulletin](https://source.android.com/docs/security/bulletin/2026/2026-11-01)
  describes platform vulnerabilities and a November 5 patch level covering the
  bulletin. Its published entries do not identify a Keybay-specific failure or
  establish a change to the fixed AES Keystore root's behavior. Keybay already
  requires maintained patched hosts. General platform exploitability is not
  evidence of a Keybay authentication bypass; #117 independently retains the
  concrete Keystore lookup hardening and its Android qualification requirement.
- [CVE-2026-120749](https://ubuntu.com/security/CVE-2026-120749) concerns native
  dbus-daemon aborting when a privileged monitor is attached and a driver
  broadcast cannot be delivered. It is an availability issue in the OS daemon,
  not the Dart dbus package. Keybay does not run a monitoring client; its
  Secret Service adapter uses bounded calls, rejects unavailable providers,
  and has no weaker storage fallback. Existing timeout/disconnect failure
  handling is the relevant boundary. Keep the host patched as distro fixes
  become available; the consulted Ubuntu record still says needs evaluation.
  No specific Keybay repair or physical-device claim follows from this signal.
- Five prior platform markers repeat. Apple qualification remains required in
  #76, including the October Keychain permissions signal. This host still runs
  macOS 26.2 build 25C56 and cannot qualify the patched October releases.

## Peers — mechanisms checked against Keybay

- Flutter Secure Storage #1293 concerns migration of EncryptedSharedPreferences
  and #1297 browser first-write races. Keybay does not import that migration or
  browser storage mechanism; native initialization is serialized and legacy
  formats are rejected rather than automatically migrated. Updated #1298 and
  #1306 retain the narrower Android first-creation action in #117. #1299's
  multi-engine RSA race does not remove Keybay's profile-level process lock or
  adopted-root conflict behavior. Its reset/migration design is not Keybay's.
- React Native Keychain [#800](https://github.com/oblador/react-native-keychain/issues/800)
  and [#824](https://github.com/oblador/react-native-keychain/pull/824) concern a
  bridged false boolean enabling cloud synchronization. Keybay supplies the
  actual `kCFBooleanFalse` on add and has no caller cloud-sync option. Its
  signed Data Protection profile is device-only. [#833](https://github.com/oblador/react-native-keychain/pull/833)
  also repairs deletion missing an access-group constraint: Keybay's exact
  delete includes its fixed access-group, service/account and Keychain family.
  #827/#828 service enumeration and persisted authentication options do not
  match Keybay's authenticated manifest and credential-method construction.
  #818/#829 concern Android DataStore native payload alignment; Keybay does not
  use that storage backend. Prompt defaults, false-result documentation,
  SwiftPM/New Architecture, release, UI and test changes add no Keybay defect.
- Go keyring [#161](https://github.com/zalando/go-keyring/issues/161) and
  [#162](https://github.com/zalando/go-keyring/pull/162) ignore a dismissed Secret
  Service prompt. Keybay never calls Unlock, Prompt, or CreateCollection and
  rejects returned prompt paths, so that dismissal-success path is absent.
  #158's optional direct Security framework backend is a peer API change;
  Keybay already uses direct framework calls and explicitly distinguishes
  account-level login Keychain from signed-group protection.
- Python keyring #781/#782 concern duplicate Windows credentials; Windows is
  unsupported in Keybay. Rust keyring #376 requests Secret Portal support;
  Keybay's Flatpak candidate already uses the Portal without falling back to
  raw Secret Service. Peer dependency, release, documentation, packaging,
  coverage and workflow changes are not imported runtime changes.

The complete peer issue/PR bodies were consulted, including runtime changes
inside test-labelled PR #833. Exact repeats retain the November 2 rationale.
No plausible undisclosed Keybay vulnerability was identified by this review.
No watcher failed, so no new watcher-failure issue or private advisory is
warranted. The existing overdue issue #82 remains accurate until publication.

## Validation and limits

Watcher formatting and analysis passed, as did 28 Dart watcher tests, 19 Python
publication tests, and workflow lint. The publication helper verified the
Actions provenance, report-only scope, and immutable raw blob in its read-only
plan. The generated summary is rebuilt from current main by that helper.
Local Dart tests used a temporary CMake wrapper selecting the installed OpenSSL
3 library consistently with libfido2; no system or repository build settings
were changed.
This assessment is monitoring evidence, not a release certificate. Provider
qualification and unmerged code repairs remain separate work.

## November 13 follow-up — verified PR #126 remediation

[PR #126](https://github.com/danReynolds/keybay/pull/126) merged as
`1f22a4c1fc74702cea0490fbb65d5e9ace6530b1`. Its tree exactly matches the
independently reviewed candidate
`fc9e59b7d224c1cce201c9b74b7fa8b7e7a0958d`; the tree comparison has no diff.
This dated follow-up reassesses the changed dependency, Android-provider and
identity boundaries. It supersedes their outstanding-maintenance/reuse
statements in the historical baseline above, while preserving the original
raw discovery, signal counts and assessment record.

### Reassessment of affected repeats

- **Example dependencies remediated.** The merged Android example selects
  Guava 33.7.2-android with refreshed Gradle verification metadata. The Rails
  example resolves Rails 8.1.4.1, Crass 1.0.8, Rack 3.2.8, Loofah 2.25.3,
  Nokogiri 1.19.7 and sanitizer 1.7.2. The original Guava/Crass markers are
  now remediated in the committed examples. Later Rails/Rack findings are
  later evidence, not additions to this report's immutable discovery set.
  [#120](https://github.com/danReynolds/keybay/issues/120) is closed completed;
  dependency PRs #122–125 were closed as superseded by the coordinated repair.
- **Go reference maintenance completed, warning retained.** The merge updates
  x/crypto to v0.56.0 and x/sys to v0.47.0, requiring Go 1.26.0. Recorded local
  module verification/tests passed and all nine reference outputs remained
  unchanged. [#75](https://github.com/danReynolds/keybay/issues/75) is closed
  completed. Actual imports still omit SSH/OpenPGP; GO-2026-5932 remains a
  visible module-level warning with `called:false`. That residual warning
  does not reopen #75 or imply an empty advisory set. Keep its import-level
  disposition visible without module-wide suppression, and assess host Go
  toolchain advisories separately. The dbus/Keypass release-marker conclusions
  are unchanged.
- **Android first creation remains bounded (#117).** The merged repair uses
  public `KeyStore.getKey` before `containsAlias`: an existing AES root is
  adopted, lookup exceptions stop before generation, and an observable
  non-key alias conflict fails closed. This replaces the old
  containsAlias-only implementation basis for Flutter Secure Storage
  #1298/#1306. The profile lock, adopted-root conflict and non-mutating
  live-store paths remain. Public getKey can also return null for pure
  certificate entries; this is AES-root hardening, not universal proof of
  `KEY_NOT_FOUND`. **#117 stays open** for physical Android provider
  qualification and remaining alias-type assurance. The 34 local
  provider/store tests establish synthetic policy and continuity evidence;
  they are not JNI or physical-device qualification.
- **Identity repair qualified in CI.** Linux Dart 3.14 split installed AOT
  images now require the canonical runtime in the same bundle while retaining
  metadata and embedded-declaration agreement checks. Activation tests assert
  the observed source or snapshot evidence and its owning package. Actual
  Linux identity execution passed in the final CI run; recorded local suites
  also passed 60 focused tests each on macOS Dart 3.12.2 and 3.14.0. Identity
  source is therefore a reviewed changed boundary, rather than unchanged
  repeat evidence. The repair does not change the reviewed peer
  storage/migration mechanisms, crypto format, provider addresses for the
  same resolved identity or existing lock policy.
- **Provider qualification remains outstanding (#76/#117).** Apple
  access-group, synchronization and exact-delete checks, Secret Service
  prompt rejection, and the Linux daemon availability disposition retain
  their source basis. #76 still requires qualification on an applicable
  patched physical Apple host; the observed macOS 26.2 (25C56) machine cannot
  qualify the patched October boundary. No Android/Apple physical test was
  run for this follow-up. Other peer/platform repeats retain their bounded
  prior dispositions. CI does not broaden earlier native-device receipts.

### Validation and publication boundary

All applicable checks passed in
[CI run 43449453052, attempt 2](https://github.com/danReynolds/keybay/actions/runs/43449453052/attempts/2),
including actual Linux identity modes. The required full-lockfile OSV gate
passed in
[supply-chain run 43449452959](https://github.com/danReynolds/keybay/actions/runs/43449452959)
with existing scan policy intact. The Flatpak retry passed. The initial Intel
core execution stalled and was cancelled without diagnostic logs; the
unchanged retry passed all checks. No cause for that initial stall is claimed.

The assessment is ready for the verified publication workflow, which must
recheck current main, preserve the original raw blob byte-for-byte, rebuild
and review the generated summary, and require green report-PR checks. This
follow-up does not itself publish or merge either report. Recheck watcher
health after both overdue assessments reach main; collection, repair and
prepared assessments do not establish that #82 is complete. This is
monitoring/remediation evidence, not physical-provider or release
qualification.

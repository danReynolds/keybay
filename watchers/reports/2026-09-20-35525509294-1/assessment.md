<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-35525509294-1","status":"needs_attention","summary":"Peer signals were assessed; Go reference dependency maintenance and updated Apple provider qualification remain tracked follow-ups.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention**

Assessed 2026-09-20 against corrected main `6194a229c418b190dce61ea621ee55153febd92f`. The successful manual all-source run used `.github/workflows/security-watchers.yml`; its unchanged raw blob is `8839aa052c77e64662e1c9b949f034ab4f42c0ca`. This triage is not release clearance.

## Dependencies

Four OSV warnings target `golang.org/x/crypto v0.52.0` in `tool/v2_suite1_reference_go/go.mod`: CVE-2026-56854 / GO-2026-6303, CVE-2026-56855 / GO-2026-6355, CVE-2026-78662 / GO-2026-6354, and GO-2026-5932. Their affected code is SSH and OpenPGP. The reference executable imports `chacha20poly1305`; source inspection plus `go list -deps ./...` found neither affected package. The Go tool is retained format evidence, not a shipped Dart SDK/CLI dependency. No reachable Keybay runtime vulnerability is established. Review an updated compatible reference module. The current OSV analysis retains four warnings; the v2.6 reporter fails only findings classified as called, consistent with the verified absent imports. No gate defect was demonstrated. Do not suppress the complete module. The OpenPGP advisory has no fixed version.

The [dbus 0.8.0 changelog](https://pub.dev/packages/dbus/changelog) adds anonymous client authentication and Dart-record code generation. No security fix requiring adoption was established. Keybay keeps its reviewed exact 0.7.15 pin and existing Unix-session D-Bus authentication; it does not opt into anonymous authentication.

## Platforms

The five Apple release bulletins were reviewed: [iOS 26.7](https://support.apple.com/en-us/149041), [iOS 27](https://support.apple.com/en-us/149034), [macOS 27](https://support.apple.com/en-us/149035), [macOS 15.8](https://support.apple.com/en-us/149043), and [macOS 26.7](https://support.apple.com/en-us/149042). Keychain Access authorization, Authentication Services deletion, MediaRemote System Keychain access, and AppleKeyStore termination fixes can affect platform-custody assumptions. The brief descriptions do not establish access to Keybay's exact item/group. Updated-host provider and applicable physical-device qualification is a concrete follow-up; existing receipts stay bound to their recorded OS and source. No OS upgrade was performed by this review.

## Peers

All 98 signals were compared with current V2. Seventy-six URLs overlap the three backlog assessments; their current source contents were reviewed together, and 22 additional URLs were examined. No additional applicable Keybay defect was identified.

- Android namespace deletion and migration reports (1144, 1265, 1266 and earlier upgrade reports) concern shared preference files, prefixes, cached instances, Tink and reset-on-error. Keybay has one immutable application binding, a dedicated framed store, no legacy migrator and no automatic reset. Its exact provider reset and file-generation revocation are explicit.
- Biometric per-operation/cancellation/recovery changes (1264, 1267, 1268, 1271) concern authentication features Keybay does not implement. The initialization report 1276 is an Android 8 missing BiometricPrompt class; Keybay requires Android 12+ and uses no BiometricPrompt/plugin lifecycle.
- Apple accessibility query changes (1269 and associated releases) retain the earlier disposition: Keybay lookup does not filter by accessibility, and its fixed profile is selected explicitly. The provisioning documentation (1270) does not change Keybay's distinct entitled and login-Keychain boundaries.
- Python keyring PR 767 corrects empty piped input falling into a prompt. Keybay deliberately rejects empty `set --stdin` input and never crosses from pipe to terminal value input; the controlling-terminal passphrase channel is separately tested.
- Linux alternative-provider documentation (1273, 1275) does not change Keybay's typed Secret Service/Portal selection, fixed attributes or no-fallback rule. SPM, Kotlin/Rust workflow, platform-interface and release-only entries are peer maintenance, not Keybay dependencies.
- Remaining overlapping signals retain the V2-specific Android, Apple, Linux and native-protocol dispositions documented in the backlog assessments. No per-record Keychain, secret-tool or React DataStore architecture was assumed.

## Actions

- [Go reference dependency maintenance and advisory disposition (#75)](https://github.com/danReynolds/keybay/issues/75).
- [Apple provider qualification on September security updates (#76)](https://github.com/danReynolds/keybay/issues/76).

Both are public maintenance/qualification follow-ups. No plausible undisclosed Keybay vulnerability was identified, so no private advisory was created.

<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-37651745087-1","status":"needs_attention","summary":"All sources completed; no new Keybay defect established. Existing Go-reference and Apple qualification follow-ups remain.","actions":[{"label":"Go reference dependency maintenance","url":"https://github.com/danReynolds/keybay/issues/75"},{"label":"Apple provider qualification","url":"https://github.com/danReynolds/keybay/issues/76"}]} -->

# Assessment

Status: **Needs attention** for existing tracked follow-ups; all three watchers completed.

Assessed on 2026-10-07 against `afcd3e298f249e469455191782f80e2119a82d70`. The successful manual all-source
Actions run [37651745087](https://github.com/danReynolds/keybay/actions/runs/37651745087) used the reviewed default-branch watcher. Its report-only
branch and immutable raw blob `7476c185b91c0fc45a14a938bed30756155d5880` were verified before assessment.
This is monitoring and triage evidence, not a release certificate or renewed
physical-device qualification.

## Delta and reuse basis

The report contains **39 signals: 8 new, 1 updated and 30 reused**. There are
five dependency, four platform and thirty peer markers. Counts were compared
against all retained raw reports; exact repeated markers are reused only for
the unchanged mechanisms identified below. See the [October 5 assessment](../2026-10-05-37280532141-1/assessment.md)
and [September 28 assessment](../2026-09-28-36394038936-1/assessment.md).

Since the October 5 assessment, Keybay added multi-method passkey protection
and CLI hardware flows, pinned hosted Keypass, and migrated Fleury to its hosted
widget catalog. Reuse is therefore mechanism-specific, not an assertion that
the entire application is unchanged. The platform root adapters and their
insert-only creation, exact read-back and prepared-reset contracts are unchanged.
The nonshipping Go reference and reviewed D-Bus version are unchanged. The new
passkey route uses Keypass's Credential Manager/AuthenticationServices boundary;
it does not enable the peers' Keystore biometric-per-operation or automatic
reset modes. The authenticated methods layer fails closed on missing PRF output
and provider failures. Existing device receipts keep their original scope.

## Dependencies

The repeated Go x/crypto advisories concern SSH/OpenPGP code absent from the
nonshipping reference tool's dependency graph. They do not apply to the Dart
SDK/CLI runtime; reference-module maintenance remains tracked in
[issue #75](https://github.com/danReynolds/keybay/issues/75). The repeated D-Bus
0.8.0 release signal establishes no required security fix; the exact reviewed
0.7.15 pin remains. Hosted Keypass 0.1.0-dev.2 is now explicitly monitored.

## Platforms

Android's [September](https://source.android.com/docs/security/bulletin/2026/2026-09-01)
and [October](https://source.android.com/docs/security/bulletin/2026/2026-10-01)
bulletins were examined after fixing both the moved index and year-qualified
paths. They describe OS/framework/kernel/vendor fixes. No specific defect in
Keybay's Keystore or passkey mechanism was established. Supported deployments
must use a maintained OS with current security updates; the API minimum is not
an endorsement of an unpatched OS. Successful discovery closes the source-gap
condition tracked in [issue #89](https://github.com/danReynolds/keybay/issues/89).

The September 28 Apple group covers CoreGraphics CVE-2026-86950 in the
[iOS/iPadOS 26.7.1](https://support.apple.com/en-us/149226),
[macOS Sequoia 15.8.1](https://support.apple.com/en-us/149229) and
[macOS Tahoe 26.7.1](https://support.apple.com/en-us/149228) notices.
This is OS patch work, with no Keybay-specific parser or custody defect
established. The September 14 group retains the bounded qualification follow-up
in [issue #76](https://github.com/danReynolds/keybay/issues/76). Neither group
renews physical-device evidence or broadens a provider guarantee.

## Peers

- Flutter Secure Storage's [biometric key invalidation report](https://github.com/juliansteenbakker/flutter_secure_storage/issues/1285)
  depends on `requireBiometricsPerOperation`, biometric enrollment invalidation
  and recovery/deletion behavior. Keybay's root Keystore key explicitly sets
  user authentication to false, never automatically resets on an open failure,
  and uses Credential Manager for the separate passkey wrapper. The reported
  peer mechanism is not applicable. Provider/credential removal can still cause
  typed passkey failures; that is not a new successful lifecycle qualification.
- Flutter Secure Storage [#1286](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1286),
  [#1287](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1287),
  and updated [#1281](https://github.com/juliansteenbakker/flutter_secure_storage/pull/1281)
  change peer example/Gradle build dependencies, not Keybay runtime code.
- React Native Keychain's [DataStore alignment report](https://github.com/oblador/react-native-keychain/issues/818)
  concerns its DataStore native library and GNU_RELRO alignment. Keybay does not
  use that peer storage implementation. Keypass declares Credential Manager
  1.6.0 and Startup Runtime 1.2.0; this report establishes no shared failing
  native library. This is not a claim to have qualified every Android page-size
  and transitive dependency combination. Its [SwiftPM scaffold](https://github.com/oblador/react-native-keychain/pull/819)
  is React Native integration maintenance, outside Keybay's direct FFI bridge.
- Exact repeated peer signals retain the linked October 5 and September 28
  dispositions: biometric reset recursion, failed-update/delete replacement,
  denied-delete exception mapping, DataStore singleton, StrongBox RSA latency,
  unroot-caused authentication-tag reports, Python wrapper/type maintenance,
  unsupported Windows behavior and Rust release/CI maintenance. The relevant
  root-provider policies and absence of those peer runtimes remain unchanged.

No plausible undisclosed Keybay vulnerability was identified from these
signals. No new issue or private advisory was warranted. Issues #75 and #76
remain open; the Android monitoring repair is verified by this successful
all-source run. A `findings` status means reviewable input, not watcher failure.

The first repaired-source run, [37649554346](https://github.com/danReynolds/keybay/actions/runs/37649554346),
failed because launching these pure-Dart tools invoked the workspace native app
build hook on runners without its prerequisites. Report rendering failed too,
so that attempt produced no raw-report branch. Its Actions logs remain retained.
[PR #92](https://github.com/danReynolds/keybay/pull/92) isolates monitoring launches
from app hooks; this successful all-source run verifies the repair on main.

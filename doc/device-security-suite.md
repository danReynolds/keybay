# Keybay native and device security suite

For routine SDK regression runs, use `./tool/test_e2e.sh all` or a platform
subset. The [regression guide](platform-regression.md) describes that shared
local/CI entrypoint. This document covers the additional physical-device,
lifecycle, signing, and release evidence; routine success does not clear those
gates automatically.

> **V2 qualification status:** Android and iOS runner selections exercise the
> public V2 store and produce source/nonce-bound reports. Implementation of a
> runner is not physical-device qualification. Historical reports for the old
> API do not qualify V2. macOS has no V2 device-report adapter; its ordinary
> native-provider and signed-harness lanes are separate evidence.

The [latest platform qualification report](qualification-status.md) records
what passed, the tested source and environment, and the remaining gaps for each
platform. The notes below explain findings that shaped the current procedures.

The iOS baseline establishes in-process reopen for its recorded source. Earlier
repeated XCTest launches returned fresh seed results and did not establish
continuity; their cause remains unclassified. The replacement fixture requires
an explicit reopen phase and an existing store. It subsequently passed the
physical Profile/AOT separate-process procedure; the dated report links its
retained receipts. Application-update continuity remains a separate gate.

Review also found that iOS storage domains included the absolute application
container path, which the OS can change during an update. A regression reproduced
the failure by moving a complete container. The corrected iOS binding uses the
authenticated application identity and fixed container-relative location;
filesystem validation still uses the actual native container path. The regression
now preserves records and passphrase access after relocation and rejects an empty
replacement container with a retained provider root. Other profiles keep their
existing domain encoding. Physical update continuity remains to be established.
The simulator harness waits for Flutter's asynchronous accessibility startup
before recording the first test's handle baseline; normal leak verification
remains enabled.

Native qualification found that classic file Keychains can ignore the per-call
UI suppression flag. The protector now rejects interaction-forbidden
acquisitions before calling the native API; the locked regression verifies
that record operations do not enter that path. Trusted UI remains permitted
for open, authentication changes and reset. The SDK does not toggle the
process-global Keychain interaction setting.

This document owns Keybay's qualification procedures, security oracles, safety
rules, evidence handling, and trigger policy. The product
guarantees are normative in [design.md](design.md#security-guarantees); this
suite references their `KB-INV-*` identifiers rather than restating them.

The suite complements exploratory review. Exploration looks for new chains. A
finding becomes a permanent scenario only when a deterministic check protects a
meaningful Keybay guarantee or a plausible recurring platform behavior.

## Evidence classes

- `hermetic`: no real platform credential service.
- `native-host`: a real host service or signed host application.
- `virtual-device`: an Android emulator or iOS simulator using genuine APIs.
- `physical-device`: an explicitly selected physical target.

A lower class never substitutes for a scenario's minimum. One Pixel report
qualifies that device/build/provider configuration, not every Android OEM.
Functional support and a stronger qualified configuration are separate claims.

## Safety boundary

Automation may touch only the dedicated `dev.keybay.securityharness`
application and its one OS-derived V2 store. It must never
inspect or mutate another application's data, change a screen credential or
biometric enrollment, switch a personal backup transport, unlock a bootloader,
or collect a PIN, account credential, signing secret, raw serial, or UDID.

Baseline and `--tamper` runs may create and remove their own namespaced
application/key state. Artifact-tamper tests retain exact originals, restore
them in a `finally` path, and re-prove readability. `--tamper` also authorizes
deletion and replacement of only the dedicated harness KEK for the root-loss
challenges; package cleanup removes the remaining test state. Reset of any other package,
reboot, relock, provider locking, backup/restore, and transfer are separate
procedures requiring an exact target and explicit authorization. Cleanup is an
oracle: a passing report cannot survive failed cleanup.

## Execution policy

Two kinds of execution are enough:

1. **Continuous checks** run hermetic tests, deterministic mutation tests, real
   disposable login-Keychain/GNOME-Keyring integration, and maintained
   simulator/emulator lanes in CI.
2. **Qualification scenarios** run where OS policy, hardware, signing, or
   lifecycle behavior is part of the claim. Run the affected scenarios after a
   relevant implementation/platform change, advisory, incident, changed
   oracle, or before making a new claim. A version or release alone is not a
   trigger.

## Current runner

From the repository root:

```sh
./tool/device_security.sh doctor android
./tool/device_security.sh run android --device SERIAL
./tool/device_security.sh run android --device SERIAL --tamper \
  --allow-package-reset

./tool/device_security.sh doctor ios
./tool/device_security.sh run ios --device UDID

./tool/device_security.sh doctor macos

./tool/device_security.sh doctor linux
```

The current Flutter test transport requires the physical iOS target over USB;
Flutter 3.44's test command cannot publish its debugging port for wireless use.
macOS currently supports only `doctor` in this adapter; its native-provider
tests and signed Flutter harness have separate run paths.

Android package reset requires `--allow-package-reset` and is scoped to the
selected Android user. Linux has no device adapter yet; its real disposable
GNOME Keyring integration remains a Continuous check. Working artifacts go to
private directories under `build/device-security/`. Mobile scenarios use the
same V2 integration tests as the virtual-device lanes. Their names identify the
scenario; a separate metadata test binds the run nonce and checked source.
Flutter build output and JSON reporter output are separate private files, so
build messages cannot be mistaken for test outcomes. Review the sanitized
`report.json`, then attach it to the issue that triggered the run; raw logs stay
private and ephemeral.

## Executable inventory

Pending executable V2 coverage: `KB-INV-004`, `KB-INV-008`.

These lifecycle and backup/transfer obligations remain unqualified. The current
reopen and missing-root tests do not implement their physical procedures. The
repository coverage check keeps this gap visible; it does not turn it into a
passing scenario or a release claim.

[`tool/device_security/catalog.dart`](../tool/device_security/catalog.dart) is
the machine authority for runnable scenario identity, platform, guarantee
references, minimum evidence, and destructive classification. It contains no
planned scenarios, revisions, release tier, score, or roadmap state. The suite
source commit versions semantics.

<!-- BEGIN GENERATED DEVICE SECURITY INVENTORY -->
| ID | Platform | Guarantees | Minimum evidence | Destructive |
| --- | --- | --- | --- | --- |
| `KB-AND-001` | android | `KB-INV-005` | physical-device | no |
| `KB-AND-010` | android | `KB-INV-005` | physical-device | no |
| `KB-AND-011` | android | `KB-INV-001`, `KB-INV-002` | physical-device | no |
| `KB-AND-020` | android | `KB-INV-007` | physical-device | no |
| `KB-AND-030` | android | `KB-INV-003` | physical-device | no |
| `KB-AND-040` | android | `KB-INV-003`, `KB-INV-005` | physical-device | yes |
| `KB-IOS-001` | ios | `KB-INV-005` | physical-device | no |
| `KB-IOS-010` | ios | `KB-INV-005` | physical-device | no |
| `KB-IOS-020` | ios | `KB-INV-007` | physical-device | no |
<!-- END GENERATED DEVICE SECURITY INVENTORY -->

## Procedures and oracles

### `KB-AND-001`

Inventory the selected target; require API 31+, production physical hardware,
the requested Android user, and retained model/OS/API/patch/build plus verified
boot, lock, SELinux, and FBE facts. Reject an emulator or ambiguous target.

### `KB-AND-010`

Provision the one application KEK and query its native `KeyInfo` through the
harness oracle. Require AES-256, encrypt/decrypt purposes, GCM/NoPadding and no
per-use user authentication. `--expect-level hardware` requires TEE or StrongBox;
`software` requires software. The SDK does not expose or invent a hardware
capability result. API choice alone is not a hardware pass.

### `KB-AND-011`

Write string and binary canaries through `Keybay.open()`. Require one framed
ciphertext store in the native no-backup directory, directory mode 0700 and file
mode 0600, and no plaintext canary in the file. Close and reopen through a fresh
engine; add a passphrase, require `authRequired` without it, unlock and remove
it. Wipe caller credential buffers immediately after submission to exercise the
ownership contract. Reset in `finally`. This establishes in-process reopen;
it does not establish force-stop/relaunch, backup or transfer behavior.

### `KB-AND-020`

Race four worker isolates against the one application store, starting from
reset. Each uses its own public singleton and native binding. Worker open and set
operations may retry only `storeBusy`, with a 30-second monotonic retry window
per operation and 50-millisecond pauses. The SDK's one-second lock deadline stays
unchanged. Require all 32 exact values and final enumeration, then reset. This
exercises concurrent first provisioning and serialized file updates without
caller-selected app IDs; it is not a multi-process interruption test.

### `KB-AND-030`

With `--tamper`, flip one manifest ciphertext byte. Opening still authenticates
the unchanged package; the first record access must fail with
`storeAuthenticationFailed`. Require the changed file to remain byte-for-byte
unchanged by that failure. Restore exact original bytes, re-prove readability,
and restore again in `finally` before reset. Package/frame corruption has
separate hermetic coverage.

### `KB-AND-040`

With `--tamper`, delete only the harness's fixed derived Android Keystore alias.
An already authenticated session can still use its retained store key; a fresh
open must return `platformKeyInvalidated`. Require the encrypted file unchanged
and the alias still absent, then explicitly reset and prove a fresh empty store.
The same selection also checks reset after replacing that alias with a new key.
These root-loss challenges do not establish real backup, restore or transfer
behavior.

### `KB-IOS-001`

Resolve exactly one connected, supported physical iOS target through both
Flutter and Xcode inventory. Reject a simulator, missing support metadata,
ambiguous selection or mismatched physical identity. Record Xcode's hardware
model rather than the personal device name; omit the UDID.

### `KB-IOS-010`

Require the dedicated harness bundle identity, exact application-identifier
Keychain access group, Foundation backup-exclusion readback, and the V2 framed
file with directory mode 0700 and file mode 0600. Exercise string/binary round
trips, fresh-engine reopen, passphrase addition/unlock/removal, and reset.
Require ciphertext without the canary and removal of both the provider root and
encrypted file after reset. This does not claim Secure Enclave protection or
physical lock/restore behavior. Final signed entitlements remain a separate
host and artifact obligation.

### `KB-IOS-020`

Race four worker isolates through their own public singleton and Security FFI
binding against one freshly reset application store. Use the same bounded
`storeBusy` retry policy as `KB-AND-020`, require all 32 exact values and final
enumeration, then reset. This covers isolate contention and native
lifetime behavior; it does not substitute for cross-process or access-group
transition qualification.

### Separate process continuity

The dedicated [`mobile_lifecycle_harness.dart`](../example_flutter/lib/mobile_lifecycle_harness.dart)
fixture is separate from the XCTest baseline. Build it once in Profile/AOT mode
from a clean source snapshot, with a fresh 64-character hexadecimal
`KEYBAY_SECURITY_NONCE` and `KEYBAY_SECURITY_SUBJECT=git-commit:<commit>`.
Install only the dedicated `dev.keybay.securityharness` application.

On iOS the existing entrypoint automates this procedure, including USB target
validation, signing, one installation, both launches, and receipt validation:

```sh
KEYBAY_APPLE_TEAM_ID=<your-team-id> \
  ./tool/device_security.sh run ios --device <device-udid> --lifecycle
```

It requires a clean checkout, an unlocked physical iPhone with Developer Mode,
and Apple Development signing/provisioning already available to Xcode. The
runner uses a temporary signing configuration without editing project files.
It retains a separate `build/device-security/*-ios-lifecycle.*/report.json`,
the signed executable/AOT hashes, and private native command diagnostics.

Launch the same installed binary in explicit `seed` and then `reopen` phases,
waiting for each process to exit. On iOS, supply native process arguments
`--keybay-lifecycle-seed` and `--keybay-lifecycle-reopen`; on Android, supply the
`keybayLifecyclePhase` string intent extra. Do not reinstall between phases.
Retain both fixed JSON results only when their nonce/source match the build,
their phases are distinct, and both status and exit code indicate success.
The iOS runner checks the native process termination result, not just launcher
success. It copies `Library/Application Support/keybay-lifecycle-result.json`
from the dedicated app container because CoreDevice may discard Flutter's
console output. This public receipt contains the challenge, source, phase,
mode, compiled build, process ID and outcome; it remains after the encrypted store and
control file are reset.
The runner independently lists the dedicated container and requires the control,
store, and staging files to be absent. The empty coordination lock file may remain.

The Android arm64 adapter runs the same fixture and phase assertions:

```sh
./tool/device_security.sh run android --device <device-serial> --lifecycle
```

It requires an authorized physical API 31+ device, Flutter, Android build tools
and a working JDK. Profile/AOT uses the harness's debug signing and debuggable
manifest so `run-as` can retrieve its public receipt. The runner verifies the
APK signature, package identity and AOT hash, then installs once. It correlates
the receipt's process ID with Android's `ApplicationExitInfo` and requires self-exit with code zero
for the same PID, UID, user and process. Missing or changed diagnostic formats
cannot produce a pass. See the [Android exit-status contract](https://developer.android.com/reference/android/app/ApplicationExitInfo#getStatus()).

Both processes must be absent before proceeding, with distinct PIDs. The runner
checks control/store/staging absence, then uninstalls the dedicated harness and
verifies package absence before passing. As with the baseline,
`--allow-package-reset` is needed if that dedicated package is already installed;
another Android user/profile owning the package prevents the run.
The report is retained under `build/device-security/*-android-lifecycle.*/`.
`--lifecycle`, `--upgrade`, `--crash` and `--tamper` are separate selections.

Reopen requires a different process ID, the surviving public control file, an
existing store, and both encrypted fixture records. A freshly initialized store
cannot pass. Reopen and failed runs reset the fixture; a successful seed leaves
it for the next phase. This procedure does not establish reboot, relock,
backup/transfer, or application-upgrade behavior. Its result must be retained
separately from an in-process baseline.

### Signed app upgrade and passphrase continuity

Use the same adapters with `--upgrade` instead of `--lifecycle`:

```sh
./tool/device_security.sh run android --device <device-serial> --upgrade
KEYBAY_APPLE_TEAM_ID=<your-team-id> \
  ./tool/device_security.sh run ios --device <device-udid> --upgrade
```

Build 101 seeds the records and adds a public fixture passphrase. The runner
builds 102 from the same clean source and replaces the installed app in place,
preserving its data. It verifies actual signed build numbers, distinct AOT
binaries, and stable signing/application identity before the second installation.
Build 102 requires the original control marker and encrypted records, rejects
missing and wrong passphrases, then opens with the correct phrase without
initialization. Native process exits and final cleanup are verified as above.

The mode and compiled build are part of every source/nonce-bound receipt. The
runner cannot count an old build or repeated seed result as an upgrade pass.
Android also requires the installed UID to remain unchanged. Evidence is kept
in `build/device-security/*-android-upgrade.*/` or `*-ios-upgrade.*/`.
These are development-signing upgrade tests; they do not qualify store-format
migration, distribution signing, reboot/relock, or backup/transfer.

### Physical process crashes

Use `--crash` with the same Android or iOS adapter. It builds one signed
Profile/AOT fixture and runs three distinct processes: seed, mutate and reopen.
The host verifies a source/nonce-bound ready receipt before sending SIGKILL to
the exact seed or mutation process. Android requires a matching native signal
exit record; iOS verifies the native process identity and its absence after the
signal. A failed signal, stale receipt or surviving process cannot pass.

The seed adds passphrase protection. The mutation process verifies the original
records and auth policy, then acknowledges numbered writes using atomic public
receipt replacement. Reopen requires the last acknowledged sequence or its
immediate successor, verifies another write, and resets the fixture. Cleanup
also checks the control and acknowledgment files. The host runner tests cover
rejected receipts, process identity, signals and failure cleanup; both native
builds have compiled. Physical upgrade and crash execution passed on both
Android and iOS on Sep 6; the qualification report retains each source and
configuration separately.

See [the remaining mobile procedures](mobile-failure-qualification.md) for
commands and limits. This workload does not place a signal inside a particular
filesystem syscall, and does not establish reboot, relock or backup behavior.

### Process crashes at the file boundary

The ordinary `core` lane includes `v2_process_crash_test.dart` on macOS/Linux.
Run it alone from `packages/keybay` with:

```sh
dart test test/v2_process_crash_test.dart
```

For both record writes and passphrase/key rotation, a child running the
production engine and POSIX file adapter pauses after the first staging append,
before durable replacement, after durable replacement, or after the operation
returns. The parent sends SIGKILL, waits for process death, and opens the store
with a fresh engine. Pre-replacement cases require the original live bytes;
post-replacement cases require the new value or credential. Every case preserves
acknowledged records, rejects a wrong credential, avoids initialization, removes
abandoned staging, and permits a subsequent write after the dead process's lock
is released.

The interruption wrappers live only under `test/support`; the SDK has no crash
hook or new public option. This is real host process/filesystem evidence with a
disposable test provider and fast test KDF. It does not qualify a mobile provider,
sudden power loss, or the interval inside the native rename/directory-sync call.

## AOT passphrase measurements

Measure the production profile on each maintained device class. On a native
desktop host, compile the SDK's small measurement program and run it directly:

```sh
cd packages/keybay
mkdir -p build
dart compile exe test/support/v2_kdf_measurement.dart -o build/keybay-kdf
./build/keybay-kdf
```

It runs five fresh processes, checks the production Argon2 result against the
public reference vector, and reports derivation time and peak resident memory.
The separate baseline measures a process without derivation. Peak RSS includes
the runtime and allocator; subtracting the baseline is not an isolated KDF
working-memory measurement. Run without competing build/test work and record
the CPU, memory capacity, OS, SDK, source and executable identity alongside the
output. No key or credential is emitted.

Measurements are observations until the maintained device classes and their
latency/memory acceptance budgets are recorded. One desktop result cannot close
the mobile or sandbox-profile qualification gate. Flutter debug/JIT test timing
does not establish the AOT profile's cost.

## Result and evidence contract

Scenario status is `pass`, `fail`, `blocked`, `skipped`, or `inconclusive`.
Only `pass` is affirmative evidence. A security-oracle contradiction is
`fail`; missing capability is `blocked`; infrastructure failure or unattributed
aggregate-command failure is `inconclusive`.

The report writer derives scenario outcomes from nonce-bound structured Flutter
output and the aggregate command result. It requires a clean source commit and
records that commit, the named configuration, date, per-scenario results,
cleanup, and explicit limitations. A failed or truncated aggregate command can
never sit beside a passing report.

The report does not claim an exact release archive or installer identity. It
records the checked source because qualification and artifact provenance are
different questions. Reports never contain canaries, secrets, account data,
signing credentials, raw serials, or UDIDs. Review `report.json` before
attaching it to the triggering issue; do not retain raw logs or create a second
repository ledger.

## Qualification triggers and claim boundary

Run the affected scenarios only when triggered by:

- container, wrapping, parser, authentication, or fail-closed changes;
- transaction, concurrency, interruption, or native-boundary changes;
- OS/provider policy, signing, entitlement, access-group, backup, transfer,
  restore, install, lock, or reboot changes;
- a relevant advisory, incident, or exploit chain; or
- a changed scenario oracle.

Each scenario states its required evidence class. Missing capability is
`blocked` or unqualified, never a lower-class pass. A release is not itself a
trigger. During release or issue review, missing applicable evidence narrows
the affected claim; it does not become a product-wide failure or a lower-class
pass.

Official guidance and peer advisories are triaged when automation, an issue, or
security-sensitive work surfaces them. Record applicable, uncertain,
claim-affecting, or non-obvious decisions in that issue or PR; do not create a
feed ledger or manual calendar.

### Pre-1.0 exploit-chain baseline

The maintained qualification matrix follows security-relevant distinctions:
Android needs its emulator tier plus one physical device whose generated-key
protection is independently checked with `KeyInfo`; iOS needs the simulator
tier plus one provisioned physical iPhone before any physical-iOS claim; macOS
needs Apple-silicon native-host coverage of both the unentitled
encrypted-file/login-Keychain path and the signed, entitled Data Protection
path; Linux needs real disposable GNOME Keyring integration, with other
providers claimed only after equivalent qualification.

Before the strongest 1.0 claims, run this bounded baseline once, then rerun
only the affected destructive scenarios under the triggers above:

- Android restored encrypted-store state without the original KEK must
  fail without self-heal; force-stop/reboot continuity and reference-app
  backup/transfer behavior must match the contract.
- Apple accessibility must match the contract across reboot, first unlock, and
  relock. Query, update, enumeration, and deletion must not cross the intended
  access group; a colliding pre-existing item must not silently retain weaker
  accessibility; and entitlement loss or prior native state must not silently
  appear as a fresh lower-protection store.
- A stable signed macOS CLI/harness must preserve the intended login-Keychain
  ACL identity across upgrade. A locked or interaction-required operation must
  return a typed bounded failure without a hang. Open, authentication mutations
  and reset may invoke trusted provider UI; record operations may not.
- Linux locked and disconnected provider operations must terminate promptly
  and fail closed.
- Encrypted-file backends must survive real multi-process first-write and
  interruption races without key replacement, silent reset, or
  unauthenticated state.

No suite result is a certification. Public statements name the exact source
commit, configuration, evidence class, scenarios, limitations, and date. A
report proves only what its recorded results and oracle establish.

## Relationship to releases

Qualification and release provenance answer different questions. A device run
records what the suite observed for one clean source commit and named
configuration. Release review decides whether later security-relevant changes
make that observation inapplicable; a version change or release by itself does
not require another device run.

Device evidence is not consumed by the publishing pipeline. Missing applicable
evidence narrows the affected public qualification claim; it does not become a
pass and does not block an unrelated package or platform release. rk owns
publication and release-artifact provenance, while the credential-free release
auditor independently compares public package contents with signed source.

# Keybay native and device security suite

This document owns Keybay's qualification procedures, security oracles, safety
rules, evidence handling, and release applicability policy. The product
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

A lower class never substitutes for a scenario's minimum. One Pixel receipt
qualifies that device/build/provider configuration, not every Android OEM.
Functional support and a stronger qualified configuration are separate claims.

## Safety boundary

Automation may touch only the dedicated `dev.keybay.securityharness`
application and the exact test namespaces listed by its adapter. It must never
inspect or mutate another application's data, change a screen credential or
biometric enrollment, switch a personal backup transport, unlock a bootloader,
or collect a PIN, account credential, signing secret, raw serial, or UDID.

Baseline and `--tamper` runs may create and remove their own namespaced
application/key state. Artifact-tamper tests retain exact originals, restore
them in a `finally` path, and re-prove readability. `--tamper` also authorizes
deletion of only the dedicated harness KEK for the missing-key challenge;
package cleanup removes the remaining test state. Reset of any other package,
reboot, relock, provider locking, backup/restore, and transfer are separate
procedures requiring an exact target and explicit authorization. Cleanup is an
oracle: a release-eligible pass cannot survive failed cleanup.

## Execution policy

Two kinds of execution are enough:

1. **Continuous checks** run hermetic tests, deterministic mutation tests, real
   disposable login-Keychain/GNOME-Keyring integration, and maintained
   simulator/emulator lanes in CI.
2. **Qualification scenarios** run where OS policy, hardware, signing, or
   lifecycle behavior is part of the claim. Non-disruptive applicable baselines
   run against each candidate intended for publication; disruptive procedures
   run only after an affected implementation/platform change, relevant
   advisory/incident, or changed oracle.

The release gate consumes applicable CI and qualification evidence. It is not a
third execution mode. The core package and CLI are separate release subjects;
a CLI release does not require mobile qualification.

## Current runner

From the repository root:

```sh
./tool/device_security.sh doctor android
./tool/device_security.sh run android --device SERIAL --core-archive PATH
./tool/device_security.sh run android --device SERIAL --tamper \
  --allow-package-reset --core-archive PATH

./tool/device_security.sh doctor ios
./tool/device_security.sh run ios --device UDID --core-archive PATH

./tool/device_security.sh doctor macos
./tool/device_security.sh run macos --core-archive PATH
./tool/device_security.sh run macos --tamper --core-archive PATH

./tool/device_security.sh doctor linux
```

Android package reset requires `--allow-package-reset` and is scoped to the
selected Android user. Linux has no device adapter yet; its real disposable
GNOME Keyring integration remains a Continuous check. Working artifacts go to
private directories under `build/device-security/`; promotion is a separate
reviewed action.

## Executable inventory

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
| `KB-AND-040` | android | `KB-INV-003`, `KB-INV-004`, `KB-INV-005`, `KB-INV-008` | physical-device | yes |
| `KB-IOS-001` | ios | `KB-INV-005` | physical-device | no |
| `KB-IOS-010` | ios | `KB-INV-005` | physical-device | no |
| `KB-IOS-020` | ios | `KB-INV-007` | physical-device | no |
| `KB-MAC-001` | macos | `KB-INV-005` | native-host | no |
| `KB-MAC-010` | macos | `KB-INV-001`, `KB-INV-002`, `KB-INV-005` | native-host | no |
| `KB-MAC-020` | macos | `KB-INV-007` | native-host | no |
| `KB-MAC-030` | macos | `KB-INV-003`, `KB-INV-007` | native-host | no |
<!-- END GENERATED DEVICE SECURITY INVENTORY -->

## Procedures and oracles

### `KB-AND-001`

Inventory the selected target; require API 31+, production physical hardware,
the requested Android user, and retained model/OS/API/patch/build plus verified
boot, lock, SELinux, and FBE facts. Reject an emulator or ambiguous target.

### `KB-AND-010`

Provision the Keybay KEK and compare Keybay's reported protection with an
independent native `KeyInfo.getSecurityLevel()` query in the same application
identity. TEE/StrongBox maps to `hardwareBacked`; software maps honestly to
`softwareBacked`. API choice alone is not a hardware pass.

### `KB-AND-011`

Store a per-run canary; require an encrypted container and versioned wrapped-key
blob, prove neither contains the canary, read it back, then remove only the test
state. Artifact copies alone must not yield plaintext.

### `KB-AND-020`

Race spawned-isolate operations first across distinct app IDs and then one fresh
shared app ID. Require isolation, one usable KEK, every update retained, honest
diagnostics, and no native crash or cross-store value.

### `KB-AND-030`

With `--tamper`, corrupt the container and wrapped blob separately. Each read
must fail with the expected typed closed failure without returning the canary or
creating replacement state. Restore the original bytes and re-prove readability.

### `KB-AND-040`

With `--tamper`, provision a dedicated harness store, retain its encrypted
container and wrapped-key blob, then delete only that store's Android Keystore
KEK through the debug-only native oracle. Reads must return `KeyInvalidated`,
leave both artifacts byte-for-byte unchanged, and not silently provision a
replacement KEK. Final package cleanup removes the intentionally unrecoverable
test state.

### `KB-IOS-001`

Resolve exactly one connected, supported physical iOS target. Reject simulator,
missing support metadata, ambiguous selection, and malformed platform identity.

### `KB-IOS-010`

Require `nativeItems`, a complete round trip, and no invented hardware level.
The signed host's final entitlements/access groups remain a host obligation.

### `KB-IOS-020`

Stress concurrent native-item operations and enumeration through the Security
FFI boundary. Require exact item isolation, stable typed results, and no native
crash or leaked test value.

### `KB-MAC-001`

Record model, architecture, OS, storage track, and signing mode. The current
baseline is native-host evidence for the unentitled encrypted-file/login-
Keychain track, not physical-hardware evidence.

### `KB-MAC-010`

In an unentitled app, require `encryptedFile`, a real login-Keychain store key,
`loginBound`, ciphertext at rest, and no silent native-item selection.

### `KB-MAC-020`

Stress spawned-isolate contention through the file/login-Keychain track. Require
all updates, no cross-store value, bounded failure, and non-optimistic
diagnostics. This does not substitute for the separately triggered stable-
signed multi-process/ACL procedure.

### `KB-MAC-030`

With `--tamper`, modify the encrypted container, require typed authenticated
failure and prove the backend did not heal/replace the tampered bytes. Restore
the original and re-prove readability.

## Result and evidence contract

Scenario status is `pass`, `fail`, `blocked`, `skipped`, or `inconclusive`.
Only `pass` is affirmative evidence. A security-oracle contradiction is
`fail`; missing capability is `blocked`; infrastructure failure or unattributed
aggregate-command failure is `inconclusive`.

The schema-v2 writer derives release-eligible scenario status from nonce-bound
structured Flutter reporter output. It validates the executable selection,
platform fields, evidence hashes, private paths, no-overwrite publication,
clean checkout, exact package subject, exact installer input, package identity,
cleanup, and fail-dominant aggregate status. It records:

- clean suite commit and exact subject identity;
- exact APK or canonical signed app/IPA installer input, controlled install
  result, and verified package/bundle identity for installed-app tests;
- target/configuration facts without raw identifiers;
- per-scenario derived status/reason and retained allowlisted evidence hashes;
- cleanup result for any mutation; and
- timestamp.

Missing/skipped required scenarios, nonce mismatch, caller-supplied status,
dirty source, subject mismatch, failed cleanup, or unresolved evidence cannot
become a release pass. Sensitive raw logs are ephemeral; every digest used by a
gate resolves to a retained sanitized object. Receipts never contain canaries,
secrets, account data, signing credentials, raw serials, or UDIDs.

## Qualification triggers and claim boundary

Run the affected non-disruptive baseline for each minor/major publication
candidate whose release claims that configuration as qualified. A release may
omit a target — a patch release in particular may ship without re-running a
device baseline — but then its manifest must declare that configuration
unqualified rather than carry forward a pass.

Destructive or operator-driven scenarios are never a routine release
requirement. Run them only when affected by:

- container, wrapping, parser, authentication, or fail-closed changes;
- transaction, concurrency, interruption, or native-boundary changes;
- OS/provider policy, signing, entitlement, access-group, backup, transfer,
  restore, install, lock, or reboot changes;
- a relevant advisory, incident, or exploit chain; or
- a changed scenario oracle.

Each scenario states its required evidence class. Missing capability is
`blocked` or unqualified, never a lower-class pass.

Finding disposition at a release gate: Critical and High findings block
release. A Medium finding is fixed, or temporarily accepted with scope,
rationale, expiry, and any required claim reduction. An unresolved finding of
any severity cannot coexist with a release claim it directly contradicts;
unknown or inconclusive evidence blocks only the affected claim or
configuration. Low findings follow normal issue policy unless explicitly
release-relevant.

Review official Apple/Android/Dart/Secret Service guidance and applicable peer
advisories on the recurring sweep cadence and before security-sensitive
releases. Record only applicable, uncertain, claim-affecting, or non-obvious
dismissal decisions in their advisory/issue/PR; do not build a feed ledger.

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

- Android restored container/wrapped-key state without the original KEK must
  fail without self-heal; force-stop/reboot continuity and reference-app
  backup/transfer behavior must match the contract.
- Apple accessibility must match the contract across reboot, first unlock, and
  relock. Query, update, enumeration, and deletion must not cross the intended
  access group; a colliding pre-existing item must not silently retain weaker
  accessibility; and entitlement loss or prior native state must not silently
  appear as a fresh lower-protection store.
- A stable signed macOS CLI/harness must preserve the intended login-Keychain
  ACL identity across upgrade. A locked or interaction-required operation must
  return a typed bounded failure without an unexpected GUI prompt or hang.
- Linux locked and disconnected provider operations must terminate promptly
  and fail closed.
- Encrypted-file backends must survive real multi-process first-write and
  interruption races without key replacement, silent reset, or
  unauthenticated state.

No suite result is a certification. Public statements name the exact source
commit, configuration, evidence class, scenarios, limitations, and date. A
report proves only what its retained evidence and oracle establish.

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

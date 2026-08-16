# Security assurance operating plan

Status: temporary implementation plan. Delete this file when its exit criteria
are met. The final system must be understandable from its authorities,
executable checks, receipts, and release manifests without preserving another
planning document.

## Outcome

Keybay should make narrow, falsifiable security claims and retain evidence for
what an exact release established on named configurations. It should not grow a
parallel compliance product.

The operating loop is:

```text
report, advisory, or platform change
  -> applicability decision
  -> product guarantee
  -> implementation and regression test
  -> native/device qualification when OS behavior matters
  -> exact-subject receipt
  -> subject-specific release manifest
  -> stated limitations or temporary exception
```

This is a reasoning chain, not a separate registry for every noun in it.

## First principles

1. **Claims precede tools.** A test or scanner exists only because it can
   falsify a security property Keybay actually claims.
2. **One fact has one authority.** Other documents may explain or link, but
   they must not maintain competing security or implementation status.
3. **Claims do not outrun qualification.** Functional support, a maintained
   qualification target, and the evidence class achieved on that target are
   distinct facts.
4. **Cheap checks run continuously; environmental checks run when they prove
   something new.** Physical and disruptive work is release- or
   change-triggered, not pull-request ceremony.
5. **Exploration and regression are different.** One-off red-team work becomes
   a permanent scenario only when it finds a defect, protects a meaningful
   guarantee, or represents a plausible recurring attack chain.
6. **Complexity must retire something.** A new document, identifier, service,
   or gate must remove duplication or close a demonstrated security gap.

## Scope and claim boundaries

The program concentrates on where Keybay's security result can fail:

- separation of encrypted data from platform-held key material;
- authenticated, fail-closed behavior under corruption or key loss;
- Keychain, Keystore, Secret Service, entitlement, and provider semantics;
- migration, concurrency, interruption, lock, reboot, reinstall, backup, and
  restore behavior;
- honest reporting of hardware and protection properties;
- FFI/JNI and process-boundary correctness; and
- dependency and release integrity.

The threat model's documented non-goals remain non-goals. Stable non-goals do
not need exceptions or expiry dates.

Use these terms precisely:

- **Supported runtime/configuration:** normal use is maintained and exercised
  by genuine API/service integration tests.
- **Qualification target:** a named OS, provider, device class, signing mode,
  and reference-harness configuration on which stronger security claims were
  tested.
- **Evidence class:** hermetic, native-host, virtual-device, or physical-device.
  A lower class never substitutes for a required higher class.

A physical Pixel receipt qualifies that named Android configuration; it does
not prove all Android OEMs. Missing physical evidence narrows the physical
assurance claim, not necessarily the functional support statement.

### Library and host-application boundary

Keybay owns its cryptography, formats, derived paths, platform-store queries,
fail-closed behavior, diagnostics, reference harness, and any host validation it
can perform. A consuming application owns its final signing/provisioning,
entitlements and access groups, Android backup and transfer rules, and other
application policy outside the package.

Keybay must test and document its reference integration and validate host
configuration mechanically where practical. It must not imply that a passing
reference harness proves an arbitrary consuming app is configured safely.
Android backup behavior and Apple access groups are therefore both product test
inputs and explicit host obligations; see the official
[Android backup guidance](https://developer.android.com/identity/data/autobackup)
and [Apple access-group contract](https://developer.apple.com/documentation/security/ksecattraccessgroup).

## Final authority model

There are three human-authored authorities:

| Authority | Sole responsibility |
| --- | --- |
| `SECURITY.md` | Reporting routes, supported versions, response/disclosure expectations, and links |
| `doc/design.md` | Assets, adversaries, trust boundaries, numbered `KB-INV-*` guarantees, platform responsibilities, non-goals, and design rationale |
| `doc/device-security-suite.md` | Runnable scenario procedures/oracles, evidence handling, safety rules, and qualification/release policy |

README, SDK, CLI, architecture, and platform guides retain only the consumer
configuration, lifecycle, and limitations they need. They link to these
authorities and do not carry mutable assurance status.

### Executable scenario catalog

Move the scenario constants duplicated across receipt code and adapters into
one small typed Dart catalog under `tool/device_security/`. It contains only
runnable scenarios and only fields consumed by code:

- stable scenario ID;
- platform/configuration;
- referenced `KB-INV-*` guarantee IDs;
- minimum evidence class;
- whether the scenario is destructive; and
- runner selector or entrypoint.

The exact suite source commit versions scenario semantics. Do not add a second
revision or supersession system. Planned work stays in issues or this temporary
plan; it does not receive an executable catalog entry.

Procedures and security oracles remain human-authored in the suite. The catalog
generates only a marked executable inventory, and a simple ID/anchor check
verifies that every catalog entry has one suite procedure and every guarantee
reference exists in the design. Do not build a Markdown parser to enforce this.
Tests remain ordinary Dart, Kotlin, Swift, and narrowly scoped shell. Do not
build a scenario DSL.

## Execution and release policy

### Continuous checks

Run on every relevant pull request and the default branch:

- Dart analysis, unit tests, crypto vectors, failure injection, concurrency,
  and dependency-closure checks;
- deterministic mutation/state-machine properties with reproducible seeds and
  a retained regression corpus for every discovered failure;
- disposable macOS login-Keychain and Linux GNOME Keyring integration;
- maintained Android emulator and iOS simulator integration;
- workflow, Gradle wrapper, archive, and publication-policy checks;
- advisory scanning for all committed lockfiles; and
- catalog, receipt, and generated-inventory validation.

Actual signing, notarization, and publication remain release checks. Every check
named as required must be enforced by the main ruleset or be an explicit
dependency of the relevant release workflow; merely running an optional job is
not a gate. Continuous checks use ordinary CI results and do not need ceremonial
device receipts.

### Qualification scenarios

Non-destructive native/device baselines run against every candidate intended
for publication for each configuration that release names as
security-qualified. This avoids a staleness policy and avoids claiming that
release X passed a test actually run against artifact Y. A release may omit a
target, but then it must call that configuration unqualified rather than carry
forward a pass.

Destructive or operator-driven scenarios run only when affected by:

- container, wrapping, parser, authentication, or fail-closed changes;
- transaction, concurrency, interruption, or native-boundary changes;
- OS/provider policy, signing, entitlement, access-group, backup, transfer,
  restore, install, lock, or reboot changes;
- a relevant advisory, incident, or exploit chain; or
- a changed scenario oracle.

Each scenario states its required evidence class. Missing capability is
`blocked` or unqualified, never a lower-class pass. A destructive all-platform
run is not a routine release requirement.

### Release gate

Keybay core and the CLI are independently released subjects. Each gets its own
manifest and only the checks/configurations relevant to that subject. A CLI
release does not require Android or iOS qualification.

Before creating an append-only release tag, a local or protected candidate
workflow must validate:

1. the candidate subject identity and clean source;
2. required Continuous checks for the exact candidate;
3. non-destructive receipts for every configuration claimed as qualified;
4. every triggered destructive scenario;
5. retained evidence resolution and required cleanup; and
6. finding and temporary-exception disposition.

The tag workflow revalidates those inputs before publication and generates the
final subject-specific manifest. This prevents an immutable tag/version from
being consumed merely to discover that assurance prerequisites were missing.

Finding disposition is explicit:

- Critical and High findings block release.
- Medium findings are fixed or accepted temporarily with scope, rationale,
  approver/review kind, expiry, and any required claim reduction.
- An unresolved finding of any severity cannot coexist with a release claim it
  directly contradicts.
- Unknown or inconclusive evidence blocks only the affected claim/configuration.
- Low findings follow normal issue policy unless explicitly release-relevant.

Sensitive findings remain in GitHub Security Advisories; ordinary findings and
research remain in issues. The manifest references only information safe to
publish. Do not create a parallel risk or exception database unless the first
real automated exception demonstrates that one is needed.

## Minimum pre-1.0 qualification

The maintained matrix follows security-relevant distinctions, not device count:

- **Android:** minimum/current emulator integration and one physical device
  whose generated-key protection is checked independently with `KeyInfo`.
- **iOS:** current simulator integration and one provisioned physical iPhone
  target before claiming physical iOS qualification.
- **macOS:** Apple-silicon native-host coverage for the unentitled
  encrypted-file/login-Keychain path and the signed, entitled Data Protection
  Keychain path.
- **Linux:** real disposable GNOME Keyring integration. Claim KWallet or another
  provider only after equivalent native-provider qualification. No physical
  ceremony is needed where Keybay makes no hardware-backed claim.

Before the strongest 1.0 claims, run this bounded exploit-chain baseline once:

- Android restored container/wrapped-key state without the original KEK must
  fail without self-heal; force-stop/reboot continuity and reference-app
  backup/transfer behavior must match the contract.
- Apple accessibility must match the contract across reboot, first unlock, and
  relock. Query, update, enumeration, and deletion must not cross the intended
  access group; a colliding pre-existing item must not silently retain weaker
  accessibility; and entitlement loss or prior native state must not silently
  appear as a fresh lower-protection store. Otherwise the affected
  multi-group/transition configuration remains explicitly unqualified.
- A stable signed macOS CLI/harness must preserve the intended login-Keychain
  ACL identity across upgrade. A locked or interaction-required operation must
  return a typed bounded failure without an unexpected GUI prompt or hang.
- Linux locked and disconnected provider operations must terminate promptly and
  fail closed.
- Encrypted-file backends must survive real multi-process first-write and
  interruption races without key replacement, silent reset, or unauthenticated
  state.

After that baseline, rerun only the affected destructive scenarios under the
triggers above.

## Exact-subject receipts

The release subject is not always one byte-identical artifact:

- **Core pub package:** use the existing canonical package-content identity
  over member paths, types, modes, and bytes. Build the harness from the
  extracted candidate archive, and post-publication prove that pub.dev serves
  the same canonical content.
- **CLI:** bind the exact archive and binary bytes already verified by the CLI
  release process.
- **Installed harness:** every release-eligible installed-app qualification
  binds the exact installer input: the APK or canonical signed `.app`/IPA
  artifact digest, controlled install command/result, and verified
  package/bundle identity. The device need not permit reading installed bytes
  back, but the runner must prove which retained host artifact it installed. If
  it cannot, that target is unqualified. A separate app digest is unnecessary
  only for a genuine native-host/source test with no installed application.

A release-eligible receipt is produced from nonce-bound structured test output
and records only what is needed to verify the observation:

- schema and suite source commit/clean state;
- exact subject identity;
- exact installer-input identity, install result, and package/bundle identity
  for installed-app tests;
- target/configuration facts without raw device identifiers;
- scenario ID, derived status, and reason;
- hashes of retained, allowlisted structured evidence;
- cleanup result when the scenario mutates state; and
- timestamp.

Scenario-specific observed properties or phases may be included where they are
part of the oracle; they are not mandatory boilerplate. Manual action claims
must be paired with observable pre/post facts where the platform exposes them.
Otherwise the phase remains explicitly manual and cannot imply an automated
oracle.

Overall status is derived. Missing/skipped required scenarios, nonce mismatch,
contradictory oracles, dirty release source, subject mismatch, failed cleanup,
or caller-supplied fictional status cannot become `pass`.

Sensitive raw logs are ephemeral and are never referenced as durable evidence.
Every digest used by a gate resolves to a retained sanitized object stored with
the receipt or manifest. Receipts never contain canaries, secrets, account data,
signing credentials, raw serials, or UDIDs.

## Release assurance manifest

The manifest is assembled from validated machine facts and an explicit human
decision about applicability and temporary exceptions. It contains only:

- released subject, version, source, and artifact/content identities;
- required CI run identity;
- applicable receipt and retained-evidence hashes;
- temporary exception/advisory/issue references safe to publish; and
- configurations or claims left unqualified, plus links to applicable stable
  limitations in the canonical design/platform documentation.

It contains no security score and no machine-invented statement that the
release is secure.

For core, use the canonical package-content SHA-256 and a stable synthetic
subject name as the attestation subject through GitHub's `subject-checksums`
input, with the release manifest as a custom predicate. Post-publication,
recompute that canonical digest from the hosted pub.dev archive and verify the
attestation's repository, workflow, tag, subject, and predicate. This makes the
public attestation discoverable from pub.dev content without depending on an
expiring workflow artifact or byte-identical repackaging. For the CLI, attach
the manifest to the existing GitHub Release and include it in the existing
artifact-attestation/postflight process. Use GitHub's current attestation
mechanism; do not add a second PKI.

## Vulnerability and research intake

Use a few sources with clear jobs:

- GitHub private vulnerability reporting and Security Advisories for private
  reports and coordinated fixes;
- OSV and Dependabot for dependency advisories and reviewed update proposals;
- Apple, Android, Dart, Secret Service/libsecret, and claimed provider guidance
  for platform changes; and
- relevant secure-storage and crypto peer advisories for analogous failures.

Enable private vulnerability reporting, Dependabot vulnerability alerts and
security updates, and all-lockfile scanning. Crypto dependency changes remain
review-only, never automatic.

Review platform and peer changes before a security-sensitive release and with
one short quarterly checklist in the suite policy. Do not create a calendar
system, review log, or feed-ingestion service. Record only applicable,
uncertain, claim-affecting, or non-obviously dismissed items, and record the
decision in the originating alert, advisory, issue, or pull request rather than
a feed ledger.

For an applicable item: identify reachability and affected configurations, fix
the product, add the smallest regression that would have caught it, and add or
revise a native/device scenario only when OS behavior is part of the guarantee.
An advisory does not automatically create a permanent control or test.

Security-sensitive changes affect cryptography, formats/key lifecycle,
Keychain/Keystore/Secret Service, FFI/JNI, entitlements, backup/restore,
receipt/manifest validation, or release workflows. Their review states the
affected guarantee, applicable regression/platform evidence, and change to any
published limitation.

Use a second human reviewer for security-sensitive releases, accepted Medium
risk, and release-evidence changes when one is available. If not, label the
result self-assessed; AI or repeated self-review is not independence. Add
`CODEOWNERS` only when it routes to a real reviewer.

## Implementation sequence

### 1. Make truth singular and routine checks real

- Move canonical `KB-INV-*` guarantees into `design.md`; leave procedures and
  oracles in the suite.
- Replace Full/profile certification language with Continuous checks,
  qualification scenarios, and the subject-specific release gate.
- Add the executable-only Dart catalog and generated inventory; remove scenario
  constants/status from adapters and receipt code.
- Extract live obligations into issues/advisories, then archive completed
  implementation plans, `research-agenda.md`, and narrative `receipts.md`.
- Remove duplicated assurance status from consumer/platform documents.
- Expand `SECURITY.md` with supported versions, private GitHub reporting,
  acknowledgement/triage/disclosure expectations, and backport policy.
- Enable private vulnerability reporting, Dependabot alerts/security updates,
  and OSV scanning for all committed lockfiles.
- Add required Android emulator/iOS simulator lanes and ensure every named
  required check is actually enforced.
- Fix confirmed product findings or prevent the release from making any
  guarantee they contradict. This includes the current Apple multi-access-group
  query scope, duplicate-update accessibility, and entitlement-loss scheme-fork
  conditions; uncommon collision or upgrade prerequisites do not make those
  conditions invisible.

Exit: each mutable fact has one authority, every gate named as current is
executable and enforced, and no release obligation exists only in historical
prose.

### 2. Bind evidence to release subjects

- Emit nonce-bound structured scenario results.
- Implement the minimal receipt contract and adversarially test omission,
  substitution, dirty source, subject mismatch, cleanup failure, and output
  races.
- Build qualification harnesses from the extracted candidate core package.
- Implement pre-tag validation and subject-specific manifests for core and CLI.
- Retain/attest manifest evidence through each subject's actual publication
  path and verify it after publication.

Exit: aggregate success, a fabricated status, wrong subject, dirty release
source, unresolved evidence, or failed cleanup cannot satisfy a release claim.

### 3. Qualify only the claims Keybay makes

- Establish clean non-destructive release baselines for each named
  qualification target.
- Complete the bounded pre-1.0 exploit-chain baseline above.
- Narrow every provider/hardware/lifecycle statement that lacks the required
  evidence class.

Exit: release manifests and public documentation distinguish functional support
from precisely scoped native/device qualification.

### 4. Obtain independent review and remove this plan

Commission one open-book assessment against an exact release candidate after
the product fixes and evidence pipeline are stable. Scope it to the threat
model, crypto/container integration, native boundaries, platform identities and
lifecycle, concurrency/interruption, backup/restore, host obligations, and
release evidence.

Remediate findings and obtain auditor verification for fixes and every
security-relevant delta before describing the shipped release as independently
assessed. A self-reviewed delta is acceptable only when it is explicitly
non-security-relevant; otherwise name only the audited candidate as independently
assessed and label the shipped delta self-assessed. Publish the exact
commits/artifacts, scope, findings, dispositions, and untested areas. Repeat
only after a material redesign, serious incident, or demonstrated
adoption/customer need.

Exit: the strongest 1.0 claim has independent, artifact-scoped review; the
three authorities, executable catalog, receipts, and manifests fully operate
the program; this plan is deleted.

## Explicit deferrals

Do not add these without a demonstrated failure or external requirement:

- separate threat/control/claim/risk registries or a generic scenario DSL;
- planned scenarios in executable code;
- framework crosswalks, dashboards, assurance percentages, or security scores;
- evidence-age or receipt-supersession machinery;
- automated platform-threat ingestion;
- generic SAST/workflow scanners without demonstrated Keybay signal;
- automatic crypto updates or risk acceptance;
- a broad Android OEM farm or physical testing on every pull request;
- core-dump memory-residue testing as a release gate;
- a custom signing PKI, transparency log, or higher SLSA claim;
- a public bug bounty before private intake has been exercised; or
- FIPS, Common Criteria, ISO 27001, SOC 2, or certification language without a
  concrete customer requirement.

OWASP MASVS/MASTG, NIST SSDF, OpenSSF guidance, official platform security
documentation, peer advisories, and independent review are inputs to human
assessment, not parallel authorities or badges.

## Public claim boundary

Before exact-subject receipts and independent review, describe Keybay as
security-designed, threat-modeled, and self-assessed, naming only the exact
automated/native/device evidence retained.

After this plan is complete, the strongest routine statement is:

> Keybay release X passed its required automated checks and the listed
> native/device scenarios on the exact subjects and configurations identified
> in its release assurance manifest. Unqualified configurations, known
> limitations, and temporary exceptions are identified there or in the linked
> canonical documentation. This is scoped, point-in-time assurance, not a
> guarantee or certification.

An independent assessment may be named only with its exact version, artifacts,
scope, and date. Never claim blanket platform security, OWASP certification, or
the absence of vulnerabilities.

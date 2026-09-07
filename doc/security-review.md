# SDK security review handoff

The [independent Claude report](reviews/2026-09-06-claude.md), supplied by the
maintainer, reviews commit `88c9cb5e…`. It is a separate AI model review, not a
human external audit. Its additional referenced receipts were not supplied with
the pasted report, but were subsequently located in the local reviewer output.
The [follow-up review](reviews/2026-09-07-claude-followup.md) accepts all five
remediations and the informational dispositions at `0042f6d…`.
**The Claude review and remediation phase is closed.** This is not release
approval or a claim of a human external audit.

Both reports and the available reviewer receipts are retained byte-for-byte in
the [acceptance evidence](../build/qualification/claude-review-acceptance-20260907/README.md)
with a hash manifest. They are reviewer executions, separately attributed from
project CI/device runs; null or scratch-commit receipt identities have not been
relabelled as clean-source runs. CLI/TUI, Snap, Windows, migration, hardware
credentials and rollback anchors remain deferred.

## Remediation of the Claude findings

The shared engine and fixed platform adapters remain. The targeted corrections
are:

- **KB-CR-001:** select `fstat$INODE64` on macOS x64 to match the declared struct,
  use a variadic `fcntl` binding consistently, and add native Intel core/provider
  CI alongside arm64. Descriptor metadata is compared with native file stat;
  this is actual SDK coverage, in addition to the reproduced Rosetta C probe.
- **KB-CR-002/005:** document root-only `storeStateConflict`, deliberate reset,
  test-runner identity and bounded `storeBusy` handling. A conflict is not proof
  of reinstall and never implies automatic reset. Qualification wording now
  reflects the recorded Flatpak and physical mobile runs.
- **KB-CR-003:** retain the Argon2 workspace before derivation, overwrite it
  before release, preserve primary failure and attempt release even if clearing
  fails. Whole-word clearing avoids a slow byte loop. Tests verify ownership and
  success/failure cleanup while memory is live; no freed view is read. The
  protected accessor is an explicitly reviewed dependency coupling. No custom
  KDF, native allocator or new dependency is introduced.
- **KB-CR-004:** delete provider-based cross-runtime stale diagnostics. Record
  operations and `auth.list` never acquire providers, even after corruption or
  peer rotation. Cross-runtime changes can report `storeAuthenticationFailed`;
  local invalidation still reports `staleSession`. Secret Service also rejects
  forbidden acquisitions before provider access. Tests cover all record methods,
  auth listing, provider call counts and peer-record preservation.

For the informational findings: **006** retains transaction ordering and adds
bounded retry guidance; **007** is covered by the simplified failure contract;
**009** documents the test-runner limitation; **010** corrects `fcntl` above.
**008** (exact post-write generation comparison) and **011** (dependency-owned
Argon2 helpers) remain unchanged: this review established no defect requiring
either mechanism to be replaced.

The runtime correction is commit `48e2bb80…`; a test-worker startup correction
followed at `b4b198a…`. All 14 normal CI jobs passed for that exact source,
including native Intel core/provider coverage. The [qualification report](qualification-status.md)
retains local Rosetta timing failures and distinguishes new CI evidence from
earlier physical and signing runs. Missing lifecycle/release evidence remains
missing. The [local follow-up brief](../build/qualification/claude-remediation-20260907/REVIEW_NEXT.md)
provides the exact diff and retained reports. The accepted follow-up adds real
Rosetta native-provider and additional Dart-version runs. Its remaining
same-runtime in-flight error-classification clarification is now in the SDK
guide and RFC; no runtime change or broader architecture work is required.

Rosetta JIT timings vary widely on both the reviewed and remediated runtime.
The reviewer also recorded one exit-255 failure without its full error. This
does not identify the underlying cause or limit its possible effect to tests.
Native Intel CI remains the routine x64 regression lane; retain the Rosetta
observation without blanket timeout increases or a new KDF implementation.

Earlier physical and signing evidence remains applicable to unchanged native
identity, custody and storage boundaries. The changed reader failure and KDF
cleanup paths have hermetic and platform CI coverage; their remediation alone
does not require repeating completed physical procedures. Unobserved lifecycle
phases, maintained-device KDF acceptance and configuration-specific release
claims still need their own evidence.

The sections below preserve the earlier engineering review and its historical
source/evidence claims. They do not describe the new provider-free record path.

## Review target

Read [architecture](architecture.md), [RFC 0001](rfcs/0001-per-application-stores.md)
and the [qualification report](qualification-status.md) first. The retained
[handoff archive](../build/qualification/signing-followup-20260906/security-review/keybay-sdk-review-20260906-r2.tar.gz)
includes a source manifest, exact snapshot identity, selected
public evidence, and this brief. Raw device/provider logs and signing material
are excluded. No external recipient has been selected or sent the package.

The R2 archive remains immutable at `387c0d97…`. Subsequent physical iOS
upgrade/crash evidence and native CI reports are linked from the qualification
report and retained in a [public evidence addendum](../build/qualification/signing-followup-20260906/security-review/keybay-sdk-review-20260906-addendum.tar.gz).
Later changes affect test fixtures, CI and documentation;
the reviewed SDK runtime, dependency locks and physical iOS harness are unchanged.
A subsequent [physical Android crash report](../build/qualification/android-crash-20260906T154620Z/observation.json)
adds native termination/recovery and cleanup evidence for the unchanged SDK and
mobile fixture; it does not alter either immutable archive.

The design has one common framed-snapshot engine, one immutable host binding,
and one platform protector per supported profile. Review the actual boundary
and lifecycle invariants; avoid adding general-purpose storage or capability
abstractions unless a demonstrated defect requires them.

| Review area | Main implementation | Questions to resolve |
| --- | --- | --- |
| Binary format and cryptographic transcript | `packages/keybay/lib/src/v2/format/` | Are domain separation, key derivation, AAD, nonce use, canonical decoding and all resource bounds sound? Can attacker-controlled metadata select authority or cause unauthenticated plaintext to escape? |
| Reads, writes and auth changes | `framed_store_reader.dart`, `framed_store_writer.dart`, `framed_store_rotation.dart`, `keybay_v2.dart` in the V2 directory | Are generation pins, copy-forward authentication, session invalidation, passphrase changes and old-or-new commit semantics correct under concurrent processes and failures? |
| Custody and cleanup | `platform_protector.dart`, `exportable_root_lease.dart`, `exportable_root_protector_core.dart`, `passphrase_kdf.dart` | Does every owned secret have a bounded lifetime? Does cleanup preserve primary failure and revoke exactly the intended state? Distinguish best-effort managed-memory clearing from a secure-erasure guarantee. |
| Host authority | `application_identity.dart`, `host_binding.dart`, `*_host_platform.dart` | Does native or declared identity exclusively select the location and provider? Are OS container relocation and namespace-only desktop limitations represented honestly? |
| OS adapters | `posix_store_files.dart`, Apple/JNI FFI and platform root stores | Check descriptor ownership, ABI declarations, no-follow operations, durable replacement, Keychain groups/accessibility, Android key invalidation and provider races. |
| Linux portal | `linux_secret_portal.dart`, `portal_secret_pipe.dart`, `flatpak_secret_portal_protector.dart` | Check sender/owner authentication, early responses, FD ownership, cancellation/timeout cleanup, byte bounds, no continuation tokens and no Secret Service fallback. |

The attacker can supply malformed or restored store files and race operations
within the documented filesystem/provider permissions. An ordinary same-user
desktop process is not an OS-isolated application. Root/admin compromise,
arbitrary code execution inside the application, live-memory confidentiality,
and complete-store rollback resistance are not promised.

## Local findings

### SR-001: cancelled portal read keeps the process alive — fixed

The real GNOME prompt test returned `platformOperationFailed` after cancellation,
but the Dart process remained alive beyond 70 seconds. The retained receipt
distinguishes the returned API failure from the process timeout. Dart's
`ReadPipe` implementation defers cancellation until its blocking read completes;
an outstanding provider descriptor can prevent completion indefinitely.

The fix preserves the anonymous pipe and replaces its blocking reader with a
bounded nonblocking descriptor, polled only while retrieval is active. Failure
closes the reader and clears its native buffer synchronously. The application
API, provider protocol, encrypted format and other platform profiles are unchanged.
A child-process regression deliberately retains a duplicate provider descriptor
and must exit naturally. Real GNOME cancellation and timeout now permit clean
exit and reopening the existing store without provider restart, including two
overlapping prompt cancellations. Timeout recovery explicitly dismisses any
remaining dialog; automatic provider UI dismissal is not claimed.

External review should examine the small new FFI boundary, descriptor-alias
opening, close-on-exec behavior, native-buffer clearing, platform ABI constants
and cleanup races. The broader D-Bus deadline/resource-lifetime limitations
remain documented in the implementation.

### SR-002: hardened standalone Dart executable fails before SDK startup — bounded resolution

The new Developer ID lane verifies a trusted signature, secure timestamp,
hardened-runtime flag and empty entitlements, then requires actual execution.
On macOS 26.2 arm64 with Dart 3.12.2 the process was killed before reaching the
fixture. Its crash report identifies `CODESIGNING / Invalid Page` in an executable
`VM_ALLOCATE` region. A tiny program containing no Keybay imports reproduces
the failure: the hardened signed build exits by signal 9, while a signed
control without hardened runtime exits successfully.

This blocks the tested standalone hardened distribution shape. It does not
invalidate the separately qualified native SDK or signed Flutter app results.
The existing CLI structural signature test does not establish that the hardened
binary can launch. Do not clear this gate using structural verification alone.

The SDK qualification now uses a separately signed native AOT module and a
dedicated matching `dartaotruntime`. Both retain hardened runtime, library
validation and empty entitlements. Builds 101/102 passed actual execution,
passphrase-protected store continuity, and exact provider/file cleanup. An
ad-hoc module was separately rejected by native library validation. No signing
exception or security-setting relaxation was adopted.

The upstream [Dart 3.12.2 snapshot loader](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/bin/snapshot_utils.cc)
uses the native dynamic loader for a separate Mach-O image; an appended image
uses its custom mapper. That mapper's [executable mapping path](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/bin/file_macos.cc)
copies bytes into anonymous memory. This explains the tested distinction;
`allow-jit` alone also failed the minimal appended-image probe. The single-file
product packaging decision remains deferred with CLI work. The qualified form
is a runtime/module pair, not a repaired single-file executable.

[Dart documents executable signing support](https://dart.dev/tools/dart-compile);
[Apple's distribution-signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
requires hardened runtime for Developer ID distribution. The observed failure
does not require an SDK cryptographic redesign.

### SR-003: separate native AOT module cannot resolve embedded identity — fixed

The signed runtime/module pair launched, then failed SDK host resolution. The
resolver recognized a compiled application only when the script path equalled
the process executable. A separate module has a different script path and can
retain package configuration from compilation.

The resolver now also recognizes ELF/Mach-O native module headers and requires
the existing embedded application declaration. It does not derive an ID from
the path, header, environment or launch arguments. Source and activated launch
regressions continue to require owning metadata and reject conflicting IDs.
The existing SDK compile helper adds only `--aot-snapshot`; the encrypted
format, cryptography, host profiles and public store API are unchanged.

Review this additional format-classification boundary and its namespace-only
claim. Unit rejection cases, real compiled modules and the full hardened SDK
continuity fixture passed. Native module image recognition is not signature
verification; signed-page enforcement remains the platform loader's job.

### SR-004: HKDF destruction was described too broadly — documentation corrected

The pinned `cryptography` 2.9.0 `DartHkdf.deriveKey` returns
`SecretKeyData(result)` with `overwriteWhenDestroyed` left false. Its
`SensitiveBytes` view is immutable. Calling `destroy()` on this result releases
the reference but does not overwrite the backing bytes. Keybay correctly clears
its separate mutable snapshots, but the RFC's unqualified references to clearing
derived keys and Flatpak roots overstated what that dependency boundary achieves.

The RFC and security policy now distinguish these lifetimes explicitly. This is
a low-severity documentation finding within the existing exclusion of live-memory
confidentiality; no plaintext persistence, authentication bypass or return of
unauthenticated plaintext was demonstrated. A custom HKDF implementation solely
to erase this allocation would add crypto code while leaving other dependency,
VM and OS copies outside our control. Keep the pinned implementation and its
independent vectors. External review should assess this residual memory exposure.

## Adversarial source review, 2026-09-06

This additional engineering review inspected the SDK runtime at
`808738874ec3d0d6e8ee4d6d8f5289c0393bf1a8`, whose SDK Dart-source digest is
`4f88c9e5546a35a5e1827d8b12fcaa909c48a6370a966542584ae713535d1cf9`.
The digest rule is recorded in the qualification report. Runtime code, format,
dependency pins and public API were unchanged by this review. New tests and the
claim correction accompany the results. This is not independent external review.

| Boundary inspected | Assessment and regression evidence |
| --- | --- |
| Format, AEAD, HKDF, Argon2 and public inputs | Canonical decoders and fixed bounds precede expensive work; each transcript binds its intended context; only authenticated plaintext is returned. Existing independent format vectors remain the construction check. Six new dependency checks confirm the in-place AEAD workspace assumption for empty, 32-byte and maximum-size record values with valid and invalid tags. Invalid-tag decryption writes plaintext into that workspace; both SDK AEAD opening paths clear it in `finally`. These checks do not prove erasure of cipher internals. |
| Reader, writer, rotation, reset and session queues | Reviewed pinned reads, copy-forward frame digests, partial reset, indeterminate replacement classification, close and peer invalidation. Two new tests combine the production engine with real POSIX lock contention: a waiting writer fails stale after committed rotation, but commits after an aborted rotation. They also check reopened protection, acknowledged data, subsequent writing and reset cleanup. Provider custody and KDF are disposable test implementations in these cases. |
| POSIX boundary | Reviewed descriptor-relative fixed names, no-follow opens, file/directory modes, macOS ACL checks, staging ownership, rename/fsync ordering, lock deadlines and failure precedence. Existing symlink, FIFO, ACL, staging-fault and process-kill tests exercise these paths. This inspection does not establish filesystem behavior under sudden power loss or every mount configuration. |
| Host identity and platform custody | Reviewed ordinary declaration resolution, domain/address separation, Apple exact-group and classic-Keychain dispatch, Android package/UID/no-backup facts and JNI key operations, and Linux confinement selection. No new fallback, root-selection or cross-application authority defect was confirmed. Native platform behavior remains bounded by the configurations in the qualification report. |
| Secret Service and portal transport | Reviewed fixed D-Bus destinations, response shape, owner/sender checks, bounded pipe reads, forbidden interaction and post-timeout continuations. The new concurrent cancellation test proves that a late reply from a cancelled request cannot finish or abort its surviving peer. Existing timeout, cancellation, malformed-response and no-fallback cases remain in the same routine suite. |

No additional SDK correctness or security defect was confirmed in the reviewed
paths. The result supports retaining the existing shared engine and narrow
platform adapters. It does not justify a broader security claim or close the
remaining qualification gates. SR-004 is a claim correction, not an implementation
redesign. The nine added cases run automatically in the existing `core` lane;
there is no new qualification framework or runtime seam.

Validation: 47 focused tests passed; the local core lane passed 493 tests with
three Linux D-Bus skips, and SDK analysis was clean on Dart 3.13.3. The complete
[CI matrix](https://github.com/danReynolds/keybay/actions/runs/34045994325) then
passed at `e179370b…`, including the new cases on native Linux/macOS and minimum
Dart. All nine SDK reports identify the exact clean commit. Retained run details
are linked from the [qualification report](qualification-status.md).
Independent review, maintained-
device Argon2 acceptance budgets, remaining physical lifecycle procedures and
final supported-configuration/release acceptance remain open. No physical device
was operated during this source-review pass. The earlier immutable handoff
archives remain evidence for their recorded contents.

## Evidence and acceptance

Use the linked qualification report for each source/configuration's actual
results. Cross-language vectors, fuzzing, device runs and local inspection are
supporting evidence; none replaces an independent cryptographic format review.

The external reviewer should return a dated report naming the exact source and
dependency set, reviewed boundaries, reproducible findings with severity and
impact, unreviewed areas, and residual risks. Findings require a recorded
resolution or explicit scoped release decision. A changed security-relevant
implementation requires re-review of the affected boundary and its regression
evidence. Publication and release approval are separate steps.

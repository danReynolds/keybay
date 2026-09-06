# SDK security review handoff

Prepared 2026-09-06. **Independent external review remains pending.** This is
the review brief and record of local findings, not an external audit report.
The SDK remains the priority; CLI/TUI, Snap, Windows, migration, hardware
credentials and rollback anchors are outside this review's implementation scope.

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

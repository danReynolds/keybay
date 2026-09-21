# Keybay on macOS

macOS has two V2 host profiles. Both use the common encrypted framed
file and one Keychain root. The process's signed application identifier selects
the entitled profile; absence selects the ordinary unentitled profile. Keybay
does not retry the other profile after an operation fails.

## Protection at a glance

**Entitled app:** <span class="protection-badge protection-app">App-bound key</span><br>
**CLI / unentitled app:** <span class="protection-badge protection-account">Account-level</span>

- **Key access:** the entitled profile uses a signed Keychain group. The ordinary
  profile uses the login Keychain; its declared namespace does not authenticate
  the calling application.
- **File isolation:** entitled apps need App Sandbox for container isolation.
  An unsandboxed app's private file permissions do not isolate it from its own user.
- **Hardware assurance:** neither generic Keychain root carries a Secure Enclave claim.
- **Passphrase:** optional in both profiles; recommended for high-value records
  in the account-level profile.
- **Main limitation:** signed-group key access and file sandboxing are separate.
  Login-Keychain ACLs are not a portable application-isolation guarantee.

These are [key-access levels](../design.md#platform-protection-levels), not
hardware ratings or protection against a compromised host process.

## Requirements

For the entitled profile, the running app needs its signed application
identifier and matching Data Protection Keychain access. Enable App Sandbox
when the app also needs file isolation. Ordinary executables declare their
namespace in the owning pubspec or embed it with `keybay_compile`, and need
access to the effective account's login Keychain. Release binaries also need
the [packaging qualification](#hardened-aot-packaging) below.

## Signed and entitled application

Keybay derives the application identifier from the code signature and checks
it against the bundle identifier. The encrypted file lives in the app container
when App Sandbox is enabled, otherwise in a derived Application Support
directory. One stable random root is stored in the exact signed Data Protection
Keychain group, non-synchronizing and `WhenUnlockedThisDeviceOnly`.

The entitlement protects root access from processes outside the signed group.
It does not by itself sandbox the file; App Sandbox is a separate protection.
Keychain state can survive loss of the application container. If a reinstall,
restore or interrupted initialization leaves a root without a complete file,
`open()` returns `storeStateConflict`. Use the SDK's [deliberate recovery
procedure](../sdk.md#errors-and-limits); do not reset solely because an error
occurred. Physical reinstall/restore and entitlement transitions need their
own qualification.

Explicitly authorized same-team apps may share a group. Keybay therefore makes
no absolute per-app or Secure Enclave claim.
See [Apple's access-group model](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

## CLI and unentitled application

An ordinary executable declares its namespace in the owning pubspec or embeds
it with `keybay_compile`. The encrypted file lives in a restrictive derived
Application Support directory. One identity-derived root item lives in the
effective account's explicit login Keychain.

Classic file Keychains cannot reliably suppress UI for one native call.
Opening, changing authentication, and resetting may therefore show trusted
Keychain UI. Keybay rejects interaction-forbidden root acquisitions before
calling the Keychain. Record operations use the session's store key and never
contact the provider. If a changed file cannot be authenticated with that key,
the error remains `storeAuthenticationFailed` instead of inferring a peer
authentication change.

This profile is `namespaceOnly`: the declaration is not authenticated by the
OS. Keychain ACL behavior can add protection for a stable signed executable,
but `dart run`, unsigned/ad-hoc builds, binary replacement, and invoking a
trusted CLI do not form one portable application sandbox. Another same-user
process may also modify the application files.

Use a Keybay passphrase for passwords and other high-value records. It keeps
the store key unavailable from the login-Keychain item and encrypted file
alone. It cannot prevent an authorized same-user actor from deleting or
replacing those artifacts.

## Hardened AOT packaging

The SDK's compile helper can produce a native module:

```sh
dart run keybay:keybay_compile --aot-snapshot bin/app.dart -o build/app.aot
```

Package it with a dedicated copy of the matching SDK's `dartaotruntime`. Sign
both files with the same Developer ID team, hardened runtime and secure
timestamps, then launch the runtime with the module's absolute path. Keep
library validation enabled; the qualified pair needs no entitlement exceptions.
The namespace remains the declaration embedded in the application module.

The repeatable `macos-developer-id` lane passed native execution, passphrase
protection, replacement by a distinct signed module, and exact Keychain/file
cleanup. An ad-hoc module was separately rejected by the hardened runtime's
library validation. This covers the unentitled profile on the tested Mac;
notarization and entitled-app distribution are separate evidence.

On Dart 3.12.2/macOS 26.2 arm64, a hardened single-file `dart compile exe`
output is killed before startup. Its appended-image loader copies executable
pages into anonymous memory; a separate module uses the native loader. The
[review brief](../security-review.md) records the reproduction and source analysis.
The product CLI reproduced the hardened single-file failure on Dart 3.13.4.
Separate signed runtime/module fixtures passed startup and protected-store
upgrade checks, but the production archive, installed launcher, Homebrew
upgrade and downloaded/notarized artifact still need qualification. This is an
active CLI release gate; see [release readiness](../release-readiness.md).

## Limitations

The two profiles use the same authenticated encryption. Their difference is the
OS authority required to access the platform root. An entitled key does not
sandbox the encrypted file, and an account-level passphrase does not create
an OS-authenticated application identity. Both retain the shared
[threat model](../design.md#threat-model): no protection against a compromised
host process, plaintext after disclosure, deletion or rollback. Keybay does not
add a per-read biometric or user-presence prompt.

## Recovery

If a retained root, missing file or changed identity produces a conflict, use
the SDK's [deliberate recovery procedure](../sdk.md#errors-and-limits).
`Keybay.reset()` intentionally abandons the managed store; it cannot recover
values. Do not reset automatically after an access error or profile change.

## No fallback or migration

Entitled and unentitled profiles have different identity/file/provider
commitments. A missing entitlement, inaccessible group, Keychain access failure,
changed signature, missing root, or mismatched retained item fails closed. V2
does not probe or migrate pre-V2 state and never falls back between profiles.

## Qualification

Real login-Keychain integration exercises the unentitled profile. A signed
Flutter harness exercises the entitled Data Protection profile. Exact device
and lifecycle qualification is tracked in the
[qualification record](../qualification-status.md).

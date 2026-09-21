# Keybay on iOS

Keybay uses the application's private storage and the Data Protection Keychain.

## Protection at a glance

<span class="protection-badge protection-app">App-bound key</span>

- **Key access:** restricted to the exact signed Keychain access group.
- **File isolation:** the application's private container, with backup exclusion
  set and verified by Keybay.
- **Hardware assurance:** no Secure Enclave claim for the generic Keychain root.
- **Passphrase:** optional; adds a requirement alongside the platform root.
- **Main limitation:** deliberately authorized apps can share the access group.
  An unlocked session can return plaintext; there is no per-read biometric check.

This is a [key-access level](../design.md#platform-protection-levels), not a
hardware rating or protection against a compromised host process.

## Requirements

The processed `Info.plist` must contain:

```xml
<key>KeybayApplicationIdentifier</key>
<string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
```

This build-expanded value is checked against the exact bundle identifier and
used as the Keychain access group on every root operation. It is not a runtime
application selector. A pure Dart package cannot inject the host setting, so it
belongs in the checked-in iOS application configuration.

## Storage and access

iOS uses the common V2 encrypted framed file in the application's private
Application Support directory. Keybay sets and verifies backup exclusion. One
stable random platform root lives in the Data Protection Keychain; records do
not become individual Keychain items.

The cryptographic storage domain binds the signed application identity and the
fixed `Library/Application Support/keybay-v2` location relative to its container.
It does not persist the container's absolute UUID path, which Apple may change
on update while preserving Library data. Foundation still supplies the current
physical root, and the usual canonical-path and private-file checks apply.
See [Apple's update guidance](https://developer.apple.com/library/archive/technotes/tn2285/_index.html).

The root item is non-synchronizing and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. A peer application outside the
signed group cannot read it.

## Limitations

A developer may intentionally authorize another
same-team app into an access group, so the exact claim is signed-group
isolation—not absolute privacy and not Secure Enclave backing.
See [Apple's access-group model](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

With no additional method, an app can open after the device is currently
unlocked and the Keychain permits access. Adding a Keybay passphrase makes both
the Data Protection Keychain root and that passphrase necessary to recover the
store key. Keybay does not add biometric or per-operation presence gating in
V2.

The shared [threat model](../design.md#threat-model) still applies, including
compromised processes, plaintext after a read, deletion and rollback.

## Recovery

Keychain state may outlive uninstall while the application container does not.
If a reinstall sees retained root state without its complete encrypted store,
Keybay fails closed until the application explicitly calls `Keybay.reset()`.
The same root-only state can follow a same-device restore or interrupted first
initialization. Follow the SDK's [deliberate recovery procedure](../sdk.md#errors-and-limits);
do not reset automatically on conflict. Keychain retention after uninstall is
an [implementation detail](https://developer.apple.com/forums/thread/36442),
not a permanent OS guarantee. Keybay never treats retained or missing state as
permission to initialize over an existing encrypted store. Physical reinstall
and restore remain separate qualification cases.

## Qualification

The iOS simulator lane exercises the genuine Keychain and file APIs, including
open, persistence, passphrase protection, and reset. It does not prove physical
hardware mediation. Stronger lifecycle evidence is tracked in the
[device security suite](../device-security-suite.md).

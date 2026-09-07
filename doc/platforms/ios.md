# Keybay on iOS

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

The processed `Info.plist` must contain:

```xml
<key>KeybayApplicationIdentifier</key>
<string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
```

This build-expanded value is checked against the exact bundle identifier and
used as the Keychain access group on every root operation. It is not a runtime
application selector. A pure Dart package cannot inject the host setting, so it
belongs in the checked-in iOS application configuration.

The root item is non-synchronizing and
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. A peer application outside the
signed group cannot read it. A developer may intentionally authorize another
same-team app into an access group, so the exact claim is signed-group
isolation—not absolute privacy and not Secure Enclave backing.

With no additional method, an app can open after the device is currently
unlocked and the Keychain permits access. Adding a Keybay passphrase makes both
the Data Protection Keychain root and that passphrase necessary to recover the
store key. Keybay does not add biometric or per-operation presence gating in
V2.

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

The iOS simulator lane exercises the genuine Keychain and file APIs, including
open, persistence, passphrase protection, and reset. It does not prove physical
hardware mediation. Stronger lifecycle evidence is tracked in the
[device security suite](../device-security-suite.md).

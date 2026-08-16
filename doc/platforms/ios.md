# keybay on iOS

Each secret is a **native item in the Data Protection Keychain**. There is no
Keybay container or separate Keybay store key on this path; the operating
system owns the item's at-rest protection and access policy.

Unlike macOS, there is **no probe**: the Data Protection keychain is the only
keychain on iOS, and every app can use it (via the default access group every
signed app carries). Keybay derives the first group from the signed process and
includes it explicitly on every add, read, update, enumerate, and delete. This
prevents a colliding item in another entitled/shared group from being read,
overwritten, listed, or removed. So the scheme is unconditional, but the item
namespace is not ambiguous.

**Item policy.** Items are created
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable by background work
after the first unlock following a boot, does not migrate to another device on
restore, and is not synchronized through iCloud Keychain
(`synchronizable = false`).
Updates reassert both attributes, so a matching pre-existing item cannot retain
a weaker/migratory accessibility or synchronization policy.

**What this policy means.** The item does not migrate to a different device and
is not synchronized through iCloud. `AfterFirstUnlock` is intentionally
compatible with background work: after the first unlock following a reboot, the
item remains accessible when the device relocks. Keybay does not add biometric
or current-unlock gating.

**Note — uninstall.** Keychain items commonly persist after app uninstall, but
Apple does not document that as a contract. Applications must tolerate either
persistence or deletion across uninstall/reinstall rather than use Keychain
state as an installation sentinel.

**Requirements.** Runs inside a Flutter iOS app. Being pure Dart + FFI, it
pulls in **zero CocoaPods plugins**.

**Level reporting.** `describe().scheme` reports `nativeItems`.
`describe().level` is null: Keybay applies the documented Data Protection
Keychain policy but does not infer or attest a hardware-backing level for the
stored items.

**Validation.** The full round-trip (write/read/enumerate/delete, binary and
unicode values, cross-instance reads) is validated on the iOS simulator by the
`example_flutter/` integration suite. This proves the genuine keychain API path,
not physical hardware mediation or lifecycle behavior. The repeatable physical
qualification and its current gaps are tracked in the
[device security suite](../device-security-suite.md#ios).

# keybay on Android

**Requires Android 12 (API 31) or newer.** Older versions throw a typed
`KeystoreUnreachable` rather than degrading.

Every secret lives in **one authenticated encrypted file** in the app-private
no-backup directory (`<dataDir>/no_backup/<appId>/secrets.enc`), sealed with
**XChaCha20-Poly1305** under an HKDF-SHA256-derived key with a key-commitment
header. The 32-byte file key is wrapped by an **AES-256-GCM key created in
[Android Keystore](https://developer.android.com/privacy-and-security/keystore)**.
Keybay requests
[StrongBox](https://developer.android.com/privacy-and-security/keystore#StrongBoxKeyMint),
then retries without that request when StrongBox is unavailable. The resulting provider can be StrongBox, TEE, or
software-backed; `describe().level` inspects and reports which level Android
returns. Only the *wrapped* key blob (`store-key.wrapped`, a small versioned
`SKW1` format) sits beside the container; Keybay writes no plaintext copy of the
file key there.

**What this resists.** A copied container and wrapped-key blob cannot be opened
without a Keystore provider able to use the corresponding wrapping key. A
restore or transfer that lacks that key fails as `KeyInvalidated` rather than
silently creating a new store. Hardware resistance applies only when Android
reports TEE or StrongBox.

## Why this is pure Dart (no plugin, no `package:jni`)

Android's Keystore is a Java API with no NDK/C surface, so reaching it normally
means JNI — and the ecosystem's JNI packages require the Flutter SDK, which
would break every Flutter-less server that depends on this package. keybay
avoids that: Android exports `JNI_GetCreatedJavaVMs` from `libnativehelper` to
apps at **API 31+**, so a hand-rolled `dart:ffi` shim can discover the JVM and
call framework classes directly — **no plugin, no platform channels, no
Flutter-SDK dependency**. The maintained platform policy is in
[the security design](../design.md#9-platform-policy); deeper chronology remains
in that file's source history.

## Reliability

Android Keystore has a well-known flaky tail; the design is chosen for the
best-case reliability profile and to fail loudly, never silently:

- The wrapping key is generated `setUserAuthenticationRequired(false)` — not
  invalidated by biometric-enrollment changes; the gate is device-level and the
  container adds its own AEAD.
- **StrongBox is attempted, with a normal Android Keystore retry** on
  `StrongBoxUnavailableException`. The retry is not assumed to be hardware;
  its actual level is inspected.
- Every store creation runs a **wrap → unwrap self-test** through the real
  Keystore before anything is persisted — a device with a broken Keystore fails
  at setup, not later at read time.
- If the wrapped-key blob is present but its Keystore key is gone or unusable
  (restore onto a different device, OS/OEM eviction, corruption), reads throw a
  typed **`KeyInvalidated`** instead of silently starting an empty store.
  Recovery is deleting the store's data directory and re-provisioning.
- **Hardware backing is measured, not assumed.** `describe().level` reads the
  KEK's
  [`KeyInfo.getSecurityLevel()`](https://developer.android.com/reference/android/security/keystore/KeyInfo#getSecurityLevel()):
  `hardwareBacked` only when the Keystore
  reports `TRUSTED_ENVIRONMENT` or `STRONGBOX`, otherwise `softwareBacked`
  (a software Keystore implementation, or an emulator). Presence of the
  Keystore is never taken as proof of hardware.

## Backup behavior and upgrade migration

The store and every sidecar live beneath Android's no-backup namespace, so a
host app no longer needs path-specific manifest exclusions for Keybay. The
pure-Dart resolver derives that namespace from the app's framework cache path;
the Android integration harness independently compares it with
`Context.getNoBackupFilesDir()` on each maintained emulator tier.

On the first open after upgrading from 0.1.0, Keybay atomically renames the
complete `<dataDir>/files/<appId>/` directory into the no-backup namespace. The
container, wrapped key, and lock move together and the Android Keystore alias
does not change. If both locations contain state, `StoreMigrationConflict`
fails closed without modifying either. A legacy container restored without its
device-bound Keystore key still fails as `KeyInvalidated`; migration never
rekeys or silently replaces it.

Android-managed backup exclusion is intrinsic to this location. Physical or
service-backed cross-platform transfer remains outside the current retained
qualification evidence; the boundary is tracked in the
[device security suite](../device-security-suite.md#pre-10-exploit-chain-baseline).

**Validation.** The full round-trip, 0.1.0 migration, no-backup path, and on-disk
shape (container is ciphertext; only the small wrapped-key blob is beside it)
are maintained on API 31 and API 36 emulators. As with iOS, an
emulator's secure hardware is software-emulated, so the hardware property itself
is established only by a retained physical report for
[`KB-AND-010`](../device-security-suite.md#android). The repeatable device suite,
not an emulator run, is also where OEM and lifecycle variance is recorded.

# keybay on Android

**Requires Android 12 (API 31) or newer.** Older versions throw a typed
`KeystoreUnreachable` rather than degrading.

Every secret lives in **one authenticated encrypted file** in the app-private
files directory (`<dataDir>/files/<appId>/secrets.enc`), sealed with
**XChaCha20-Poly1305** under an HKDF-SHA256-derived key with a key-commitment
header. The 32-byte file key is wrapped by an **AES-256-GCM key created in
Android Keystore**. Keybay requests StrongBox, then retries without that request
when StrongBox is unavailable. The resulting provider can be StrongBox, TEE, or
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
  KEK's `KeyInfo.getSecurityLevel()`: `hardwareBacked` only when the Keystore
  reports `TRUSTED_ENVIRONMENT` or `STRONGBOX`, otherwise `softwareBacked`
  (a software Keystore implementation, or an emulator). Presence of the
  Keystore is never taken as proof of hardware.

## Exclude the store from backups

Because the wrapping key never migrates, backed-up or transferred store data
can't be decrypted on another device (you'd get `KeyInvalidated`). Excluding the
store directory avoids that confusing restore state and keeps your ciphertext
out of backups. **Security does not depend on this** — restored blobs are
useless without the original device — and since this is a plain Dart package,
not a plugin, it can't inject manifest rules for you. Add them (API 31+):

```xml
<!-- AndroidManifest.xml -->
<application android:dataExtractionRules="@xml/data_extraction_rules" …>
```

```xml
<!-- res/xml/data_extraction_rules.xml — <appId> is the id you pass to
     SecretStorage(appId:) -->
<data-extraction-rules>
  <cloud-backup><exclude domain="file" path="<appId>/" /></cloud-backup>
  <device-transfer><exclude domain="file" path="<appId>/" /></device-transfer>
</data-extraction-rules>
```

The `example_flutter/` app carries these rules as a living example.

**Validation.** The full round-trip and the on-disk shape (container is
ciphertext; only the small wrapped-key blob is beside it) are validated on an
API 33 emulator, including the StrongBox-fallback branch. As with iOS, an
emulator's secure hardware is software-emulated, so the hardware property itself
is pending a one-time physical-device run.

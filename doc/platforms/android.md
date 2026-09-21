# Keybay on Android

Keybay uses Android's application sandbox and a non-exportable Keystore key.

## Protection at a glance

<span class="protection-badge protection-app">App-bound key</span>

- **Key access:** restricted to the installed application's package/UID context.
- **File isolation:** the application's private `noBackupFilesDir`.
- **Hardware assurance:** StrongBox, TEE or software, depending on the device;
  a non-exportable key does not by itself establish hardware backing.
- **Passphrase:** optional; required in addition to the Keystore operation when set.
- **Main limitation:** Keybay does not require biometric or user-presence
  authentication for each key use. A compromised app can still use its key.

This is a [key-access level](../design.md#platform-protection-levels), not a
hardware rating or protection against a compromised host process.

## Requirements

Keybay V2 requires Android 12 (API 31) or newer. Android Keystore and the
application's private storage must be available. Identity and paths come from
the host runtime; callers cannot substitute another application's identity.

## Storage and access

Keybay derives the installed
package/UID identity from the host process and stores one encrypted framed file
under the application's private `noBackupFilesDir`.

One non-exportable AES-256-GCM key in Android Keystore protects the store's
changing key package. Record frames remain under an independent random store
key; compromising one file frame does not turn it into the Keystore root or
another store's key.

Android Keystore has no NDK secret-storage surface. Keybay reaches the framework
API through its existing direct JNI FFI boundary, avoiding a Flutter plugin or
platform channel. The app-private file location comes from the Android runtime,
not a caller-provided path or application ID.

## Limitations

Key generation requests StrongBox once and retries without that request only
for Android's documented `StrongBoxUnavailableException`. The result may be
StrongBox, TEE, or software-backed. Keybay's austere V2 SDK exposes no generic
capability API; qualification reads `KeyInfo.getSecurityLevel()` and reports
only what Android establishes. An emulator proves the genuine API path, not
physical hardware mediation.
See [Android's Keystore protection and hardware guidance](https://developer.android.com/privacy-and-security/keystore).

The package/UID sandbox normally keeps peer applications away from both the
file and the Keystore key. A Keybay passphrase is optional defense in depth. It
is still additive: opening then needs both the application-bound Keystore
operation and the passphrase.

Keybay sets user authentication for Keystore operations to not required. Device
lock does not establish a Keybay per-use authentication barrier. The shared
[threat model](../design.md#threat-model) also excludes a compromised process,
plaintext after a read, deletion and rollback.

## Recovery

If the encrypted file exists but the Keystore key is missing, unusable, or
invalidated, Keybay fails with a typed platform-key error. It does not generate
a replacement root or initialize an empty store. `Keybay.reset()` is the
explicit destructive recovery when the data is intentionally abandoned.

## Qualification

API 31 and current emulator lanes exercise initialization, persistence,
passphrase protection, tamper failure, and reset. Physical/OEM and lifecycle
evidence is tracked separately in the
[device security suite](../device-security-suite.md#android).

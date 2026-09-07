# Keybay on Android

Keybay V2 requires Android 12 (API 31) or newer. It derives the installed
package/UID identity from the host process and stores one encrypted framed file
under the application's private `noBackupFilesDir`.

One non-exportable AES-256-GCM key in Android Keystore protects the store's
changing key package. Record frames remain under an independent random store
key; compromising one file frame does not turn it into the Keystore root or
another store's key.

Key generation requests StrongBox once and retries without that request only
for Android's documented `StrongBoxUnavailableException`. The result may be
StrongBox, TEE, or software-backed. Keybay's austere V2 SDK exposes no generic
capability API; qualification reads `KeyInfo.getSecurityLevel()` and reports
only what Android establishes. An emulator proves the genuine API path, not
physical hardware mediation.

The package/UID sandbox normally keeps peer applications away from both the
file and the Keystore key. A Keybay passphrase is optional defense in depth. It
is still additive: opening then needs both the application-bound Keystore
operation and the passphrase.

If the encrypted file exists but the Keystore key is missing, unusable, or
invalidated, Keybay fails with a typed platform-key error. It does not generate
a replacement root or initialize an empty store. `Keybay.reset()` is the
explicit destructive recovery when the data is intentionally abandoned.

Android Keystore has no NDK secret-storage surface. Keybay reaches the framework
API through its existing direct JNI FFI boundary, avoiding a Flutter plugin or
platform channel. The app-private file location comes from the Android runtime,
not a caller-provided path or application ID.

API 31 and current emulator lanes exercise initialization, persistence,
passphrase protection, tamper failure, and reset. Physical/OEM and lifecycle
evidence is tracked separately in the
[device security suite](../device-security-suite.md#android).

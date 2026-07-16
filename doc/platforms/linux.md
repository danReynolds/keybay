# keybay on Linux

Every secret lives in **one authenticated encrypted file** at
`${XDG_DATA_HOME:-~/.local/share}/<appId>/secrets.enc` (mode `0600`, written
atomically), sealed with **XChaCha20-Poly1305** under an HKDF-SHA256-derived key
with a key-commitment header. The 32-byte file key is stored in the **Secret
Service** (GNOME Keyring or KWallet) via `secret-tool`. Keybay writes no
plaintext copy of that key beside the container; the service owns how it
persists credential data.

**What this resists.** The file key sits in the Secret Service under a
login-derived key: safe from other local users and casual theft. Against a
stolen disk it is only as strong as the login/keyring password. The
authenticated container adds tamper detection and separates the portable data
file from its key; it does not turn a login-bound key into hardware protection.

**Transport.** The secret crosses to `secret-tool` on **stdin** (never argv,
which is visible in `ps`), base64-encoded so binary and newlines survive. Every
call has a hard timeout — a locked collection would otherwise spawn a GUI
prompter that hangs forever over SSH — and on timeout the library kills it and
surfaces a typed `KeystoreLocked`.

**Requirements.** `secret-tool` (Debian/Ubuntu: `libsecret-tools`) and a Secret
Service provider — GNOME Keyring, or KWallet ≥ 5.97.

**Validation.** Real Secret Service round-trips (set/get/update/delete, every
byte through the base64 transport, enumeration) run against a real
gnome-keyring under a throwaway D-Bus session — in CI on every push, and
re-runnable from a Mac via `tool/test_linux.sh` (Docker).

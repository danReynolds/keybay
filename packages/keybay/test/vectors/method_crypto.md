# Method key primitive vectors

`v2_method_crypto_test.dart` first checks RFC 9180 Appendix A.2.1's published
base-mode vector for DHKEM(X25519, HKDF-SHA256), HKDF-SHA256 and
ChaCha20Poly1305. This pins the ephemeral DeriveKeyPair operation, KEM transcript,
HPKE key schedule and sequence-zero encryption against an external result.
The implementation supports only single-shot base mode with that fixed suite.
It does not expose suite negotiation, PSKs, authenticated modes or exporters.

The second fixture checks Keybay's credential KDF and domain-separated envelope
against `method_crypto_reference.py`, using Python's stdlib HMAC/SHA256 and
`cryptography` X25519/ChaCha20Poly1305. It was generated with cryptography 49.0.0.
The generator also checks its HPKE implementation against the published vector.
Regenerate from `packages/keybay`:

```
python3 test/vectors/method_crypto_reference.py > test/vectors/method_crypto.json
dart test test/v2_method_crypto_test.dart
```

## Frozen primitive profile

The method private key is the 32-byte result of HKDF-SHA256 with credential
material as input, a random 16-byte method salt, and info equal to ASCII
`keybay:v2:methods1:key:private`, one zero byte, and the canonical stable method
context. Credential material is an Argon2 profile's 32-byte output or a verified
Keypass PRF output. Raw passphrases are never inputs to this helper. The store's
context codec must bind store ID, method ID, method kind, salt, and stable
passkey record identity where applicable. It must exclude epoch, the public key
derived from this output, and mutable passkey verifier state.

The method public key is X25519's public key for that private key. Neither a
private key nor a credential-derived symmetric key is persisted. A method's
public key lets an authorized session encrypt a fresh store key after removing
another method without authenticating every surviving credential again.

Store-key wrapping is RFC 9180 base mode, KEM 0x0020, KDF 0x0001, AEAD 0x0003.
HPKE info is ASCII `keybay:v2:methods1:hpke:store-key`, one zero byte, and the
canonical epoch-specific method context. That same context is the AEAD AAD.
It must bind store ID, epoch, method ID and stable method identity, including
the recipient public key. The 80-byte envelope is the 32-byte encapsulation
followed by the 32-byte ciphertext and 16-byte authentication tag. Sequence is
always zero; nonce is derived by HPKE. Every encryption requires an independent
fresh random 32-byte ephemeral seed, expanded using HPKE DeriveKeyPair.

HPKE base mode does not authenticate the sender. Recovering a candidate store
key is insufficient: the engine must authenticate the existing manifest, whose
AAD binds the entire sealed platform package and therefore every method and
public key, before returning a session or encrypting to any stored public key.
Mutable Keypass verifier updates belong in that authenticated directory and must
commit before the corresponding unlock is published. The primitive does not
replace the platform protector, storage transaction or verifier-state CAS.

All-zero X25519 shared secrets are rejected. Returned secret buffers belong to
the caller. Input buffers are synchronously copied. Keybay-owned credential,
derived-key, DH-output, HKDF and plaintext work buffers are cleared on success
and failure; AEAD workspaces are also cleared when the dependency decrypts before
reporting an invalid tag. Pinned-dependency tests check writable HMAC output and
AEAD workspace identity. The Dart X25519 implementation creates private scalar
and arithmetic temporaries that Keybay cannot explicitly overwrite, and the VM
may retain copies. This is not a guarantee of total process-memory erasure.

The primitive tests cover invalid lengths, low-order points, every envelope byte,
every context byte, independent info/AAD changes, credential/salt/context
separation, rewrapping with only a survivor's public key, and caller mutation
immediately after starting an operation. The framing and engine suites must
separately cover method-directory authentication, actual record revocation,
canonical context encoding, migration and atomic commit failures.

Sources: [RFC 9180](https://www.rfc-editor.org/rfc/rfc9180.html),
[RFC 7748](https://www.rfc-editor.org/rfc/rfc7748.html).

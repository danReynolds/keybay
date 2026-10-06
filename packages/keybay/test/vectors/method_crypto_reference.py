"""Independent fixture generator: Python cryptography + stdlib HKDF-SHA256.

Run from packages/keybay:
  python3 test/vectors/method_crypto_reference.py > test/vectors/method_crypto.json

RFC 9180, mode 0, X25519 / HKDF-SHA256 / ChaCha20Poly1305. Only sequence 0
is used: each store-key envelope gets an independently fresh ephemeral seed.
"""

import hashlib
import hmac
import json

from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

KEM_SUITE = b"KEM\x00\x20"
HPKE_SUITE = b"HPKE\x00\x20\x00\x01\x00\x03"


def extract(salt, ikm):
    return hmac.new(salt, ikm, hashlib.sha256).digest()


def expand(prk, info, length):
    assert 0 < length <= 32
    return hmac.new(prk, info + b"\x01", hashlib.sha256).digest()[:length]


def labeled_extract(suite, salt, label, ikm):
    return extract(salt, b"HPKE-v1" + suite + label + ikm)


def labeled_expand(suite, prk, label, info, length):
    return expand(prk, length.to_bytes(2, "big") + b"HPKE-v1" + suite + label + info, length)


def public(sk):
    return X25519PrivateKey.from_private_bytes(sk).public_key().public_bytes_raw()


def seal(pk, plaintext, info, aad, seed):
    dkp = labeled_extract(KEM_SUITE, b"", b"dkp_prk", seed)
    sk = labeled_expand(KEM_SUITE, dkp, b"sk", b"", 32)
    enc = public(sk)
    dh = X25519PrivateKey.from_private_bytes(sk).exchange(X25519PublicKey.from_public_bytes(pk))
    eae_prk = labeled_extract(KEM_SUITE, b"", b"eae_prk", dh)
    shared = labeled_expand(KEM_SUITE, eae_prk, b"shared_secret", enc + pk, 32)
    psk_hash = labeled_extract(HPKE_SUITE, b"", b"psk_id_hash", b"")
    info_hash = labeled_extract(HPKE_SUITE, b"", b"info_hash", info)
    context = b"\x00" + psk_hash + info_hash
    secret = labeled_extract(HPKE_SUITE, shared, b"secret", b"")
    key = labeled_expand(HPKE_SUITE, secret, b"key", context, 32)
    nonce = labeled_expand(HPKE_SUITE, secret, b"base_nonce", context, 12)
    return enc + ChaCha20Poly1305(key).encrypt(nonce, plaintext, aad)


rfc = {
    "source": "https://www.rfc-editor.org/rfc/rfc9180.html#appendix-A.2.1",
    "info": "4f6465206f6e2061204772656369616e2055726e",
    "ephemeralSeed": "909a9b35d3dc4713a5e72a4da274b55d3d3821a37e5d099e74a647db583a904b",
    "publicKey": "4310ee97d88cc1f088a5576c77ab0cf5c3ac797f3d95139c6c84b5429c59662a",
    "privateKey": "8057991eef8f1f1af18f4a9491d16a1ce333f695d4db8e38da75975c4478e0fb",
    "enc": "1afa08d3dec047a643885163f1180476fa7ddb54c6a8029ea33f95796bf2ac4a",
    "plaintext": "4265617574792069732074727574682c20747275746820626561757479",
    "aad": "436f756e742d30",
    "ciphertext": "1c5250d8034ec2b784ba2cfd69dbdb8af406cfe3ff938e131f0def8c8b60b4db21993c62ce81883d2dd1b51a28",
}
r = lambda name: bytes.fromhex(rfc[name])
assert seal(r("publicKey"), r("plaintext"), r("info"), r("aad"), r("ephemeralSeed")) == r("enc") + r("ciphertext")

# These opaque byte contexts test the primitive boundary. The canonical store
# codec has its own transcript tests and is intentionally not reproduced here.
material = bytes(range(32))
salt = bytes(range(32, 48))
context = b"stable-method-context\x00\x01\xff"
hpke_context = b"store-epoch-method-context\x00\x02\xfe"
seed = bytes(range(64, 96))
store_key = bytes(range(96, 128))
private_key = expand(extract(salt, material), b"keybay:v2:methods1:key:private\x00" + context, 32)
pk = public(private_key)
envelope = seal(pk, store_key, b"keybay:v2:methods1:hpke:store-key\x00" + hpke_context, hpke_context, seed)

print(json.dumps({
    "reference": "Python cryptography X25519/ChaCha20Poly1305 + stdlib hmac/hashlib; method_crypto_reference.py",
    "rfc9180": rfc,
    "keybay": {name: value.hex() for name, value in {
        "material": material,
        "salt": salt,
        "context": context,
        "hpkeContext": hpke_context,
        "ephemeralSeed": seed,
        "storeKey": store_key,
        "privateKey": private_key,
        "publicKey": pk,
        "envelope": envelope,
    }.items()},
}, indent=2))

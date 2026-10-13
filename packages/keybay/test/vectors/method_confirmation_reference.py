#!/usr/bin/env python3
"""Independent stdlib-only reference for policy-3 method confirmations.

Computes the credential-derived confirmation MAC and the vault-secret subkey
and AAD from the RFC 0003 text, without Keybay code. The vault-secret AEAD is
the store's XChaCha20-Poly1305 primitive, already pinned by other vectors; the
Dart test applies it to the subkey and AAD fixed here.
"""

import hashlib
import hmac
import json
import struct


def hkdf(ikm: bytes, salt: bytes, info: bytes, length: int = 32) -> bytes:
    prk = hmac.new(salt, ikm, hashlib.sha256).digest()
    out, block, counter = b"", b"", 1
    while len(out) < length:
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha256).digest()
        out += block
        counter += 1
    return out[:length]


def lp(*fields: bytes) -> bytes:
    return b"".join(struct.pack(">I", len(field)) + field for field in fields)


def sequence(start: int, length: int) -> bytes:
    return bytes((start + index) & 0xFF for index in range(length))


def confirmation_case(kind: int, record_id: str) -> dict:
    material = sequence(0x01, 32)
    salt = sequence(0x21, 16)
    store_id = sequence(0x31, 16)
    method_id = sequence(0x41, 16)
    public_key = sequence(0x51, 32)
    vault_secret = sequence(0x71, 32)
    context = lp(
        b"keybay:v2:methods:1",
        store_id,
        method_id,
        bytes([kind]),
        salt,
        record_id.encode("ascii"),
    )
    key = hkdf(material, salt, b"keybay:v2:methods2:key:confirm\x00" + context)
    tag = hmac.new(
        key,
        b"keybay:v2:methods2:confirm\x00" + lp(context, public_key, vault_secret),
        hashlib.sha256,
    ).digest()
    return {
        "material": material.hex(),
        "salt": salt.hex(),
        "context": context.hex(),
        "publicKey": public_key.hex(),
        "vaultSecret": vault_secret.hex(),
        "confirmation": tag.hex(),
    }


def vault_secret_case() -> dict:
    store_key = sequence(0x81, 32)
    store_id = sequence(0x31, 16)
    epoch = 7
    return {
        "storeKey": store_key.hex(),
        "storeId": store_id.hex(),
        "epoch": epoch,
        "vaultSecret": sequence(0x71, 32).hex(),
        "nonce": sequence(0x91, 24).hex(),
        "subkey": hkdf(store_key, store_id, b"keybay:v2:methods2:key:vault-secret").hex(),
        "aad": (
            b"keybay:v2:methods2:aad:vault-secret\x00"
            + lp(store_id, struct.pack(">Q", epoch))
        ).hex(),
    }


if __name__ == "__main__":
    print(
        json.dumps(
            {
                "passphraseConfirmation": confirmation_case(1, ""),
                "hardwarePasskeyConfirmation": confirmation_case(
                    3, "Zm9yLXRlc3Qtb25seQ"
                ),
                "vaultSecret": vault_secret_case(),
            },
            indent=2,
        )
    )

// Command v2_suite1_reference independently reproduces the cryptographic
// outputs in packages/keybay/test/vectors/v2_suite1.json.
//
// Run it from this directory with `go run .`. This is retained format evidence,
// not a Keybay build dependency or fixture generator.
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"

	"golang.org/x/crypto/chacha20poly1305"
)

func sequence(start, length int) []byte {
	result := make([]byte, length)
	for i := range result {
		result[i] = byte(start + i)
	}
	return result
}

func uint32Bytes(value int) []byte {
	result := make([]byte, 4)
	binary.BigEndian.PutUint32(result, uint32(value))
	return result
}

func uint64Bytes(value int) []byte {
	result := make([]byte, 8)
	binary.BigEndian.PutUint64(result, uint64(value))
	return result
}

func aad(label string, fields ...[]byte) []byte {
	result := append([]byte(label), 0)
	for _, field := range fields {
		result = append(result, uint32Bytes(len(field))...)
		result = append(result, field...)
	}
	return result
}

func hkdf32(inputKey, salt []byte, info string) []byte {
	extract := hmac.New(sha256.New, salt)
	_, _ = extract.Write(inputKey)
	pseudorandomKey := extract.Sum(nil)
	expand := hmac.New(sha256.New, pseudorandomKey)
	_, _ = expand.Write([]byte(info))
	_, _ = expand.Write([]byte{1})
	return expand.Sum(nil)
}

func seal(key, nonce, plaintext, additionalData []byte) []byte {
	aead, err := chacha20poly1305.NewX(key)
	if err != nil {
		panic(err)
	}
	return append(append([]byte{}, nonce...), aead.Seal(nil, nonce, plaintext, additionalData)...)
}

func show(name string, value []byte) {
	fmt.Printf("%s=%s\n", name, hex.EncodeToString(value))
}

func main() {
	storageDomain := sequence(0, 32)
	bootstrapCore := append([]byte{'K', 'B', 'V', '2', 0, 1}, uint32Bytes(4)...)
	bootstrapCore = append(bootstrapCore, 0xde, 0xad, 0xbe, 0xef)
	sealedPackage := sequence(0xc0, 48)
	bootstrap := append(append([]byte{}, bootstrapCore...), uint32Bytes(len(sealedPackage))...)
	storeID := sequence(0x10, 16)
	storeKey := sequence(0x20, 32)
	methodID := sequence(0x40, 16)
	salt := sequence(0x50, 16)
	passphraseKey := sequence(0x60, 32)
	recordNonce := sequence(0x80, 24)
	manifestNonce := sequence(0x98, 24)
	passphraseNonce := sequence(0xb0, 24)

	packageAAD := aad("keybay:v2:s1:aad:platform-package", storageDomain, bootstrapCore)
	manifestAAD := aad("keybay:v2:s1:aad:manifest", storageDomain, bootstrap, sealedPackage)
	passphraseAAD := aad("keybay:v2:s1:aad:passphrase-envelope", storeID, uint64Bytes(7), methodID, []byte{1}, salt)
	recordAAD := aad("keybay:v2:s1:aad:record-frame", storeID, uint64Bytes(7), []byte{1}, []byte("service/token"))
	manifestKey := hkdf32(storeKey, storeID, "keybay:v2:s1:key:manifest")
	recordFrameKey := hkdf32(storeKey, storeID, "keybay:v2:s1:key:record-frame")
	recordFrame := seal(recordFrameKey, recordNonce, []byte("correct horse"), recordAAD)
	recordDigest := sha256.Sum256(recordFrame)
	manifest := append([]byte{}, uint32Bytes(1)...)
	manifest = append(manifest, uint32Bytes(len("service/token"))...)
	manifest = append(manifest, []byte("service/token")...)
	manifest = append(manifest, uint32Bytes(len(recordFrame))...)
	manifest = append(manifest, recordDigest[:]...)
	sealedManifest := seal(manifestKey, manifestNonce, manifest, manifestAAD)
	passphraseEnvelope := seal(passphraseKey, passphraseNonce, storeKey, passphraseAAD)

	show("package_aad", packageAAD)
	show("manifest_aad", manifestAAD)
	show("passphrase_aad", passphraseAAD)
	show("record_aad", recordAAD)
	show("manifest_key", manifestKey)
	show("record_frame_key", recordFrameKey)
	show("record_frame", recordFrame)
	show("record_digest", recordDigest[:])
	show("manifest_plaintext", manifest)
	show("sealed_manifest", sealedManifest)
	show("passphrase_envelope", passphraseEnvelope)
}

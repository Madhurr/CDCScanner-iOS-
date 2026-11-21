// Package jose decrypts the JWE payloads produced by the iOS SDK.
package jose

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	gojose "github.com/go-jose/go-jose/v4"
)

// PayloadType is the `typ` the SDK puts in the protected header.
const PayloadType = "cdc-card+json"

// Key is the relay's P-256 key agreement key. In an enclave it is generated at
// boot and never leaves; its public half is published in the attestation document.
type Key struct {
	Private *ecdsa.PrivateKey
	KID     string
}

// Generate makes a fresh P-256 key.
func Generate(kid string) (*Key, error) {
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	return &Key{Private: priv, KID: kid}, nil
}

// PublicJWK returns the public key as JWK JSON.
func (k *Key) PublicJWK() ([]byte, error) {
	jwk := gojose.JSONWebKey{Key: &k.Private.PublicKey, KeyID: k.KID, Algorithm: string(gojose.ECDH_ES_A256KW), Use: "enc"}
	return jwk.MarshalJSON()
}

// Header is what the relay learns from the protected header before decrypting.
type Header struct {
	Type  string
	IAT   time.Time
	Nonce string
}

var (
	ErrAlgorithm = errors.New("unsupported JWE algorithm")
	ErrHeader    = errors.New("missing or invalid protected header")
)

// Decrypt opens a JWE (general or flattened JSON, or compact) addressed to this
// key and returns the plaintext together with the authenticated header claims.
func (k *Key) Decrypt(raw []byte) (plaintext []byte, hdr Header, err error) {
	keyAlgs := []gojose.KeyAlgorithm{gojose.ECDH_ES_A256KW}
	encs := []gojose.ContentEncryption{gojose.A256GCM}
	var obj *gojose.JSONWebEncryption
	if len(raw) > 0 && raw[0] == '{' {
		obj, err = gojose.ParseEncryptedJSON(string(raw), keyAlgs, encs)
	} else {
		obj, err = gojose.ParseEncryptedCompact(string(raw), keyAlgs, encs)
	}
	if err != nil {
		return nil, hdr, fmt.Errorf("%w: %v", ErrAlgorithm, err)
	}
	plaintext, err = obj.Decrypt(k.Private)
	if err != nil {
		return nil, hdr, err
	}
	// Read claims from the *protected* header only: it is the AES-GCM additional authenticated
	// data, so a successful decrypt proves it was not altered. Shared unprotected headers are
	// deliberately ignored.
	protectedB64, err := protectedSegment(raw)
	if err != nil {
		return nil, hdr, ErrHeader
	}
	protectedJSON, err := base64.RawURLEncoding.DecodeString(protectedB64)
	if err != nil {
		return nil, hdr, ErrHeader
	}
	var claims struct {
		Typ   string `json:"typ"`
		IAT   string `json:"iat"`
		Nonce string `json:"nonce"`
	}
	if err := json.Unmarshal(protectedJSON, &claims); err != nil {
		return nil, hdr, ErrHeader
	}
	var iat int64
	if _, err := fmt.Sscanf(claims.IAT, "%d", &iat); err != nil || claims.Typ != PayloadType || len(claims.Nonce) < 16 {
		return nil, hdr, ErrHeader
	}
	return plaintext, Header{Type: claims.Typ, IAT: time.Unix(iat, 0), Nonce: claims.Nonce}, nil
}

// protectedSegment extracts the base64url protected header from JSON or compact serialisation.
func protectedSegment(raw []byte) (string, error) {
	if len(raw) > 0 && raw[0] == '{' {
		var envelope struct {
			Protected string `json:"protected"`
		}
		if err := json.Unmarshal(raw, &envelope); err != nil || envelope.Protected == "" {
			return "", ErrHeader
		}
		return envelope.Protected, nil
	}
	parts := strings.Split(string(raw), ".")
	if len(parts) != 5 {
		return "", ErrHeader
	}
	return parts[0], nil
}

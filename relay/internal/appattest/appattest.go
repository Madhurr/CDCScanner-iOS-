// Package appattest verifies Apple App Attest attestation objects and assertions.
//
// Steps follow Apple's "Validating apps that connect to your server". The relay uses it to
// accept tokenisation requests only from genuine, unmodified builds of the merchant app.
package appattest

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"encoding/pem"
	"errors"
	"sync"
	"time"

	"github.com/fxamacker/cbor/v2"
)

// AppleRootPEM is the Apple App Attestation Root CA, from
// https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
// (SHA-256 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32).
const AppleRootPEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`

var nonceExtensionOID = asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 8, 2}

var (
	ErrFormat      = errors.New("app attest: malformed object")
	ErrChain       = errors.New("app attest: certificate chain not trusted")
	ErrNonce       = errors.New("app attest: nonce mismatch")
	ErrKeyID       = errors.New("app attest: key id mismatch")
	ErrAppID       = errors.New("app attest: app id mismatch")
	ErrCounter     = errors.New("app attest: counter did not increase")
	ErrEnvironment = errors.New("app attest: wrong environment (development vs production)")
	ErrUnknownKey  = errors.New("app attest: unknown key id")
	ErrSignature   = errors.New("app attest: bad signature")
)

// KeyStore persists attested keys. The in-memory implementation is for a single instance.
type KeyStore interface {
	Get(keyID string) (pub *ecdsa.PublicKey, counter uint32, ok bool)
	Put(keyID string, pub *ecdsa.PublicKey, counter uint32)
}

type MemoryKeyStore struct {
	mu   sync.Mutex
	keys map[string]entry
}
type entry struct {
	pub     *ecdsa.PublicKey
	counter uint32
}

func NewMemoryKeyStore() *MemoryKeyStore { return &MemoryKeyStore{keys: map[string]entry{}} }
func (m *MemoryKeyStore) Get(id string) (*ecdsa.PublicKey, uint32, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.keys[id]
	return e.pub, e.counter, ok
}
func (m *MemoryKeyStore) Put(id string, pub *ecdsa.PublicKey, counter uint32) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.keys[id] = entry{pub, counter}
}

// Verifier checks attestations and assertions for one app.
type Verifier struct {
	// AppID is "TEAMID.bundle.identifier".
	AppID string
	// Production selects the "appattest" aaguid; otherwise "appattestdevelop".
	Production bool
	Roots      *x509.CertPool
	Keys       KeyStore
	Now        func() time.Time
}

// New returns a verifier trusting Apple's root.
func New(appID string, production bool, keys KeyStore) *Verifier {
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM([]byte(AppleRootPEM))
	return &Verifier{AppID: appID, Production: production, Roots: roots, Keys: keys, Now: time.Now}
}

type attestationObject struct {
	Format  string `cbor:"fmt"`
	AttStmt struct {
		X5C     [][]byte `cbor:"x5c"`
		Receipt []byte   `cbor:"receipt"`
	} `cbor:"attStmt"`
	AuthData []byte `cbor:"authData"`
}

type assertionObject struct {
	Signature         []byte `cbor:"signature"`
	AuthenticatorData []byte `cbor:"authenticatorData"`
}

// VerifyAttestation validates a first-use attestation object and stores the key.
// clientDataHash is SHA-256 of the challenge or request body the client used.
func (v *Verifier) VerifyAttestation(attestationB64, keyID string, clientDataHash []byte) error {
	raw, err := base64.StdEncoding.DecodeString(attestationB64)
	if err != nil {
		return ErrFormat
	}
	var obj attestationObject
	if err := cbor.Unmarshal(raw, &obj); err != nil || obj.Format != "apple-appattest" || len(obj.AttStmt.X5C) < 2 {
		return ErrFormat
	}
	credCert, err := x509.ParseCertificate(obj.AttStmt.X5C[0])
	if err != nil {
		return ErrFormat
	}
	inters := x509.NewCertPool()
	for _, der := range obj.AttStmt.X5C[1:] {
		c, err := x509.ParseCertificate(der)
		if err != nil {
			return ErrFormat
		}
		inters.AddCert(c)
	}
	if _, err := credCert.Verify(x509.VerifyOptions{Roots: v.Roots, Intermediates: inters, CurrentTime: v.Now(), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}); err != nil {
		return ErrChain
	}

	// Step 2-4: nonce = SHA256(authData || clientDataHash) must equal the certificate extension value.
	expected := sha256.Sum256(append(append([]byte{}, obj.AuthData...), clientDataHash...))
	var found []byte
	for _, ext := range credCert.Extensions {
		if ext.Id.Equal(nonceExtensionOID) {
			var wrapper struct {
				Nonce []byte `asn1:"tag:1,explicit"`
			}
			if _, err := asn1.Unmarshal(ext.Value, &wrapper); err != nil {
				return ErrFormat
			}
			found = wrapper.Nonce
		}
	}
	if !bytes.Equal(found, expected[:]) {
		return ErrNonce
	}

	// Step 5: key identifier is SHA256 of the uncompressed public key.
	pub, ok := credCert.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return ErrFormat
	}
	pubBytes := uncompressedPoint(pub)
	keyHash := sha256.Sum256(pubBytes)
	if base64.StdEncoding.EncodeToString(keyHash[:]) != keyID {
		return ErrKeyID
	}

	// Steps 6-9: authData layout = rpIdHash(32) flags(1) counter(4) aaguid(16) credIdLen(2) credId.
	if len(obj.AuthData) < 32+1+4+16+2 {
		return ErrFormat
	}
	appHash := sha256.Sum256([]byte(v.AppID))
	if !bytes.Equal(obj.AuthData[:32], appHash[:]) {
		return ErrAppID
	}
	if binary.BigEndian.Uint32(obj.AuthData[33:37]) != 0 {
		return ErrCounter
	}
	aaguid := bytes.TrimRight(obj.AuthData[37:53], "\x00")
	want := "appattestdevelop"
	if v.Production {
		want = "appattest"
	}
	if string(aaguid) != want {
		return ErrEnvironment
	}
	credLen := int(binary.BigEndian.Uint16(obj.AuthData[53:55]))
	if len(obj.AuthData) < 55+credLen || !bytes.Equal(obj.AuthData[55:55+credLen], keyHash[:]) {
		return ErrKeyID
	}
	v.Keys.Put(keyID, pub, 0)
	return nil
}

// VerifyAssertion validates a per-request assertion over clientDataHash (SHA-256 of the body).
func (v *Verifier) VerifyAssertion(assertionB64, keyID string, clientDataHash []byte) error {
	pub, counter, ok := v.Keys.Get(keyID)
	if !ok {
		return ErrUnknownKey
	}
	raw, err := base64.StdEncoding.DecodeString(assertionB64)
	if err != nil {
		return ErrFormat
	}
	var obj assertionObject
	if err := cbor.Unmarshal(raw, &obj); err != nil || len(obj.AuthenticatorData) < 37 {
		return ErrFormat
	}
	nonce := sha256.Sum256(append(append([]byte{}, obj.AuthenticatorData...), clientDataHash...))
	if !ecdsa.VerifyASN1(pub, nonce[:], obj.Signature) {
		return ErrSignature
	}
	appHash := sha256.Sum256([]byte(v.AppID))
	if !bytes.Equal(obj.AuthenticatorData[:32], appHash[:]) {
		return ErrAppID
	}
	newCounter := binary.BigEndian.Uint32(obj.AuthenticatorData[33:37])
	if newCounter <= counter {
		return ErrCounter
	}
	v.Keys.Put(keyID, pub, newCounter)
	return nil
}

func uncompressedPoint(pub *ecdsa.PublicKey) []byte {
	size := (pub.Curve.Params().BitSize + 7) / 8
	out := make([]byte, 1+2*size)
	out[0] = 4
	pub.X.FillBytes(out[1 : 1+size])
	pub.Y.FillBytes(out[1+size:])
	return out
}

// ParsePEMCertificate is a small helper for tests and tooling.
func ParsePEMCertificate(p []byte) (*x509.Certificate, error) {
	block, _ := pem.Decode(p)
	if block == nil {
		return nil, ErrFormat
	}
	return x509.ParseCertificate(block.Bytes)
}

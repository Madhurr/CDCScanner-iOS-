package appattest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"math/big"
	"testing"
	"time"

	"github.com/fxamacker/cbor/v2"
)

// Builds a synthetic Apple-shaped attestation with our own root so the parsing and checks run end to end.
func TestAttestationAndAssertion(t *testing.T) {
	rootKey, _ := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	rootTmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Fake App Attest Root"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	rootDER, _ := x509.CreateCertificate(rand.Reader, rootTmpl, rootTmpl, &rootKey.PublicKey, rootKey)
	root, _ := x509.ParseCertificate(rootDER)
	interKey, _ := ecdsa.GenerateKey(elliptic.P384(), rand.Reader)
	interTmpl := &x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "Fake Intermediate"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	interDER, _ := x509.CreateCertificate(rand.Reader, interTmpl, root, &interKey.PublicKey, rootKey)
	inter, _ := x509.ParseCertificate(interDER)

	deviceKey, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	pubBytes := uncompressedPoint(&deviceKey.PublicKey)
	keyHash := sha256.Sum256(pubBytes)
	keyID := base64.StdEncoding.EncodeToString(keyHash[:])
	appID := "ABCDE12345.com.example.checkout"
	appHash := sha256.Sum256([]byte(appID))

	authData := append([]byte{}, appHash[:]...)
	authData = append(authData, 0x40)       // flags
	authData = append(authData, 0, 0, 0, 0) // counter 0
	aaguid := make([]byte, 16)
	copy(aaguid, "appattestdevelop")
	authData = append(authData, aaguid...)
	authData = append(authData, 0, 32)
	authData = append(authData, keyHash[:]...)

	clientData := sha256.Sum256([]byte("challenge"))
	nonce := sha256.Sum256(append(append([]byte{}, authData...), clientData[:]...))
	extValue, _ := asn1.Marshal(struct {
		Nonce []byte `asn1:"tag:1,explicit"`
	}{Nonce: nonce[:]})
	credTmpl := &x509.Certificate{SerialNumber: big.NewInt(3), Subject: pkix.Name{CommonName: keyID}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour),
		ExtraExtensions: []pkix.Extension{{Id: nonceExtensionOID, Value: extValue}}, KeyUsage: x509.KeyUsageDigitalSignature}
	credDER, _ := x509.CreateCertificate(rand.Reader, credTmpl, inter, &deviceKey.PublicKey, interKey)

	var obj attestationObject
	obj.Format = "apple-appattest"
	obj.AttStmt.X5C = [][]byte{credDER, interDER}
	obj.AuthData = authData
	raw, _ := cbor.Marshal(obj)

	roots := x509.NewCertPool()
	roots.AddCert(root)
	v := &Verifier{AppID: appID, Production: false, Roots: roots, Keys: NewMemoryKeyStore(), Now: time.Now}
	if err := v.VerifyAttestation(base64.StdEncoding.EncodeToString(raw), keyID, clientData[:]); err != nil {
		t.Fatalf("attestation: %v", err)
	}
	if err := v.VerifyAttestation(base64.StdEncoding.EncodeToString(raw), keyID, []byte("wrong")); err != ErrNonce {
		t.Fatalf("expected nonce mismatch, got %v", err)
	}
	v.Production = true
	if err := v.VerifyAttestation(base64.StdEncoding.EncodeToString(raw), keyID, clientData[:]); err != ErrEnvironment {
		t.Fatalf("expected environment error, got %v", err)
	}
	v.Production = false

	// Assertion over a body hash with counter 1.
	body := sha256.Sum256([]byte(`{"jwe":"..."}`))
	assertAuth := append([]byte{}, appHash[:]...)
	assertAuth = append(assertAuth, 0x40, 0, 0, 0, 1)
	assertNonce := sha256.Sum256(append(append([]byte{}, assertAuth...), body[:]...))
	sig, _ := ecdsa.SignASN1(rand.Reader, deviceKey, assertNonce[:])
	assertion, _ := cbor.Marshal(assertionObject{Signature: sig, AuthenticatorData: assertAuth})
	if err := v.VerifyAssertion(base64.StdEncoding.EncodeToString(assertion), keyID, body[:]); err != nil {
		t.Fatalf("assertion: %v", err)
	}
	// Replaying the same assertion must fail on the counter.
	if err := v.VerifyAssertion(base64.StdEncoding.EncodeToString(assertion), keyID, body[:]); err != ErrCounter {
		t.Fatalf("expected counter error, got %v", err)
	}
	if err := v.VerifyAssertion(base64.StdEncoding.EncodeToString(assertion), "unknown", body[:]); err != ErrUnknownKey {
		t.Fatalf("expected unknown key, got %v", err)
	}
	_ = binary.BigEndian
}

func TestAppleRootParses(t *testing.T) {
	cert, err := ParsePEMCertificate([]byte(AppleRootPEM))
	if err != nil || cert.Subject.CommonName != "Apple App Attestation Root CA" {
		t.Fatalf("apple root: %v %v", err, cert)
	}
}

func TestCounterAdvancesOnceAndSurvivesRegistration(t *testing.T) {
	store := NewMemoryKeyStore()
	store.Register("test", nil)
	results := make(chan bool, 16)
	for i := 0; i < cap(results); i++ {
		go func() { results <- store.Advance("test", 1) }()
	}
	accepted := 0
	for i := 0; i < cap(results); i++ {
		if <-results {
			accepted++
		}
	}
	store.Register("test", nil)
	if accepted != 1 || store.Advance("test", 1) {
		t.Fatal("counter must advance once")
	}
}

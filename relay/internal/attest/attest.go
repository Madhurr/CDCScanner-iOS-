// Package attest produces and verifies AWS Nitro Enclaves style attestation documents.
//
// Two providers exist: Dev, which signs documents with a self-made P-384 chain so the whole
// system can be exercised outside AWS, and Nitro (build tag `nitro`), which asks the Nitro
// Secure Module through /dev/nsm. Clients pin the root and the PCRs they expect.
package attest

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha512"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/fxamacker/cbor/v2"
)

// Document is the CBOR payload of a Nitro attestation document.
type Document struct {
	ModuleID    string          `cbor:"module_id"`
	Digest      string          `cbor:"digest"`
	Timestamp   uint64          `cbor:"timestamp"`
	PCRs        map[uint][]byte `cbor:"pcrs"`
	Certificate []byte          `cbor:"certificate"`
	CABundle    [][]byte        `cbor:"cabundle"`
	PublicKey   []byte          `cbor:"public_key,omitempty"`
	UserData    []byte          `cbor:"user_data,omitempty"`
	Nonce       []byte          `cbor:"nonce,omitempty"`
}

// Provider returns a signed attestation document binding nonce, userData and publicKey.
type Provider interface {
	Attest(nonce, userData, publicKey []byte) ([]byte, error)
	// RootPEM is the root clients must pin, or nil when it is the AWS root.
	RootPEM() []byte
	// PCRs reports the measurements clients should pin for this build, when known.
	PCRs() map[uint][]byte
}

const coseES384 = -35

var encMode, _ = cbor.CoreDetEncOptions().EncMode()

// Dev signs documents with an in-process P-384 chain: root -> intermediate -> leaf.
type Dev struct {
	ModuleID string
	root     *x509.Certificate
	rootPEM  []byte
	inter    *x509.Certificate
	leaf     *x509.Certificate
	leafKey  *ecdsa.PrivateKey
	pcrs     map[uint][]byte
}

// NewDev builds a development provider whose PCR0 is derived from imageID.
func NewDev(moduleID, imageID string) (*Dev, error) {
	now := time.Now()
	newKey := func() (*ecdsa.PrivateKey, error) { return ecdsa.GenerateKey(elliptic.P384(), rand.Reader) }
	rootKey, err := newKey()
	if err != nil {
		return nil, err
	}
	interKey, err := newKey()
	if err != nil {
		return nil, err
	}
	leafKey, err := newKey()
	if err != nil {
		return nil, err
	}
	mk := func(serial int64, cn string, pub *ecdsa.PublicKey, parent *x509.Certificate, parentKey *ecdsa.PrivateKey, ca bool, ttl time.Duration) (*x509.Certificate, error) {
		tmpl := &x509.Certificate{
			SerialNumber:          big.NewInt(serial),
			Subject:               pkix.Name{Country: []string{"US"}, Organization: []string{"Dev"}, OrganizationalUnit: []string{"CDC"}, CommonName: cn},
			NotBefore:             now.Add(-time.Hour),
			NotAfter:              now.Add(ttl),
			BasicConstraintsValid: true,
			IsCA:                  ca,
			SignatureAlgorithm:    x509.ECDSAWithSHA384,
		}
		if ca {
			tmpl.KeyUsage = x509.KeyUsageCertSign | x509.KeyUsageCRLSign
		} else {
			tmpl.KeyUsage = x509.KeyUsageDigitalSignature
		}
		if parent == nil {
			parent = tmpl
		}
		der, err := x509.CreateCertificate(rand.Reader, tmpl, parent, pub, parentKey)
		if err != nil {
			return nil, err
		}
		return x509.ParseCertificate(der)
	}
	root, err := mk(1, "dev.nitro-enclaves", &rootKey.PublicKey, nil, rootKey, true, 30*365*24*time.Hour)
	if err != nil {
		return nil, err
	}
	inter, err := mk(2, "dev-intermediate", &interKey.PublicKey, root, rootKey, true, 365*24*time.Hour)
	if err != nil {
		return nil, err
	}
	leaf, err := mk(3, moduleID, &leafKey.PublicKey, inter, interKey, false, 24*time.Hour)
	if err != nil {
		return nil, err
	}
	zero := make([]byte, 48)
	pcr := func(label string) []byte { s := sha512.Sum384([]byte(label)); return s[:] }
	return &Dev{
		ModuleID: moduleID,
		root:     root,
		rootPEM:  pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: root.Raw}),
		inter:    inter,
		leaf:     leaf,
		leafKey:  leafKey,
		pcrs:     map[uint][]byte{0: pcr("cdc-relay-image:" + imageID), 1: pcr("cdc-relay-kernel"), 2: pcr("cdc-relay-app:" + imageID), 3: zero, 4: zero, 8: zero},
	}, nil
}

func (d *Dev) RootPEM() []byte                    { return d.rootPEM }
func (d *Dev) PCRs() map[uint][]byte              { return d.pcrs }
func (d *Dev) RootCertificate() *x509.Certificate { return d.root }

// Attest signs a document exactly as the NSM would: COSE_Sign1, tag 18, ES384, raw r||s signature.
func (d *Dev) Attest(nonce, userData, publicKey []byte) ([]byte, error) {
	doc := Document{
		ModuleID:    d.ModuleID,
		Digest:      "SHA384",
		Timestamp:   uint64(time.Now().UnixMilli()),
		PCRs:        d.pcrs,
		Certificate: d.leaf.Raw,
		CABundle:    [][]byte{d.root.Raw, d.inter.Raw},
		PublicKey:   publicKey,
		UserData:    userData,
		Nonce:       nonce,
	}
	payload, err := encMode.Marshal(doc)
	if err != nil {
		return nil, err
	}
	return SignCOSE(payload, d.leafKey)
}

// SignCOSE wraps payload in a COSE_Sign1 signed with an ES384 key.
func SignCOSE(payload []byte, key *ecdsa.PrivateKey) ([]byte, error) {
	protected, err := encMode.Marshal(map[int]int{1: coseES384})
	if err != nil {
		return nil, err
	}
	sigStructure, err := encMode.Marshal([]any{"Signature1", protected, []byte{}, payload})
	if err != nil {
		return nil, err
	}
	digest := sha512.Sum384(sigStructure)
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		return nil, err
	}
	sig := make([]byte, 96)
	r.FillBytes(sig[:48])
	s.FillBytes(sig[48:])
	return encMode.Marshal(cbor.Tag{Number: 18, Content: []any{protected, map[int]int{}, payload, sig}})
}

// Verify checks a document against a root pool and returns its payload. It mirrors the checks
// the iOS SDK performs so a relay can validate peer enclaves too.
func Verify(raw []byte, roots *x509.CertPool, now time.Time) (*Document, error) {
	var tagged cbor.RawTag
	if err := cbor.Unmarshal(raw, &tagged); err == nil && tagged.Number == 18 {
		raw = tagged.Content
	}
	var env []cbor.RawMessage
	if err := cbor.Unmarshal(raw, &env); err != nil || len(env) != 4 {
		return nil, errors.New("not a COSE_Sign1")
	}
	var protectedBytes, payload, sig []byte
	if err := cbor.Unmarshal(env[0], &protectedBytes); err != nil {
		return nil, err
	}
	if err := cbor.Unmarshal(env[2], &payload); err != nil {
		return nil, err
	}
	if err := cbor.Unmarshal(env[3], &sig); err != nil {
		return nil, err
	}
	var protected map[int]int
	if err := cbor.Unmarshal(protectedBytes, &protected); err != nil || protected[1] != coseES384 {
		return nil, errors.New("unsupported COSE algorithm")
	}
	var doc Document
	if err := cbor.Unmarshal(payload, &doc); err != nil {
		return nil, fmt.Errorf("payload: %w", err)
	}
	if doc.Digest != "SHA384" || len(doc.CABundle) == 0 {
		return nil, errors.New("malformed document")
	}
	leaf, err := x509.ParseCertificate(doc.Certificate)
	if err != nil {
		return nil, err
	}
	inters := x509.NewCertPool()
	for _, der := range doc.CABundle[1:] {
		c, err := x509.ParseCertificate(der)
		if err != nil {
			return nil, err
		}
		inters.AddCert(c)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{Roots: roots, Intermediates: inters, CurrentTime: now, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}); err != nil {
		return nil, fmt.Errorf("chain: %w", err)
	}
	pub, ok := leaf.PublicKey.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P384() || len(sig) != 96 {
		return nil, errors.New("leaf key must be P-384")
	}
	sigStructure, err := encMode.Marshal([]any{"Signature1", protectedBytes, []byte{}, payload})
	if err != nil {
		return nil, err
	}
	digest := sha512.Sum384(sigStructure)
	if !ecdsa.Verify(pub, digest[:], new(big.Int).SetBytes(sig[:48]), new(big.Int).SetBytes(sig[48:])) {
		return nil, errors.New("bad signature")
	}
	return &doc, nil
}

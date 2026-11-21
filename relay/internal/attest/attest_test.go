package attest

import (
	"bytes"
	"crypto/x509"
	"testing"
	"time"
)

func TestDevDocumentVerifies(t *testing.T) {
	dev, err := NewDev("i-dev-enc0", "test")
	if err != nil {
		t.Fatal(err)
	}
	nonce := []byte("nonce-1")
	doc, err := dev.Attest(nonce, []byte("cdc-relay/test"), []byte(`{"kty":"EC"}`))
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(dev.RootCertificate())
	parsed, err := Verify(doc, roots, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if parsed.ModuleID != "i-dev-enc0" || !bytes.Equal(parsed.Nonce, nonce) || !bytes.Equal(parsed.PCRs[0], dev.PCRs()[0]) {
		t.Fatalf("unexpected document %+v", parsed)
	}
	// A different root must fail.
	other, _ := NewDev("x", "y")
	otherRoots := x509.NewCertPool()
	otherRoots.AddCert(other.RootCertificate())
	if _, err := Verify(doc, otherRoots, time.Now()); err == nil {
		t.Fatal("expected chain failure with foreign root")
	}
	// Tampering must fail.
	bad := append([]byte(nil), doc...)
	bad[len(bad)-20] ^= 1
	if _, err := Verify(bad, roots, time.Now()); err == nil {
		t.Fatal("expected signature failure")
	}
}

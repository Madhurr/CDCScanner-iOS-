package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	gojose "github.com/go-jose/go-jose/v4"

	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/attest"
	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/jose"
)

func testServer(t *testing.T) *server {
	t.Helper()
	s, err := newServer(func(k, d string) string { return d })
	if err != nil {
		t.Fatal(err)
	}
	s.now = func() time.Time { return time.Date(2027, 1, 15, 12, 0, 0, 0, time.UTC) }
	return s
}

// The iOS SDK encrypted this payload (see Tests/CDCSecureFieldsTests/RelayFixtureExportTests.swift)
// to the key in testdata/relay_key.json. The relay must open it with no shared code.
func TestDecryptsPayloadFromSwiftSDK(t *testing.T) {
	keyJSON, err := os.ReadFile("../../testdata/relay_key.json")
	if err != nil {
		t.Skip("fixture missing")
	}
	var jwk gojose.JSONWebKey
	if err := jwk.UnmarshalJSON(keyJSON); err != nil {
		t.Fatal(err)
	}
	key := &jose.Key{Private: jwk.Key.(*ecdsa.PrivateKey), KID: "enclave"}
	body, err := os.ReadFile("../../testdata/swift_jwe.json")
	if err != nil {
		t.Skip("fixture missing")
	}
	plaintext, hdr, err := key.Decrypt(body)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if hdr.Type != jose.PayloadType || hdr.IAT.Unix() != 1_800_000_000 || len(hdr.Nonce) != 32 {
		t.Fatalf("header %+v", hdr)
	}
	var p map[string]string
	if err := json.Unmarshal(plaintext, &p); err != nil {
		t.Fatal(err)
	}
	if p["number"] != "4111111111111111" || p["exp_month"] != "09" || p["exp_year"] != "2027" || p["cvc"] != "123" || p["name"] != "Jane Doe" {
		t.Fatalf("payload %v", p)
	}
	if bytes.Contains(body, []byte("4111")) {
		t.Fatal("ciphertext leaks PAN")
	}
}

func TestAttestationEndpointAndTokenizeFlow(t *testing.T) {
	s := testServer(t)
	ts := httptest.NewServer(s.routes())
	defer ts.Close()

	// 1. Fetch and verify the attestation document with the dev root, like the phone does.
	nonce := bytes.Repeat([]byte{7}, 32)
	res, err := http.Get(ts.URL + "/v1/attestation?nonce=" + hex.EncodeToString(nonce))
	if err != nil || res.StatusCode != 200 {
		t.Fatalf("attestation: %v %v", err, res.Status)
	}
	var docBuf bytes.Buffer
	docBuf.ReadFrom(res.Body)
	roots := x509.NewCertPool()
	roots.AddCert(s.attester.(*attest.Dev).RootCertificate())
	doc, err := attest.Verify(docBuf.Bytes(), roots, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(doc.Nonce, nonce) || !bytes.Equal(doc.UserData, []byte("cdc-relay/dev")) {
		t.Fatalf("document %+v", doc)
	}
	var pub gojose.JSONWebKey
	if err := pub.UnmarshalJSON(doc.PublicKey); err != nil {
		t.Fatal(err)
	}

	// 2. Encrypt a card to the attested key, as the SDK does.
	encrypter, err := gojose.NewMultiEncrypter(gojose.A256GCM, []gojose.Recipient{{Algorithm: gojose.ECDH_ES_A256KW, Key: pub.Key, KeyID: "enclave"}},
		&gojose.EncrypterOptions{ExtraHeaders: map[gojose.HeaderKey]any{"typ": jose.PayloadType, "iat": "1800000000", "nonce": strings.Repeat("ab", 16)}})
	if err != nil {
		t.Fatal(err)
	}
	s.now = func() time.Time { return time.Unix(1_800_000_000, 0) }
	obj, err := encrypter.Encrypt([]byte(`{"number":"4111111111111111","exp_month":"09","exp_year":"2027","cvc":"123"}`))
	if err != nil {
		t.Fatal(err)
	}
	body := obj.FullSerialize()

	post := func() *http.Response {
		r, err := http.Post(ts.URL+"/v1/tokenize", "application/jose+json", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	r := post()
	if r.StatusCode != 200 {
		t.Fatalf("tokenize: %s", r.Status)
	}
	var out map[string]any
	json.NewDecoder(r.Body).Decode(&out)
	if !strings.HasPrefix(out["token"].(string), "tok_dev_") || out["brand"] != "visa" || out["last4"] != "1111" || out["bin"] != "411111" {
		t.Fatalf("response %v", out)
	}
	// 3. Replay is refused.
	if r := post(); r.StatusCode != http.StatusConflict {
		t.Fatalf("expected replay rejection, got %s", r.Status)
	}
	// 4. Stale payload is refused.
	s.now = func() time.Time { return time.Unix(1_800_000_000+3600, 0) }
	obj2, _ := encrypter.Encrypt([]byte(`{"number":"4111111111111111","exp_month":"09","exp_year":"2027"}`))
	r2, _ := http.Post(ts.URL+"/v1/tokenize", "application/jose+json", strings.NewReader(obj2.FullSerialize()))
	if r2.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected expired, got %s", r2.Status)
	}
	// 5. Garbage is refused without leaking why.
	r3, _ := http.Post(ts.URL+"/v1/tokenize", "application/jose+json", strings.NewReader(`{"protected":"x"}`))
	if r3.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected 400, got %s", r3.Status)
	}
	_ = sha256.Sum256
}

func TestAppAttestRequiredRejectsMissingHeaders(t *testing.T) {
	s, err := newServer(func(k, d string) string {
		switch k {
		case "APP_ATTEST":
			return "required"
		case "APP_ATTEST_APP_ID":
			return "TEAM.com.example"
		}
		return d
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(s.routes())
	defer ts.Close()
	r, _ := http.Post(ts.URL+"/v1/tokenize", "application/jose+json", strings.NewReader(`{}`))
	if r.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %s", r.Status)
	}
}

func TestRejectsInvalidSettings(t *testing.T) {
	for _, settings := range []map[string]string{
		{"RELAY_MODE": "mistyped"},
		{"RELAY_PSP": "mistyped"},
		{"APP_ATTEST": "mistyped"},
		{"APP_ATTEST": "required", "APP_ATTEST_APP_ID": "TEST.app", "APP_ATTEST_ENV": "mistyped"},
		{"RELAY_MODE": "nitro", "APP_ATTEST": "off"},
	} {
		_, err := newServer(func(k, fallback string) string {
			if value, ok := settings[k]; ok {
				return value
			}
			return fallback
		})
		if err == nil {
			t.Fatal("invalid settings accepted", settings)
		}
	}
}

// Command relay is the reference zero-trust tokenisation relay for CDCSecureFields.
//
// It publishes an attestation document that binds its freshly generated P-256 key to the
// enclave's measurements, decrypts JWE payloads from the iOS SDK, optionally requires Apple App
// Attest proof that the request came from a genuine app build, validates the card, forwards it to
// a payment provider and returns only the token. It never logs or stores card data.
//
// Configuration is by environment variable:
//
//	RELAY_ADDR          listen address (default :8080)
//	RELAY_MODE          dev | nitro (default dev)
//	RELAY_VERSION       reported in user_data (default dev)
//	RELAY_PSP           echo | stripe (default echo)
//	STRIPE_SECRET_KEY   for RELAY_PSP=stripe
//	APP_ATTEST          off | required (default off)
//	APP_ATTEST_APP_ID   TEAMID.bundle.id
//	APP_ATTEST_ENV      production | development (default production)
package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/appattest"
	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/attest"
	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/card"
	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/jose"
	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/psp"
	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/store"
)

const (
	maxBody        = 64 << 10
	maxPayloadAge  = 5 * time.Minute
	nonceTTL       = 10 * time.Minute
	challengeTTL   = 5 * time.Minute
	headerKeyID    = "X-App-Attest-Key-Id"
	headerAssert   = "X-App-Attest-Assertion"
	headerAttest   = "X-App-Attest-Attestation"
	headerChalleng = "X-App-Attest-Challenge"
)

type server struct {
	key        *jose.Key
	attester   attest.Provider
	psp        psp.Adapter
	nonces     *store.NonceCache
	challenges *store.NonceCache // reused as a "seen once" set for challenges
	appAttest  *appattest.Verifier
	version    string
	now        func() time.Time
}

func main() {
	env := func(k, d string) string {
		if v := os.Getenv(k); v != "" {
			return v
		}
		return d
	}
	s, err := newServer(env)
	if err != nil {
		log.Fatal(err)
	}
	addr := env("RELAY_ADDR", ":8080")
	log.Printf("cdc-relay %s listening on %s mode=%s psp=%s app_attest=%s", s.version, addr, env("RELAY_MODE", "dev"), s.psp.Name(), env("APP_ATTEST", "off"))
	srv := &http.Server{Addr: addr, Handler: s.routes(), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

func newServer(env func(k, d string) string) (*server, error) {
	key, err := jose.Generate("enclave")
	if err != nil {
		return nil, err
	}
	s := &server{key: key, nonces: store.NewNonceCache(nonceTTL), challenges: store.NewNonceCache(challengeTTL), version: env("RELAY_VERSION", "dev"), now: time.Now}
	switch env("RELAY_MODE", "dev") {
	case "nitro":
		s.attester, err = attest.NewNitro()
	default:
		s.attester, err = attest.NewDev("cdc-relay-dev", s.version)
	}
	if err != nil {
		return nil, err
	}
	switch env("RELAY_PSP", "echo") {
	case "stripe":
		if env("STRIPE_SECRET_KEY", "") == "" {
			return nil, errors.New("STRIPE_SECRET_KEY is required for RELAY_PSP=stripe")
		}
		s.psp = psp.Stripe{SecretKey: env("STRIPE_SECRET_KEY", "")}
	default:
		secret := make([]byte, 32)
		_, _ = rand.Read(secret)
		s.psp = psp.Echo{Secret: secret}
	}
	if env("APP_ATTEST", "off") == "required" {
		appID := env("APP_ATTEST_APP_ID", "")
		if appID == "" {
			return nil, errors.New("APP_ATTEST_APP_ID is required when APP_ATTEST=required")
		}
		s.appAttest = appattest.New(appID, env("APP_ATTEST_ENV", "production") == "production", appattest.NewMemoryKeyStore())
	}
	return s, nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	mux.HandleFunc("GET /v1/attestation", s.handleAttestation)
	mux.HandleFunc("GET /v1/attestation/dev-root", s.handleDevRoot)
	mux.HandleFunc("GET /v1/attestation/pcrs", s.handlePCRs)
	mux.HandleFunc("POST /v1/challenge", s.handleChallenge)
	mux.HandleFunc("POST /v1/tokenize", s.handleTokenize)
	return securityHeaders(mux)
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}

func (s *server) handleAttestation(w http.ResponseWriter, r *http.Request) {
	nonce, err := hex.DecodeString(r.URL.Query().Get("nonce"))
	if err != nil || len(nonce) < 16 || len(nonce) > 512 {
		httpError(w, http.StatusBadRequest, "nonce must be 16..512 bytes of hex")
		return
	}
	pub, err := s.key.PublicJWK()
	if err != nil {
		httpError(w, http.StatusInternalServerError, "key")
		return
	}
	doc, err := s.attester.Attest(nonce, []byte("cdc-relay/"+s.version), pub)
	if err != nil {
		log.Printf("attestation failed: %v", err)
		httpError(w, http.StatusServiceUnavailable, "attestation unavailable")
		return
	}
	w.Header().Set("Content-Type", "application/cbor")
	_, _ = w.Write(doc)
}

func (s *server) handleDevRoot(w http.ResponseWriter, _ *http.Request) {
	root := s.attester.RootPEM()
	if root == nil {
		httpError(w, http.StatusNotFound, "production relays chain to the AWS Nitro root")
		return
	}
	w.Header().Set("Content-Type", "application/x-pem-file")
	_, _ = w.Write(root)
}

func (s *server) handlePCRs(w http.ResponseWriter, _ *http.Request) {
	pcrs := s.attester.PCRs()
	if pcrs == nil {
		httpError(w, http.StatusNotFound, "read PCRs from the enclave image with nitro-cli describe-eif")
		return
	}
	out := map[string]string{}
	for i, v := range pcrs {
		out[fmt.Sprint(i)] = hex.EncodeToString(v)
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *server) handleChallenge(w http.ResponseWriter, _ *http.Request) {
	c := make([]byte, 32)
	_, _ = rand.Read(c)
	encoded := base64.StdEncoding.EncodeToString(c)
	s.challenges.Check("issued:"+encoded, s.now()) // record issuance
	writeJSON(w, http.StatusOK, map[string]string{"challenge": encoded})
}

type tokenizeResult struct {
	psp.Token
	Reference string `json:"reference,omitempty"`
}

func (s *server) handleTokenize(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, maxBody+1))
	if err != nil || len(body) == 0 || len(body) > maxBody {
		httpError(w, http.StatusBadRequest, "body")
		return
	}
	bodyHash := sha256.Sum256(body)

	if s.appAttest != nil {
		if err := s.verifyAppAttest(r, bodyHash[:]); err != nil {
			log.Printf("app attest rejected: %v", err)
			httpError(w, http.StatusUnauthorized, "app attestation failed")
			return
		}
	}

	plaintext, hdr, err := s.key.Decrypt(body)
	if err != nil {
		httpError(w, http.StatusBadRequest, "payload could not be decrypted")
		return
	}
	defer zero(plaintext)
	now := s.now()
	if age := now.Sub(hdr.IAT); age > maxPayloadAge || age < -maxPayloadAge {
		httpError(w, http.StatusBadRequest, "payload expired")
		return
	}
	if !s.nonces.Check(hdr.Nonce, now) {
		httpError(w, http.StatusConflict, "replay")
		return
	}

	var p card.Payload
	if err := json.Unmarshal(plaintext, &p); err != nil {
		httpError(w, http.StatusBadRequest, "payload")
		return
	}
	defer p.Wipe()
	brand, err := p.Validate(now)
	if err != nil {
		httpError(w, http.StatusUnprocessableEntity, "card data invalid")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 25*time.Second)
	defer cancel()
	token, err := s.psp.Tokenize(ctx, p)
	if err != nil {
		log.Printf("psp %s failed: %v", s.psp.Name(), err)
		httpError(w, http.StatusBadGateway, "provider rejected the card")
		return
	}
	writeJSON(w, http.StatusOK, tokenizeResult{Token: psp.Token{
		Token: token, Provider: s.psp.Name(), Brand: brand,
		BIN: p.Number[:6], Last4: p.Number[len(p.Number)-4:], ExpMonth: p.ExpMonth, ExpYear: p.ExpYear,
	}})
}

func (s *server) verifyAppAttest(r *http.Request, bodyHash []byte) error {
	keyID := r.Header.Get(headerKeyID)
	assertion := r.Header.Get(headerAssert)
	if keyID == "" || assertion == "" {
		return errors.New("missing headers")
	}
	if attestation := r.Header.Get(headerAttest); attestation != "" {
		clientData := bodyHash
		if challenge := r.Header.Get(headerChalleng); challenge != "" {
			// A challenge may be used once, and only if this relay issued it.
			if s.challenges.Check("issued:"+challenge, s.now()) {
				return errors.New("unknown challenge")
			}
			if !s.challenges.Check("used:"+challenge, s.now()) {
				return errors.New("challenge reused")
			}
			sum := sha256.Sum256([]byte(challenge))
			clientData = sum[:]
		}
		if err := s.appAttest.VerifyAttestation(attestation, keyID, clientData); err != nil {
			return err
		}
	}
	return s.appAttest.VerifyAssertion(assertion, keyID, bodyHash)
}

func zero(b []byte) {
	for i := range b {
		b[i] = 0
	}
}

func httpError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

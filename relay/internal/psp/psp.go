// Package psp exchanges validated card data for a provider token. Adapters run inside the
// enclave, so provider secrets never leave it either.
package psp

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/Madhurr/CDCScanner-iOS-/relay/internal/card"
)

// Token is what the relay returns to the app and what the merchant backend charges with.
type Token struct {
	Token    string `json:"token"`
	Provider string `json:"provider"`
	Brand    string `json:"brand"`
	BIN      string `json:"bin"`
	Last4    string `json:"last4"`
	ExpMonth string `json:"exp_month"`
	ExpYear  string `json:"exp_year"`
}

type Adapter interface {
	Name() string
	Tokenize(ctx context.Context, p card.Payload) (string, error)
}

// Echo issues a deterministic HMAC token. For development and tests only.
type Echo struct{ Secret []byte }

func (Echo) Name() string { return "echo" }
func (e Echo) Tokenize(_ context.Context, p card.Payload) (string, error) {
	mac := hmac.New(sha256.New, e.Secret)
	mac.Write([]byte(p.Number))
	return "tok_dev_" + hex.EncodeToString(mac.Sum(nil))[:24], nil
}

// Stripe creates a card token with the raw card data API (form-encoded). Requires the account to
// have raw card data APIs enabled; the secret key stays inside the enclave.
type Stripe struct {
	SecretKey string
	BaseURL   string
	Client    *http.Client
}

func (Stripe) Name() string { return "stripe" }

func (s Stripe) Tokenize(ctx context.Context, p card.Payload) (string, error) {
	base := s.BaseURL
	if base == "" {
		base = "https://api.stripe.com"
	}
	client := s.Client
	if client == nil {
		client = &http.Client{Timeout: 20 * time.Second}
	}
	// A provider redirect must never forward the card or the API credential.
	scopedClient := *client
	scopedClient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	form := url.Values{}
	form.Set("card[number]", p.Number)
	form.Set("card[exp_month]", p.ExpMonth)
	form.Set("card[exp_year]", p.ExpYear)
	if p.CVC != "" {
		form.Set("card[cvc]", p.CVC)
	}
	if p.Name != "" {
		form.Set("card[name]", p.Name)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1/tokens", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Authorization", "Bearer "+s.SecretKey)
	res, err := scopedClient.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<16))
	var out struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(body, &out)
	if res.StatusCode/100 != 2 || out.ID == "" {
		// The response can contain card details. Preserve only the HTTP status.
		return "", fmt.Errorf("stripe: HTTP %d", res.StatusCode)
	}
	return out.ID, nil
}

var ErrNoAdapter = errors.New("no PSP adapter configured")

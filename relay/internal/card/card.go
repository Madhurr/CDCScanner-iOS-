// Package card validates decrypted card data. It never logs or stores it.
package card

import (
	"errors"
	"strconv"
	"strings"
	"time"
)

// Payload is the decrypted JWE content produced by the iOS SDK's EncryptingTokenizer.
type Payload struct {
	Number   string `json:"number"`
	ExpMonth string `json:"exp_month"`
	ExpYear  string `json:"exp_year"`
	CVC      string `json:"cvc,omitempty"`
	Name     string `json:"name,omitempty"`
}

// Wipe overwrites the sensitive strings' backing memory as far as Go allows.
// Go strings are immutable, so this zeroes the fields; the GC frees the old
// values. It is a best effort, documented as such.
func (p *Payload) Wipe() {
	p.Number = ""
	p.CVC = ""
}

var ErrInvalid = errors.New("invalid card data")

// Validate checks structure, Luhn and expiry. It returns a brand name or "unknown".
func (p Payload) Validate(now time.Time) (brand string, err error) {
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, p.Number)
	if len(digits) != len(p.Number) || len(digits) < 12 || len(digits) > 19 {
		return "", ErrInvalid
	}
	if !Luhn(digits) {
		return "", ErrInvalid
	}
	month, err1 := strconv.Atoi(p.ExpMonth)
	year, err2 := strconv.Atoi(p.ExpYear)
	if err1 != nil || err2 != nil || month < 1 || month > 12 {
		return "", ErrInvalid
	}
	if year < 100 {
		year += 2000
	}
	// Valid through the end of the expiry month.
	expiresAt := time.Date(year, time.Month(month)+1, 1, 0, 0, 0, 0, time.UTC)
	if !now.Before(expiresAt) || year > now.Year()+20 {
		return "", ErrInvalid
	}
	if p.CVC != "" && (len(p.CVC) < 3 || len(p.CVC) > 4) {
		return "", ErrInvalid
	}
	return Brand(digits), nil
}

// Luhn reports whether digits passes the mod-10 check.
func Luhn(digits string) bool {
	sum := 0
	double := false
	for i := len(digits) - 1; i >= 0; i-- {
		d := int(digits[i] - '0')
		if double {
			d *= 2
			if d > 9 {
				d -= 9
			}
		}
		sum += d
		double = !double
	}
	return sum%10 == 0
}

// Brand returns a coarse brand name from the leading digits.
func Brand(digits string) string {
	prefix := func(n int) int {
		if len(digits) < n {
			return -1
		}
		v, _ := strconv.Atoi(digits[:n])
		return v
	}
	switch {
	case prefix(1) == 4:
		return "visa"
	case prefix(2) >= 51 && prefix(2) <= 55, prefix(4) >= 2221 && prefix(4) <= 2720:
		return "mastercard"
	case prefix(2) == 34, prefix(2) == 37:
		return "amex"
	case prefix(4) == 6011, prefix(6) >= 622126 && prefix(6) <= 622925, prefix(3) >= 644 && prefix(3) <= 649, prefix(2) == 65:
		return "discover"
	case prefix(4) >= 3528 && prefix(4) <= 3589:
		return "jcb"
	case prefix(2) == 36, prefix(3) >= 300 && prefix(3) <= 305, prefix(2) == 38, prefix(2) == 39:
		return "diners"
	case prefix(2) == 62:
		return "unionpay"
	}
	return "unknown"
}

package card

import (
	"testing"
	"time"
)

func TestValidate(t *testing.T) {
	now := time.Date(2026, 11, 21, 0, 0, 0, 0, time.UTC)
	ok := Payload{Number: "4111111111111111", ExpMonth: "09", ExpYear: "2027", CVC: "123"}
	brand, err := ok.Validate(now)
	if err != nil || brand != "visa" {
		t.Fatalf("expected visa, got %q %v", brand, err)
	}
	bad := []Payload{
		{Number: "4111111111111112", ExpMonth: "09", ExpYear: "2027"},
		{Number: "4111 1111 1111 1111", ExpMonth: "09", ExpYear: "2027"},
		{Number: "4111111111111111", ExpMonth: "13", ExpYear: "2027"},
		{Number: "4111111111111111", ExpMonth: "10", ExpYear: "2026"},
		{Number: "4111111111111111", ExpMonth: "09", ExpYear: "2027", CVC: "12"},
	}
	for _, p := range bad {
		if _, err := p.Validate(now); err == nil {
			t.Errorf("expected rejection for %+v", p)
		}
	}
	if _, err := (Payload{Number: "4111111111111111", ExpMonth: "11", ExpYear: "26"}).Validate(now); err != nil {
		t.Errorf("card valid through end of current month: %v", err)
	}
	if Brand("378282246310005") != "amex" || Brand("5555555555554444") != "mastercard" {
		t.Error("brand detection")
	}
}

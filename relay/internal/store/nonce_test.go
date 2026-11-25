package store

import (
	"testing"
	"time"
)

func TestConsumeIssuedChallenge(t *testing.T) {
	cache := NewNonceCache(time.Minute)
	now := time.Now()
	if cache.Consume("test", now) || cache.Consume("test", now) {
		t.Fatal("unknown challenge accepted")
	}
	cache.Check("test", now)
	if !cache.Consume("test", now) || cache.Consume("test", now) {
		t.Fatal("challenge must be accepted once")
	}
	cache.Check("test", now)
	if cache.Consume("test", now.Add(time.Minute)) {
		t.Fatal("expired challenge accepted")
	}
}

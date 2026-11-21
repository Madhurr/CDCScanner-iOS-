// Package store holds short-lived relay state. Everything here is in memory and
// per-process; a multi-instance deployment needs a shared store such as Redis.
package store

import (
	"sync"
	"time"
)

// NonceCache rejects a nonce seen within the TTL.
type NonceCache struct {
	mu   sync.Mutex
	seen map[string]time.Time
	ttl  time.Duration
}

func NewNonceCache(ttl time.Duration) *NonceCache {
	return &NonceCache{seen: make(map[string]time.Time), ttl: ttl}
}

// Check records the nonce and returns false when it was already used.
func (c *NonceCache) Check(nonce string, now time.Time) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	for k, t := range c.seen {
		if now.Sub(t) > c.ttl {
			delete(c.seen, k)
		}
	}
	if _, dup := c.seen[nonce]; dup {
		return false
	}
	c.seen[nonce] = now
	return true
}

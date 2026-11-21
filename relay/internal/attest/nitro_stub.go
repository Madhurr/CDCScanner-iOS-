//go:build !nitro

package attest

import "errors"

// Nitro is only available when built with `-tags nitro` inside an enclave image.
type Nitro struct{}

func NewNitro() (*Nitro, error) {
	return nil, errors.New("this binary was built without the nitro tag; rebuild with -tags nitro")
}

func (n *Nitro) RootPEM() []byte       { return nil }
func (n *Nitro) PCRs() map[uint][]byte { return nil }
func (n *Nitro) Attest(nonce, userData, publicKey []byte) ([]byte, error) {
	return nil, errors.New("unavailable")
}

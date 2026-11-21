//go:build nitro

package attest

import (
	"errors"

	"github.com/hf/nsm"
	"github.com/hf/nsm/request"
)

// Nitro asks the Nitro Secure Module for a genuine attestation document.
// Build with `-tags nitro` inside the enclave image.
type Nitro struct{}

func NewNitro() (*Nitro, error) { return &Nitro{}, nil }

func (n *Nitro) RootPEM() []byte       { return nil } // clients pin the AWS root
func (n *Nitro) PCRs() map[uint][]byte { return nil } // read them from `nitro-cli describe-eif`

func (n *Nitro) Attest(nonce, userData, publicKey []byte) ([]byte, error) {
	sess, err := nsm.OpenDefaultSession()
	if err != nil {
		return nil, err
	}
	defer sess.Close()
	res, err := sess.Send(&request.Attestation{Nonce: nonce, UserData: userData, PublicKey: publicKey})
	if err != nil {
		return nil, err
	}
	if res.Error != "" {
		return nil, errors.New(string(res.Error))
	}
	if res.Attestation == nil || len(res.Attestation.Document) == 0 {
		return nil, errors.New("NSM returned no attestation document")
	}
	return res.Attestation.Document, nil
}

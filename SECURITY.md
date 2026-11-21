# Security policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub's private vulnerability reporting](https://github.com/Madhurr/CDCScanner-iOS-/security/advisories/new)
rather than a public issue. You should receive an acknowledgement within 72 hours. Please include
a description, reproduction steps and the affected version or commit.

Card data is sensitive; please do not include real card numbers in reports. Test numbers such as
`4111 1111 1111 1111` are fine.

## Scope

- `CDCCore`, `CDCScanner`, `CDCSecureFields` (Swift packages)
- The reference relay under `relay/`

## What we consider a vulnerability

- Any path by which a card number or security code becomes readable to code outside the field,
  the tokenizer or the relay enclave: public API, logs, descriptions, snapshots, accessibility,
  pasteboard, analytics.
- Weaknesses in the JWE construction, key agreement, attestation verification or App Attest
  verification, including acceptance of documents or assertions that should be rejected.
- Replay, downgrade or confused-deputy issues in the relay protocol.

## Hardening already in place

See `docs/ZERO_TRUST.md` section 7 for the threat model and residual risks. The parsing and
cryptographic code has unit tests including cross-implementation checks against `jwcrypto`
(Python) and `go-jose` (Go), and attestation fixtures generated independently with `cbor2` and
`cryptography`.

## Known limitations

- Swift `String` memory cannot be zeroed; UIKit retains displayed text. The fields minimise
  copies and lifetime but cannot eliminate them.
- The relay has not yet been exercised inside a real Nitro enclave; the enclave code path is
  built behind the `nitro` build tag and verified only by review.
- No third-party audit has been performed yet.

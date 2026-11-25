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

See `docs/ZERO_TRUST.md` for the threat model and residual risks. The parsing and
cryptographic code has unit tests including cross-implementation checks against `jwcrypto`
(Python) and `go-jose` (Go), and attestation fixtures generated independently with `cbor2` and
`cryptography`.

## Known limitations

- Swift `String` memory cannot be zeroed; UIKit retains displayed text. The fields minimise
  copies and lifetime but cannot eliminate them.
- The relay has not yet been exercised inside a real Nitro enclave; the enclave code path is
  built behind the `nitro` build tag and verified only by review.
- No third-party audit has been performed yet.

## Beta evidence and outstanding work

| Path | Evidence in the repository | Still to establish |
| --- | --- | --- |
| Native checkout | Simulator walkthrough, UI test and Swift validation tests. The demo issues a synthetic token in-process. | Physical-device entry, VoiceOver, screenshot and recording behavior across supported OS versions. |
| HTTPS tokenization | Request mapping, token parsing, origin policy and raw-body handling. | Sandbox contract with the chosen vault, a full provider token lifecycle, and review of the app’s credentials and telemetry. |
| Encrypted relay | Swift/Go interoperability fixtures, one-time challenge consumption and atomic in-memory assertion counters. | Real App Attest enrollment and recovery, deployment on Nitro, key distribution, restart and multi-instance replay protection, operational rate limits and independent crypto review. |
| PCI DSS | Data-flow descriptions and component tests. | The merchant’s deployed environment, service-provider evidence, retention controls and validation agreed with the acquirer. |

The reference relay keeps keys, counters and challenges in process. A restart loses enrollment state. The client may need to reset its App Attest key and enroll again after a failed first exchange or relay restart. The reference deployment needs an independently reviewed plan for persistent counters, trusted image measurements and recovery before handling live cards.

The scanner returns a Codable value containing the full PAN. The field form also offers explicit plaintext access for custom tokenizers. Review everything running in the host app, including third-party telemetry. A field API cannot isolate data from other code in that process. Token sensitivity depends on how the provider allows it to be used.

PCI DSS scope depends on what actually handles or can affect account data. Merchants must prevent retention of CVC after authorization and establish responsibilities for outsourced processing. [Encryption and scope](https://www.pcisecuritystandards.org/faqs/1086/) · [CVC retention](https://www.pcisecuritystandards.org/faqs/1280/) · [Outsourcing](https://www.pcisecuritystandards.org/faqs/1092/)

# Experimental encrypted relay

The reference client encrypts a card payload to recipient keys, and the Go relay exchanges the decrypted data for a provider token. The phone, SDK and tokenization code share one process. The relay and processor handle plaintext. Hardware validation and independent review are pending.

## Components

```mermaid
sequenceDiagram
    autonumber
    participant F as Secure field (iOS)
    participant A as Apple App Attest
    participant R as Relay (Nitro enclave)
    participant P as Payment provider
    participant M as Merchant backend

    F->>R: GET /v1/attestation?nonce=N
    R-->>F: COSE_Sign1 attestation {PCRs, cert chain, nonce N, public_key K}
    F->>F: verify chain to AWS root, ES384 signature, PCR0 == pinned hash, nonce == N
    F->>F: JWE(ECDH-ES+A256KW, A256GCM) of {PAN, exp, cvc} to K (and optional PSP keys)
    F->>A: generateAssertion(SHA-256(body))
    A-->>F: assertion
    F->>R: POST /v1/tokenize  body=JWE  headers: key id, assertion
    R->>R: verify assertion (counter, signature, app id); decrypt inside enclave; Luhn, expiry
    R->>P: tokenise card over TLS (vsock egress proxy)
    P-->>R: token
    R-->>F: {token, brand, bin, last4}
    F->>M: token only
    M->>P: charge with token
```

| Component | Where it runs | What it knows |
|---|---|---|
| `SecureCardNumberField` and friends | Merchant app | The PAN, for the lifetime of the entry screen. No `text` API. |
| `EncryptingTokenizer` | Merchant app | Builds the JWE. Stringifies the PAN once, immediately encrypts. |
| `AttestedEnclaveKeyProvider` | Merchant app | Verifies the relay's attestation document and extracts its key. |
| `AppAttestRequestAttestor` | Merchant app | Proves app integrity to the relay. Never sees card data. |
| Merchant backend, CDN, proxies | Merchant | Ciphertext only. Cannot decrypt. |
| Relay | AWS Nitro Enclave | Decrypts in enclave memory, forwards, forgets. |
| Payment provider | Vendor | The PAN, as it always has. Verify the chosen provider’s validation for the service in use. |

## Cryptography

| Purpose | Choice | Reason |
|---|---|---|
| Content encryption | AES-256-GCM | AEAD; the protected header (`typ`, `iat`, `nonce`) is authenticated. |
| Key management | ECDH-ES + A256KW on P-256 | One ciphertext, many recipients: enclave plus optional processor keys for failover. Standard JOSE (RFC 7518), interoperable with go-jose, jwcrypto and others; verified both ways in the test suite. |
| Attestation signature | ES384 over COSE_Sign1 | Fixed by AWS Nitro. Apple builds also evaluate the pinned certificate path with Security.framework. |
| Chain of trust | AWS Nitro Enclaves root G1, SHA-256 `641a0321…bb5b` | Pinned constant, checked against the published certificate in tests. |
| App integrity | Apple App Attest, ES256 assertions | Hardware-bound key per app install; counter prevents replay. |
| Transport | TLS 1.2+, HTTPS only, no cross-host redirects | Second layer. Pinning optional via custom `URLSession`. |

Why ECDH-ES with key wrapping rather than direct ECDH-ES: direct mode derives the content key
from a single agreement, so a message can have only one recipient. Wrapping a random content key
per recipient is what makes "encrypt once, any of N processors can open it" possible without a
vault holding plaintext.

## Attestation, both directions

**Enclave to phone.** The relay asks the Nitro Secure Module for a document binding the phone's
nonce, the relay's fresh P-256 public key and a version string to the enclave's PCRs. The phone:

1. parses COSE_Sign1 and requires `alg = ES384`;
2. parses the CBOR payload and requires `digest = SHA384`;
3. builds leaf → intermediates → root from `certificate` and `cabundle`, checks validity
   periods, verifies each certificate's signature with its issuer, and requires the root's
   SHA-256 to match the pinned AWS value;
4. verifies the COSE signature with the leaf key;
5. requires the timestamp to be fresh, PCR0 to be all-zero only if debug mode is allowed,
   every policy PCR to match a published value, and the nonce to match.

Only then does it extract `public_key` and encrypt to it. A document captured yesterday fails on
nonce and age; a document from a modified relay fails on PCR0; a document signed by anyone but
AWS fails on the root.

**Phone to enclave.** On first use the app creates an App Attest key and sends Apple's
attestation object once. On every tokenisation it sends an assertion over the SHA-256 of the
request body. The relay verifies the certificate chain to Apple's App Attestation Root CA, the
nonce extension, the key identifier, the app identifier hash, the environment and the
monotonically increasing counter. A script replaying a captured request fails on the counter;
a script with its own key fails on the chain; a modified app fails on Apple's side.

## Assessment scope

Document the native app, key recipients, relay, processor, deployment pipeline and any systems able to affect them. Check data flows and operational controls in the deployed environment with an assessor. Encryption and attestation alone establish neither SAQ eligibility nor a reduction in scope. [PCI SSC FAQ 1086](https://www.pcisecuritystandards.org/faqs/1086/)

## Threat model

| Threat | Mitigation | Residual risk |
|---|---|---|
| Merchant backend or CDN compromised | Holds ciphertext only; no key exists there. | Attacker can drop or replay requests; replay fails on relay nonce and App Attest counter. |
| TLS interception (corporate proxy, malicious root CA on device) | Payload is encrypted to the enclave key before TLS. | Interceptor sees ciphertext and metadata. |
| Relay operator or AWS host compromised | Enclave memory is isolated; key never leaves. | Operator can deny service or swap the enclave image, which changes PCR0 and fails client pinning. |
| Malicious relay impersonation | Phone pins AWS root and PCR0; nonce prevents document replay. | Pin distribution, trust policy and the release process require independent review. |
| Card-testing bots against `/v1/tokenize` | App Attest required; assertion bound to body hash with a counter. | Jailbroken devices with a genuine app may still drive it at human speed; rate-limit per key id. |
| Modified or repackaged app | Fails App Attest (Apple's attestation covers the binary). | Development builds use the `appattestdevelop` environment and must not be accepted in production. |
| Memory scraping on the device | Field minimises copies; no logging; covered in app switcher and during screen recording. | iOS cannot zero `String` memory; UIKit holds displayed text. Jailbroken devices are out of scope. |
| Relay logging plaintext | Relay logs only status codes and error classes; plaintext buffer zeroed after use. | Go strings are immutable; zeroing is best effort. |
| Enclave image supply chain | Deployers must measure their image and distribute trusted pins independently. | Requires discipline; a signed EIF (PCR8) adds a second anchor. |
| Processor outage | Multi-recipient JWE lets the same ciphertext be opened by a second processor's key. | Requires that processor to accept JWE, or a second relay. |

## Deployment checklist

1. Build the relay image reproducibly with `-tags nitro`; record PCR0, PCR1, PCR2 and, if signed,
   PCR8 from `nitro-cli describe-eif`.
2. Publish the PCRs with the release; ship them in the app's `NitroAttestationPolicy`. Allow two
   values during a rollout.
3. Run the parent instance with a vsock egress proxy that allows only the payment provider's host.
4. Set `APP_ATTEST=required` with your app identifier; use `development` only in test builds.
5. Rate-limit `/v1/tokenize` per App Attest key id and per source address.
6. Rotate the processor secret via the enclave's KMS attestation-gated decrypt, not a file.
7. Write the targeted risk analysis and keep this document with it.

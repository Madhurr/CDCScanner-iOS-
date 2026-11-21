# Zero-trust card tokenisation

*Design document for `CDCSecureFields` and the reference relay. Written to be handed to a QSA,
a security reviewer or an investor.*

## 1. The problem with hosted fields

Hosted-field products (VGS Collect, Basis Theory Elements, Evervault Inputs) reduce a merchant's
PCI DSS scope by moving the card number out of the merchant's systems and into the vendor's.
The merchant trusts the vendor because the vendor holds a PCI DSS Attestation of Compliance.
That trust is contractual, not cryptographic: the vendor's staff, infrastructure and any
compromise of it see plaintext card numbers.

This design keeps the scope reduction and removes the trust. Nobody operating the system can
read a card number, and the phone verifies that claim before it sends one.

## 2. Principles

1. **Encrypt at the point of entry.** The PAN is encrypted inside the text field, to keys the
   device has verified, before it becomes a request body. TLS is a second layer, not the first.
2. **Nobody holds plaintext and keys together.** The merchant's servers forward ciphertext they
   cannot open. The relay's key exists only inside a hardware enclave whose memory the operator
   cannot read.
3. **Verify, do not trust, in both directions.** The phone checks the enclave's measured code
   hash before encrypting to it. The enclave checks Apple's attestation that the request came
   from a genuine build of the merchant's app on a real device.
4. **Minimise what exists.** The relay is stateless, stores nothing, logs no card data, and
   issues the processor's own token so there is no second vault to protect.
5. **Everything is open.** Client SDK, relay, enclave image build and the hash the phone pins are
   public. Trust is in the reproducible hash, not in a brand.

## 3. Components

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
| Payment provider | Vendor | The PAN, as it always has. Already PCI DSS Level 1. |

## 4. Cryptography

| Purpose | Choice | Reason |
|---|---|---|
| Content encryption | AES-256-GCM | AEAD; the protected header (`typ`, `iat`, `nonce`) is authenticated. |
| Key management | ECDH-ES + A256KW on P-256 | One ciphertext, many recipients: enclave plus optional processor keys for failover. Standard JOSE (RFC 7518), interoperable with go-jose, jwcrypto and others; verified both ways in the test suite. |
| Attestation signature | ES384 over COSE_Sign1 | Fixed by AWS Nitro. Verified in pure Swift with no platform certificate API. |
| Chain of trust | AWS Nitro Enclaves root G1, SHA-256 `641a0321…bb5b` | Pinned constant, checked against the published certificate in tests. |
| App integrity | Apple App Attest, ES256 assertions | Hardware-bound key per app install; counter prevents replay. |
| Transport | TLS 1.2+, HTTPS only, no cross-host redirects | Second layer. Pinning optional via custom `URLSession`. |

Why ECDH-ES with key wrapping rather than direct ECDH-ES: direct mode derives the content key
from a single agreement, so a message can have only one recipient. Wrapping a random content key
per recipient is what makes "encrypt once, any of N processors can open it" possible without a
vault holding plaintext.

Why not RSA-OAEP: CryptoKit has no RSA. Adyen's client-side encryption uses RSA because it
predates widespread EC support on clients.

## 5. Attestation, both directions

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

## 6. What a QSA will ask

**Does encryption take the merchant out of scope?** Not on its own. PCI SSC FAQ 1086 states that
encryption alone is insufficient to render cardholder data out of scope. FAQ 1233 adds that an
entity that receives or stores only data encrypted by another party, and has no ability to
decrypt it, *may be able to* consider that data out of scope. This design is built to meet the
second statement literally: the merchant has no key, by construction, and can show the assessor
the code that proves it.

**Where is the key?** Inside a Nitro enclave. The parent EC2 instance, its operator and AWS staff
cannot read enclave memory. The key is generated at enclave boot, never persisted and never
exported. The enclave's identity is its PCR measurements, published with each release.

**What is in scope?** The relay enclave, as a system component that decrypts cardholder data,
and the merchant's responsibility for operating it: the enclave image build pipeline, the PCR
publication process, access to the parent instance, logging and monitoring. This is a small,
stateless, single-purpose component with a published hash. It is far less than a vault, a
database and the staff who can reach them.

**Is this a customised approach?** It can be documented as one under PCI DSS v4.0 for the
requirements it addresses differently from the defined approach, with the targeted risk analysis
the standard requires. The controls here are stronger than the defined approach in each case,
which is the scenario the customised approach was written for.

**Which SAQ?** The acquirer decides. The data flow matches the one that lets e-commerce merchants
use SAQ A with a third-party hosted page; for native mobile apps assessors vary, and the merchant
should raise this design with their QSA early. The honest position in the README says the same.

## 7. Threat model

| Threat | Mitigation | Residual risk |
|---|---|---|
| Merchant backend or CDN compromised | Holds ciphertext only; no key exists there. | Attacker can drop or replay requests; replay fails on relay nonce and App Attest counter. |
| TLS interception (corporate proxy, malicious root CA on device) | Payload is encrypted to the enclave key before TLS. | Interceptor sees ciphertext and metadata. |
| Relay operator or AWS host compromised | Enclave memory is isolated; key never leaves. | Operator can deny service or swap the enclave image, which changes PCR0 and fails client pinning. |
| Malicious relay impersonation | Phone pins AWS root and PCR0; nonce prevents document replay. | None if pins are correct and the release process is sound. |
| Card-testing bots against `/v1/tokenize` | App Attest required; assertion bound to body hash with a counter. | Jailbroken devices with a genuine app may still drive it at human speed; rate-limit per key id. |
| Modified or repackaged app | Fails App Attest (Apple's attestation covers the binary). | Development builds use the `appattestdevelop` environment and must not be accepted in production. |
| Memory scraping on the device | Field minimises copies; no logging; covered in app switcher and during screen recording. | iOS cannot zero `String` memory; UIKit holds displayed text. Jailbroken devices are out of scope. |
| Relay logging plaintext | Relay logs only status codes and error classes; plaintext buffer zeroed after use. | Go strings are immutable; zeroing is best effort. |
| Enclave image supply chain | Reproducible build, PCRs published per release, clients pin them. | Requires discipline; a signed EIF (PCR8) adds a second anchor. |
| Processor outage | Multi-recipient JWE lets the same ciphertext be opened by a second processor's key. | Requires that processor to accept JWE, or a second relay. |

## 8. What this is not

- Not a PCI DSS certification. The merchant still attests; this design makes the attestation
  smaller and the controls demonstrable.
- Not network tokenisation. Visa and Mastercard token services require partnership agreements.
- Not an Apple Pay replacement. Apple Pay never exposes the PAN at all; this is for cards typed
  into a merchant's own form.
- Not finished until it has run on real hardware. The relay has run in dev mode with a self-made
  chain; the enclave build has not yet been exercised on an EC2 instance with Nitro Enclaves.

## 9. Comparison

| | VGS Collect + Vault | Evervault Inputs + Enclaves | This design |
|---|---|---|---|
| Open source | No | No | Yes, client and relay |
| Operator can read PANs | Yes (vault) | No (enclave) | No (enclave) |
| Client verifies server attestation | No | Yes (PCR pinning in SDK) | Yes (PCRs, root, nonce, age) |
| Server verifies client integrity | No | No | Yes (App Attest) |
| Multi-processor from one ciphertext | Via vault | Via relay | Via multi-recipient JWE |
| Telemetry sent to vendor | Yes | Yes | None |
| Self-hostable | No | No | Yes |
| Certified vendor behind it | Yes | Yes | No. That is the trade. |

## 10. Deployment checklist

1. Build the relay image reproducibly with `-tags nitro`; record PCR0, PCR1, PCR2 and, if signed,
   PCR8 from `nitro-cli describe-eif`.
2. Publish the PCRs with the release; ship them in the app's `NitroAttestationPolicy`. Allow two
   values during a rollout.
3. Run the parent instance with a vsock egress proxy that allows only the payment provider's host.
4. Set `APP_ATTEST=required` with your app identifier; use `development` only in test builds.
5. Rate-limit `/v1/tokenize` per App Attest key id and per source address.
6. Rotate the processor secret via the enclave's KMS attestation-gated decrypt, not a file.
7. Write the targeted risk analysis and keep this document with it.

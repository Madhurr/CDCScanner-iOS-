# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] – 2026-11-26

First stable Swift Package Manager release of `CDCScanner`, `CDCSecureFields`, and `CDCCore`. It includes offline scanning with rules for 15 card networks, native card-entry fields, and a configurable HTTPS tokenizer. The example app provides a local test-card checkout.

The public Swift APIs match `1.0.0-beta.1`. The README adds checkout screenshots, a tokenization architecture diagram, and the supported network list. The encrypted reference relay remains experimental.

## [1.0.0-beta.1] – 2026-11-26

First public beta of the rewritten API. Earlier scanner integrations need migration.

- Updated the relay to go-jose 4.1.4 for GO-2026-4945.
- Added a runnable test-card checkout, UI test and simulator walkthrough.
- Built-in tokenizers discard raw response bodies, reject empty or echoed-PAN tokens and restrict default HTTPS redirects to the original origin.
- Apple builds evaluate the enclave certificate path against the pinned anchor. Production verification requires a PCR0 image pin.
- The reference relay consumes enrollment challenges once and advances in-memory assertion counters atomically. Clients using their own enrollment service must return a fresh 32-byte challenge.
- Unknown relay modes fail startup. Nitro mode requires production App Attest. The default listen address is loopback.
- Documented data access in the host process and the remaining PCI and hardware assessment work.

### Added
- Zero-trust tokenisation: `EncryptingTokenizer` encrypts card data inside the field with JOSE JWE
  (ECDH-ES+A256KW, A256GCM) to one or many recipients; `AttestedEnclaveKeyProvider` and
  `NitroAttestationVerifier` verify AWS Nitro Enclaves attestation documents (COSE_Sign1, ES384,
  certificate chain to the pinned AWS root, PCR and nonce policy) in pure Swift;
  `AppAttestRequestAttestor` proves app integrity to the relay with Apple App Attest. Includes a
  CBOR decoder, a minimal X.509 parser and JWK types. Interop-tested against `jwcrypto` and `go-jose`.
- `relay/`: a reference Go relay that publishes attestation documents, decrypts SDK payloads,
  verifies App Attest, validates cards and tokenises with Stripe or an echo adapter. Dev mode runs
  on a laptop with a self-made chain; `-tags nitro` targets a real enclave.
- `docs/ZERO_TRUST.md` design document and threat model; `SECURITY.md`.
- `CDCSecureFields`, a second product for PCI-conscious card entry: `SecureCardNumberField`,
  `SecureExpiryField`, `SecureCVCField` and `CardholderNameField` with no `text` on their public
  API, blocked copy/cut/share, a configurable paste policy, privacy covers during screen capture
  and in the app switcher, redacted VoiceOver values, live brand detection and per-brand
  formatting and lengths.
- `SecureCardForm` to track completeness across fields and tokenise, `SecureCardData` (not
  `Codable`, redacted descriptions, closure-only access to the PAN), the `CardTokenizer` protocol
  and `HTTPTokenizer` for any HTTPS JSON vault or payment-provider endpoint.
- SwiftUI wrappers: `SecureCardNumberTextField`, `SecureExpiryTextField`, `SecureCVCTextField`,
  `CardholderNameTextField`.
- `CDCCore` product holding the brand rules, Luhn and parsers shared by both UI products.
- VisionKit-based camera scanning via `DataScannerViewController`. All recognition stays on device.
- `CardScannerViewController` (UIKit, delegate-based), `CardScanner.scan(from:)` (`async`/`await`) and
  `CardScannerView` plus a `.cardScanner(isPresented:)` modifier (SwiftUI).
- A pure, testable parsing core: `CardNumberParser`, `ExpiryParser`, `Luhn` and `ScanSession`.
- Typed results: `ScannedCard`, `CardBrand`, `CardExpiry`, with formatting and masking helpers.
- `CardBrandRule` for restricting or extending brand recognition, including custom brands.
- `ScannerConfiguration` for confirmations, expiry handling, recognition quality and UI text.
- Correct per-brand length handling (15-digit Amex, 14-digit Diners, 19-digit Visa/UnionPay/Maestro).
- Camera-permission handling, simulator and unsupported-device detection, torch toggle, rotation and
  iPad support, Dynamic Type, VoiceOver labels and a card-shaped region of interest.
- Privacy manifest (`PrivacyInfo.xcprivacy`), DocC documentation comments, unit tests and CI.

### Changed
- Minimum deployment target is iOS 16.
- Package manifest declares its platform, so Swift Package Index no longer reports failed builds on
  platforms the library never targeted.

### Removed
- The `CDCScanner` view-controller subclass, `CDCScannerDelegate.ccScannerCompleted`, `CardType`,
  `Card` and the hand-rolled AVFoundation pipeline.

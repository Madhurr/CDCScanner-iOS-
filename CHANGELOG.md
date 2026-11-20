# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] – 2026-11-20

First tagged release. This is a rewrite; nothing from the untagged `main` history is API-compatible.

### Added
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

# CDCScanner

[![CI](https://github.com/Madhurr/CDCScanner-iOS-/actions/workflows/ci.yml/badge.svg)](https://github.com/Madhurr/CDCScanner-iOS-/actions/workflows/ci.yml)
[![Swift Package Index](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FMadhurr%2FCDCScanner-iOS-%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Madhurr/CDCScanner-iOS-)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FMadhurr%2FCDCScanner-iOS-%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Madhurr/CDCScanner-iOS-)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

On-device credit and debit card scanning for iOS, built on VisionKit.

Point the camera at a card and get back its number, brand and expiry as typed Swift values.
Recognition runs entirely on the device through Apple's `DataScannerViewController`; no frames or
card data ever leave the phone.

- **Three ways in:** UIKit delegate, `async`/`await`, or SwiftUI.
- **Accurate by design:** every read is Luhn-checked, matched to a brand's issuer ranges and length,
  and confirmed across several frames before it is reported.
- **Testable core:** parsing is pure Swift with no camera dependency and is covered by unit tests.
- **Configurable:** restrict brands, add your own, skip the expiry, tune quality and confirmations.
- **Ships the right paperwork:** privacy manifest, DocC comments, CI.

## Requirements

| | |
|---|---|
| iOS | 16.0+ |
| Swift | 5.9+ (Xcode 15+) |
| Hardware | A12 Bionic or newer. VisionKit's live scanner does not run on the simulator; check `CardScanner.isSupported`. |

Add `NSCameraUsageDescription` to your app's `Info.plist`.

## Installation

In Xcode choose **File ▸ Add Package Dependencies…** and enter the repository URL, or add it to
your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Madhurr/CDCScanner-iOS-.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: ["CDCScanner"])
]
```

## Usage

### SwiftUI

```swift
import CDCScanner
import SwiftUI

struct PaymentForm: View {
    @State private var isScanning = false
    @State private var cardNumber = ""

    var body: some View {
        Form {
            TextField("Card number", text: $cardNumber)
            Button("Scan card") { isScanning = true }
                .disabled(!CardScanner.isSupported)
        }
        .cardScanner(isPresented: $isScanning) { card in
            cardNumber = card.formattedNumber
        }
    }
}
```

`CardScannerView` is also available directly if you want to host it yourself.

### UIKit with `async`/`await`

```swift
import CDCScanner

func scanCard() async {
    do {
        let card = try await CardScanner.scan(from: self)
        numberField.text = card.formattedNumber
        expiryField.text = card.expiry?.formatted ?? ""
        brandLabel.text = card.brand.displayName
    } catch is CancellationError {
        // User tapped Cancel.
    } catch {
        presentAlert(error.localizedDescription)
    }
}
```

The scanner is presented full screen and dismissed before the call returns.

### UIKit with a delegate

```swift
import CDCScanner

final class CheckoutViewController: UIViewController, CardScannerDelegate {
    func scanTapped() {
        let scanner = CardScannerViewController()
        scanner.delegate = self
        present(scanner, animated: true)
    }

    func cardScanner(_ scanner: CardScannerViewController, didScan card: ScannedCard) {
        dismiss(animated: true)
        print(card.maskedNumber, card.brand, card.expiry ?? "no expiry")
    }

    func cardScannerDidCancel(_ scanner: CardScannerViewController) {
        dismiss(animated: true)
    }

    func cardScanner(_ scanner: CardScannerViewController, didFailWith error: CardScannerError) {
        dismiss(animated: true)
    }
}
```

Like `UIImagePickerController`, the controller does not dismiss itself; the delegate decides.

## Configuration

```swift
var configuration = ScannerConfiguration()
configuration.brandRules = CardBrandRule.defaults(for: [.visa, .mastercard, .americanExpress])
configuration.requiresExpiry = false          // finish as soon as the number is confirmed
configuration.requiredConfirmations = 4       // frames that must agree (default 3)
configuration.recognitionQuality = .accurate  // .fast, .balanced (default) or .accurate
configuration.title = "Add a card"
configuration.instructions = "Line the card up inside the frame"

let card = try await CardScanner.scan(from: self, configuration: configuration)
```

| Option | Default | Effect |
|---|---|---|
| `brandRules` | `CardBrandRule.defaults` | Which brands are accepted and how they are recognised. |
| `requiredConfirmations` | `3` | Frames that must agree before a value is accepted. |
| `requiresExpiry` | `true` | Keep looking for an expiry after the number is confirmed. |
| `expiryTimeout` | `5` s | Give up on the expiry after this long and return the number alone. |
| `recognitionQuality` | `.balanced` | Passed through to VisionKit. |
| `showsCardGuide` | `true` | Draw the card-shaped frame. |
| `restrictsRecognitionToGuide` | `true` | Only read text inside the frame. |
| `showsTorchButton` | `true` | Offer a flashlight toggle on devices that have one. |
| `title`, `instructions` | – | On-screen text. |

### Custom brands

Teach the scanner about a store card or any network it does not know:

```swift
let storeCard = CardBrandRule(brand: .custom("Acme Rewards"), prefix: 9000, lengths: [16])
configuration.brandRules = CardBrandRule.defaults + [storeCard]
```

## Results

```swift
public struct ScannedCard {
    let number: String        // "4111111111111111"
    let brand: CardBrand      // .visa
    let expiry: CardExpiry?   // 09/27

    var formattedNumber: String  // "4111 1111 1111 1111" (Amex: "3782 822463 10005")
    var maskedNumber: String     // "•••• •••• •••• 1111"
    var lastFour: String         // "1111"
}
```

`CardExpiry` knows whether it `isExpired(asOf:)`, and everything is `Hashable`, `Sendable` and `Codable`.

## Supported brands

Visa, Mastercard, American Express, Discover, Diners Club, JCB, UnionPay, Maestro, RuPay, Mir,
Dankort, China T-Union, InterPayment, UATP and NPS Pridnestrovie. Issuer ranges live in
`CardBrandRule.defaults`; pull requests that update them are welcome.

## Using the parser without the camera

The parsing layer has no UIKit or VisionKit dependency, so you can run it on text from any OCR
source, or in unit tests:

```swift
let parser = CardNumberParser()
parser.parse("4111 1111 1111 1111")          // [CardNumberMatch(number: "4111111111111111", brand: .visa)]

ExpiryParser().bestExpiry(in: "VALID THRU 09/27")   // CardExpiry(month: 9, year: 2027)

var session = ScanSession()
for frame in recognisedFrames {
    if let card = session.ingest(frame) { print(card); break }
}
```

## How it works

1. `DataScannerViewController` streams recognised text, restricted to the card-shaped region of interest.
2. `CardNumberParser` pulls digit runs out of each frame, repairs numbers that OCR split or glued
   together, Luhn-checks every candidate and matches it to the most specific issuer range.
3. `ExpiryParser` collects `MM/YY` dates and prefers the latest, which is the "valid thru" on every
   common layout.
4. `ScanSession` counts votes across frames and only reports a card once enough frames agree, then
   waits briefly for an expiry before returning.

## Contributing

Run the core tests with `swift test` on any platform, or the full suite on an iOS simulator with
`xcodebuild test -scheme CDCScanner -destination 'platform=iOS Simulator,name=iPhone 16'`.
CI runs both on every pull request.

## License

MIT. See [LICENSE](LICENSE).

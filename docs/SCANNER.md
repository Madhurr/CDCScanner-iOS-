# CDCScanner: camera scanning reference

Everything about the `CDCScanner` product: API, configuration, results, brand rules, the parser
without a camera, and troubleshooting. The README covers architecture and security.

## Usage (camera scanning)

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

The modifier presents the scanner full screen and resets the binding on scan, cancel or error.
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
Call `restartScanning()` to scan another card without dismissing.

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
| `title`, `instructions` | – | On-screen text. Pass localised strings. |

### Custom brands

Teach the scanner about a store card or any network it does not know:

```swift
let storeCard = CardBrandRule(brand: .custom("Acme Rewards"), prefix: 9000, lengths: [16])
configuration.brandRules = CardBrandRule.defaults + [storeCard]
```

A rule takes exact prefixes (`[34, 37]`), ranges (`2221...2720`) or a mix, plus the lengths the
network issues. When several rules match, the longest prefix wins, so a specific rule can sit
inside a broader one.

## Results

```swift
public struct ScannedCard {
    let number: String        // "4111111111111111"
    let brand: CardBrand      // .visa
    let expiry: CardExpiry?   // 09/27, nil if the card shows none or it timed out

    var formattedNumber: String  // "4111 1111 1111 1111" (Amex: "3782 822463 10005")
    var maskedNumber: String     // "•••• •••• •••• 1111"
    var lastFour: String         // "1111"
}
```

`CardExpiry` exposes `month`, a four-digit `year`, `formatted` (`"09/27"`) and
`isExpired(asOf:)`. Every result type is `Hashable`, `Sendable` and `Codable`.


## Supported brands

| Brand | Prefixes | Lengths |
|---|---|---|
| Visa | 4 | 13, 16, 19 |
| Mastercard | 51–55, 2221–2720 | 16 |
| American Express | 34, 37 | 15 |
| Discover | 6011, 622126–622925, 644–649, 65 | 16–19 |
| Diners Club | 300–305, 36, 38–39 | 14–19 |
| JCB | 3528–3589 | 16–19 |
| UnionPay | 62 | 16–19 |
| Maestro | 5018, 5020, 5038, 5893, 6304, 67 | 12–19 |
| RuPay | 60, 6521–6522, 81–82, 508 | 16 |
| Mir | 2200–2204 | 16 |
| Dankort | 5019 | 16 |
| China T-Union | 31 | 19 |
| InterPayment | 636 | 16–19 |
| UATP | 1 | 15 |
| NPS Pridnestrovie | 6054740–6054744 | 16 |

Issuer ranges live in `CardBrandRule.defaults`. Pull requests that update them are welcome.

## Using the parser without the camera

The parsing layer has no UIKit or VisionKit dependency, so you can run it on text from any OCR
source, on the server, or in unit tests:

```swift
let parser = CardNumberParser()
parser.parse("4111 1111 1111 1111")
// [CardNumberMatch(number: "4111111111111111", brand: .visa)]

ExpiryParser().bestExpiry(in: "VALID THRU 09/27")
// CardExpiry(month: 9, year: 2027)

var session = ScanSession()
for frame in recognisedFrames {           // [[String]] – one array of text lines per frame
    if let card = session.ingest(frame) {
        print(card)
        break
    }
}
```

## How it works

1. `DataScannerViewController` streams recognised text, restricted to the card-shaped region of
   interest so background text is never considered.
2. `CardNumberParser` pulls digit runs out of each frame, repairs numbers that OCR split across
   lines or glued to a stray digit, Luhn-checks every candidate and matches it to the most specific
   issuer range for its length.
3. `ExpiryParser` collects `MM/YY` and `MM/YYYY` dates and prefers the latest, which is the
   "valid thru" on every common layout.
4. `ScanSession` counts votes across frames and only reports a card once
   `requiredConfirmations` frames agree, then waits up to `expiryTimeout` for an expiry before
   returning.

## Privacy and PCI

- All processing is on device. The library makes no network requests and the bundled
  `PrivacyInfo.xcprivacy` declares no tracking, no collected data and no required-reason APIs.
- Treat `ScannedCard.number` as cardholder data. Pass it straight to your payment provider's SDK
  or tokenisation endpoint, show the user `maskedNumber`, and never write the full number to logs,
  analytics or crash reports.
- Scanning only reads what is printed on the card. It does not read the CVV from the back, and it
  cannot replace your provider's validation.

## Troubleshooting

**Nothing happens, or `didFailWith` reports `unsupportedDevice`.** VisionKit's live scanner needs
an A12 chip or newer and does not run on the simulator. Test on a physical device and gate the
button on `CardScanner.isSupported`.

**`cameraAccessDenied`.** The user declined camera access or it is restricted by a device policy.
Offer a link to `UIApplication.openSettingsURLString`.

**The number is read but the expiry comes back `nil`.** Embossed expiry dates on dark cards can
be hard to read. Try `recognitionQuality = .accurate`, encourage the torch, or set
`requiresExpiry = false` and ask for the expiry manually.

**A wrong number was accepted.** Raise `requiredConfirmations`, or restrict `brandRules` to the
brands you actually accept so fewer candidates qualify.


## Migrating from the untagged API

The original scanner API preceded the versioned releases. If you vendored that implementation or depended on its branch, use these replacements when migrating to 1.0.0.

| Before | Now |
|---|---|
| `CDCScanner().startScanner(viewController:)` | `CardScannerViewController` + `present`, or `CardScanner.scan(from:)` |
| `CDCScannerDelegate.ccScannerCompleted(cardNumber:expDate:cardType:)` | `CardScannerDelegate.cardScanner(_:didScan:)` with a `ScannedCard` |
| `CardType` string raw values | `CardBrand` enum with `displayName` |
| `Card(binRange:lengthRange:)` + `addCustomCards` | `CardBrandRule(brand: .custom(...), prefix:, lengths:)` |
| `recognitionLevel` | `ScannerConfiguration.recognitionQuality` and `requiredConfirmations` |
| iOS 13 minimum | iOS 16 minimum |


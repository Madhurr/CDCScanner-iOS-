# CDCScanner for iOS

Scan a payment card with the iPhone camera, or add native card entry to a SwiftUI or UIKit checkout. Send the form to a compatible HTTPS tokenization endpoint and use the returned token in your app.

[![CI](https://github.com/Madhurr/CDCScanner-iOS-/actions/workflows/ci.yml/badge.svg)](https://github.com/Madhurr/CDCScanner-iOS-/actions/workflows/ci.yml) · [Swift Package Index](https://swiftpackageindex.com/Madhurr/CDCScanner-iOS-) · [MIT license](LICENSE)

## Try the checkout

<a href="docs/media/checkout.mp4"><img src="docs/media/checkout.gif" width="264" alt="iPhone demo filling a sample Visa, entering a masked security code and receiving tok_demo_visa"></a>

[Watch the MP4](docs/media/checkout.mp4) · [Browse the example app](Examples/CardCheckout/App)

1. Clone this repository and open `Examples/CardCheckout/CardCheckout.xcodeproj` in Xcode.
2. Select the **CardCheckout** scheme, choose an iPhone simulator and press **Run**. The project uses the local package.
3. Tap **Use test card**, enter **123** in **Security code**, then tap **Create test token**. The receipt shows `tok_demo_visa` and the last four digits. Entering a different three-digit code lets you try the rejection and retry flow.

The demo uses the SDK’s real fields, validation, JSON request builder and token parser. Its example-only URL protocol answers requests on the device. Use synthetic data. The fixture token has no payment value. On a supported physical iPhone, **Scan a test card** also fills the number and expiry.

## Install the beta

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/Madhurr/CDCScanner-iOS-.git`, and select **Exact Version** `1.0.0-beta.1`. For a Swift package manifest use:

```swift
.package(url: "https://github.com/Madhurr/CDCScanner-iOS-.git", exact: "1.0.0-beta.1")
```

| Add this product | When you need |
| --- | --- |
| `CDCSecureFields` | Native number, expiry and CVC fields, form validation and tokenization. [Integration guide](docs/SECURE_FIELDS.md) |
| `CDCScanner` | A VisionKit camera scanner returning the number, brand and optional expiry. [Scanner guide](docs/SCANNER.md) |
| `CDCCore` | Card rules, Luhn checks and date parsing without UI. |

The UI targets require iOS 16+. The manifest requires Swift tools 5.9+. Camera scanning requires a supported physical device and an `NSCameraUsageDescription` entry. Check `CardScanner.isSupported` before offering it. The example requires Xcode with an installed iOS simulator runtime.

## Connect your vault

Use a provider endpoint intended for native clients that accepts JSON card data and returns a token. The example below uses the default request keys `number`, `exp_month`, `exp_year`, and `cvc`. Configure `HTTPTokenizer.FieldMapping` for other formats. Supply only client-authorized credentials.

```swift
import CDCSecureFields

// form is a SecureCardForm attached to the three fields.
let tokenizer = HTTPTokenizer(
    url: vaultTokenURL,
    headers: ["Authorization": "Bearer " + clientSessionToken],
    tokenPath: "data.id"
)
let token = try await form.tokenize(using: tokenizer)
form.clear()
// Pass token.value to your backend using the provider's payment flow.
```

Endpoint authentication, token permissions and payment authorization belong to the chosen provider. Confirm its sandbox contract before integration. SDK tokenizers discard raw provider response bodies on success and failure. The default session follows redirects only within the original HTTPS origin. A custom session owns its own redirect, trust and storage policies.

## Security and PCI DSS

The fields and their host app share a process. Field state exposes validation and masked details. A custom tokenizer can read the PAN and CVC, and scanning deliberately returns the full number. Exclude these paths from logs, session replay, analytics and crash attachments. After successful tokenization the form clears its CVC field. An integrating app must also clear abandoned forms and control data retained elsewhere.

The optional [encrypted relay](docs/ZERO_TRUST.md) is experimental. Tests exercise JWE interoperability and synthetic attestation fixtures. Real Apple App Attest enrollment, production processor behavior, AWS Nitro hardware and independent security assessment remain open. This beta has no PCI DSS attestation. Determine scope for the actual integration with your acquirer or assessor. [Evidence and limits](SECURITY.md) · [PCI SSC on encryption and scope](https://www.pcisecuritystandards.org/faqs/1086/)

## Run the checks

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
(cd relay && go test -race ./... && go vet ./... && go build -tags nitro ./...)
```

In the example project, choose **Product → Test** to run the checkout UI test. [Report a security issue privately](https://github.com/Madhurr/CDCScanner-iOS-/security/advisories/new).

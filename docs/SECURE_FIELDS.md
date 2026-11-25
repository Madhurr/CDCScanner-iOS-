# CDCSecureFields: card entry reference

Everything about the hardened entry fields, the form, `SecureCardData` and the plain HTTPS
tokenizer. For the attested, field-encrypted mode see [ZERO_TRUST.md](ZERO_TRUST.md); for the
security model see the README.

The fields collect the card number, expiry, security code and name in the host app’s process. The ordinary checkout API returns a token. Custom tokenizer code is trusted with plaintext card data.

## What the fields do that a `UITextField` does not

| Protection | Detail |
|---|---|
| No `text` on the public API | The field exposes validation and masked metadata. Observe `numberState` (brand, validity, BIN, last four) instead. |
| Copy, cut, share and look-up blocked | The edit menu offers paste only. `pastePolicy = .disabled` removes that too. |
| Keyboard cannot learn the value | Autocorrection, predictive text, spell checking and smart punctuation are off. |
| Hidden from the app switcher | Contents are covered while the app is inactive, so the snapshot shows bullets. |
| Hidden from screen recording | Contents are covered while the screen is recorded, mirrored or shared. |
| Screenshot callback | iOS cannot block screenshots, but `onScreenshotTaken` lets you warn the user or log it. |
| Redacted accessibility | VoiceOver hears "Visa ending in 1 1 1 1", never the full number. |
| Redacted everywhere else | `SecureCardData` is not `Codable`; `print`, string interpolation, `dump` and the debugger show the masked number. |
| Live validation | Brand detected from the first digits, grouping and maximum length follow the brand, Luhn checked on every keystroke, expiry checked against today. |
| Honest about limits | iOS strings cannot be zeroed and UIKit keeps the displayed text in its own memory. The fields minimise copies and lifetime; they do not claim the impossible. |

## UIKit

```swift
import CDCSecureFields

let numberField = SecureCardNumberField()
let expiryField = SecureExpiryField()
let cvcField = SecureCVCField()
numberField.placeholder = "Card number"

let form = SecureCardForm()
form.attach(numberField: numberField, expiryField: expiryField, cvcField: cvcField)

form.$isComplete
    .receive(on: RunLoop.main)
    .assign(to: \.isEnabled, on: payButton)
    .store(in: &cancellables)

numberField.onStateChange = { state in
    brandLabel.text = state.brand?.displayName
}

// Pay button:
let token = try await form.tokenize(using: tokenizer)
await backend.charge(token: token.value)  // your server never sees the PAN
```

## SwiftUI

```swift
struct CheckoutView: View {
    @StateObject private var form = SecureCardForm()

    var body: some View {
        VStack(spacing: 12) {
            SecureCardNumberTextField(form: form, placeholder: "Card number")
            HStack(spacing: 12) {
                SecureExpiryTextField(form: form)
                SecureCVCTextField(form: form)
            }
            Button("Pay") {
                Task { let token = try await form.tokenize(using: tokenizer) }
            }
            .disabled(!form.isComplete)
        }
    }
}
```

## Tokenisation

`HTTPTokenizer` posts JSON to any HTTPS endpoint, refuses plain HTTP, never follows a redirect
to another host, uses an ephemeral session with caching and cookies off, and reads the token
back from a configurable key path. Field names are mapped, so it fits VGS inbound routes, Basis
Theory, Evervault, Skyflow, or a payment provider's client-side tokenisation API:

```swift
let tokenizer = HTTPTokenizer(
    url: URL(string: "https://vault.example.com/v1/tokens")!,
    headers: ["Authorization": "Bearer pk_live_…"],
    mapping: .init(number: "card.number", expiryMonth: "card.exp_month",
                   expiryYear: "card.exp_year", securityCode: "card.cvc"),
    tokenPath: "data.id"
)
```

A custom `URLSession` takes responsibility for redirects, credentials, certificate trust and caching. Refuse redirects outside the original HTTPS origin. For a provider SDK that does not speak
JSON, implement `CardTokenizer` yourself; `form.makeCardData()` gives you a `SecureCardData` whose
number is only reachable inside `withNumber { }`, which keeps every access point easy to find in
code review.

## PCI DSS scope

Identify every component that handles plaintext, can decrypt it or can change the client that captures it. This includes the scanner callback and any custom tokenizer. Review the actual deployment with your acquirer or assessor. The SDK has no assessed SAQ eligibility. [PCI SSC guidance on outsourced processing](https://www.pcisecuritystandards.org/faqs/1092/)

The form clears its CVC field when tokenization succeeds. Call `form.clear()` when leaving checkout. After a failed request the fields remain available for correction. Exclude card data from persistent storage and diagnostics. PCI DSS prohibits merchants from retaining the CVC after authorization, including encrypted copies. [PCI SSC FAQ 1280](https://www.pcisecuritystandards.org/faqs/1280/)

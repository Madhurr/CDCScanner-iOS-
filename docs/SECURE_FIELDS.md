# CDCSecureFields: card entry reference

Everything about the hardened entry fields, the form, `SecureCardData` and the plain HTTPS
tokenizer. For the attested, field-encrypted mode see [ZERO_TRUST.md](ZERO_TRUST.md); for the
security model see the README.

`CDCSecureFields` is an open alternative to hosted-field SDKs such as VGS Collect. The fields
collect the card number, expiry, security code and name, and hand the data straight to a
tokeniser. Your view controllers, view models and servers only ever see a token, the brand, the
BIN and the last four digits.

## What the fields do that a `UITextField` does not

| Protection | Detail |
|---|---|
| No `text` on the public API | The number is unreachable from host code. Observe `numberState` (brand, validity, BIN, last four) instead. |
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

Pass your own `URLSession` to add certificate pinning. For a provider SDK that does not speak
JSON, implement `CardTokenizer` yourself; `form.makeCardData()` gives you a `SecureCardData` whose
number is only reachable inside `withNumber { }`, which keeps every access point easy to find in
code review.

## What this does and does not do for PCI DSS

A text field cannot make an app compliant. What reduces your scope is the data flow: when the PAN
goes from the field directly to a PCI DSS certified vault or payment provider and only a token
reaches your backend, your servers never store, process or transmit cardholder data, which is
what lets most merchants attest with SAQ A or SAQ A-EP rather than SAQ D. `CDCSecureFields`
gives you the client half of that design and keeps the number out of your app's code paths. The
vault, the attestation and the rest of the controls remain yours.

The security code is cleared from the field after a successful `tokenize`, because PCI DSS
forbids retaining it after authorisation. Expiry and cardholder name may be stored and are
exposed directly.


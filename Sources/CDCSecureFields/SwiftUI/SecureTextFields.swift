#if os(iOS)
import CDCCore
import SwiftUI

/// SwiftUI wrapper for ``SecureCardNumberField``.
///
/// ```swift
/// @StateObject private var form = SecureCardForm()
///
/// var body: some View {
///     VStack {
///         SecureCardNumberTextField(form: form, placeholder: "Card number")
///         HStack {
///             SecureExpiryTextField(form: form, placeholder: "MM/YY")
///             SecureCVCTextField(form: form, placeholder: "CVC")
///         }
///         Button("Pay") { Task { try await form.tokenize(using: tokenizer) } }
///             .disabled(!form.isComplete)
///     }
/// }
/// ```
public struct SecureCardNumberTextField: UIViewRepresentable {
    public var form: SecureCardForm?
    public var placeholder: String?
    public var appearance: SecureFieldAppearance
    public var pastePolicy: PastePolicy
    public var masksNumberWhenInactive: Bool
    public var brandImageProvider: ((CardBrand?) -> UIImage?)?
    public var onStateChange: ((CardNumberState) -> Void)?

    public init(
        form: SecureCardForm? = nil,
        placeholder: String? = nil,
        appearance: SecureFieldAppearance = .default,
        pastePolicy: PastePolicy = .sanitized,
        masksNumberWhenInactive: Bool = false,
        brandImageProvider: ((CardBrand?) -> UIImage?)? = nil,
        onStateChange: ((CardNumberState) -> Void)? = nil
    ) {
        self.form = form
        self.placeholder = placeholder
        self.appearance = appearance
        self.pastePolicy = pastePolicy
        self.masksNumberWhenInactive = masksNumberWhenInactive
        self.brandImageProvider = brandImageProvider
        self.onStateChange = onStateChange
    }

    public func makeUIView(context: Context) -> SecureCardNumberField {
        let field = SecureCardNumberField()
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        form?.attach(field)
        return field
    }

    public func updateUIView(_ field: SecureCardNumberField, context: Context) {
        field.placeholder = placeholder
        field.appearance = appearance
        field.pastePolicy = pastePolicy
        field.masksNumberWhenInactive = masksNumberWhenInactive
        field.brandImageProvider = brandImageProvider
        field.onStateChange = onStateChange
    }
}

/// SwiftUI wrapper for ``SecureExpiryField``.
public struct SecureExpiryTextField: UIViewRepresentable {
    public var form: SecureCardForm?
    public var placeholder: String?
    public var appearance: SecureFieldAppearance
    public var onStateChange: ((ExpiryFieldState) -> Void)?

    public init(
        form: SecureCardForm? = nil,
        placeholder: String? = "MM/YY",
        appearance: SecureFieldAppearance = .default,
        onStateChange: ((ExpiryFieldState) -> Void)? = nil
    ) {
        self.form = form
        self.placeholder = placeholder
        self.appearance = appearance
        self.onStateChange = onStateChange
    }

    public func makeUIView(context: Context) -> SecureExpiryField {
        let field = SecureExpiryField()
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        form?.attach(field)
        return field
    }

    public func updateUIView(_ field: SecureExpiryField, context: Context) {
        field.placeholder = placeholder
        field.appearance = appearance
        field.onStateChange = onStateChange
    }
}

/// SwiftUI wrapper for ``SecureCVCField``. Attach the same `form` as the number field so the
/// accepted length follows the detected brand.
public struct SecureCVCTextField: UIViewRepresentable {
    public var form: SecureCardForm?
    public var placeholder: String?
    public var appearance: SecureFieldAppearance
    public var obscuresDigits: Bool
    public var onStateChange: ((CVCFieldState) -> Void)?

    public init(
        form: SecureCardForm? = nil,
        placeholder: String? = "CVC",
        appearance: SecureFieldAppearance = .default,
        obscuresDigits: Bool = false,
        onStateChange: ((CVCFieldState) -> Void)? = nil
    ) {
        self.form = form
        self.placeholder = placeholder
        self.appearance = appearance
        self.obscuresDigits = obscuresDigits
        self.onStateChange = onStateChange
    }

    public func makeUIView(context: Context) -> SecureCVCField {
        let field = SecureCVCField()
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        form?.attach(field)
        return field
    }

    public func updateUIView(_ field: SecureCVCField, context: Context) {
        field.placeholder = placeholder
        field.appearance = appearance
        field.obscuresDigits = obscuresDigits
        field.onStateChange = onStateChange
    }
}

/// SwiftUI wrapper for ``CardholderNameField``.
public struct CardholderNameTextField: UIViewRepresentable {
    public var form: SecureCardForm?
    public var placeholder: String?
    public var appearance: SecureFieldAppearance
    public var onNameChange: ((String) -> Void)?

    public init(
        form: SecureCardForm? = nil,
        placeholder: String? = "Name on card",
        appearance: SecureFieldAppearance = .default,
        onNameChange: ((String) -> Void)? = nil
    ) {
        self.form = form
        self.placeholder = placeholder
        self.appearance = appearance
        self.onNameChange = onNameChange
    }

    public func makeUIView(context: Context) -> CardholderNameField {
        let field = CardholderNameField()
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        form?.attach(field)
        return field
    }

    public func updateUIView(_ field: CardholderNameField, context: Context) {
        field.placeholder = placeholder
        field.appearance = appearance
        field.onNameChange = onNameChange
    }
}
#endif

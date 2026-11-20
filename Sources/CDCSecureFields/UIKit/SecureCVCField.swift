#if os(iOS)
import CDCCore
import UIKit

/// A text field for the card security code (CVC, CVV, CID).
///
/// Link it to a ``SecureCardNumberField`` so the accepted length follows the detected brand:
/// four digits for American Express, three for everything else. The code is never exposed and,
/// per PCI DSS, must never be stored anywhere after authorisation.
@MainActor
public final class SecureCVCField: SecureField {
    public private(set) var state: CVCFieldState = .empty
    public var onStateChange: ((CVCFieldState) -> Void)?

    /// The number field whose brand decides the expected length.
    public weak var cardNumberField: SecureCardNumberField? {
        didSet { brandProvider = { [weak self] in self?.cardNumberField?.state.brand } }
    }

    /// Show bullets instead of digits. Default `false`, because the code is short and users
    /// typically read it off the card while typing.
    public var obscuresDigits = false {
        didSet { textField.isSecureTextEntry = obscuresDigits }
    }

    var brandProvider: (() -> CardBrand?)? {
        didSet { setRawValue(rawValue, caretAtEnd: true) }
    }

    private var brand: CardBrand? { brandProvider?() }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        textField.keyboardType = .asciiCapableNumberPad
        if #available(iOS 17.0, *) {
            textField.textContentType = .creditCardSecurityCode
        }
        textField.accessibilityLabel = NSLocalizedString("Security code", comment: "Accessibility label")
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Secure fields do not support storyboards; create them in code.")
    }

    func collectCode() -> String? {
        rawValue.isEmpty ? nil : rawValue
    }

    override func normalize(_ value: String) -> String {
        String(value.prefix(CVCRules.length(for: brand)))
    }

    override var keepsCaretAtEnd: Bool { true }

    override var showsInvalidState: Bool {
        !state.isEmpty && !state.isComplete && !isEditing
    }

    override func accessibilityValueForCurrentValue() -> String? {
        guard !rawValue.isEmpty else { return nil }
        let format = NSLocalizedString("%d digits entered", comment: "VoiceOver: partial security code")
        return String(format: format, rawValue.count)
    }

    override func valueDidChange() {
        let newState = CVCRules.state(digits: rawValue, brand: brand)
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }

    /// Re-evaluates completeness after the linked number field's brand changed.
    func brandDidChange() {
        setRawValue(rawValue, caretAtEnd: true)
    }
}
#endif

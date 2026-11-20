#if os(iOS)
import CDCCore
import UIKit

/// A hardened text field for the card number (PAN).
///
/// The number never leaves the field through the public API. Observe ``state`` for the brand,
/// validity, BIN and last four, and hand the field to a ``SecureCardForm`` to tokenise.
///
/// ```swift
/// let numberField = SecureCardNumberField()
/// numberField.placeholder = "Card number"
/// numberField.onStateChange = { state in
///     brandIcon.image = icon(for: state.brand)
///     payButton.isEnabled = state.isValid
/// }
/// ```
@MainActor
public final class SecureCardNumberField: SecureField {
    /// What the host app may know about the number. Updated on every keystroke.
    public private(set) var state: CardNumberState = .empty

    /// Called whenever ``state`` changes.
    public var onStateChange: ((CardNumberState) -> Void)?

    /// The brands accepted. Numbers of other brands are reported as invalid.
    public var brandRules: [CardBrandRule] = CardBrandRule.defaults {
        didSet {
            formatter.rules = brandRules
            setRawValue(rawValue, caretAtEnd: true)
        }
    }

    /// Show only the last four digits while the field is not being edited. Default `false`.
    public var masksNumberWhenInactive = false {
        didSet { if !isEditing { textField.text = inactiveDisplay(for: rawValue) } }
    }

    /// Supplies a brand image for the trailing accessory. Return `nil` for no image.
    /// The SDK ships no brand artwork; provide your own, licensed assets.
    public var brandImageProvider: ((CardBrand?) -> UIImage?)? {
        didSet { updateBrandImage() }
    }

    private var formatter = CardNumberFormatter()
    private let brandImageView = UIImageView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        textField.keyboardType = .asciiCapableNumberPad
        textField.textContentType = .creditCardNumber
        textField.accessibilityLabel = NSLocalizedString("Card number", comment: "Accessibility label")
        brandImageView.contentMode = .scaleAspectFit
        brandImageView.tintColor = appearance.placeholderColor
        brandImageView.isAccessibilityElement = false
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Secure fields do not support storyboards; create them in code.")
    }

    /// Fills the field from a scan or another trusted source. The value is sanitised like typed input.
    public func setNumber(_ number: String) {
        setRawValue(number, caretAtEnd: true)
    }

    /// The number, for the form and tokenizers in this module only.
    func collectNumber() -> String { rawValue }

    // MARK: Hooks

    override func normalize(_ value: String) -> String {
        String(value.prefix(brandRules.maxLength(forPrefix: value)))
    }

    override func display(for value: String) -> String {
        formatter.format(value)
    }

    override func inactiveDisplay(for value: String) -> String {
        guard masksNumberWhenInactive, value.count > 4 else { return display(for: value) }
        let masked = String(repeating: "•", count: value.count - 4) + value.suffix(4)
        // Group the bullets the same way as the digits for a stable width.
        let groups = CardNumberFormatter.groups(for: state.brand, length: value.count)
        var result = ""
        var index = masked.startIndex
        for (position, size) in groups.enumerated() where index < masked.endIndex {
            let end = masked.index(index, offsetBy: size, limitedBy: masked.endIndex) ?? masked.endIndex
            if position > 0 { result.append(" ") }
            result.append(contentsOf: masked[index..<end])
            index = end
        }
        if index < masked.endIndex { result.append(" " + masked[index...]) }
        return result
    }

    override func isSignificant(_ character: Character) -> Bool {
        character.isNumber || character == "•"
    }

    override var showsInvalidState: Bool {
        !state.isEmpty && !state.isPotentiallyValid
    }

    override func accessibilityValueForCurrentValue() -> String? {
        guard !rawValue.isEmpty else { return nil }
        if let lastFour = state.lastFour {
            let format = NSLocalizedString("%@ ending in %@", comment: "VoiceOver: card brand and last four digits")
            return String(format: format, state.brand?.displayName ?? NSLocalizedString("Card", comment: ""), lastFour.map(String.init).joined(separator: " "))
        }
        let format = NSLocalizedString("%d digits entered", comment: "VoiceOver: partial card number")
        return String(format: format, rawValue.count)
    }

    override func valueDidChange() {
        let newState = CardNumberState(digits: rawValue, rules: brandRules)
        guard newState != state else { return }
        state = newState
        updateBrandImage()
        onStateChange?(newState)
    }

    private func updateBrandImage() {
        guard let provider = brandImageProvider else {
            textField.rightView = nil
            textField.rightViewMode = .never
            return
        }
        brandImageView.image = provider(state.brand)
        if brandImageView.image != nil {
            brandImageView.frame = CGRect(x: 0, y: 0, width: 32, height: 20)
            textField.rightView = brandImageView
            textField.rightViewMode = .always
        } else {
            textField.rightView = nil
            textField.rightViewMode = .never
        }
    }
}
#endif

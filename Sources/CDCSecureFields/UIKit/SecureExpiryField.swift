#if os(iOS)
import CDCCore
import UIKit

/// A text field for the expiry date, formatted as `MM/YY` while typing.
@MainActor
public final class SecureExpiryField: SecureField {
    public private(set) var state: ExpiryFieldState = .empty
    public var onStateChange: ((ExpiryFieldState) -> Void)?

    private let formatter = ExpiryInputFormatter()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        textField.keyboardType = .asciiCapableNumberPad
        if #available(iOS 17.0, *) {
            textField.textContentType = .creditCardExpiration
        }
        textField.accessibilityLabel = NSLocalizedString("Expiry date", comment: "Accessibility label")
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Secure fields do not support storyboards; create them in code.")
    }

    /// Fills the field from a scan or another trusted source.
    public func setExpiry(_ expiry: CardExpiry) {
        setRawValue(String(format: "%02d%02d", expiry.month, expiry.year % 100), caretAtEnd: true)
    }

    func collectExpiry() -> CardExpiry? {
        formatter.expiry(from: rawValue)
    }

    override func normalize(_ value: String) -> String {
        formatter.digits(from: value)
    }

    override func display(for value: String) -> String {
        formatter.format(value)
    }

    override var keepsCaretAtEnd: Bool { true }

    override var showsInvalidState: Bool {
        state.isComplete && !state.isValid
    }

    override func accessibilityValueForCurrentValue() -> String? {
        state.expiry?.formatted ?? (rawValue.isEmpty ? nil : display(for: rawValue))
    }

    override func valueDidChange() {
        let newState = formatter.state(for: rawValue)
        guard newState != state else { return }
        state = newState
        onStateChange?(newState)
    }
}
#endif

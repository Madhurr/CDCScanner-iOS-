#if os(iOS)
import UIKit

/// A text field for the cardholder name, with the same hardening as the other fields.
///
/// PCI DSS allows the name to be stored, so unlike the other fields it exposes its ``name``.
@MainActor
public final class CardholderNameField: SecureField {
    /// The trimmed name.
    public var name: String {
        get { rawValue.trimmingCharacters(in: .whitespaces) }
        set { setRawValue(newValue, caretAtEnd: true) }
    }

    public var onNameChange: ((String) -> Void)?

    /// Maximum number of characters. Default 26, the ISO/IEC 7813 track-1 name field width.
    public var maximumLength = 26

    public override init(frame: CGRect) {
        super.init(frame: frame)
        textField.keyboardType = .asciiCapable
        textField.textContentType = .name
        textField.autocapitalizationType = .words
        textField.accessibilityLabel = NSLocalizedString("Name on card", comment: "Accessibility label")
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Secure fields do not support storyboards; create them in code.")
    }

    override func sanitize(_ input: String) -> String {
        input.filter { $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" || $0 == "." }
    }

    override func normalize(_ value: String) -> String {
        String(value.prefix(maximumLength))
    }

    override func isSignificant(_ character: Character) -> Bool { true }

    override func accessibilityValueForCurrentValue() -> String? {
        name.isEmpty ? nil : name
    }

    override func valueDidChange() {
        onNameChange?(name)
    }
}
#endif

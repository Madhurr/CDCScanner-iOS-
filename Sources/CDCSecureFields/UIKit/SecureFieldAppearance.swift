#if os(iOS)
import UIKit

/// Visual styling shared by the secure fields.
public struct SecureFieldAppearance {
    public var font: UIFont
    public var textColor: UIColor
    public var placeholderColor: UIColor
    public var backgroundColor: UIColor
    public var borderColor: UIColor
    public var focusedBorderColor: UIColor
    public var invalidBorderColor: UIColor
    public var borderWidth: CGFloat
    public var cornerRadius: CGFloat
    public var contentInsets: UIEdgeInsets
    public var textAlignment: NSTextAlignment
    /// Colour of the content shown while the field is covered (app switcher, screen recording).
    public var privacyCoverColor: UIColor

    public init(
        font: UIFont = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .placeholderText,
        backgroundColor: UIColor = .secondarySystemBackground,
        borderColor: UIColor = .separator,
        focusedBorderColor: UIColor = .systemBlue,
        invalidBorderColor: UIColor = .systemRed,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 10,
        contentInsets: UIEdgeInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14),
        textAlignment: NSTextAlignment = .natural,
        privacyCoverColor: UIColor = .secondaryLabel
    ) {
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.focusedBorderColor = focusedBorderColor
        self.invalidBorderColor = invalidBorderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.contentInsets = contentInsets
        self.textAlignment = textAlignment
        self.privacyCoverColor = privacyCoverColor
    }

    public static let `default` = SecureFieldAppearance()

    /// No background or border; for embedding in your own container.
    public static let plain = SecureFieldAppearance(
        backgroundColor: .clear,
        borderColor: .clear,
        focusedBorderColor: .clear,
        invalidBorderColor: .clear,
        borderWidth: 0,
        cornerRadius: 0,
        contentInsets: .zero
    )
}
#endif

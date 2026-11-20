#if os(iOS)
import UIKit

/// The `UITextField` inside every secure field. Not exposed to host apps.
///
/// Blocks copy, cut, share, look-up and selection actions, tracks paste so the owning field can
/// apply its ``PastePolicy``, and reports a redacted value to assistive technologies.
@MainActor
final class HardenedTextField: UITextField {
    var pastePolicy: PastePolicy = .sanitized
    var accessibilityValueProvider: (() -> String?)?
    private(set) var isPasting = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        autocorrectionType = .no
        spellCheckingType = .no
        smartDashesType = .no
        smartQuotesType = .no
        smartInsertDeleteType = .no
        autocapitalizationType = .none
        clearButtonMode = .never
        adjustsFontForContentSizeCategory = true
        // Dictation and the camera text capture button would route the number through other
        // system components; the number pad has neither, but be explicit for other keyboards.
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HardenedTextField does not support storyboards.")
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return pastePolicy != .disabled && UIPasteboard.general.hasStrings
        }
        // Everything else (copy, cut, select, selectAll, share, look up, translate, define,
        // capture text from camera, text style options) is refused.
        return false
    }

    override func paste(_ sender: Any?) {
        guard pastePolicy != .disabled else { return }
        isPasting = true
        super.paste(sender)
        isPasting = false
    }

    override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        // Keep only a paste action when allowed; never offer copy or share.
        guard pastePolicy != .disabled, UIPasteboard.general.hasStrings else { return nil }
        let paste = UIAction(title: NSLocalizedString("Paste", comment: "Edit menu")) { [weak self] _ in
            self?.paste(nil)
        }
        return UIMenu(children: [paste])
    }

    override var accessibilityValue: String? {
        get { accessibilityValueProvider?() ?? super.accessibilityValue }
        set { super.accessibilityValue = newValue }
    }
}
#endif

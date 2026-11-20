#if os(iOS)
import CDCCore
import UIKit

/// Base class for the secure entry fields. Use ``SecureCardNumberField``, ``SecureExpiryField``,
/// ``SecureCVCField`` or ``CardholderNameField``; this class is not useful on its own.
///
/// What every field does to keep card data inside the SDK boundary:
/// - The underlying text field is private. There is no `text` property on the public API.
/// - Copy, cut, share, look-up and selection are blocked. Paste follows ``pastePolicy``.
/// - Autocorrection, predictive text and spell checking are off so the keyboard does not learn the value.
/// - The contents are covered while the app is inactive (app switcher snapshot) and while the
///   screen is being recorded or mirrored.
/// - VoiceOver reads a redacted value.
/// - The field is excluded from state restoration.
@MainActor
open class SecureField: UIControl {
    /// Visual styling.
    public var appearance: SecureFieldAppearance = .default {
        didSet { applyAppearance() }
    }

    public var placeholder: String? {
        didSet { applyAppearance() }
    }

    /// What happens when the user pastes. Default ``PastePolicy/sanitized``.
    public var pastePolicy: PastePolicy = .sanitized {
        didSet { textField.pastePolicy = pastePolicy }
    }

    /// Cover the contents when the app resigns active, so the app-switcher snapshot does not show
    /// the number. Default `true`.
    public var obscuresWhenAppIsInactive = true

    /// Cover the contents while the screen is recorded, mirrored or shared. Default `true`.
    public var obscuresDuringScreenCapture = true {
        didSet { updatePrivacyCover() }
    }

    /// Called when the user takes a screenshot while this field is on screen. iOS does not allow
    /// preventing the screenshot; use this to warn the user or log a security event.
    public var onScreenshotTaken: (() -> Void)?

    /// Called whenever editing begins or ends.
    public var onEditingChanged: ((_ isEditing: Bool) -> Void)?

    public var keyboardAppearance: UIKeyboardAppearance {
        get { textField.keyboardAppearance }
        set { textField.keyboardAppearance = newValue }
    }

    public var returnKeyType: UIReturnKeyType {
        get { textField.returnKeyType }
        set { textField.returnKeyType = newValue }
    }

    /// Called when the return key is tapped. Return `true` to dismiss the keyboard.
    public var onReturn: (() -> Bool)?

    public override var isEnabled: Bool {
        didSet {
            textField.isEnabled = isEnabled
            alpha = isEnabled ? 1 : 0.5
        }
    }

    public var isEditing: Bool { textField.isEditing }
    public var isEmpty: Bool { rawValue.isEmpty }

    // MARK: Internals shared with subclasses

    let textField = HardenedTextField()
    /// The canonical value: digits for card fields, trimmed text for the name field.
    private(set) var rawValue = ""
    /// Set by ``SecureCardForm`` to be told about changes.
    var formCallback: (() -> Void)?

    private let privacyCover = PrivacyCoverView()
    private var observers: [NSObjectProtocol] = []
    private var isCoveredForInactivity = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Secure fields do not support storyboards; create them in code.")
    }

    // MARK: Hooks for subclasses

    /// Keep only the characters that belong in the value. Default: digits.
    func sanitize(_ input: String) -> String {
        input.filter(\.isNumber)
    }

    /// Enforce a maximum length or other normalisation on the whole value. Default: unchanged.
    func normalize(_ value: String) -> String {
        value
    }

    /// The text shown while editing. Default: the value.
    func display(for value: String) -> String {
        value
    }

    /// The text shown when not editing. Default: same as while editing.
    func inactiveDisplay(for value: String) -> String {
        display(for: value)
    }

    /// Whether `character` in a displayed string corresponds to a character of the value.
    func isSignificant(_ character: Character) -> Bool {
        character.isNumber
    }

    /// Whether the caret should always sit at the end after an edit.
    var keepsCaretAtEnd: Bool { false }

    /// The redacted value read by VoiceOver.
    func accessibilityValueForCurrentValue() -> String? {
        rawValue.isEmpty ? nil : NSLocalizedString("Entered", comment: "VoiceOver value for a secure field with content")
    }

    /// Whether to draw the invalid border right now.
    var showsInvalidState: Bool { false }

    /// Called after the value changed. Subclasses update their state and notify.
    func valueDidChange() {}

    // MARK: Public control

    /// Removes the contents.
    public func clear() {
        setRawValue("", caretAtEnd: true)
    }

    /// Replaces the contents programmatically, for example from a card scan. Sanitised like typed input.
    func setRawValue(_ value: String, caretAtEnd: Bool) {
        rawValue = normalize(sanitize(value))
        textField.text = textField.isEditing ? display(for: rawValue) : inactiveDisplay(for: rawValue)
        if caretAtEnd, let end = textField.position(from: textField.endOfDocument, offset: 0) {
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }
        valueDidChange()
        updateBorder()
        formCallback?()
        sendActions(for: .valueChanged)
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        textField.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        textField.resignFirstResponder()
    }

    public override var canBecomeFirstResponder: Bool { textField.canBecomeFirstResponder }
    public override var isFirstResponder: Bool { textField.isFirstResponder }

    public override var intrinsicContentSize: CGSize {
        let insets = appearance.contentInsets
        let height = ceil(appearance.font.lineHeight) + insets.top + insets.bottom
        return CGSize(width: UIView.noIntrinsicMetric, height: max(height, 44))
    }

    // MARK: Lifecycle

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopObserving() : startObserving()
        updatePrivacyCover()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let insets = appearance.contentInsets
        textField.frame = bounds.inset(by: insets)
        privacyCover.frame = bounds
        layer.cornerRadius = appearance.cornerRadius
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearance()
    }

    // MARK: Setup

    private func setUp() {
        restorationIdentifier = nil
        isAccessibilityElement = false
        clipsToBounds = true

        textField.delegate = self
        textField.pastePolicy = pastePolicy
        textField.accessibilityValueProvider = { [weak self] in self?.accessibilityValueForCurrentValue() }
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        textField.addTarget(self, action: #selector(editingBegan), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(editingEnded), for: .editingDidEnd)
        addSubview(textField)

        privacyCover.isHidden = true
        privacyCover.isUserInteractionEnabled = false
        addSubview(privacyCover)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applyAppearance()
    }

    private func applyAppearance() {
        backgroundColor = appearance.backgroundColor
        layer.cornerRadius = appearance.cornerRadius
        layer.borderWidth = appearance.borderWidth
        layer.cornerCurve = .continuous
        textField.font = appearance.font
        textField.textColor = appearance.textColor
        textField.tintColor = appearance.focusedBorderColor
        textField.textAlignment = appearance.textAlignment
        textField.attributedPlaceholder = placeholder.map {
            NSAttributedString(string: $0, attributes: [.foregroundColor: appearance.placeholderColor, .font: appearance.font])
        }
        privacyCover.coverColor = appearance.privacyCoverColor
        privacyCover.backgroundColor = appearance.backgroundColor
        updateBorder()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func updateBorder() {
        if textField.isEditing {
            layer.borderColor = appearance.focusedBorderColor.cgColor
        } else if showsInvalidState {
            layer.borderColor = appearance.invalidBorderColor.cgColor
        } else {
            layer.borderColor = appearance.borderColor.cgColor
        }
    }

    // MARK: Events

    @objc private func tapped() {
        _ = becomeFirstResponder()
    }

    @objc private func editingBegan() {
        textField.text = display(for: rawValue)
        updateBorder()
        onEditingChanged?(true)
        sendActions(for: .editingDidBegin)
    }

    @objc private func editingEnded() {
        textField.text = inactiveDisplay(for: rawValue)
        updateBorder()
        onEditingChanged?(false)
        sendActions(for: .editingDidEnd)
    }

    /// Safety net for changes that bypass `shouldChangeCharactersIn`, such as some autofill paths.
    @objc private func editingChanged() {
        let shown = textField.text ?? ""
        if shown != display(for: rawValue) {
            setRawValue(shown, caretAtEnd: true)
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.obscuresWhenAppIsInactive else { return }
                    self.isCoveredForInactivity = true
                    self.updatePrivacyCover()
                }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isCoveredForInactivity = false
                    self?.updatePrivacyCover()
                }
            },
            center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePrivacyCover() }
            },
            center.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onScreenshotTaken?() }
            },
        ]
    }

    private func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func updatePrivacyCover() {
        let captured = obscuresDuringScreenCapture && (window?.screen.isCaptured ?? false)
        let shouldCover = !rawValue.isEmpty && (captured || isCoveredForInactivity)
        privacyCover.isHidden = !shouldCover
        textField.isHidden = shouldCover
    }
}

// MARK: - UITextFieldDelegate

extension SecureField: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if self.textField.isPasting && pastePolicy == .disabled {
            return false
        }

        let current = (textField.text ?? "") as NSString
        guard range.location + range.length <= current.length else { return false }

        let before = current.substring(to: range.location)
        let inRange = current.substring(with: range)
        let startOffset = before.filter(isSignificant).count
        let removedCount = inRange.filter(isSignificant).count

        var value = Array(rawValue)
        var caret: Int
        if string.isEmpty, removedCount == 0, range.length > 0, startOffset > 0 {
            // Backspace over a separator deletes the character before it.
            value.remove(at: startOffset - 1)
            caret = startOffset - 1
        } else {
            let inserted = Array(sanitize(string))
            let end = min(startOffset + removedCount, value.count)
            value.replaceSubrange(startOffset..<end, with: inserted)
            caret = startOffset + inserted.count
        }

        let newValue = normalize(String(value))
        caret = min(caret, newValue.count)
        rawValue = newValue
        let shown = display(for: newValue)
        textField.text = shown

        let caretOffset = keepsCaretAtEnd ? shown.count : formattedOffset(forSignificantOffset: caret, in: shown)
        if let position = textField.position(from: textField.beginningOfDocument, offset: caretOffset) {
            textField.selectedTextRange = textField.textRange(from: position, to: position)
        }

        valueDidChange()
        updateBorder()
        formCallback?()
        sendActions(for: .valueChanged)
        sendActions(for: .editingChanged)
        return false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let onReturn { return onReturn() ? textField.resignFirstResponder() : false }
        return textField.resignFirstResponder()
    }

    private func formattedOffset(forSignificantOffset target: Int, in shown: String) -> Int {
        guard target > 0 else { return 0 }
        var seen = 0
        for (index, character) in shown.enumerated() where isSignificant(character) {
            seen += 1
            if seen == target { return index + 1 }
        }
        return shown.count
    }
}

/// Drawn over the field while the app is inactive or the screen is being captured.
@MainActor
private final class PrivacyCoverView: UIView {
    var coverColor: UIColor = .secondaryLabel {
        didSet { label.textColor = coverColor }
    }

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.text = "••••"
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = coverColor
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}
#endif

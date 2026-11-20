#if os(iOS)
import CDCCore
import Combine
import Foundation

/// Ties the secure fields together, tracks completeness and performs tokenisation.
///
/// ```swift
/// let form = SecureCardForm()
/// form.attach(numberField: numberField, expiryField: expiryField, cvcField: cvcField)
///
/// form.$isComplete
///     .assign(to: \.isEnabled, on: payButton)
///
/// let token = try await form.tokenize(using: tokenizer)
/// ```
///
/// The form is the only component that reads the fields' values, and it only does so inside
/// ``tokenize(using:)`` and ``makeCardData()``.
@MainActor
public final class SecureCardForm: ObservableObject {
    @Published public private(set) var numberState: CardNumberState = .empty
    @Published public private(set) var expiryState: ExpiryFieldState = .empty
    @Published public private(set) var cvcState: CVCFieldState = .empty
    @Published public private(set) var cardholderName = ""
    /// `true` when every required field is valid.
    @Published public private(set) var isComplete = false

    public var requiresExpiry = true { didSet { recompute() } }
    public var requiresCVC = true { didSet { recompute() } }
    public var requiresCardholderName = false { didSet { recompute() } }

    /// Brands accepted by the attached number field.
    public var brandRules: [CardBrandRule] {
        didSet { numberField?.brandRules = brandRules }
    }

    public private(set) weak var numberField: SecureCardNumberField?
    public private(set) weak var expiryField: SecureExpiryField?
    public private(set) weak var cvcField: SecureCVCField?
    public private(set) weak var nameField: CardholderNameField?

    public init(brandRules: [CardBrandRule] = CardBrandRule.defaults) {
        self.brandRules = brandRules
    }

    // MARK: Attaching fields

    public func attach(
        numberField: SecureCardNumberField? = nil,
        expiryField: SecureExpiryField? = nil,
        cvcField: SecureCVCField? = nil,
        nameField: CardholderNameField? = nil
    ) {
        if let numberField { attach(numberField) }
        if let expiryField { attach(expiryField) }
        if let cvcField { attach(cvcField) }
        if let nameField { attach(nameField) }
    }

    public func attach(_ field: SecureCardNumberField) {
        numberField = field
        field.brandRules = brandRules
        field.formCallback = { [weak self] in
            self?.cvcField?.brandDidChange()
            self?.recompute()
        }
        cvcField?.brandProvider = { [weak field] in field?.state.brand }
        recompute()
    }

    public func attach(_ field: SecureExpiryField) {
        expiryField = field
        field.formCallback = { [weak self] in self?.recompute() }
        recompute()
    }

    public func attach(_ field: SecureCVCField) {
        cvcField = field
        field.formCallback = { [weak self] in self?.recompute() }
        if let numberField {
            field.brandProvider = { [weak numberField] in numberField?.state.brand }
        }
        recompute()
    }

    public func attach(_ field: CardholderNameField) {
        nameField = field
        field.formCallback = { [weak self] in self?.recompute() }
        recompute()
    }

    // MARK: Actions

    /// Clears every attached field.
    public func clear() {
        numberField?.clear()
        expiryField?.clear()
        cvcField?.clear()
        nameField?.clear()
    }

    /// Moves focus to the first field that is not yet valid, if any.
    @discardableResult
    public func focusFirstInvalidField() -> Bool {
        if let numberField, !numberState.isValid { return numberField.becomeFirstResponder() }
        if requiresExpiry, let expiryField, !expiryState.isValid { return expiryField.becomeFirstResponder() }
        if requiresCVC, let cvcField, !cvcState.isComplete { return cvcField.becomeFirstResponder() }
        if requiresCardholderName, let nameField, cardholderName.isEmpty { return nameField.becomeFirstResponder() }
        return false
    }

    /// Collects the card data for a custom ``CardTokenizer``.
    ///
    /// Prefer ``tokenize(using:)``; call this only when you must hand the data to a provider SDK
    /// that does not fit the protocol. Throws ``TokenizationError/invalidCardData(_:)`` when a
    /// required field is not valid.
    public func makeCardData() throws -> SecureCardData {
        guard let numberField else { throw TokenizationError.invalidCardData("No card number field is attached.") }
        guard numberState.isValid else { throw TokenizationError.invalidCardData("The card number is not valid.") }
        if requiresExpiry, !expiryState.isValid { throw TokenizationError.invalidCardData("The expiry date is not valid.") }
        if requiresCVC, !cvcState.isComplete { throw TokenizationError.invalidCardData("The security code is incomplete.") }
        if requiresCardholderName, cardholderName.isEmpty { throw TokenizationError.invalidCardData("The cardholder name is missing.") }

        return SecureCardData(
            number: numberField.collectNumber(),
            expiry: expiryField?.collectExpiry(),
            securityCode: cvcField?.collectCode(),
            cardholderName: nameField?.name.nilIfEmpty,
            rules: brandRules
        )
    }

    /// Validates the fields, sends the card data to `tokenizer` and returns the token.
    ///
    /// On success the security code field is cleared, since PCI DSS forbids retaining it.
    public func tokenize(using tokenizer: some CardTokenizer) async throws -> CardToken {
        let card = try makeCardData()
        let token = try await tokenizer.tokenize(card)
        cvcField?.clear()
        return token
    }

    // MARK: State

    private func recompute() {
        numberState = numberField?.state ?? .empty
        expiryState = expiryField?.state ?? .empty
        cvcState = cvcField?.state ?? .empty
        cardholderName = nameField?.name ?? ""
        isComplete = numberState.isValid
            && (!requiresExpiry || expiryState.isValid)
            && (!requiresCVC || cvcState.isComplete)
            && (!requiresCardholderName || !cardholderName.isEmpty)
    }
}
#endif

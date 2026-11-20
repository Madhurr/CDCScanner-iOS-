import CDCCore
import Foundation

/// Everything a host app is allowed to know about the number in a ``SecureCardNumberField``.
///
/// The state is derived from the digits but never contains them. It is safe to log, bind to UI
/// and send to analytics.
public struct CardNumberState: Hashable, Sendable {
    /// Number of digits typed.
    public let length: Int
    /// The brand, once the typed prefix is unambiguous.
    public let brand: CardBrand?
    /// Every brand the typed prefix could still belong to.
    public let candidateBrands: [CardBrand]
    /// `true` when the number has an accepted length for its brand and passes the Luhn check.
    public let isValid: Bool
    /// `true` when more digits could still turn the number into a valid one.
    public let isPotentiallyValid: Bool
    /// The first six digits (the Bank Identification Number), available once typed.
    /// PCI DSS permits storing and displaying the BIN together with the last four digits.
    public let bin: String?
    /// The last four digits, available once the number is valid.
    public let lastFour: String?

    public var isEmpty: Bool { length == 0 }

    /// The expected CVC length for the detected brand: 4 for American Express, otherwise 3.
    public var cvcLength: Int { CVCRules.length(for: brand) }

    public init(digits: String, rules: [CardBrandRule] = CardBrandRule.defaults) {
        let clean = digits.filter(\.isNumber)
        length = clean.count
        candidateBrands = rules.candidateBrands(forPrefix: clean)
        brand = rules.detectedBrand(forPrefix: clean)

        let accepted = rules.acceptedLengths(forPrefix: clean)
        let luhnOK = Luhn.isValid(clean)
        isValid = !clean.isEmpty && accepted.contains(clean.count) && luhnOK && rules.brand(for: clean) != nil
        isPotentiallyValid = isValid || (!candidateBrands.isEmpty && clean.count < rules.maxLength(forPrefix: clean))
        bin = clean.count >= 6 ? String(clean.prefix(6)) : nil
        lastFour = isValid ? String(clean.suffix(4)) : nil
    }

    public static let empty = CardNumberState(digits: "")
}

extension CardNumberState: CustomStringConvertible {
    public var description: String {
        "CardNumberState(length: \(length), brand: \(brand.map(\.displayName) ?? "unknown"), valid: \(isValid))"
    }
}

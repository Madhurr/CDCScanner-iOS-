import CDCCore
import Foundation

/// Card data collected from the secure fields, on its way to a ``CardTokenizer``.
///
/// The type is deliberately awkward to misuse:
/// - It is not `Codable`, so it cannot be serialised by accident.
/// - `description` and `debugDescription` are redacted, so interpolating it into a log prints the
///   masked number.
/// - The PAN and security code are only reachable inside ``withNumber(_:)`` and
///   ``withSecurityCode(_:)``, which keeps the sensitive value's lifetime short and makes every
///   access point greppable in a code review.
public struct SecureCardData: Sendable {
    private let number: String
    private let securityCode: String?
    /// PCI DSS allows the expiry to be stored and displayed, so it is exposed directly.
    public let expiry: CardExpiry?
    /// PCI DSS allows the cardholder name to be stored and displayed, so it is exposed directly.
    public let cardholderName: String?
    /// The detected brand.
    public let brand: CardBrand?

    public init(number: String, expiry: CardExpiry?, securityCode: String?, cardholderName: String?, rules: [CardBrandRule] = CardBrandRule.defaults) {
        let digits = number.filter(\.isNumber)
        self.number = digits
        self.expiry = expiry
        self.securityCode = securityCode.map { $0.filter(\.isNumber) }.flatMap { $0.isEmpty ? nil : $0 }
        self.cardholderName = cardholderName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.brand = rules.brand(for: digits) ?? rules.detectedBrand(forPrefix: digits)
    }

    /// The first six digits.
    public var bin: String { String(number.prefix(6)) }
    /// The last four digits.
    public var lastFour: String { String(number.suffix(4)) }
    /// The number with all but the last four digits replaced by bullets.
    public var maskedNumber: String {
        String(repeating: "•", count: max(0, number.count - 4)) + lastFour
    }
    public var hasSecurityCode: Bool { securityCode != nil }

    /// Gives the full card number to `body` and returns its result.
    public func withNumber<T>(_ body: (String) throws -> T) rethrows -> T {
        try body(number)
    }

    /// Gives the security code to `body`, or `nil` to it when none was collected.
    public func withSecurityCode<T>(_ body: (String?) throws -> T) rethrows -> T {
        try body(securityCode)
    }
}

extension SecureCardData: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "SecureCardData(\(brand?.displayName ?? "unknown") \(maskedNumber), expiry: \(expiry?.formatted ?? "none"), cvc: \(hasSecurityCode ? "present" : "none"))"
    }

    public var debugDescription: String { description }

    /// Keeps the debugger's variable view and `dump()` from printing the number.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "brand": brand as Any,
            "maskedNumber": maskedNumber,
            "expiry": expiry as Any,
            "hasSecurityCode": hasSecurityCode,
            "cardholderName": cardholderName as Any,
        ])
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

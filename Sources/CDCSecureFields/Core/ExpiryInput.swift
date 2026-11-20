import CDCCore
import Foundation

/// Formats and validates expiry dates as they are typed.
public struct ExpiryInputFormatter: Sendable {
    public var separator: String
    public var calendar: Calendar
    /// How far in the future an expiry may be and still count as valid.
    public var maximumYearsAhead: Int

    public init(separator: String = "/", calendar: Calendar = Calendar(identifier: .gregorian), maximumYearsAhead: Int = 20) {
        self.separator = separator
        self.calendar = calendar
        self.maximumYearsAhead = maximumYearsAhead
    }

    /// Normalises typed digits into at most four digits (MMYY), fixing up single-digit months.
    ///
    /// Typing `3` becomes `03`; typing `1` waits for the next digit so `11` and `12` stay possible.
    public func digits(from input: String) -> String {
        var clean = String(input.filter(\.isNumber).prefix(4))
        if let first = clean.first, first > "1", clean.count >= 1 {
            clean.insert("0", at: clean.startIndex)
            clean = String(clean.prefix(4))
        }
        if clean.count >= 2, let month = Int(clean.prefix(2)), month == 0 || month > 12 {
            // Impossible month: keep only the first digit so the user can correct it.
            clean = String(clean.prefix(1))
        }
        return clean
    }

    /// Formats normalised digits as `MM/YY`.
    public func format(_ digits: String) -> String {
        let clean = self.digits(from: digits)
        guard clean.count > 2 else {
            return clean.count == 2 ? clean + separator : clean
        }
        return String(clean.prefix(2)) + separator + String(clean.dropFirst(2))
    }

    /// Parses complete input into an expiry, or `nil` while incomplete or invalid.
    public func expiry(from input: String) -> CardExpiry? {
        let clean = digits(from: input)
        guard clean.count == 4, let month = Int(clean.prefix(2)), let year = Int(clean.suffix(2)) else { return nil }
        return CardExpiry(month: month, year: year)
    }

    /// The state the field exposes.
    public func state(for input: String, now: Date = Date()) -> ExpiryFieldState {
        let clean = digits(from: input)
        guard let expiry = expiry(from: clean) else {
            return ExpiryFieldState(expiry: nil, isComplete: false, isValid: false, isEmpty: clean.isEmpty)
        }
        let currentYear = calendar.component(.year, from: now)
        let isValid = !expiry.isExpired(asOf: now, calendar: calendar) && expiry.year <= currentYear + maximumYearsAhead
        return ExpiryFieldState(expiry: expiry, isComplete: true, isValid: isValid, isEmpty: false)
    }
}

/// What a host app may know about the contents of a ``SecureExpiryField``.
public struct ExpiryFieldState: Hashable, Sendable {
    /// The expiry, once four digits have been typed. PCI DSS allows the expiry to be stored and
    /// displayed, so it is exposed in full.
    public let expiry: CardExpiry?
    public let isComplete: Bool
    /// Complete, not in the past and not unreasonably far ahead.
    public let isValid: Bool
    public let isEmpty: Bool

    public init(expiry: CardExpiry?, isComplete: Bool, isValid: Bool, isEmpty: Bool) {
        self.expiry = expiry
        self.isComplete = isComplete
        self.isValid = isValid
        self.isEmpty = isEmpty
    }

    public static let empty = ExpiryFieldState(expiry: nil, isComplete: false, isValid: false, isEmpty: true)
}

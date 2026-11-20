import Foundation

/// A card expiry month, such as `09/27`.
public struct CardExpiry: Hashable, Sendable, Codable, Comparable {
    /// Month of the year, 1 through 12.
    public let month: Int
    /// Four-digit year.
    public let year: Int

    /// Creates an expiry, or returns `nil` when the month is outside 1...12.
    ///
    /// Two-digit years are interpreted as 2000 through 2099.
    public init?(month: Int, year: Int) {
        guard (1...12).contains(month), year >= 0 else { return nil }
        self.month = month
        self.year = year < 100 ? 2000 + year : year
    }

    /// The expiry formatted as `MM/YY`.
    public var formatted: String {
        String(format: "%02d/%02d", month, year % 100)
    }

    /// The expiry formatted as `MM/YYYY`.
    public var formattedLong: String {
        String(format: "%02d/%04d", month, year)
    }

    /// The first instant after the card stops being valid, i.e. the start of the following month.
    public func expirationDate(in calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let start = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: start)
    }

    /// Whether the card has expired as of `date`.
    public func isExpired(asOf date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let end = expirationDate(in: calendar) else { return true }
        return date >= end
    }

    public static func < (lhs: CardExpiry, rhs: CardExpiry) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

extension CardExpiry: CustomStringConvertible {
    public var description: String { formatted }
}

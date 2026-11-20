import Foundation

/// Extracts expiry dates in `MM/YY` or `MM/YYYY` form from recognised text.
///
/// Cards often print more than one date, such as a "valid from" and a "valid thru". The parser
/// returns every plausible date and ``bestExpiry(in:)`` picks the latest one, which is the
/// expiry on every card layout in common use.
public struct ExpiryParser: Sendable {
    /// Dates earlier than this many years before the reference year are ignored.
    public var yearsInPast: Int
    /// Dates later than this many years after the reference year are ignored.
    public var yearsInFuture: Int
    /// The calendar used to work out the current year. Defaults to the Gregorian calendar.
    public var calendar: Calendar

    private static let pattern = #"(?<![0-9])(0[1-9]|1[0-2])\s*[/\-]\s*((?:20)?[0-9]{2})(?![0-9])"#
    private static let regex = try! NSRegularExpression(pattern: pattern)

    public init(yearsInPast: Int = 5, yearsInFuture: Int = 20, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.yearsInPast = yearsInPast
        self.yearsInFuture = yearsInFuture
        self.calendar = calendar
    }

    /// Returns every plausible expiry in `text`, latest first, without duplicates.
    public func parse(_ text: String, referenceDate: Date = Date()) -> [CardExpiry] {
        let currentYear = calendar.component(.year, from: referenceDate)
        let acceptedYears = (currentYear - yearsInPast)...(currentYear + yearsInFuture)

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var found: [CardExpiry] = []
        for result in Self.regex.matches(in: text, range: range) {
            guard result.numberOfRanges == 3,
                  let month = Int(nsText.substring(with: result.range(at: 1))),
                  let year = Int(nsText.substring(with: result.range(at: 2))),
                  let expiry = CardExpiry(month: month, year: year),
                  acceptedYears.contains(expiry.year),
                  !found.contains(expiry)
            else { continue }
            found.append(expiry)
        }
        return found.sorted(by: >)
    }

    /// Returns the latest plausible expiry in `text`, or `nil`.
    public func bestExpiry(in text: String, referenceDate: Date = Date()) -> CardExpiry? {
        parse(text, referenceDate: referenceDate).first
    }
}

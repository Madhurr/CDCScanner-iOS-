import CDCCore
import Foundation

/// Groups card digits the way they are printed on the card.
///
/// Formatting is a pure function of the digits typed so far and the detected brand, which keeps
/// the field's behaviour predictable and testable.
public struct CardNumberFormatter: Sendable {
    public var rules: [CardBrandRule]
    public var separator: Character

    public init(rules: [CardBrandRule] = CardBrandRule.defaults, separator: Character = " ") {
        self.rules = rules
        self.separator = separator
    }

    /// The group sizes used for a number of `length` digits of `brand`.
    public static func groups(for brand: CardBrand?, length: Int) -> [Int] {
        switch (brand, length) {
        case (.americanExpress, _), (.uatp, _):
            return [4, 6, 5]
        case (.dinersClub, 14):
            return [4, 6, 4]
        case (_, 13):
            return [4, 4, 5]
        case (_, 15):
            return [4, 6, 5]
        default:
            return Array(repeating: 4, count: max(1, (length + 3) / 4))
        }
    }

    /// Formats whatever has been typed so far. Non-digits in `digits` are ignored.
    public func format(_ digits: String) -> String {
        let clean = digits.filter(\.isNumber)
        guard !clean.isEmpty else { return "" }
        let brand = rules.detectedBrand(forPrefix: clean)
        let expectedLength = expectedLength(forPrefix: clean, brand: brand)
        let pattern = Self.groups(for: brand, length: expectedLength)

        var result = ""
        var index = clean.startIndex
        for (position, size) in pattern.enumerated() where index < clean.endIndex {
            let end = clean.index(index, offsetBy: size, limitedBy: clean.endIndex) ?? clean.endIndex
            if position > 0 { result.append(separator) }
            result.append(contentsOf: clean[index..<end])
            index = end
        }
        if index < clean.endIndex {
            // Longer than the pattern (e.g. 19-digit Visa typed past 16): keep grouping in fours.
            var remainder = clean[index...]
            while !remainder.isEmpty {
                result.append(separator)
                let end = remainder.index(remainder.startIndex, offsetBy: 4, limitedBy: remainder.endIndex) ?? remainder.endIndex
                result.append(contentsOf: remainder[remainder.startIndex..<end])
                remainder = remainder[end...]
            }
        }
        return result
    }

    /// The most likely final length for the digits typed so far.
    ///
    /// Prefers the shortest accepted length that the typed digits have not yet exceeded, so a Visa
    /// is grouped as 16 digits until a 17th digit is typed.
    public func expectedLength(forPrefix prefix: String, brand: CardBrand?) -> Int {
        let accepted: Set<Int>
        if let brand {
            accepted = rules.filter { $0.brand == brand }.reduce(into: Set<Int>()) { $0.formUnion($1.lengths) }
        } else {
            accepted = rules.acceptedLengths(forPrefix: prefix)
        }
        let candidates = accepted.filter { $0 >= prefix.count }.sorted()
        return candidates.first ?? accepted.max() ?? 16
    }

    /// Converts an offset into the formatted string into the number of digits before it.
    public func digitOffset(forFormattedOffset offset: Int, in formatted: String) -> Int {
        formatted.prefix(max(0, min(offset, formatted.count))).filter(\.isNumber).count
    }

    /// Converts a digit count into the matching caret position in the formatted string.
    public func formattedOffset(forDigitOffset digitOffset: Int, in formatted: String) -> Int {
        guard digitOffset > 0 else { return 0 }
        var seen = 0
        for (index, character) in formatted.enumerated() where character.isNumber {
            seen += 1
            if seen == digitOffset {
                return index + 1
            }
        }
        return formatted.count
    }
}

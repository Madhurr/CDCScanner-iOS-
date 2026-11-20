import Foundation

/// A card number found in recognised text, together with the brand it was matched to.
public struct CardNumberMatch: Hashable, Sendable {
    /// Digits only, no separators.
    public let number: String
    public let brand: CardBrand

    public init(number: String, brand: CardBrand) {
        self.number = number
        self.brand = brand
    }
}

/// Extracts valid card numbers from free text produced by OCR.
///
/// The parser is pure and has no dependency on the camera or VisionKit, so it can be unit
/// tested and reused for text from any source.
///
/// ```swift
/// let parser = CardNumberParser()
/// parser.parse("4111 1111 1111 1111")  // [CardNumberMatch(number: "4111111111111111", brand: .visa)]
/// ```
public struct CardNumberParser: Sendable {
    /// The rules used to classify candidate numbers. A candidate that matches no rule is rejected.
    public var rules: [CardBrandRule]

    /// Card numbers are between 12 and 19 digits long.
    static let lengthRange = 12...19

    public init(rules: [CardBrandRule] = CardBrandRule.defaults) {
        self.rules = rules
    }

    /// Finds every Luhn-valid, brand-matching number in `text`.
    ///
    /// Digits may be separated by spaces, hyphens or dots, as they commonly are on a card. When
    /// a run of digits is longer than any valid number, the parser slides a window over it and
    /// returns the longest matches it finds.
    public func parse(_ text: String) -> [CardNumberMatch] {
        parse(lines: [text])
    }

    /// Finds card numbers in several pieces of recognised text.
    ///
    /// Besides checking each line on its own, consecutive lines are also joined, which recovers
    /// numbers that OCR split into separate observations such as `"4111 1111"` and `"1111 1111"`.
    public func parse(lines: [String]) -> [CardNumberMatch] {
        var candidates: [String] = []
        var seen: Set<String> = []

        func add(_ digits: String) {
            guard digits.count >= CardNumberParser.lengthRange.lowerBound, !seen.contains(digits) else { return }
            seen.insert(digits)
            candidates.append(digits)
        }

        // Joining fragments is only ever a repair for a number that was split, so a joined
        // candidate must itself be a plausible card length. Joining two complete numbers would
        // otherwise manufacture Luhn-valid substrings that were never on the card.
        func addJoined(_ fragments: [String]) {
            let joined = fragments.joined()
            guard fragments.count > 1,
                  CardNumberParser.lengthRange.contains(joined.count),
                  fragments.allSatisfy({ $0.count < CardNumberParser.lengthRange.lowerBound })
            else { return }
            add(joined)
        }

        let perLine = lines.map(Self.digitRuns)
        for runs in perLine {
            for run in runs { add(run) }
            addJoined(runs)
        }
        // Join adjacent lines in case the number was split across observations.
        if perLine.count > 1 {
            for index in perLine.indices.dropLast() {
                addJoined([perLine[index].joined(), perLine[index + 1].joined()])
            }
        }

        var results: [CardNumberMatch] = []
        var emitted: Set<String> = []
        for candidate in candidates {
            for match in matches(in: candidate) where !emitted.contains(match.number) {
                emitted.insert(match.number)
                results.append(match)
            }
        }
        return results
    }

    /// Splits text into runs of digits, dropping the separators cards commonly use.
    static func digitRuns(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        var pendingSeparator = false

        for scalar in text.unicodeScalars {
            if ("0"..."9").contains(String(scalar)) {
                current.unicodeScalars.append(scalar)
                pendingSeparator = false
            } else if scalar == " " || scalar == "-" || scalar == "." || scalar == "\u{00A0}" {
                // Separators are allowed between digit groups but a run of them ends the number.
                if pendingSeparator, !current.isEmpty {
                    runs.append(current)
                    current = ""
                }
                pendingSeparator = !current.isEmpty
            } else {
                if !current.isEmpty { runs.append(current) }
                current = ""
                pendingSeparator = false
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Checks a digit string exactly, and falls back to a sliding window when it is too long.
    private func matches(in digits: String) -> [CardNumberMatch] {
        if let match = validate(digits) {
            return [match]
        }
        guard digits.count > CardNumberParser.lengthRange.lowerBound else { return [] }

        let longest = min(digits.count - 1, CardNumberParser.lengthRange.upperBound)
        for length in stride(from: longest, through: CardNumberParser.lengthRange.lowerBound, by: -1) {
            var found: [CardNumberMatch] = []
            var start = digits.startIndex
            while let end = digits.index(start, offsetBy: length, limitedBy: digits.endIndex) {
                if let match = validate(String(digits[start..<end])) {
                    found.append(match)
                }
                start = digits.index(after: start)
            }
            if !found.isEmpty { return found }
        }
        return []
    }

    private func validate(_ digits: String) -> CardNumberMatch? {
        guard CardNumberParser.lengthRange.contains(digits.count),
              Luhn.isValid(digits),
              let brand = rules.brand(for: digits)
        else { return nil }
        return CardNumberMatch(number: digits, brand: brand)
    }
}

import Foundation

/// Describes how to recognise a ``CardBrand`` from a card number.
///
/// A rule matches when the number's leading digits fall inside one of ``prefixes`` and
/// the total number of digits is one of ``lengths``. Each prefix range must have the same
/// number of digits at both ends, for example `2221...2720` or `4...4`.
public struct CardBrandRule: Hashable, Sendable {
    public let brand: CardBrand
    public let prefixes: [ClosedRange<Int>]
    public let lengths: Set<Int>

    /// Creates a rule from one or more prefix ranges.
    ///
    /// - Parameters:
    ///   - brand: The brand the rule identifies.
    ///   - prefixes: Inclusive ranges of leading digits. Both bounds of a range must have the
    ///     same digit count.
    ///   - lengths: The card-number lengths the brand issues.
    public init(brand: CardBrand, prefixes: [ClosedRange<Int>], lengths: Set<Int>) {
        precondition(!prefixes.isEmpty, "A CardBrandRule needs at least one prefix range.")
        precondition(!lengths.isEmpty, "A CardBrandRule needs at least one length.")
        for range in prefixes {
            precondition(
                String(range.lowerBound).count == String(range.upperBound).count,
                "Prefix range \(range) must have the same digit count at both ends."
            )
        }
        self.brand = brand
        self.prefixes = prefixes
        self.lengths = lengths
    }

    /// Creates a rule from a list of exact prefixes, such as `[34, 37]`.
    public init(brand: CardBrand, prefixes: [Int], lengths: Set<Int>) {
        self.init(brand: brand, prefixes: prefixes.map { $0...$0 }, lengths: lengths)
    }

    /// Creates a rule from a single prefix range.
    public init(brand: CardBrand, prefix: ClosedRange<Int>, lengths: Set<Int>) {
        self.init(brand: brand, prefixes: [prefix], lengths: lengths)
    }

    /// Creates a rule from a single exact prefix.
    public init(brand: CardBrand, prefix: Int, lengths: Set<Int>) {
        self.init(brand: brand, prefixes: [prefix...prefix], lengths: lengths)
    }

    /// Returns `true` when `digits` has an accepted length and begins with one of the rule's prefixes.
    public func matches(_ digits: String) -> Bool {
        matchingPrefixWidth(for: digits) != nil
    }

    /// The number of leading digits consumed by the most specific prefix that matches, or `nil`.
    ///
    /// A wider prefix means a more specific rule. ``CardNumberParser`` uses this to prefer, for
    /// example, Discover's `622126...622925` over UnionPay's `62`.
    func matchingPrefixWidth(for digits: String) -> Int? {
        guard lengths.contains(digits.count) else { return nil }
        var best: Int?
        for range in prefixes {
            let width = String(range.lowerBound).count
            guard digits.count >= width,
                  let value = Int(digits.prefix(width)),
                  range.contains(value)
            else { continue }
            if best.map({ width > $0 }) ?? true {
                best = width
            }
        }
        return best
    }
}

extension CardBrandRule {
    /// The rules CDCScanner ships with.
    ///
    /// Prefix data follows the public IIN assignments of each network. Pass a modified copy of
    /// this array to ``ScannerConfiguration/brandRules`` to restrict or extend recognition.
    public static let defaults: [CardBrandRule] = [
        CardBrandRule(brand: .visa, prefix: 4, lengths: [13, 16, 19]),
        CardBrandRule(brand: .mastercard, prefixes: [51...55, 2221...2720], lengths: [16]),
        CardBrandRule(brand: .americanExpress, prefixes: [34, 37], lengths: [15]),
        CardBrandRule(
            brand: .discover,
            prefixes: [6011...6011, 622_126...622_925, 644...649, 65...65],
            lengths: [16, 17, 18, 19]
        ),
        CardBrandRule(
            brand: .dinersClub,
            prefixes: [300...305, 36...36, 38...39],
            lengths: [14, 15, 16, 17, 18, 19]
        ),
        CardBrandRule(brand: .jcb, prefix: 3528...3589, lengths: [16, 17, 18, 19]),
        CardBrandRule(brand: .unionPay, prefix: 62, lengths: [16, 17, 18, 19]),
        CardBrandRule(
            brand: .maestro,
            prefixes: [5018...5018, 5020...5020, 5038...5038, 5893...5893, 6304...6304, 67...67],
            lengths: [12, 13, 14, 15, 16, 17, 18, 19]
        ),
        CardBrandRule(brand: .ruPay, prefixes: [60...60, 6521...6522, 81...82, 508...508], lengths: [16]),
        CardBrandRule(brand: .mir, prefix: 2200...2204, lengths: [16]),
        CardBrandRule(brand: .dankort, prefix: 5019, lengths: [16]),
        CardBrandRule(brand: .chinaTUnion, prefix: 31, lengths: [19]),
        CardBrandRule(brand: .interPayment, prefix: 636, lengths: [16, 17, 18, 19]),
        CardBrandRule(brand: .uatp, prefix: 1, lengths: [15]),
        CardBrandRule(brand: .npsPridnestrovie, prefix: 6_054_740...6_054_744, lengths: [16]),
    ]

    /// Returns the default rules restricted to the given brands.
    public static func defaults(for brands: Set<CardBrand>) -> [CardBrandRule] {
        defaults.filter { brands.contains($0.brand) }
    }
}

extension Array where Element == CardBrandRule {
    /// Resolves the brand for a full card number, preferring the most specific matching prefix.
    ///
    /// - Returns: The matching ``CardBrand`` or `nil` when no rule applies.
    public func brand(for digits: String) -> CardBrand? {
        var best: (brand: CardBrand, width: Int)?
        for rule in self {
            guard let width = rule.matchingPrefixWidth(for: digits) else { continue }
            if best.map({ width > $0.width }) ?? true {
                best = (rule.brand, width)
            }
        }
        return best?.brand
    }
}

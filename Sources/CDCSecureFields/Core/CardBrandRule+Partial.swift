import CDCCore
import Foundation

extension CardBrandRule {
    /// Whether a number that starts with `prefix` could still match this rule once complete.
    ///
    /// Used while the user types to detect the brand early and pick the right grouping and
    /// maximum length. A full number is checked with ``CardBrandRule/matches(_:)`` instead.
    public func couldMatch(prefix: String) -> Bool {
        guard prefix.allSatisfy(\.isNumber) else { return false }
        if prefix.isEmpty { return true }
        guard prefix.count <= maxLength else { return false }
        for range in prefixes {
            let width = String(range.lowerBound).count
            if prefix.count >= width {
                if let value = Int(prefix.prefix(width)), range.contains(value) {
                    return true
                }
            } else if let typed = Int(prefix) {
                // Does any value in the range start with the typed digits?
                let scale = Int(pow(10.0, Double(width - prefix.count)))
                let lowest = typed * scale
                let highest = lowest + scale - 1
                if lowest <= range.upperBound && highest >= range.lowerBound {
                    return true
                }
            }
        }
        return false
    }

    /// The longest number this rule accepts.
    public var maxLength: Int {
        lengths.max() ?? 19
    }
}

extension Array where Element == CardBrandRule {
    /// Every brand that a number starting with `prefix` could still belong to.
    ///
    /// Returns a single brand once the typed digits are unambiguous, several while they are not,
    /// and none when nothing can match.
    public func candidateBrands(forPrefix prefix: String) -> [CardBrand] {
        var seen: Set<CardBrand> = []
        var result: [CardBrand] = []
        for rule in self where rule.couldMatch(prefix: prefix) {
            if seen.insert(rule.brand).inserted {
                result.append(rule.brand)
            }
        }
        return result
    }

    /// The brand a partially typed number belongs to, once it is unambiguous.
    ///
    /// A brand is reported as soon as it is the only candidate left (`27` can only be Mastercard),
    /// or when a rule's full prefix has been typed and it is more specific than every other match
    /// (`622126` is Discover, not UnionPay). Otherwise `nil`.
    public func detectedBrand(forPrefix prefix: String) -> CardBrand? {
        guard !prefix.isEmpty else { return nil }
        let candidates = candidateBrands(forPrefix: prefix)
        if candidates.count == 1 { return candidates[0] }

        var best: (brand: CardBrand, width: Int)?
        var ambiguous = false
        for rule in self where rule.couldMatch(prefix: prefix) {
            let width = rule.prefixes
                .filter { range in
                    let w = String(range.lowerBound).count
                    guard prefix.count >= w, let value = Int(prefix.prefix(w)) else { return false }
                    return range.contains(value)
                }
                .map { String($0.lowerBound).count }
                .max()
            guard let width else { continue } // not yet enough digits to confirm this rule
            if let current = best {
                if width > current.width {
                    best = (rule.brand, width)
                    ambiguous = false
                } else if width == current.width, current.brand != rule.brand {
                    ambiguous = true
                }
            } else {
                best = (rule.brand, width)
            }
        }
        return ambiguous ? nil : best?.brand
    }

    /// The longest number any brand matching `prefix` accepts; 19 when nothing matches yet.
    public func maxLength(forPrefix prefix: String) -> Int {
        let lengths = filter { $0.couldMatch(prefix: prefix) }.map(\.maxLength)
        return lengths.max() ?? 19
    }

    /// Lengths that would make a number starting with `prefix` complete.
    public func acceptedLengths(forPrefix prefix: String) -> Set<Int> {
        filter { $0.couldMatch(prefix: prefix) }.reduce(into: Set<Int>()) { $0.formUnion($1.lengths) }
    }
}

import CDCCore
import Foundation

/// Card security code (CVC, CVV, CID) rules.
public enum CVCRules {
    /// The code length for a brand: 4 for American Express, 3 for everything else, and 4 while
    /// the brand is unknown so nothing valid is rejected.
    public static func length(for brand: CardBrand?) -> Int {
        switch brand {
        case .americanExpress: return 4
        case .none: return 4
        default: return 3
        }
    }

    /// The lengths considered complete for a brand.
    public static func acceptedLengths(for brand: CardBrand?) -> Set<Int> {
        switch brand {
        case .americanExpress: return [4]
        case .none: return [3, 4]
        default: return [3]
        }
    }

    public static func state(digits: String, brand: CardBrand?) -> CVCFieldState {
        let clean = digits.filter(\.isNumber)
        return CVCFieldState(
            length: clean.count,
            isComplete: acceptedLengths(for: brand).contains(clean.count),
            isEmpty: clean.isEmpty
        )
    }
}

/// What a host app may know about the contents of a ``SecureCVCField``. Never the code itself.
public struct CVCFieldState: Hashable, Sendable {
    public let length: Int
    public let isComplete: Bool
    public let isEmpty: Bool

    public init(length: Int, isComplete: Bool, isEmpty: Bool) {
        self.length = length
        self.isComplete = isComplete
        self.isEmpty = isEmpty
    }

    public static let empty = CVCFieldState(length: 0, isComplete: false, isEmpty: true)
}

import Foundation

/// The result of a successful scan.
public struct ScannedCard: Hashable, Sendable, Codable {
    /// The card number as digits only, with no separators.
    public let number: String
    /// The recognised network.
    public let brand: CardBrand
    /// The expiry, when one was read. `nil` when the card shows none or it could not be read
    /// before ``ScannerConfiguration/expiryTimeout`` elapsed.
    public let expiry: CardExpiry?

    public init(number: String, brand: CardBrand, expiry: CardExpiry?) {
        self.number = number
        self.brand = brand
        self.expiry = expiry
    }

    /// The final four digits of the number.
    public var lastFour: String {
        String(number.suffix(4))
    }

    /// The number with every digit but the last four replaced by a bullet, grouped like ``formattedNumber``.
    public var maskedNumber: String {
        let keep = number.count - 4
        let masked = String(repeating: "•", count: max(keep, 0)) + number.suffix(4)
        return ScannedCard.group(masked, pattern: groupingPattern)
    }

    /// The number grouped the way it appears on the card, e.g. `4111 1111 1111 1111` or `3782 822463 10005`.
    public var formattedNumber: String {
        ScannedCard.group(number, pattern: groupingPattern)
    }

    private var groupingPattern: [Int] {
        switch (brand, number.count) {
        case (.americanExpress, 15), (.uatp, 15):
            return [4, 6, 5]
        case (.dinersClub, 14):
            return [4, 6, 4]
        default:
            return Array(repeating: 4, count: (number.count + 3) / 4)
        }
    }

    private static func group(_ string: String, pattern: [Int]) -> String {
        var groups: [Substring] = []
        var index = string.startIndex
        for size in pattern where index < string.endIndex {
            let end = string.index(index, offsetBy: size, limitedBy: string.endIndex) ?? string.endIndex
            groups.append(string[index..<end])
            index = end
        }
        if index < string.endIndex {
            groups.append(string[index...])
        }
        return groups.joined(separator: " ")
    }
}

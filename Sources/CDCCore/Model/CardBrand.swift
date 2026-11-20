import Foundation

/// The payment network a card belongs to.
///
/// Use ``CardBrand/standard`` for the brands CDCScanner recognises out of the box, or
/// ``CardBrand/custom(_:)`` together with a ``CardBrandRule`` to teach the scanner about
/// a network it does not know.
public enum CardBrand: Hashable, Sendable, Codable {
    case visa
    case mastercard
    case americanExpress
    case discover
    case dinersClub
    case jcb
    case unionPay
    case maestro
    case ruPay
    case mir
    case dankort
    case chinaTUnion
    case interPayment
    case uatp
    case npsPridnestrovie
    /// A brand defined by the host application through a custom ``CardBrandRule``.
    case custom(String)

    /// Every built-in brand, in display order.
    public static let standard: [CardBrand] = [
        .visa, .mastercard, .americanExpress, .discover, .dinersClub, .jcb, .unionPay,
        .maestro, .ruPay, .mir, .dankort, .chinaTUnion, .interPayment, .uatp, .npsPridnestrovie,
    ]

    /// A human-readable name suitable for display.
    public var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .americanExpress: return "American Express"
        case .discover: return "Discover"
        case .dinersClub: return "Diners Club"
        case .jcb: return "JCB"
        case .unionPay: return "UnionPay"
        case .maestro: return "Maestro"
        case .ruPay: return "RuPay"
        case .mir: return "Mir"
        case .dankort: return "Dankort"
        case .chinaTUnion: return "China T-Union"
        case .interPayment: return "InterPayment"
        case .uatp: return "UATP"
        case .npsPridnestrovie: return "NPS Pridnestrovie"
        case .custom(let name): return name
        }
    }
}

extension CardBrand: CustomStringConvertible {
    public var description: String { displayName }
}

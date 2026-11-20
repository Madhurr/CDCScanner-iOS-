import CDCCore
import Foundation

/// A token or reference returned by a vault or payment provider in exchange for card data.
public struct CardToken: Hashable, Sendable, Codable {
    /// The provider's token, reference or ID.
    public let value: String
    /// Brand, BIN and last four are safe to keep for display and routing.
    public let brand: CardBrand?
    public let bin: String
    public let lastFour: String
    public let expiry: CardExpiry?
    /// The provider's raw response, for fields the host app needs that are not modelled here.
    public let providerResponse: Data?

    public init(value: String, brand: CardBrand?, bin: String, lastFour: String, expiry: CardExpiry?, providerResponse: Data? = nil) {
        self.value = value
        self.brand = brand
        self.bin = bin
        self.lastFour = lastFour
        self.expiry = expiry
        self.providerResponse = providerResponse
    }
}

/// Exchanges collected card data for a token.
///
/// This is the boundary that keeps your servers out of PCI scope: implement it, or use
/// ``HTTPTokenizer``, so the PAN goes from the field straight to a PCI DSS certified vault or
/// payment provider and only the returned token reaches your backend.
public protocol CardTokenizer: Sendable {
    func tokenize(_ card: SecureCardData) async throws -> CardToken
}

/// Errors raised while tokenising.
public enum TokenizationError: Error, Sendable, Equatable {
    /// The collected data is incomplete or invalid; the associated value says what.
    case invalidCardData(String)
    /// The endpoint is not HTTPS. Card data is never sent in clear text.
    case insecureEndpoint
    /// The provider answered with a non-2xx status.
    case httpStatus(Int, body: Data?)
    /// The provider's response could not be parsed into a token.
    case malformedResponse
}

extension TokenizationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCardData(let reason): return "The card details are not valid: \(reason)"
        case .insecureEndpoint: return "Card data can only be sent over HTTPS."
        case .httpStatus(let status, _): return "The tokenisation service returned HTTP \(status)."
        case .malformedResponse: return "The tokenisation service returned an unexpected response."
        }
    }
}

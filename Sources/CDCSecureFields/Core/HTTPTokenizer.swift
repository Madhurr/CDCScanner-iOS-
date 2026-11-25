import CDCCore
import CoreFoundation
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Posts card data as JSON to any HTTPS tokenisation endpoint and reads the token back.
///
/// Works with vault products (VGS inbound routes, Basis Theory, Evervault, Skyflow) and with
/// payment providers that accept raw card data from the client with a publishable key. Configure
/// the body with ``FieldMapping`` and the response with ``tokenPath``:
///
/// ```swift
/// let tokenizer = HTTPTokenizer(
///     url: URL(string: "https://vault.example.com/tokens")!,
///     headers: ["Authorization": "Bearer pk_live_…"],
///     mapping: .init(number: "card.number", expiryMonth: "card.exp_month",
///                    expiryYear: "card.exp_year", securityCode: "card.cvc"),
///     tokenPath: "id"
/// )
/// let token = try await form.tokenize(using: tokenizer)
/// ```
///
/// The default ephemeral session follows redirects only within the original HTTPS origin.
/// A supplied session owns its redirect, trust, cookie and cache policies.
public struct HTTPTokenizer: CardTokenizer {
    /// JSON key paths for each value. Dots nest objects, e.g. `card.number`. `nil` omits the value.
    public struct FieldMapping: Sendable, Hashable {
        public var number: String
        public var expiryMonth: String?
        public var expiryYear: String?
        /// Alternative to separate month and year: a single `MM/YY` string.
        public var expiry: String?
        public var securityCode: String?
        public var cardholderName: String?
        /// Four-digit years when `true`, two-digit when `false`.
        public var usesFourDigitYear: Bool
        /// Send month and year as JSON numbers instead of strings.
        public var usesNumericDates: Bool

        public init(
            number: String = "number",
            expiryMonth: String? = "exp_month",
            expiryYear: String? = "exp_year",
            expiry: String? = nil,
            securityCode: String? = "cvc",
            cardholderName: String? = "name",
            usesFourDigitYear: Bool = true,
            usesNumericDates: Bool = false
        ) {
            self.number = number
            self.expiryMonth = expiryMonth
            self.expiryYear = expiryYear
            self.expiry = expiry
            self.securityCode = securityCode
            self.cardholderName = cardholderName
            self.usesFourDigitYear = usesFourDigitYear
            self.usesNumericDates = usesNumericDates
        }
    }

    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var mapping: FieldMapping
    /// Extra JSON merged into the body, for provider-specific flags.
    public var additionalFields: [String: String]
    /// Dotted key path of the token in the JSON response, e.g. `data.id`.
    public var tokenPath: String
    public var timeout: TimeInterval
    private let session: URLSession

    public init(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        mapping: FieldMapping = FieldMapping(),
        additionalFields: [String: String] = [:],
        tokenPath: String = "token",
        timeout: TimeInterval = 30,
        session: URLSession? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.mapping = mapping
        self.additionalFields = additionalFields
        self.tokenPath = tokenPath
        self.timeout = timeout
        self.session = session ?? HTTPTokenizer.makeSession()
    }

    public func tokenize(_ card: SecureCardData) async throws -> CardToken {
        let request = try makeRequest(for: card)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TokenizationError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TokenizationError.httpStatus(http.statusCode, body: nil)
        }
        return try token(from: data, for: card)
    }

    // MARK: - Request and response (pure, tested)

    /// Builds the request. The PAN is only ever stringified here.
    func makeRequest(for card: SecureCardData) throws -> URLRequest {
        guard url.scheme?.lowercased() == "https" else { throw TokenizationError.insecureEndpoint }

        var body: [String: Any] = [:]
        for (key, value) in additionalFields {
            Self.set(value, at: key, in: &body)
        }
        card.withNumber { number in
            Self.set(number, at: mapping.number, in: &body)
        }
        if let expiry = card.expiry {
            let year = mapping.usesFourDigitYear ? expiry.year : expiry.year % 100
            if let monthKey = mapping.expiryMonth {
                Self.set(mapping.usesNumericDates ? expiry.month : String(format: "%02d", expiry.month), at: monthKey, in: &body)
            }
            if let yearKey = mapping.expiryYear {
                Self.set(mapping.usesNumericDates ? year : (mapping.usesFourDigitYear ? String(year) : String(format: "%02d", year)), at: yearKey, in: &body)
            }
            if let expiryKey = mapping.expiry {
                Self.set(mapping.usesFourDigitYear ? expiry.formattedLong : expiry.formatted, at: expiryKey, in: &body)
            }
        }
        if let codeKey = mapping.securityCode {
            card.withSecurityCode { code in
                if let code { Self.set(code, at: codeKey, in: &body) }
            }
        }
        if let nameKey = mapping.cardholderName, let name = card.cardholderName {
            Self.set(name, at: nameKey, in: &body)
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    func token(from data: Data, for card: SecureCardData) throws -> CardToken {
        try Self.token(from: data, for: card, tokenPath: tokenPath)
    }

    static func token(from data: Data, for card: SecureCardData, tokenPath: String) throws -> CardToken {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let value = Self.value(at: tokenPath, in: json)
        else { throw TokenizationError.malformedResponse }

        let tokenString: String
        switch value {
        case let string as String: tokenString = string
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID(): tokenString = number.stringValue
        default: throw TokenizationError.malformedResponse
        }
        guard !tokenString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !card.withNumber({ !$0.isEmpty && tokenString.filter(\.isNumber).contains($0) })
        else { throw TokenizationError.malformedResponse }
        return CardToken(
            value: tokenString,
            brand: card.brand,
            bin: card.bin,
            lastFour: card.lastFour,
            expiry: card.expiry
        )
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        #if canImport(Darwin)
        configuration.waitsForConnectivity = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        #endif
        return URLSession(configuration: configuration, delegate: SameOriginRedirectPolicy(), delegateQueue: nil)
    }

    static func set(_ value: Any, at path: String, in object: inout [String: Any]) {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first else { return }
        if parts.count == 1 {
            object[first] = value
        } else {
            var child = object[first] as? [String: Any] ?? [:]
            set(value, at: parts.dropFirst().joined(separator: "."), in: &child)
            object[first] = child
        }
    }

    static func value(at path: String, in json: Any) -> Any? {
        var current: Any = json
        for part in path.split(separator: ".") {
            guard let dictionary = current as? [String: Any], let next = dictionary[String(part)] else { return nil }
            current = next
        }
        return current
    }
}

/// Refuses redirects that would send card data to another host.
final class SameOriginRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    static func allows(from source: URL?, to destination: URL?) -> Bool {
        guard let source, let destination,
              let host = source.host?.lowercased(), !host.isEmpty else { return false }
        return source.scheme?.lowercased() == "https"
            && destination.scheme?.lowercased() == "https"
            && destination.host?.lowercased() == host
            && (source.port ?? 443) == (destination.port ?? 443)
            && destination.user == nil && destination.password == nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.allows(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}

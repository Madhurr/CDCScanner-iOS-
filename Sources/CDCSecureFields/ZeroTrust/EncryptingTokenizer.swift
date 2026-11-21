import CDCCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Encrypts card data in the field, to keys the phone has verified, and sends only ciphertext.
///
/// The payload is a JWE (ECDH-ES+A256KW, A256GCM) addressed to every key the
/// ``RecipientKeyProvider`` returns. Nothing between the field and a holder of one of those keys,
/// including your own servers, a CDN, a TLS-terminating proxy or a debugging proxy on the device,
/// can read the card number.
///
/// ```swift
/// let enclave = AttestedEnclaveKeyProvider(
///     url: URL(string: "https://relay.example.com/v1/attestation")!,
///     policy: NitroAttestationPolicy(expectedPCRs: [0: [relayReleasePCR0]])
/// )
/// let tokenizer = EncryptingTokenizer(
///     url: URL(string: "https://relay.example.com/v1/tokenize")!,
///     recipients: enclave,
///     attestor: AppAttestRequestAttestor()
/// )
/// let token = try await form.tokenize(using: tokenizer)
/// ```
///
/// The protected header carries `typ`, `iat` and a random `nonce`, all authenticated by the
/// content encryption, so the relay can reject replays and stale payloads.
public struct EncryptingTokenizer: CardTokenizer {
    public static let payloadType = "cdc-card+json"

    public var url: URL
    public var headers: [String: String]
    public var recipients: any RecipientKeyProvider
    public var attestor: (any RequestAttestor)?
    /// Dotted key path of the token in the relay's JSON response.
    public var tokenPath: String
    /// Extra claims included inside the encrypted payload, for example a merchant reference.
    public var additionalClaims: [String: String]
    public var timeout: TimeInterval
    private let session: URLSession

    public init(
        url: URL,
        recipients: any RecipientKeyProvider,
        attestor: (any RequestAttestor)? = nil,
        headers: [String: String] = [:],
        tokenPath: String = "token",
        additionalClaims: [String: String] = [:],
        timeout: TimeInterval = 30,
        session: URLSession? = nil
    ) {
        self.url = url
        self.recipients = recipients
        self.attestor = attestor
        self.headers = headers
        self.tokenPath = tokenPath
        self.additionalClaims = additionalClaims
        self.timeout = timeout
        self.session = session ?? HTTPTokenizer.makeSession()
    }

    public func tokenize(_ card: SecureCardData) async throws -> CardToken {
        guard url.scheme?.lowercased() == "https" else { throw TokenizationError.insecureEndpoint }
        let keys = try await recipients.recipientKeys()
        guard !keys.isEmpty else { throw TokenizationError.invalidCardData("No recipient keys available.") }

        var request = try makeRequest(for: card, recipients: keys)
        if let attestor, let body = request.httpBody {
            try await attestor.attest(&request, bodyHash: Data(SHA256.hash(data: body)))
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TokenizationError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw TokenizationError.httpStatus(http.statusCode, body: data) }
        return try HTTPTokenizer.token(from: data, for: card, tokenPath: tokenPath)
    }

    /// Builds the request. The PAN is stringified only here, immediately encrypted, and the
    /// plaintext buffer goes out of scope before the function returns.
    func makeRequest(for card: SecureCardData, recipients keys: [ECPublicJWK], now: Date = Date()) throws -> URLRequest {
        var payload: [String: Any] = additionalClaims
        card.withNumber { payload["number"] = $0 }
        card.withSecurityCode { if let code = $0 { payload["cvc"] = code } }
        if let expiry = card.expiry {
            payload["exp_month"] = String(format: "%02d", expiry.month)
            payload["exp_year"] = String(expiry.year)
        }
        if let name = card.cardholderName { payload["name"] = name }
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        var nonce = [UInt8](repeating: 0, count: 16)
        for index in nonce.indices { nonce[index] = UInt8.random(in: .min ... .max) }
        let encrypter = JWEEncrypter(protectedHeader: [
            "typ": Self.payloadType,
            "iat": String(Int(now.timeIntervalSince1970)),
            "nonce": Data(nonce).hexString,
        ])
        let jwe = try encrypter.encrypt(plaintext, to: keys)

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/jose+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try jwe.jsonData()
        return request
    }
}

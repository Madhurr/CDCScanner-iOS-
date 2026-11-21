import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplies the public keys a card payload is encrypted to.
public protocol RecipientKeyProvider: Sendable {
    func recipientKeys() async throws -> [ECPublicJWK]
}

/// Fixed keys, for a relay or payment provider whose key you ship or fetch yourself.
public struct StaticRecipientKeys: RecipientKeyProvider {
    public var keys: [ECPublicJWK]

    public init(_ keys: [ECPublicJWK]) {
        self.keys = keys
    }

    public init(_ key: ECPublicJWK) {
        self.keys = [key]
    }

    public func recipientKeys() async throws -> [ECPublicJWK] { keys }
}

/// Several providers combined: a payload encrypted to all of their keys can be opened by any one
/// of them, which gives processor fail-over without a vault holding plaintext.
public struct CombinedRecipientKeys: RecipientKeyProvider {
    public var providers: [any RecipientKeyProvider]

    public init(_ providers: [any RecipientKeyProvider]) {
        self.providers = providers
    }

    public func recipientKeys() async throws -> [ECPublicJWK] {
        var keys: [ECPublicJWK] = []
        for provider in providers { keys += try await provider.recipientKeys() }
        return keys
    }
}

/// Fetches an AWS Nitro Enclaves attestation document from a relay, verifies it against a
/// ``NitroAttestationPolicy`` and returns the key the enclave generated inside itself.
///
/// This is the half of zero trust that no hosted-field SDK offers: the phone checks the server's
/// identity and code hash before it encrypts anything to it. A fresh nonce is sent on every fetch
/// and must come back in the document, so a captured document cannot be replayed.
///
/// The relay endpoint is `GET {url}?nonce=<hex>` and returns the raw COSE_Sign1 bytes with
/// `Content-Type: application/cbor`, or JSON `{"attestation": "<base64>"}`.
public struct AttestedEnclaveKeyProvider: RecipientKeyProvider {
    public var url: URL
    public var policy: NitroAttestationPolicy
    public var kid: String
    public var timeout: TimeInterval
    private let session: URLSession

    public init(url: URL, policy: NitroAttestationPolicy, kid: String = "enclave", timeout: TimeInterval = 15, session: URLSession? = nil) {
        self.url = url
        self.policy = policy
        self.kid = kid
        self.timeout = timeout
        self.session = session ?? HTTPTokenizer.makeSession()
    }

    public func recipientKeys() async throws -> [ECPublicJWK] {
        let document = try await fetchAndVerify()
        return [try document.recipientKey(kid: kid)]
    }

    /// Fetches and verifies the document; exposed so apps can display enclave identity details.
    public func fetchAndVerify(now: Date = Date()) async throws -> NitroAttestationDocument {
        guard url.scheme?.lowercased() == "https" else { throw TokenizationError.insecureEndpoint }
        var nonceBytes = [UInt8](repeating: 0, count: 32)
        for index in nonceBytes.indices { nonceBytes[index] = UInt8.random(in: .min ... .max) }
        let nonce = Data(nonceBytes)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "nonce", value: nonce.hexString)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.setValue("application/cbor, application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TokenizationError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        }

        var cose = data
        if http.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let base64 = object["attestation"] as? String,
           let decoded = Data(base64Encoded: base64) {
            cose = decoded
        }

        var policy = self.policy
        policy.expectedNonce = nonce
        return try NitroAttestationVerifier(policy: policy).verify(cose, now: now)
    }
}

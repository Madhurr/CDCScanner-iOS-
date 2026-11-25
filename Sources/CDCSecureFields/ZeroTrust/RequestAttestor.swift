import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Adds proof of the calling app's integrity to a tokenisation request.
///
/// The relay uses it to reject requests that did not come from a genuine build of your app, which
/// is what stops card-testing bots from driving your tokenisation endpoint with scripts.
public protocol RequestAttestor: Sendable {
    /// Called with the request about to be sent and the SHA-256 of its body.
    func attest(_ request: inout URLRequest, bodyHash: Data) async throws
}

/// Header names shared between the SDK and the reference relay.
public enum AttestationHeaders {
    public static let keyID = "X-App-Attest-Key-Id"
    public static let assertion = "X-App-Attest-Assertion"
    public static let attestation = "X-App-Attest-Attestation"
    public static let challenge = "X-App-Attest-Challenge"
}

#if os(iOS) && canImport(DeviceCheck)
import DeviceCheck
import Security

/// Attests requests with Apple's App Attest service.
///
/// On first use a hardware-bound key is created and attested once with Apple; the key id is kept
/// in the keychain. Every request then carries an assertion over the request body hash, so the
/// relay can verify that the body was produced by a genuine, un-tampered build of your app on a
/// real device. Not available on the simulator; check ``isSupported``.
///
/// Enrollment fetches a one-time challenge from the sibling `challenge` endpoint. Supply a
/// `challengeProvider` for a custom route or authenticated session. Return 32 decoded bytes.
public struct AppAttestRequestAttestor: RequestAttestor {
    public enum AttestorError: Error { case unsupportedDevice, missingKey, invalidChallenge }

    public var challengeProvider: (@Sendable () async throws -> Data)?
    private let keychainService: String

    public init(keychainService: String = "com.cdcscanner.appattest", challengeProvider: (@Sendable () async throws -> Data)? = nil) {
        self.keychainService = keychainService
        self.challengeProvider = challengeProvider
    }

    public static var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func attest(_ request: inout URLRequest, bodyHash: Data) async throws {
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw AttestorError.unsupportedDevice }

        var keyID = loadKeyID()
        if keyID == nil {
            let newKeyID = try await service.generateKey()
            let challenge: Data
            if let challengeProvider {
                challenge = try await challengeProvider()
            } else {
                guard let endpoint = request.url, endpoint.scheme?.lowercased() == "https" else {
                    throw TokenizationError.insecureEndpoint
                }
                let url = endpoint.deletingLastPathComponent().appendingPathComponent("challenge")
                var enrollment = URLRequest(url: url)
                enrollment.httpMethod = "POST"
                let session = HTTPTokenizer.makeSession()
                defer { session.finishTasksAndInvalidate() }
                let (data, response) = try await session.data(for: enrollment)
                struct Response: Decodable { let challenge: Data }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw AttestorError.invalidChallenge
                }
                challenge = try JSONDecoder().decode(Response.self, from: data).challenge
            }
            guard challenge.count == 32 else { throw AttestorError.invalidChallenge }
            let clientData = Data(SHA256.hash(data: challenge))
            request.setValue(challenge.base64EncodedString(), forHTTPHeaderField: AttestationHeaders.challenge)
            let attestation = try await service.attestKey(newKeyID, clientDataHash: clientData)
            request.setValue(attestation.base64EncodedString(), forHTTPHeaderField: AttestationHeaders.attestation)
            storeKeyID(newKeyID)
            keyID = newKeyID
        }

        guard let keyID else { throw AttestorError.missingKey }
        let assertion = try await service.generateAssertion(keyID, clientDataHash: bodyHash)
        request.setValue(keyID, forHTTPHeaderField: AttestationHeaders.keyID)
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: AttestationHeaders.assertion)
    }

    /// Forgets the attested key, for example after the relay reports it as unknown.
    public func reset() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: "app-attest-key-id"]
    }

    private func loadKeyID() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func storeKeyID(_ keyID: String) {
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(keyID.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(baseQuery as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
#endif

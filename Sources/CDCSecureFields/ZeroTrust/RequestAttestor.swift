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
/// For the strongest binding supply a `challengeProvider` that fetches a one-time challenge from
/// the relay; it is hashed into the attestation and sent back in a header so the relay can tie the
/// key to a session it issued.
public struct AppAttestRequestAttestor: RequestAttestor {
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
        guard service.isSupported else { return }

        var keyID = loadKeyID()
        if keyID == nil {
            let newKeyID = try await service.generateKey()
            var clientData = bodyHash
            if let challengeProvider {
                let challenge = try await challengeProvider()
                clientData = Data(SHA256.hash(data: challenge))
                request.setValue(challenge.base64EncodedString(), forHTTPHeaderField: AttestationHeaders.challenge)
            }
            let attestation = try await service.attestKey(newKeyID, clientDataHash: clientData)
            request.setValue(attestation.base64EncodedString(), forHTTPHeaderField: AttestationHeaders.attestation)
            storeKeyID(newKeyID)
            keyID = newKeyID
        }

        guard let keyID else { return }
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

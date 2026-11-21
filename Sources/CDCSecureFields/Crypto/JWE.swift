import Foundation

public enum JWEError: Error, Equatable, Sendable {
    case unsupportedKey(String)
    case unsupportedAlgorithm(String)
    case malformed(String)
    case noMatchingRecipient
    case decryptionFailed
}

/// JSON Web Encryption (RFC 7516) with `ECDH-ES+A256KW` key management and `A256GCM` content
/// encryption, for one or many recipients.
///
/// Every recipient gets its own ephemeral key agreement and wrapped copy of the content key, so a
/// single ciphertext can be opened by any of several relays or payment providers. Nothing but the
/// recipients' public keys is needed to encrypt, and nothing a recipient does lets it read a copy
/// wrapped for another.
public struct JWEEncrypter: Sendable {
    public static let keyManagementAlgorithm = "ECDH-ES+A256KW"
    public static let contentEncryptionAlgorithm = "A256GCM"

    /// Additional members for the protected header, such as `typ` or `cty`.
    public var protectedHeader: [String: String]

    public init(protectedHeader: [String: String] = [:]) {
        self.protectedHeader = protectedHeader
    }

    /// Encrypts `plaintext` for every recipient and returns the JWE in general JSON serialisation.
    ///
    /// `aad` is bound to the ciphertext but not encrypted; use it for request metadata the relay
    /// must see and the client must not be able to repudiate, such as a nonce or an attestation id.
    public func encrypt(_ plaintext: Data, to recipients: [ECPublicJWK], aad: Data? = nil) throws -> JWEObject {
        guard !recipients.isEmpty else { throw JWEError.noMatchingRecipient }

        var header = protectedHeader
        header["enc"] = Self.contentEncryptionAlgorithm
        header["alg"] = Self.keyManagementAlgorithm
        let protectedJSON = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let protectedB64 = Base64URL.encode(protectedJSON)

        let contentKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()

        var aadInput = Data(protectedB64.utf8)
        if let aad {
            aadInput.append(contentsOf: ".".utf8)
            aadInput.append(contentsOf: Base64URL.encode(aad).utf8)
        }
        let sealed = try AES.GCM.seal(plaintext, using: contentKey, nonce: nonce, authenticating: aadInput)

        let recipientEntries = try recipients.map { recipient -> JWEObject.Recipient in
            let publicKey = try recipient.keyAgreementKey
            let ephemeral = P256.KeyAgreement.PrivateKey()
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
            let kek = ConcatKDF.derive(
                sharedSecret: shared,
                algorithmID: Self.keyManagementAlgorithm,
                partyUInfo: Data(),
                partyVInfo: Data(),
                keyBits: 256
            )
            let wrapped = try AES.KeyWrap.wrap(contentKey, using: kek)
            var unprotected: [String: Any] = ["epk": ECPublicJWK(ephemeral.publicKey).jsonObject]
            if let kid = recipient.kid { unprotected["kid"] = kid }
            return JWEObject.Recipient(header: unprotected, encryptedKey: Base64URL.encode(wrapped))
        }

        return JWEObject(
            protectedB64: protectedB64,
            aadB64: aad.map(Base64URL.encode),
            iv: Base64URL.encode(Data(nonce)),
            ciphertext: Base64URL.encode(sealed.ciphertext),
            tag: Base64URL.encode(sealed.tag),
            recipients: recipientEntries
        )
    }
}

/// An encrypted message in JWE general JSON serialisation (RFC 7516 section 7.2.1).
public struct JWEObject: Sendable {
    /// `@unchecked Sendable`: the header holds only JSON value types produced by Foundation.
    public struct Recipient: @unchecked Sendable {
        /// Per-recipient unprotected header: `epk` and optionally `kid`.
        public let header: [String: Any]
        public let encryptedKey: String

        init(header: [String: Any], encryptedKey: String) {
            self.header = header
            self.encryptedKey = encryptedKey
        }
    }

    public let protectedB64: String
    public let aadB64: String?
    public let iv: String
    public let ciphertext: String
    public let tag: String
    public let recipients: [Recipient]

    /// The general JSON serialisation, suitable for `application/jose+json`.
    public func jsonData() throws -> Data {
        var object: [String: Any] = [
            "protected": protectedB64,
            "iv": iv,
            "ciphertext": ciphertext,
            "tag": tag,
            "recipients": recipients.map { ["header": $0.header, "encrypted_key": $0.encryptedKey] as [String: Any] },
        ]
        if let aadB64 { object["aad"] = aadB64 }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Parses general JSON serialisation.
    public init(jsonData: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let protectedB64 = object["protected"] as? String,
              let iv = object["iv"] as? String,
              let ciphertext = object["ciphertext"] as? String,
              let tag = object["tag"] as? String
        else { throw JWEError.malformed("missing JWE members") }

        let recipients: [Recipient]
        if let list = object["recipients"] as? [[String: Any]] {
            recipients = try list.map { entry in
                guard let key = entry["encrypted_key"] as? String else { throw JWEError.malformed("recipient without encrypted_key") }
                return Recipient(header: entry["header"] as? [String: Any] ?? [:], encryptedKey: key)
            }
        } else if let key = object["encrypted_key"] as? String {
            // Flattened serialisation.
            recipients = [Recipient(header: object["header"] as? [String: Any] ?? [:], encryptedKey: key)]
        } else {
            throw JWEError.malformed("no recipients")
        }

        self.init(protectedB64: protectedB64, aadB64: object["aad"] as? String, iv: iv, ciphertext: ciphertext, tag: tag, recipients: recipients)
    }

    init(protectedB64: String, aadB64: String?, iv: String, ciphertext: String, tag: String, recipients: [Recipient]) {
        self.protectedB64 = protectedB64
        self.aadB64 = aadB64
        self.iv = iv
        self.ciphertext = ciphertext
        self.tag = tag
        self.recipients = recipients
    }
}

public extension JWEEncrypter {
    /// Encrypts for a single recipient and returns the compact serialisation
    /// (`header.encrypted_key.iv.ciphertext.tag`), for endpoints that expect `application/jose`.
    func encryptCompact(_ plaintext: Data, to recipient: ECPublicJWK) throws -> String {
        let publicKey = try recipient.keyAgreementKey
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: publicKey)
        let kek = ConcatKDF.derive(sharedSecret: shared, algorithmID: Self.keyManagementAlgorithm, partyUInfo: Data(), partyVInfo: Data(), keyBits: 256)

        var header: [String: Any] = protectedHeader
        header["alg"] = Self.keyManagementAlgorithm
        header["enc"] = Self.contentEncryptionAlgorithm
        header["epk"] = ECPublicJWK(ephemeral.publicKey).jsonObject
        if let kid = recipient.kid { header["kid"] = kid }
        let protectedB64 = Base64URL.encode(try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]))

        let contentKey = SymmetricKey(size: .bits256)
        let wrapped = try AES.KeyWrap.wrap(contentKey, using: kek)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: contentKey, nonce: nonce, authenticating: Data(protectedB64.utf8))

        return [protectedB64, Base64URL.encode(wrapped), Base64URL.encode(Data(nonce)), Base64URL.encode(sealed.ciphertext), Base64URL.encode(sealed.tag)].joined(separator: ".")
    }
}

/// Decrypts JWEs produced by ``JWEEncrypter``. Used by relays written in Swift and by tests.
public struct JWEDecrypter: Sendable {
    public let key: ECPrivateJWK

    public init(key: ECPrivateJWK) {
        self.key = key
    }

    public func decrypt(_ jwe: JWEObject) throws -> Data {
        guard let protectedData = Base64URL.decode(jwe.protectedB64),
              let protected = try JSONSerialization.jsonObject(with: protectedData) as? [String: Any]
        else { throw JWEError.malformed("protected header") }
        guard protected["enc"] as? String == JWEEncrypter.contentEncryptionAlgorithm else {
            throw JWEError.unsupportedAlgorithm(String(describing: protected["enc"]))
        }

        var aadInput = Data(jwe.protectedB64.utf8)
        if let aadB64 = jwe.aadB64 {
            aadInput.append(contentsOf: ".".utf8)
            aadInput.append(contentsOf: aadB64.utf8)
        }
        guard let iv = Base64URL.decode(jwe.iv), let ciphertext = Base64URL.decode(jwe.ciphertext), let tag = Base64URL.decode(jwe.tag) else {
            throw JWEError.malformed("iv, ciphertext or tag")
        }

        for recipient in jwe.recipients {
            var header = protected
            for (k, v) in recipient.header { header[k] = v }
            if let kid = header["kid"] as? String, let ours = key.kid, kid != ours { continue }
            guard header["alg"] as? String == JWEEncrypter.keyManagementAlgorithm else { continue }
            guard let epkObject = header["epk"] as? [String: Any],
                  let epkData = try? JSONSerialization.data(withJSONObject: epkObject),
                  let epk = try? ECPublicJWK(json: epkData),
                  let wrapped = Base64URL.decode(recipient.encryptedKey)
            else { continue }

            do {
                let shared = try key.privateKey.sharedSecretFromKeyAgreement(with: try epk.keyAgreementKey)
                let kek = ConcatKDF.derive(sharedSecret: shared, algorithmID: JWEEncrypter.keyManagementAlgorithm, partyUInfo: Data(), partyVInfo: Data(), keyBits: 256)
                let contentKey = try AES.KeyWrap.unwrap(wrapped, using: kek)
                let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
                return try AES.GCM.open(box, using: contentKey, authenticating: aadInput)
            } catch {
                continue // wrong recipient copy; try the next one
            }
        }
        throw JWEError.decryptionFailed
    }

    /// Decrypts a compact serialisation.
    public func decryptCompact(_ compact: String) throws -> Data {
        let parts = compact.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else { throw JWEError.malformed("compact JWE needs 5 parts") }
        let object = JWEObject(protectedB64: parts[0], aadB64: nil, iv: parts[2], ciphertext: parts[3], tag: parts[4],
                               recipients: [JWEObject.Recipient(header: [:], encryptedKey: parts[1])])
        return try decrypt(object)
    }
}

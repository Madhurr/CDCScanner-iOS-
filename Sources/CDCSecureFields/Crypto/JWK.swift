import Foundation

/// A P-256 public key in JSON Web Key form (RFC 7517, RFC 7518 section 6.2).
///
/// This is how a relay, enclave or payment provider publishes the key the field encrypts to.
public struct ECPublicJWK: Hashable, Sendable, Codable {
    public let kty: String
    public let crv: String
    public let x: String
    public let y: String
    public var kid: String?
    public var use: String?
    public var alg: String?

    enum CodingKeys: String, CodingKey { case kty, crv, x, y, kid, use, alg }

    public init(x: Data, y: Data, kid: String? = nil) {
        self.kty = "EC"
        self.crv = "P-256"
        self.x = Base64URL.encode(x)
        self.y = Base64URL.encode(y)
        self.kid = kid
    }

    public init(_ key: P256.KeyAgreement.PublicKey, kid: String? = nil) {
        let raw = key.rawRepresentation // x || y, 64 bytes
        self.init(x: raw.prefix(32), y: raw.suffix(32), kid: kid)
    }

    /// Parses a JWK JSON document. Throws when it is not a P-256 EC public key.
    public init(json: Data) throws {
        self = try JSONDecoder().decode(ECPublicJWK.self, from: json)
        try validate()
    }

    public func validate() throws {
        guard kty == "EC" else { throw JWEError.unsupportedKey("kty \(kty)") }
        guard crv == "P-256" else { throw JWEError.unsupportedKey("crv \(crv)") }
        guard let xData = Base64URL.decode(x), let yData = Base64URL.decode(y), xData.count == 32, yData.count == 32 else {
            throw JWEError.unsupportedKey("malformed coordinates")
        }
    }

    public var keyAgreementKey: P256.KeyAgreement.PublicKey {
        get throws {
            try validate()
            let raw = Base64URL.decode(x)! + Base64URL.decode(y)!
            return try P256.KeyAgreement.PublicKey(rawRepresentation: raw)
        }
    }

    /// RFC 7638 thumbprint, a stable identifier derived from the key material.
    public var thumbprint: String {
        let canonical = #"{"crv":"P-256","kty":"EC","x":"\#(x)","y":"\#(y)"}"#
        return Base64URL.encode(Data(SHA256.hash(data: Data(canonical.utf8))))
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = ["kty": kty, "crv": crv, "x": x, "y": y]
        if let kid { object["kid"] = kid }
        return object
    }
}

/// A P-256 private key in JWK form. Used by relays and in tests; the SDK itself never needs one.
/// Marked `@unchecked Sendable`: the key is an immutable value; swift-crypto on Linux lacks the annotation.
public struct ECPrivateJWK: @unchecked Sendable {
    public let privateKey: P256.KeyAgreement.PrivateKey
    public var kid: String?

    public init(kid: String? = nil) {
        self.privateKey = P256.KeyAgreement.PrivateKey()
        self.kid = kid
    }

    public init(privateKey: P256.KeyAgreement.PrivateKey, kid: String? = nil) {
        self.privateKey = privateKey
        self.kid = kid
    }

    public init(json: Data) throws {
        struct Raw: Decodable { let kty: String; let crv: String; let d: String; let kid: String? }
        let raw = try JSONDecoder().decode(Raw.self, from: json)
        guard raw.kty == "EC", raw.crv == "P-256", let d = Base64URL.decode(raw.d) else {
            throw JWEError.unsupportedKey("not a P-256 private key")
        }
        self.privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: d)
        self.kid = raw.kid
    }

    public var publicJWK: ECPublicJWK {
        ECPublicJWK(privateKey.publicKey, kid: kid)
    }

    /// Serialises the key, including `d`. Handle the result as a secret.
    public func jsonData() throws -> Data {
        var object = publicJWK.jsonObject
        object["d"] = Base64URL.encode(privateKey.rawRepresentation)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

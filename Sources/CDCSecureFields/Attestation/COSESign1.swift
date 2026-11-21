import Foundation

/// A COSE single-signer message (RFC 9052 section 4.2), as used by AWS Nitro attestation documents.
public struct COSESign1: Sendable {
    public static let tag: UInt64 = 18
    /// COSE algorithm identifier for ECDSA with SHA-384 on P-384.
    public static let es384: Int = -35
    public static let es256: Int = -7

    public let protectedBytes: Data
    public let protectedHeader: CBORValue
    public let unprotectedHeader: CBORValue
    public let payload: Data
    public let signature: Data

    public init(data: Data) throws {
        var value = try CBORDecoder.decode(data)
        if case .tagged(let tag, let inner) = value {
            guard tag == Self.tag else { throw CBORError.malformed("COSE tag \(tag)") }
            value = inner
        }
        guard let items = value.arrayValue, items.count == 4,
              let protectedBytes = items[0].bytesValue,
              let payload = items[2].bytesValue,
              let signature = items[3].bytesValue
        else { throw CBORError.malformed("COSE_Sign1 must be [protected, unprotected, payload, signature]") }

        self.protectedBytes = protectedBytes
        self.protectedHeader = protectedBytes.isEmpty ? .map([:]) : try CBORDecoder.decode(protectedBytes)
        self.unprotectedHeader = items[1]
        self.payload = payload
        self.signature = signature
    }

    /// The `alg` header parameter (label 1).
    public var algorithm: Int? {
        protectedHeader[1]?.intValue
    }

    /// The bytes that are signed: `Sig_structure` = ["Signature1", protected, external_aad, payload].
    public func signatureInput(externalAAD: Data = Data()) -> Data {
        CBOREncoder.encode(.array([.text("Signature1"), .bytes(protectedBytes), .bytes(externalAAD), .bytes(payload)]))
    }

    /// Verifies the signature with a P-384 key (ES384). The COSE signature is raw `r || s`.
    public func verify(with key: P384.Signing.PublicKey, externalAAD: Data = Data()) throws -> Bool {
        guard algorithm == Self.es384 else { throw CBORError.unsupported("COSE alg \(algorithm.map(String.init) ?? "missing")") }
        let signature = try P384.Signing.ECDSASignature(rawRepresentation: self.signature)
        return key.isValidSignature(signature, for: SHA384.hash(data: signatureInput(externalAAD: externalAAD)))
    }
}

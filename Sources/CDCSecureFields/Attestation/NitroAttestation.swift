import Foundation

/// Why an attestation document was rejected.
public enum AttestationError: Error, Equatable, Sendable {
    case malformed(String)
    case unsupportedAlgorithm
    case badSignature
    case untrustedRoot
    case brokenChain(index: Int)
    case certificateNotValid(index: Int)
    case stale(ageSeconds: Double)
    case debugMode
    case pcrMismatch(index: Int)
    case nonceMismatch
    case missingPublicKey
}

/// What to require of an enclave before trusting its key.
///
/// At minimum pin PCR0 (the enclave image hash) to the published hash of the relay release you
/// deploy. Pin PCR1 and PCR2 as well to fix the kernel and application, and PCR8 to fix the
/// signing certificate when the image is signed.
public struct NitroAttestationPolicy: Sendable {
    /// SHA-256 of the DER root certificate the chain must end in. Defaults to the AWS Nitro Enclaves root.
    public var trustedRootSHA256: Data
    /// Accepted values per PCR index. Several values allow a rolling upgrade between two releases.
    public var expectedPCRs: [Int: Set<Data>]
    /// Reject documents older than this.
    public var maxDocumentAge: TimeInterval
    /// Tolerated difference between the device clock and the enclave's.
    public var clockSkewTolerance: TimeInterval
    /// When set, the document's `nonce` must equal this value.
    public var expectedNonce: Data?
    /// Debug-mode enclaves report all-zero PCRs and must never be trusted in production.
    public var allowsDebugMode: Bool

    public init(
        trustedRootSHA256: Data = NitroAttestationPolicy.awsNitroRootSHA256,
        expectedPCRs: [Int: Set<Data>],
        maxDocumentAge: TimeInterval = 300,
        clockSkewTolerance: TimeInterval = 120,
        expectedNonce: Data? = nil,
        allowsDebugMode: Bool = false
    ) {
        self.trustedRootSHA256 = trustedRootSHA256
        self.expectedPCRs = expectedPCRs
        self.maxDocumentAge = maxDocumentAge
        self.clockSkewTolerance = clockSkewTolerance
        self.expectedNonce = expectedNonce
        self.allowsDebugMode = allowsDebugMode
    }

    /// SHA-256 fingerprint of `AWS_NitroEnclaves_Root-G1`, computed from the certificate AWS publishes at
    /// https://aws-nitro-enclaves.amazonaws.com/AWS_NitroEnclaves_Root-G1.zip and matching the value on
    /// https://docs.aws.amazon.com/enclaves/latest/user/verify-root.html.
    public static let awsNitroRootSHA256 = Data(hexString: "641a0321a3e244efe456463195d606317ed7cdcc3c1756e09893f3c68f79bb5b")!

    /// The AWS Nitro Enclaves root certificate (CN=aws.nitro-enclaves, valid 2019-10-28 to 2049-10-28).
    public static let awsNitroRootPEM = """
-----BEGIN CERTIFICATE-----
MIICETCCAZagAwIBAgIRAPkxdWgbkK/hHUbMtOTn+FYwCgYIKoZIzj0EAwMwSTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoMBkFtYXpvbjEMMAoGA1UECwwDQVdTMRswGQYD
VQQDDBJhd3Mubml0cm8tZW5jbGF2ZXMwHhcNMTkxMDI4MTMyODA1WhcNNDkxMDI4
MTQyODA1WjBJMQswCQYDVQQGEwJVUzEPMA0GA1UECgwGQW1hem9uMQwwCgYDVQQL
DANBV1MxGzAZBgNVBAMMEmF3cy5uaXRyby1lbmNsYXZlczB2MBAGByqGSM49AgEG
BSuBBAAiA2IABPwCVOumCMHzaHDimtqQvkY4MpJzbolL//Zy2YlES1BR5TSksfbb
48C8WBoyt7F2Bw7eEtaaP+ohG2bnUs990d0JX28TcPQXCEPZ3BABIeTPYwEoCWZE
h8l5YoQwTcU/9KNCMEAwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUkCW1DdkF
R+eWw5b6cp3PmanfS5YwDgYDVR0PAQH/BAQDAgGGMAoGCCqGSM49BAMDA2kAMGYC
MQCjfy+Rocm9Xue4YnwWmNJVA44fA0P5W2OpYow9OYCVRaEevL8uO1XYru5xtMPW
rfMCMQCi85sWBbJwKKXdS6BptQFuZbT73o/gBh1qUxl/nNr12UO8Yfwr6wPLb+6N
IwLz3/Y=
-----END CERTIFICATE-----
"""
}

/// The verified contents of an attestation document.
public struct NitroAttestationDocument: Sendable {
    public let moduleID: String
    public let timestamp: Date
    public let digest: String
    public let pcrs: [Int: Data]
    public let certificate: Data
    public let cabundle: [Data]
    public let publicKey: Data?
    public let userData: Data?
    public let nonce: Data?

    /// The enclave's encryption key, as a JWK JSON document or a DER SubjectPublicKeyInfo (P-256).
    public func recipientKey(kid: String? = nil) throws -> ECPublicJWK {
        guard let publicKey, !publicKey.isEmpty else { throw AttestationError.missingPublicKey }
        if let jwk = try? ECPublicJWK(json: publicKey) {
            var key = jwk
            if let kid { key.kid = kid }
            return key
        }
        let spki = try ASN1.parse(publicKey)
        let parts = try spki.children()
        guard parts.count == 2, parts[1].tag == 0x03 else { throw AttestationError.malformed("public_key") }
        let algorithm = try parts[0].children()
        guard algorithm.count == 2,
              ASN1.oid(algorithm[0].contentData) == X509Certificate.ecPublicKeyOID,
              ASN1.oid(algorithm[1].contentData) == X509Certificate.prime256v1OID
        else { throw AttestationError.malformed("public_key must be a P-256 key") }
        let point = parts[1].contentData.dropFirst()
        guard point.count == 65, point.first == 0x04 else { throw AttestationError.malformed("public_key point") }
        return ECPublicJWK(x: point.dropFirst().prefix(32), y: point.suffix(32), kid: kid ?? moduleID)
    }
}

/// Verifies AWS Nitro Enclaves attestation documents without any platform certificate API, so the
/// same code runs on iOS, macOS and Linux and can be unit tested.
///
/// Verification steps, in order:
/// 1. Parse the COSE_Sign1 envelope and require ES384.
/// 2. Parse the CBOR payload and its mandatory fields; require `digest == "SHA384"`.
/// 3. Build the path leaf → intermediates → root from `certificate` and `cabundle`, check every
///    certificate's validity period, verify each signature with its issuer's key, and require the
///    root's SHA-256 to equal the policy's trusted root.
/// 4. Verify the COSE signature with the leaf certificate's P-384 key.
/// 5. Check freshness, debug mode, PCR values and the nonce against the policy.
public struct NitroAttestationVerifier: Sendable {
    public var policy: NitroAttestationPolicy

    public init(policy: NitroAttestationPolicy) {
        self.policy = policy
    }

    public func verify(_ document: Data, now: Date = Date()) throws -> NitroAttestationDocument {
        let cose: COSESign1
        do { cose = try COSESign1(data: document) } catch { throw AttestationError.malformed("COSE: \(error)") }
        guard cose.algorithm == COSESign1.es384 else { throw AttestationError.unsupportedAlgorithm }

        let payload: CBORValue
        do { payload = try CBORDecoder.decode(cose.payload) } catch { throw AttestationError.malformed("payload: \(error)") }
        let parsed = try Self.parse(payload)
        guard parsed.digest == "SHA384" else { throw AttestationError.malformed("digest \(parsed.digest)") }

        var path: [X509Certificate] = []
        do {
            path.append(try X509Certificate(der: parsed.certificate))
            for der in parsed.cabundle.reversed() { path.append(try X509Certificate(der: der)) }
        } catch { throw AttestationError.malformed("certificate: \(error)") }
        guard path.count >= 2 else { throw AttestationError.brokenChain(index: 0) }

        for (index, certificate) in path.enumerated() where !certificate.isValid(at: now) {
            throw AttestationError.certificateNotValid(index: index)
        }
        for index in 0..<(path.count - 1) where !path[index].isSigned(by: path[index + 1]) {
            throw AttestationError.brokenChain(index: index)
        }
        let root = path[path.count - 1]
        guard root.isSigned(by: root), root.sha256Fingerprint == policy.trustedRootSHA256 else {
            throw AttestationError.untrustedRoot
        }

        guard path[0].curve == .p384 else { throw AttestationError.unsupportedAlgorithm }
        let leafKey: P384.Signing.PublicKey
        do { leafKey = try P384.Signing.PublicKey(x963Representation: path[0].publicKeyPoint) } catch { throw AttestationError.malformed("leaf key") }
        guard (try? cose.verify(with: leafKey)) == true else { throw AttestationError.badSignature }

        let age = now.timeIntervalSince(parsed.timestamp)
        guard age <= policy.maxDocumentAge, age >= -policy.clockSkewTolerance else {
            throw AttestationError.stale(ageSeconds: age)
        }

        if let pcr0 = parsed.pcrs[0], pcr0.allSatisfy({ $0 == 0 }), !policy.allowsDebugMode {
            throw AttestationError.debugMode
        }
        for (index, accepted) in policy.expectedPCRs {
            guard let actual = parsed.pcrs[index], accepted.contains(actual) else {
                throw AttestationError.pcrMismatch(index: index)
            }
        }
        if let expected = policy.expectedNonce {
            guard parsed.nonce == expected else { throw AttestationError.nonceMismatch }
        }
        return parsed
    }

    private static func parse(_ payload: CBORValue) throws -> NitroAttestationDocument {
        guard let moduleID = payload["module_id"]?.textValue, !moduleID.isEmpty else { throw AttestationError.malformed("module_id") }
        guard let digest = payload["digest"]?.textValue else { throw AttestationError.malformed("digest") }
        guard let timestampMs = payload["timestamp"]?.uint64Value, timestampMs > 0 else { throw AttestationError.malformed("timestamp") }
        guard let pcrMap = payload["pcrs"]?.mapValue, !pcrMap.isEmpty, pcrMap.count <= 32 else { throw AttestationError.malformed("pcrs") }
        var pcrs: [Int: Data] = [:]
        for (key, value) in pcrMap {
            guard let index = key.intValue, (0..<32).contains(index), let bytes = value.bytesValue, [32, 48, 64].contains(bytes.count) else {
                throw AttestationError.malformed("pcr entry")
            }
            pcrs[index] = bytes
        }
        guard let certificate = payload["certificate"]?.bytesValue, !certificate.isEmpty, certificate.count <= 1024 else { throw AttestationError.malformed("certificate") }
        guard let bundle = payload["cabundle"]?.arrayValue, !bundle.isEmpty else { throw AttestationError.malformed("cabundle") }
        let cabundle = try bundle.map { item -> Data in
            guard let der = item.bytesValue, !der.isEmpty, der.count <= 1024 else { throw AttestationError.malformed("cabundle entry") }
            return der
        }
        func optionalBytes(_ name: String) throws -> Data? {
            guard let value = payload[name] else { return nil }
            if case .null = value { return nil }
            guard let bytes = value.bytesValue, bytes.count <= 1024 else { throw AttestationError.malformed(name) }
            return bytes
        }
        return NitroAttestationDocument(
            moduleID: moduleID,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000),
            digest: digest,
            pcrs: pcrs,
            certificate: certificate,
            cabundle: cabundle,
            publicKey: try optionalBytes("public_key"),
            userData: try optionalBytes("user_data"),
            nonce: try optionalBytes("nonce")
        )
    }
}

extension Data {
    /// Parses hex, ignoring colons and whitespace.
    public init?(hexString: String) {
        let clean = hexString.filter { !$0.isWhitespace && $0 != ":" }
        guard clean.count % 2 == 0 else { return nil }
        var data = Data(capacity: clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    public var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

import Foundation

/// The minimum of ASN.1 DER and X.509 needed to validate an ECDSA certificate chain without a
/// platform dependency: enough to pull out the public key, validity dates, the signed bytes and
/// the signature. Not a general-purpose parser.
enum ASN1 {
    struct Node {
        let tag: UInt8
        let header: Range<Int>
        let content: Range<Int>
        let data: Data

        var contentData: Data { data.subdata(in: content) }
        /// The full TLV bytes.
        var encoded: Data { data.subdata(in: header.lowerBound..<content.upperBound) }

        func children() throws -> [Node] {
            var nodes: [Node] = []
            var offset = content.lowerBound
            while offset < content.upperBound {
                let node = try ASN1.parse(data, at: offset)
                nodes.append(node)
                offset = node.content.upperBound
            }
            return nodes
        }
    }

    enum Error: Swift.Error { case truncated, unsupportedLength, unexpectedStructure(String) }

    static func parse(_ data: Data, at start: Int = 0) throws -> Node {
        guard start < data.endIndex - 1 else { throw Error.truncated }
        let tag = data[data.startIndex + start]
        var index = start + 1
        let first = data[data.startIndex + index]
        index += 1
        var length = Int(first & 0x7f)
        if first & 0x80 != 0 {
            let count = Int(first & 0x7f)
            guard count >= 1, count <= 4, data.count - index >= count else { throw Error.unsupportedLength }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(data[data.startIndex + index])
                index += 1
            }
        }
        guard data.count - index >= length else { throw Error.truncated }
        return Node(tag: tag, header: start..<index, content: index..<(index + length), data: data)
    }

    static func oid(_ content: Data) -> String {
        guard let first = content.first else { return "" }
        var components = [String(Int(first) / 40), String(Int(first) % 40)]
        var value = 0
        for byte in content.dropFirst() {
            value = value << 7 | Int(byte & 0x7f)
            if byte & 0x80 == 0 {
                components.append(String(value))
                value = 0
            }
        }
        return components.joined(separator: ".")
    }
}

/// An X.509 certificate reduced to the fields a chain check needs.
struct X509Certificate {
    enum Curve { case p256, p384 }
    enum SignatureAlgorithm { case ecdsaSHA256, ecdsaSHA384 }

    let der: Data
    let tbsCertificate: Data
    let signature: Data
    let signatureAlgorithm: SignatureAlgorithm
    let curve: Curve
    /// Uncompressed EC point, `04 || x || y`.
    let publicKeyPoint: Data
    let notBefore: Date
    let notAfter: Date
    let subject: Data
    let issuer: Data

    static let ecPublicKeyOID = "1.2.840.10045.2.1"
    static let prime256v1OID = "1.2.840.10045.3.1.7"
    static let secp384r1OID = "1.3.132.0.34"
    static let ecdsaWithSHA256OID = "1.2.840.10045.4.3.2"
    static let ecdsaWithSHA384OID = "1.2.840.10045.4.3.3"

    init(der: Data) throws {
        let certificate = try ASN1.parse(der)
        let parts = try certificate.children()
        guard certificate.tag == 0x30, parts.count == 3 else { throw ASN1.Error.unexpectedStructure("Certificate") }
        let tbs = parts[0]
        let sigAlg = try parts[1].children()
        let sigValue = parts[2]
        guard sigValue.tag == 0x03, let sigAlgOID = sigAlg.first, sigAlgOID.tag == 0x06 else { throw ASN1.Error.unexpectedStructure("signature") }

        switch ASN1.oid(sigAlgOID.contentData) {
        case Self.ecdsaWithSHA256OID: signatureAlgorithm = .ecdsaSHA256
        case Self.ecdsaWithSHA384OID: signatureAlgorithm = .ecdsaSHA384
        case let other: throw ASN1.Error.unexpectedStructure("signature algorithm \(other)")
        }
        // BIT STRING: first content byte is the unused-bits count.
        signature = sigValue.contentData.dropFirst()
        tbsCertificate = tbs.encoded
        self.der = der

        var fields = try tbs.children()
        if let first = fields.first, first.tag == 0xa0 { fields.removeFirst() } // explicit version
        // serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
        guard fields.count >= 6 else { throw ASN1.Error.unexpectedStructure("TBSCertificate") }
        issuer = fields[2].encoded
        subject = fields[4].encoded

        let validity = try fields[3].children()
        guard validity.count == 2 else { throw ASN1.Error.unexpectedStructure("Validity") }
        notBefore = try Self.parseTime(validity[0])
        notAfter = try Self.parseTime(validity[1])

        let spki = try fields[5].children()
        guard spki.count == 2, spki[1].tag == 0x03 else { throw ASN1.Error.unexpectedStructure("SubjectPublicKeyInfo") }
        let algorithm = try spki[0].children()
        guard algorithm.count == 2, ASN1.oid(algorithm[0].contentData) == Self.ecPublicKeyOID else {
            throw ASN1.Error.unexpectedStructure("only EC public keys are supported")
        }
        switch ASN1.oid(algorithm[1].contentData) {
        case Self.prime256v1OID: curve = .p256
        case Self.secp384r1OID: curve = .p384
        case let other: throw ASN1.Error.unexpectedStructure("curve \(other)")
        }
        publicKeyPoint = spki[1].contentData.dropFirst()
        guard publicKeyPoint.first == 0x04 else { throw ASN1.Error.unexpectedStructure("compressed EC point") }
    }

    var sha256Fingerprint: Data { Data(SHA256.hash(data: der)) }

    func isValid(at date: Date) -> Bool {
        date >= notBefore && date <= notAfter
    }

    /// Verifies that this certificate was signed by `issuer`'s key.
    func isSigned(by issuer: X509Certificate) -> Bool {
        do {
            switch (issuer.curve, signatureAlgorithm) {
            case (.p384, .ecdsaSHA384):
                let key = try P384.Signing.PublicKey(x963Representation: issuer.publicKeyPoint)
                return key.isValidSignature(try P384.Signing.ECDSASignature(derRepresentation: signature), for: SHA384.hash(data: tbsCertificate))
            case (.p256, .ecdsaSHA256):
                let key = try P256.Signing.PublicKey(x963Representation: issuer.publicKeyPoint)
                return key.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: signature), for: SHA256.hash(data: tbsCertificate))
            case (.p256, .ecdsaSHA384):
                let key = try P256.Signing.PublicKey(x963Representation: issuer.publicKeyPoint)
                return key.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: signature), for: SHA384.hash(data: tbsCertificate))
            case (.p384, .ecdsaSHA256):
                let key = try P384.Signing.PublicKey(x963Representation: issuer.publicKeyPoint)
                return key.isValidSignature(try P384.Signing.ECDSASignature(derRepresentation: signature), for: SHA256.hash(data: tbsCertificate))
            }
        } catch {
            return false
        }
    }

    private static func parseTime(_ node: ASN1.Node) throws -> Date {
        guard let text = String(data: node.contentData, encoding: .ascii) else { throw ASN1.Error.unexpectedStructure("time") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        switch node.tag {
        case 0x17: formatter.dateFormat = "yyMMddHHmmss'Z'"   // UTCTime
        case 0x18: formatter.dateFormat = "yyyyMMddHHmmss'Z'" // GeneralizedTime
        default: throw ASN1.Error.unexpectedStructure("time tag \(node.tag)")
        }
        guard let date = formatter.date(from: text) else { throw ASN1.Error.unexpectedStructure("time format \(text)") }
        return date
    }

    /// Parses a PEM-encoded certificate.
    init(pem: String) throws {
        let body = pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body) else { throw ASN1.Error.unexpectedStructure("PEM") }
        try self.init(der: der)
    }
}

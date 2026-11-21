import Foundation

/// The single-step Concat KDF from NIST SP 800-56A section 5.8.1, as profiled by RFC 7518
/// section 4.6.2 for ECDH-ES.
enum ConcatKDF {
    /// Derives `keyBits` bits (256 here, a single SHA-256 round) from the ECDH shared secret.
    static func derive(sharedSecret: SharedSecret, algorithmID: String, partyUInfo: Data, partyVInfo: Data, keyBits: Int) -> SymmetricKey {
        precondition(keyBits == 256, "Only 256-bit output is needed for A256KW/A256GCM.")
        var otherInfo = Data()
        otherInfo.append(lengthPrefixed(Data(algorithmID.utf8)))
        otherInfo.append(lengthPrefixed(partyUInfo))
        otherInfo.append(lengthPrefixed(partyVInfo))
        otherInfo.append(bigEndian(UInt32(keyBits)))

        var input = bigEndian(UInt32(1)) // round counter
        sharedSecret.withUnsafeBytes { input.append(contentsOf: $0) }
        input.append(otherInfo)
        return SymmetricKey(data: Data(SHA256.hash(data: input)))
    }

    private static func lengthPrefixed(_ data: Data) -> Data {
        bigEndian(UInt32(data.count)) + data
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 4)
    }
}

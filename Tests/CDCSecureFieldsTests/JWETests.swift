import XCTest
@testable import CDCSecureFields

final class JWETests: XCTestCase {
    let plaintext = Data(#"{"number":"4111111111111111","cvc":"123"}"#.utf8)

    func testRoundTripSingleRecipient() throws {
        let key = ECPrivateJWK(kid: "k1")
        let jwe = try JWEEncrypter().encrypt(plaintext, to: [key.publicJWK])
        XCTAssertEqual(jwe.recipients.count, 1)
        XCTAssertEqual(jwe.recipients[0].header["kid"] as? String, "k1")
        XCTAssertNotNil(jwe.recipients[0].header["epk"])
        XCTAssertEqual(try JWEDecrypter(key: key).decrypt(jwe), plaintext)
    }

    func testRoundTripThreeRecipientsEachCanOpen() throws {
        let keys = [ECPrivateJWK(kid: "relay"), ECPrivateJWK(kid: "psp-a"), ECPrivateJWK(kid: "psp-b")]
        let jwe = try JWEEncrypter().encrypt(plaintext, to: keys.map(\.publicJWK))
        XCTAssertEqual(jwe.recipients.count, 3)
        for key in keys {
            XCTAssertEqual(try JWEDecrypter(key: key).decrypt(jwe), plaintext, key.kid ?? "")
        }
    }

    func testOutsiderCannotDecrypt() throws {
        let jwe = try JWEEncrypter().encrypt(plaintext, to: [ECPrivateJWK(kid: "a").publicJWK])
        XCTAssertThrowsError(try JWEDecrypter(key: ECPrivateJWK(kid: "a")).decrypt(jwe)) { error in
            XCTAssertEqual(error as? JWEError, .decryptionFailed)
        }
    }

    func testJSONSerialisationRoundTrip() throws {
        let key = ECPrivateJWK(kid: "k")
        let jwe = try JWEEncrypter(protectedHeader: ["typ": "cdc+card"]).encrypt(plaintext, to: [key.publicJWK], aad: Data("req-1".utf8))
        let data = try jwe.jsonData()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["protected"]); XCTAssertNotNil(json["iv"]); XCTAssertNotNil(json["ciphertext"]); XCTAssertNotNil(json["tag"])
        XCTAssertEqual(json["aad"] as? String, Base64URL.encode(Data("req-1".utf8)))
        let protected = try XCTUnwrap(JSONSerialization.jsonObject(with: Base64URL.decode(json["protected"] as! String)!) as? [String: String])
        XCTAssertEqual(protected, ["alg": "ECDH-ES+A256KW", "enc": "A256GCM", "typ": "cdc+card"])
        let parsed = try JWEObject(jsonData: data)
        XCTAssertEqual(try JWEDecrypter(key: key).decrypt(parsed), plaintext)
    }

    func testTamperedCiphertextOrAADFails() throws {
        let key = ECPrivateJWK(kid: "k")
        let jwe = try JWEEncrypter().encrypt(plaintext, to: [key.publicJWK], aad: Data("req-1".utf8))
        let tamperedAAD = JWEObject(protectedB64: jwe.protectedB64, aadB64: Base64URL.encode(Data("req-2".utf8)), iv: jwe.iv, ciphertext: jwe.ciphertext, tag: jwe.tag, recipients: jwe.recipients)
        XCTAssertThrowsError(try JWEDecrypter(key: key).decrypt(tamperedAAD))
        var bytes = Base64URL.decode(jwe.ciphertext)!
        bytes[0] ^= 0xFF
        let tamperedCiphertext = JWEObject(protectedB64: jwe.protectedB64, aadB64: jwe.aadB64, iv: jwe.iv, ciphertext: Base64URL.encode(bytes), tag: jwe.tag, recipients: jwe.recipients)
        XCTAssertThrowsError(try JWEDecrypter(key: key).decrypt(tamperedCiphertext))
    }

    func testCompactRoundTrip() throws {
        let key = ECPrivateJWK(kid: "k")
        let compact = try JWEEncrypter().encryptCompact(plaintext, to: key.publicJWK)
        XCTAssertEqual(compact.split(separator: ".").count, 5)
        XCTAssertEqual(try JWEDecrypter(key: key).decryptCompact(compact), plaintext)
    }

    func testJWKParsingAndThumbprint() throws {
        let key = ECPrivateJWK(kid: "k")
        let json = try JSONSerialization.data(withJSONObject: key.publicJWK.jsonObject)
        let parsed = try ECPublicJWK(json: json)
        XCTAssertEqual(parsed, key.publicJWK)
        XCTAssertEqual(parsed.thumbprint.count, 43)
        XCTAssertThrowsError(try ECPublicJWK(json: Data(#"{"kty":"RSA","crv":"P-256","x":"AA","y":"AA"}"#.utf8)))
        let reparsedPrivate = try ECPrivateJWK(json: try key.jsonData())
        XCTAssertEqual(reparsedPrivate.publicJWK, key.publicJWK)
    }

    func testBase64URL() {
        XCTAssertEqual(Base64URL.encode(Data([0xfb, 0xff, 0xbf])), "-_-_")
        XCTAssertEqual(Base64URL.decode("-_-_"), Data([0xfb, 0xff, 0xbf]))
        XCTAssertEqual(Base64URL.encode(Data("hi".utf8)), "aGk")
        XCTAssertEqual(Base64URL.decode("aGk"), Data("hi".utf8))
    }
}

import XCTest
@testable import CDCSecureFields

/// Fixtures were produced by the Python `jwcrypto` library, an independent JOSE implementation.
final class JWEInteropTests: XCTestCase {
    static let relayA = try! ECPrivateJWK(json: Data("{\"crv\":\"P-256\",\"d\":\"yK3_-xiw0U2ARNIaxQD_P7txaVUcPY_J5rdbB_3orxA\",\"kid\":\"relay-a\",\"kty\":\"EC\",\"x\":\"Dcwnb7wZzX5y6ufm1JwIAyRlJmgLKHjaMBx19udqPGQ\",\"y\":\"1Zi8xZYq_v2QRfHozb1OTy-23Cyig1qqtWkwKdnzcwY\"}".utf8))
    static let relayB = try! ECPrivateJWK(json: Data("{\"crv\":\"P-256\",\"d\":\"hjrbd0-utNEHsCYvj4yh71wULsQwJGzH0ONPZjxX48k\",\"kid\":\"relay-b\",\"kty\":\"EC\",\"x\":\"4fAR31Sh1GqZvMDOOMCGcSdFgaHpMgBNAtLiZfBi_pI\",\"y\":\"4kxJpu9_CsGydAc4J1pdQR9oGqzalWAzS0mAfYNWtHE\"}".utf8))
    static let plaintext = "{\"number\":\"4111111111111111\",\"exp_month\":\"09\",\"exp_year\":\"2027\",\"cvc\":\"123\"}"
    static let generalFromPython = "{\"ciphertext\":\"1tYbomOmJzJJBe7rle7jrmpuVm4CNm-Cx8vGGhTP0NcSF11UVR3qQ2GLVWCjue-6i4RAqw1rx8VctZ0DbtX5_bCbgcbrFJkL3tpJWA\",\"iv\":\"cGkt7FDw9_gnR9db\",\"protected\":\"eyJlbmMiOiAiQTI1NkdDTSIsICJhbGciOiAiRUNESC1FUytBMjU2S1ciLCAidHlwIjogImNkYytjYXJkIn0\",\"recipients\":[{\"encrypted_key\":\"wJssoKikfkfllLN0kQfR-JTFc7xT_QMtbzOkqxbVkKlrh2sSyYpagg\",\"header\":{\"epk\":{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"zwehS9xsVDneueu8uk8CRz7GtHHivnxqPKxw68ETbjE\",\"y\":\"XopOjsCWjZ3D96iM4LxwTCU0PrY6oF8om57z-dVRZJ8\"},\"kid\":\"relay-a\"}},{\"encrypted_key\":\"hNNVWGGQzUNLWbi_ElGF8u_u9TnGukm8J93UZxlbk5pXixI6AC3hrw\",\"header\":{\"epk\":{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"M2Gr8FnuU0rNhJ53nyxsVoJWXSwuscK1TeTHur48nQY\",\"y\":\"i-oFza1iLCv2vr6yqEf2jm0hkSCiSyPQS-vo2Bp03RI\"},\"kid\":\"relay-b\"}}],\"tag\":\"7uU0sltU47O7sjI9b6pa1Q\"}"
    static let compactFromPython = "eyJhbGciOiJFQ0RILUVTK0EyNTZLVyIsImVuYyI6IkEyNTZHQ00iLCJlcGsiOnsiY3J2IjoiUC0yNTYiLCJrdHkiOiJFQyIsIngiOiJtYzEzQVlqYlpVXzc3cmtQVFFGMjNlcG1LdUFreUNGRUZGc3o2ZDhwNF9nIiwieSI6IlN5TjhGZUlBeDFXZ29la3ppNUJ3c0JDbXlFZHhTWFd5QWVUNE5KTU5MRmMifSwia2lkIjoicmVsYXktYiJ9.kjOw7OBf4Rq4tcZzwecGV80G6MPnxYqMYbog-odp4Sogz19D_HpD0A.kfXIUPGO3suigCF_.hX3TRqimVtsgUI0aVGgsW6Ze7j9WwpqvLvqUIBXrkE6eMa8WA9qBRpnkjI4eoUIQ4a-EsEVd2Axkiq1d92IonV2tLzIyNlLXhv1mSA.QzBOtikgx2bezyC3Xx0whA"
    static let withAADFromPython = "{\"aad\":\"bm9uY2UtMTIzNDU\",\"ciphertext\":\"u_vGE14wmXR_vFJmbVZghYkJZv61GY7-eEATwY4h9BLa9VSndD-Yh8a-QYkoVmobtGSkjpw5x7EOByqYQRc0icscN65mN1UZNawdtg\",\"encrypted_key\":\"jmx2c3jhgAD4M9TXYJAJuj8eCD8NhAZ5Fmae31HzDFHRmGMmXJVfZA\",\"header\":{\"epk\":{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"tHkH-9iatb_PwSrSUpH1wOC1hZlPZHCWU_tSOA4-G-c\",\"y\":\"B4qCu6NHp9rTNdnn4smxQ2V_m3MFmqpGT3fpykZMOhg\"},\"kid\":\"relay-a\"},\"iv\":\"p3uaoJZUcz_oTkxB\",\"protected\":\"eyJlbmMiOiAiQTI1NkdDTSIsICJhbGciOiAiRUNESC1FUytBMjU2S1cifQ\",\"tag\":\"glOSphVVocf_OwpHKttlow\"}"

    func testDecryptsMultiRecipientJWEFromJwcrypto() throws {
        let jwe = try JWEObject(jsonData: Data(Self.generalFromPython.utf8))
        XCTAssertEqual(jwe.recipients.count, 2)
        XCTAssertEqual(String(decoding: try JWEDecrypter(key: Self.relayA).decrypt(jwe), as: UTF8.self), Self.plaintext)
        XCTAssertEqual(String(decoding: try JWEDecrypter(key: Self.relayB).decrypt(jwe), as: UTF8.self), Self.plaintext)
    }

    func testDecryptsCompactJWEFromJwcrypto() throws {
        XCTAssertEqual(String(decoding: try JWEDecrypter(key: Self.relayB).decryptCompact(Self.compactFromPython), as: UTF8.self), Self.plaintext)
        XCTAssertThrowsError(try JWEDecrypter(key: Self.relayA).decryptCompact(Self.compactFromPython))
    }

    func testDecryptsJWEWithAADFromJwcrypto() throws {
        let jwe = try JWEObject(jsonData: Data(Self.withAADFromPython.utf8))
        XCTAssertEqual(Base64URL.decode(jwe.aadB64 ?? ""), Data("nonce-12345".utf8))
        XCTAssertEqual(String(decoding: try JWEDecrypter(key: Self.relayA).decrypt(jwe), as: UTF8.self), Self.plaintext)
    }

    /// Writes a Swift-produced JWE to `CDC_JWE_OUT` so an external implementation can decrypt it.
    func testExportsJWEForExternalVerification() throws {
        guard let path = ProcessInfo.processInfo.environment["CDC_JWE_OUT"] else { return }
        let encrypter = JWEEncrypter(protectedHeader: ["typ": "cdc+card"])
        let general = try encrypter.encrypt(Data(Self.plaintext.utf8), to: [Self.relayA.publicJWK, Self.relayB.publicJWK], aad: Data("nonce-12345".utf8))
        let compact = try encrypter.encryptCompact(Data(Self.plaintext.utf8), to: Self.relayB.publicJWK)
        let out: [String: Any] = ["general": String(decoding: try general.jsonData(), as: UTF8.self), "compact": compact]
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: path))
    }
}

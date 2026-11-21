import XCTest
@testable import CDCSecureFields
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class EncryptingTokenizerTests: XCTestCase {
    let card = SecureCardData(number: "4111 1111 1111 1111", expiry: CardExpiry(month: 9, year: 2027), securityCode: "123", cardholderName: "Jane Doe")

    func testRequestBodyIsJWEOnlyRecipientsCanOpen() async throws {
        let relay = ECPrivateJWK(kid: "relay")
        let psp = ECPrivateJWK(kid: "psp")
        let tokenizer = EncryptingTokenizer(
            url: URL(string: "https://relay.example.com/v1/tokenize")!,
            recipients: StaticRecipientKeys([relay.publicJWK, psp.publicJWK]),
            headers: ["X-Merchant": "m_1"],
            additionalClaims: ["reference": "order-42"]
        )
        let request = try tokenizer.makeRequest(for: card, recipients: try await tokenizer.recipients.recipientKeys(), now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/jose+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Merchant"), "m_1")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("4111"), "ciphertext must not contain the PAN")

        let jwe = try JWEObject(jsonData: body)
        XCTAssertEqual(jwe.recipients.count, 2)
        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: Base64URL.decode(jwe.protectedB64)!) as? [String: String])
        XCTAssertEqual(header["typ"], EncryptingTokenizer.payloadType)
        XCTAssertEqual(header["iat"], "1800000000")
        XCTAssertEqual(header["nonce"]?.count, 32)

        for key in [relay, psp] {
            let plaintext = try JWEDecrypter(key: key).decrypt(jwe)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: plaintext) as? [String: String])
            XCTAssertEqual(json, ["number": "4111111111111111", "cvc": "123", "exp_month": "09", "exp_year": "2027", "name": "Jane Doe", "reference": "order-42"])
        }
        XCTAssertThrowsError(try JWEDecrypter(key: ECPrivateJWK(kid: "relay")).decrypt(jwe), "a different key with the same kid cannot open it")
    }

    func testRefusesPlainHTTPAndEmptyRecipients() async {
        let insecure = EncryptingTokenizer(url: URL(string: "http://relay.example.com")!, recipients: StaticRecipientKeys([ECPrivateJWK().publicJWK]))
        do { _ = try await insecure.tokenize(card); XCTFail() } catch { XCTAssertEqual(error as? TokenizationError, .insecureEndpoint) }
        let empty = EncryptingTokenizer(url: URL(string: "https://relay.example.com")!, recipients: StaticRecipientKeys([]))
        do { _ = try await empty.tokenize(card); XCTFail() } catch { XCTAssertEqual(error as? TokenizationError, .invalidCardData("No recipient keys available.")) }
    }

    func testCombinedProviders() async throws {
        let a = ECPrivateJWK(kid: "a"), b = ECPrivateJWK(kid: "b")
        let keys = try await CombinedRecipientKeys([StaticRecipientKeys(a.publicJWK), StaticRecipientKeys(b.publicJWK)]).recipientKeys()
        XCTAssertEqual(keys.map(\.kid), ["a", "b"])
    }

    func testAttestationHeadersContract() {
        XCTAssertEqual(AttestationHeaders.keyID, "X-App-Attest-Key-Id")
        XCTAssertEqual(AttestationHeaders.assertion, "X-App-Attest-Assertion")
    }
}

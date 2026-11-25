import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CDCSecureFields

final class HTTPTokenizerTests: XCTestCase {
    let card = SecureCardData(number: "4111111111111111", expiry: CardExpiry(month: 9, year: 2027), securityCode: "123", cardholderName: "Jane Doe")

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDefaultMapping() throws {
        let tokenizer = HTTPTokenizer(url: URL(string: "https://vault.example.com/tokens")!, headers: ["Authorization": "Bearer pk_test"])
        let request = try tokenizer.makeRequest(for: card)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer pk_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)

        let json = try body(of: request)
        XCTAssertEqual(json["number"] as? String, "4111111111111111")
        XCTAssertEqual(json["exp_month"] as? String, "09")
        XCTAssertEqual(json["exp_year"] as? String, "2027")
        XCTAssertEqual(json["cvc"] as? String, "123")
        XCTAssertEqual(json["name"] as? String, "Jane Doe")
    }

    func testNestedMappingWithNumericTwoDigitDates() throws {
        let mapping = HTTPTokenizer.FieldMapping(
            number: "card.number",
            expiryMonth: "card.exp.month",
            expiryYear: "card.exp.year",
            securityCode: nil,
            cardholderName: nil,
            usesFourDigitYear: false,
            usesNumericDates: true
        )
        let tokenizer = HTTPTokenizer(url: URL(string: "https://vault.example.com/tokens")!, mapping: mapping, additionalFields: ["type": "card"])
        let json = try body(of: try tokenizer.makeRequest(for: card))
        let cardJSON = try XCTUnwrap(json["card"] as? [String: Any])
        let exp = try XCTUnwrap(cardJSON["exp"] as? [String: Any])
        XCTAssertEqual(cardJSON["number"] as? String, "4111111111111111")
        XCTAssertEqual(exp["month"] as? Int, 9)
        XCTAssertEqual(exp["year"] as? Int, 27)
        XCTAssertNil(cardJSON["cvc"])
        XCTAssertNil(json["name"])
        XCTAssertEqual(json["type"] as? String, "card")
    }

    func testCombinedExpiryField() throws {
        let mapping = HTTPTokenizer.FieldMapping(expiryMonth: nil, expiryYear: nil, expiry: "expiry", usesFourDigitYear: false)
        let tokenizer = HTTPTokenizer(url: URL(string: "https://vault.example.com/tokens")!, mapping: mapping)
        let json = try body(of: try tokenizer.makeRequest(for: card))
        XCTAssertEqual(json["expiry"] as? String, "09/27")
        XCTAssertNil(json["exp_month"])
    }

    func testRefusesPlainHTTP() {
        let tokenizer = HTTPTokenizer(url: URL(string: "http://vault.example.com/tokens")!)
        XCTAssertThrowsError(try tokenizer.makeRequest(for: card)) { error in
            XCTAssertEqual(error as? TokenizationError, .insecureEndpoint)
        }
    }

    func testTokenExtraction() throws {
        let tokenizer = HTTPTokenizer(url: URL(string: "https://vault.example.com/tokens")!, tokenPath: "data.id")
        let response = Data(#"{"data":{"id":"tok_123","brand":"visa"}}"#.utf8)
        let token = try tokenizer.token(from: response, for: card)
        XCTAssertEqual(token.value, "tok_123")
        XCTAssertEqual(token.brand, .visa)
        XCTAssertEqual(token.bin, "411111")
        XCTAssertEqual(token.lastFour, "1111")
        XCTAssertEqual(token.expiry, CardExpiry(month: 9, year: 2027))
        XCTAssertNil(token.providerResponse)
    }

    func testRejectsEmptyBooleanAndEchoedCardTokens() {
        let tokenizer = HTTPTokenizer(url: URL(string: "https://vault.example.com")!)
        for value in ["", " ", "4111 1111 1111 1111", true] as [Any] {
            let data = try! JSONSerialization.data(withJSONObject: ["token": value])
            XCTAssertThrowsError(try tokenizer.token(from: data, for: card))
        }
    }

    func testDefaultRedirectsStayWithinHTTPSOrigin() {
        let origin = URL(string: "https://vault.example.com/tokens")
        for url in ["https://vault.example.com:443/next", "https://VAULT.example.com/next"] {
            XCTAssertTrue(SameOriginRedirectPolicy.allows(from: origin, to: URL(string: url)))
        }
        for url in ["http://vault.example.com", "https://vault.example.com:8443", "https://other.example.com"] {
            XCTAssertFalse(SameOriginRedirectPolicy.allows(from: origin, to: URL(string: url)))
        }
    }

    func testNumericTokenAndMissingToken() throws {
        let tokenizer = HTTPTokenizer(url: URL(string: "https://vault.example.com/tokens")!, tokenPath: "id")
        XCTAssertEqual(try tokenizer.token(from: Data(#"{"id":42}"#.utf8), for: card).value, "42")
        XCTAssertThrowsError(try tokenizer.token(from: Data(#"{"other":"x"}"#.utf8), for: card)) { error in
            XCTAssertEqual(error as? TokenizationError, .malformedResponse)
        }
        XCTAssertThrowsError(try tokenizer.token(from: Data("not json".utf8), for: card))
    }
}

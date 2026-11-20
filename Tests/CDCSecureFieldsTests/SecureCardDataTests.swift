import XCTest
@testable import CDCSecureFields

final class SecureCardDataTests: XCTestCase {
    let card = SecureCardData(number: "4111 1111 1111 1111", expiry: CardExpiry(month: 9, year: 2027), securityCode: "123", cardholderName: "  Jane Doe ")

    func testDerivedValues() {
        XCTAssertEqual(card.brand, .visa)
        XCTAssertEqual(card.bin, "411111")
        XCTAssertEqual(card.lastFour, "1111")
        XCTAssertEqual(card.maskedNumber, "••••••••••••1111")
        XCTAssertEqual(card.cardholderName, "Jane Doe")
        XCTAssertTrue(card.hasSecurityCode)
    }

    func testNumberOnlyAvailableInsideClosure() {
        XCTAssertEqual(card.withNumber { $0 }, "4111111111111111")
        XCTAssertEqual(card.withSecurityCode { $0 }, "123")
    }

    func testEmptySecurityCodeBecomesNil() {
        let card = SecureCardData(number: "4111111111111111", expiry: nil, securityCode: "", cardholderName: "")
        XCTAssertFalse(card.hasSecurityCode)
        XCTAssertNil(card.cardholderName)
        XCTAssertNil(card.withSecurityCode { $0 })
    }

    func testDescriptionsAndMirrorAreRedacted() {
        for text in [card.description, card.debugDescription, "\(card)", String(reflecting: card)] {
            XCTAssertFalse(text.contains("4111111111111111"), text)
            XCTAssertFalse(text.contains("4111 1111"), text)
            XCTAssertFalse(text.contains("123"), text)
            XCTAssertTrue(text.contains("1111"), "the last four may appear")
        }
        var dumped = ""
        dump(card, to: &dumped)
        XCTAssertFalse(dumped.contains("4111111111111111"))
        XCTAssertFalse(dumped.contains("\"123\""))
    }
}

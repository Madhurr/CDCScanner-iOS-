import XCTest
@testable import CDCSecureFields

final class CardNumberStateTests: XCTestCase {
    func testEmpty() {
        let state = CardNumberState.empty
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.isValid)
        XCTAssertTrue(state.isPotentiallyValid, "typing can still produce a valid number")
        XCTAssertNil(state.brand)
        XCTAssertNil(state.bin)
        XCTAssertNil(state.lastFour)
    }

    func testPartialVisa() {
        let state = CardNumberState(digits: "4111 11")
        XCTAssertEqual(state.length, 6)
        XCTAssertEqual(state.brand, .visa)
        XCTAssertFalse(state.isValid)
        XCTAssertTrue(state.isPotentiallyValid)
        XCTAssertEqual(state.bin, "411111")
        XCTAssertNil(state.lastFour)
        XCTAssertEqual(state.cvcLength, 3)
    }

    func testCompleteVisa() {
        let state = CardNumberState(digits: "4111111111111111")
        XCTAssertTrue(state.isValid)
        XCTAssertTrue(state.isPotentiallyValid, "a 19-digit Visa could still follow")
        XCTAssertEqual(state.lastFour, "1111")
    }

    func testCompleteAmexIsNotPotentiallyLonger() {
        let state = CardNumberState(digits: "378282246310005")
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(state.brand, .americanExpress)
        XCTAssertEqual(state.cvcLength, 4)
    }

    func testBadChecksumAtFullLength() {
        let state = CardNumberState(digits: "378282246310006")
        XCTAssertFalse(state.isValid)
        XCTAssertFalse(state.isPotentiallyValid, "Amex is exactly 15 digits, so nothing can fix this")
    }

    func testUnknownPrefix() {
        let state = CardNumberState(digits: "9999")
        XCTAssertNil(state.brand)
        XCTAssertTrue(state.candidateBrands.isEmpty)
        XCTAssertFalse(state.isPotentiallyValid)
    }

    func testRestrictedRules() {
        let state = CardNumberState(digits: "5555555555554444", rules: CardBrandRule.defaults(for: [.visa]))
        XCTAssertFalse(state.isValid)
        XCTAssertFalse(state.isPotentiallyValid)
    }

    func testDescriptionNeverContainsDigits() {
        let state = CardNumberState(digits: "4111111111111111")
        XCTAssertFalse(state.description.contains("4111"))
        XCTAssertFalse(state.description.contains("1111"))
    }
}

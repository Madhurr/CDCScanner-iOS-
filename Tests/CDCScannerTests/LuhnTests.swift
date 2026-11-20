import XCTest
@testable import CDCScanner

final class LuhnTests: XCTestCase {
    func testAcceptsKnownValidNumbers() {
        for number in ["4111111111111111", "5555555555554444", "378282246310005", "6011111111111117",
                       "30569309025904", "3530111333300000", "6759649826438453", "4222222222222",
                       "6799990100000000019", "79927398713"] {
            XCTAssertTrue(Luhn.isValid(number), number)
        }
    }

    func testRejectsBadCheckDigit() {
        XCTAssertFalse(Luhn.isValid("4111111111111112"))
        XCTAssertFalse(Luhn.isValid("79927398710"))
    }

    func testRejectsNonDigitsAndShortInput() {
        XCTAssertFalse(Luhn.isValid(""))
        XCTAssertFalse(Luhn.isValid("0"))
        XCTAssertFalse(Luhn.isValid("4111 1111 1111 1111"))
        XCTAssertFalse(Luhn.isValid("41111111111111a1"))
    }
}

import XCTest
@testable import CDCSecureFields

final class CardNumberFormatterTests: XCTestCase {
    let formatter = CardNumberFormatter()

    func testVisaGroupsInFours() {
        XCTAssertEqual(formatter.format("4"), "4")
        XCTAssertEqual(formatter.format("4111"), "4111")
        XCTAssertEqual(formatter.format("41111"), "4111 1")
        XCTAssertEqual(formatter.format("4111111111111111"), "4111 1111 1111 1111")
    }

    func testVisaBeyondSixteenKeepsGrouping() {
        XCTAssertEqual(formatter.format("41111111111111111"), "4111 1111 1111 1111 1")
        XCTAssertEqual(formatter.format("4000000000000000006"), "4000 0000 0000 0000 006")
    }

    func testAmexGroupsFourSixFive() {
        XCTAssertEqual(formatter.format("37"), "37")
        XCTAssertEqual(formatter.format("37828"), "3782 8")
        XCTAssertEqual(formatter.format("3782822463"), "3782 822463")
        XCTAssertEqual(formatter.format("378282246310005"), "3782 822463 10005")
    }

    func testDinersFourteenGroupsFourSixFour() {
        XCTAssertEqual(formatter.format("30569309025904"), "3056 930902 5904")
    }

    func testIgnoresNonDigits() {
        XCTAssertEqual(formatter.format("4111-1111 abc 1111"), "4111 1111 1111")
        XCTAssertEqual(formatter.format(""), "")
    }

    func testCaretMapping() {
        let formatted = "4111 1111 1111 1111"
        XCTAssertEqual(formatter.digitOffset(forFormattedOffset: 0, in: formatted), 0)
        XCTAssertEqual(formatter.digitOffset(forFormattedOffset: 5, in: formatted), 4)
        XCTAssertEqual(formatter.digitOffset(forFormattedOffset: 6, in: formatted), 5)
        XCTAssertEqual(formatter.formattedOffset(forDigitOffset: 0, in: formatted), 0)
        XCTAssertEqual(formatter.formattedOffset(forDigitOffset: 4, in: formatted), 4)
        XCTAssertEqual(formatter.formattedOffset(forDigitOffset: 5, in: formatted), 6)
        XCTAssertEqual(formatter.formattedOffset(forDigitOffset: 16, in: formatted), 19)
    }
}

import XCTest
@testable import CDCSecureFields

final class ExpiryInputTests: XCTestCase {
    let formatter = ExpiryInputFormatter()
    let now = Date(timeIntervalSince1970: 1_795_262_400) // 20 Nov 2026

    func testTypingFlow() {
        XCTAssertEqual(formatter.format(""), "")
        XCTAssertEqual(formatter.format("1"), "1")
        XCTAssertEqual(formatter.format("12"), "12/")
        XCTAssertEqual(formatter.format("122"), "12/2")
        XCTAssertEqual(formatter.format("1227"), "12/27")
        XCTAssertEqual(formatter.format("12278"), "12/27", "capped at four digits")
    }

    func testSingleDigitMonthsArePadded() {
        XCTAssertEqual(formatter.format("3"), "03/")
        XCTAssertEqual(formatter.format("927"), "09/27")
    }

    func testImpossibleMonthsAreTruncatedForCorrection() {
        XCTAssertEqual(formatter.digits(from: "13"), "1")
        XCTAssertEqual(formatter.digits(from: "00"), "0")
        XCTAssertEqual(formatter.digits(from: "10"), "10")
    }

    func testStates() {
        XCTAssertEqual(formatter.state(for: "", now: now), .empty)
        let partial = formatter.state(for: "12", now: now)
        XCTAssertFalse(partial.isComplete)
        XCTAssertFalse(partial.isEmpty)

        let valid = formatter.state(for: "1227", now: now)
        XCTAssertTrue(valid.isComplete)
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(valid.expiry, CardExpiry(month: 12, year: 2027))

        let currentMonth = formatter.state(for: "1126", now: now)
        XCTAssertTrue(currentMonth.isValid, "valid until the end of the month")

        let expired = formatter.state(for: "1026", now: now)
        XCTAssertTrue(expired.isComplete)
        XCTAssertFalse(expired.isValid)

        let farFuture = formatter.state(for: "0199", now: now)
        XCTAssertFalse(farFuture.isValid)
    }
}

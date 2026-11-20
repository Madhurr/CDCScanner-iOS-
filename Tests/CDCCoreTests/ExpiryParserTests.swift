import XCTest
@testable import CDCCore

final class ExpiryParserTests: XCTestCase {
    let parser = ExpiryParser()
    // 20 November 2026, 12:00 UTC
    let reference = Date(timeIntervalSince1970: 1_795_262_400)

    func testBasicFormats() {
        XCTAssertEqual(parser.bestExpiry(in: "09/27", referenceDate: reference), CardExpiry(month: 9, year: 2027))
        XCTAssertEqual(parser.bestExpiry(in: "09/2027", referenceDate: reference), CardExpiry(month: 9, year: 2027))
        XCTAssertEqual(parser.bestExpiry(in: "09 / 27", referenceDate: reference), CardExpiry(month: 9, year: 2027))
        XCTAssertEqual(parser.bestExpiry(in: "09-27", referenceDate: reference), CardExpiry(month: 9, year: 2027))
        XCTAssertEqual(parser.bestExpiry(in: "VALID THRU 12/30", referenceDate: reference), CardExpiry(month: 12, year: 2030))
    }

    func testInvalidMonths() {
        XCTAssertNil(parser.bestExpiry(in: "13/27", referenceDate: reference))
        XCTAssertNil(parser.bestExpiry(in: "00/27", referenceDate: reference))
    }

    func testLatestDateWinsOverValidFrom() {
        let text = "VALID FROM 05/22 VALID THRU 05/27"
        XCTAssertEqual(parser.bestExpiry(in: text, referenceDate: reference), CardExpiry(month: 5, year: 2027))
        XCTAssertEqual(parser.parse(text, referenceDate: reference).count, 2)
    }

    func testImplausibleYearsAreIgnored() {
        XCTAssertNil(parser.bestExpiry(in: "01/99", referenceDate: reference))
        XCTAssertNil(parser.bestExpiry(in: "01/15", referenceDate: reference))
        XCTAssertEqual(parser.bestExpiry(in: "01/21", referenceDate: reference), CardExpiry(month: 1, year: 2021))
        XCTAssertEqual(parser.bestExpiry(in: "01/46", referenceDate: reference), CardExpiry(month: 1, year: 2046))
    }

    func testDoesNotMatchInsideLongerNumbers() {
        XCTAssertNil(parser.bestExpiry(in: "4111 1111 1111 1111", referenceDate: reference))
        XCTAssertNil(parser.bestExpiry(in: "112/27", referenceDate: reference))
        XCTAssertNil(parser.bestExpiry(in: "11/275", referenceDate: reference))
    }

    func testDuplicatesCollapse() {
        XCTAssertEqual(parser.parse("09/27 09/27 09/2027", referenceDate: reference).count, 1)
    }

    func testCardExpiryFormattingAndExpiration() throws {
        let expiry = try XCTUnwrap(CardExpiry(month: 9, year: 27))
        XCTAssertEqual(expiry.year, 2027)
        XCTAssertEqual(expiry.formatted, "09/27")
        XCTAssertEqual(expiry.formattedLong, "09/2027")
        XCTAssertNil(CardExpiry(month: 0, year: 2027))
        XCTAssertNil(CardExpiry(month: 13, year: 2027))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let november2026 = try XCTUnwrap(CardExpiry(month: 11, year: 2026))
        let october2026 = try XCTUnwrap(CardExpiry(month: 10, year: 2026))
        XCTAssertFalse(november2026.isExpired(asOf: reference, calendar: utc), "valid through the end of its month")
        XCTAssertTrue(october2026.isExpired(asOf: reference, calendar: utc))
        XCTAssertTrue(november2026 > october2026)
    }
}

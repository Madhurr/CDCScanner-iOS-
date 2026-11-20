import XCTest
@testable import CDCCore

final class CardNumberParserTests: XCTestCase {
    let parser = CardNumberParser()

    func testPlainNumber() {
        XCTAssertEqual(parser.parse("4111111111111111"), [CardNumberMatch(number: "4111111111111111", brand: .visa)])
    }

    func testSeparators() {
        for text in ["4111 1111 1111 1111", "4111-1111-1111-1111", "4111.1111.1111.1111", "4111\u{00A0}1111 1111 1111"] {
            XCTAssertEqual(parser.parse(text).map(\.number), ["4111111111111111"], text)
        }
    }

    func testAmexAndDinersGrouping() {
        XCTAssertEqual(parser.parse("3782 822463 10005").first, CardNumberMatch(number: "378282246310005", brand: .americanExpress))
        XCTAssertEqual(parser.parse("3056 930902 5904").first, CardNumberMatch(number: "30569309025904", brand: .dinersClub))
    }

    func testNineteenDigitNumbers() {
        XCTAssertEqual(parser.parse("6799 9901 0000 0000 019").first?.brand, .maestro)
        XCTAssertEqual(parser.parse("6799 9901 0000 0000 019").first?.number, "6799990100000000019")
    }

    func testSurroundingText() {
        let text = "BANK NAME\nVALID THRU 09/27\n4111 1111 1111 1111\nJOHN APPLESEED"
        XCTAssertEqual(parser.parse(text).map(\.number), ["4111111111111111"])
    }

    func testNumberSplitAcrossLines() {
        let matches = parser.parse(lines: ["4111 1111", "1111 1111"])
        XCTAssertEqual(matches.map(\.number), ["4111111111111111"])
    }

    func testLeadingNoiseDigitRecoveredBySlidingWindow() {
        // An OCR artefact glued to the front of the number.
        XCTAssertEqual(parser.parse("04111111111111111").map(\.number), ["4111111111111111"])
        XCTAssertEqual(parser.parse("41111111111111117").map(\.number), ["4111111111111111"])
    }

    func testRejectsInvalidChecksumAndUnknownBrand() {
        XCTAssertTrue(parser.parse("4111 1111 1111 1112").isEmpty)
        XCTAssertTrue(parser.parse("9999 0000 0000 0004").isEmpty)
        XCTAssertTrue(parser.parse("no digits here").isEmpty)
        XCTAssertTrue(parser.parse("").isEmpty)
    }

    func testExpiryAndShortNumbersAreNotMistakenForCards() {
        XCTAssertTrue(parser.parse("09/27 1234").isEmpty)
        XCTAssertTrue(parser.parse("Tel 0800 123 4567").isEmpty)
    }

    func testRespectsRestrictedRules() {
        let visaOnly = CardNumberParser(rules: CardBrandRule.defaults(for: [.visa]))
        XCTAssertTrue(visaOnly.parse("5555 5555 5555 4444").isEmpty)
        XCTAssertEqual(visaOnly.parse("4111 1111 1111 1111").first?.brand, .visa)
    }

    func testMultipleNumbersAreAllReturnedOnce() {
        let matches = parser.parse(lines: ["4111 1111 1111 1111", "5555 5555 5555 4444", "4111 1111 1111 1111"])
        XCTAssertEqual(matches.map(\.number), ["4111111111111111", "5555555555554444"])
    }

    func testAdjacentCompleteNumbersAreNotJoined() {
        // Joining these would create Luhn-valid 16-digit substrings that were never on a card.
        let matches = parser.parse(lines: ["4111111111111111", "5555555555554444"])
        XCTAssertEqual(matches.count, 2)
    }

    func testExpiryOnSameLineAsNumber() {
        XCTAssertEqual(parser.parse("09/27 4111 1111 1111 1111").map(\.number), ["4111111111111111"])
    }

    func testDigitRuns() {
        XCTAssertEqual(CardNumberParser.digitRuns(in: "4111 1111 1111 1111"), ["4111111111111111"])
        XCTAssertEqual(CardNumberParser.digitRuns(in: "09/27"), ["09", "27"], "a non-separator ends a run")
        XCTAssertEqual(CardNumberParser.digitRuns(in: "27 4111"), ["274111"], "a single separator joins groups")
        XCTAssertEqual(CardNumberParser.digitRuns(in: "4111  1111"), ["4111", "1111"], "a double space ends a run")
    }
}

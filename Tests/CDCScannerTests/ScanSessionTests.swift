import XCTest
@testable import CDCScanner

final class ScanSessionTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_795_262_400) // 20 Nov 2026
    let fullFrame = ["BANK", "4111 1111 1111 1111", "09/27", "JOHN APPLESEED"]
    let numberOnlyFrame = ["4111 1111 1111 1111"]

    private func frame(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }

    func testCompletesAfterRequiredConfirmations() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 3))
        XCTAssertNil(session.ingest(fullFrame, at: frame(0)))
        XCTAssertNil(session.ingest(fullFrame, at: frame(0.1)))
        XCTAssertEqual(session.phase, .searchingForNumber)

        let card = session.ingest(fullFrame, at: frame(0.2))
        XCTAssertEqual(card, ScannedCard(number: "4111111111111111", brand: .visa, expiry: CardExpiry(month: 9, year: 2027)))
        XCTAssertEqual(session.card, card)
        XCTAssertNil(session.ingest(fullFrame, at: frame(0.3)), "a completed session reports once")
    }

    func testSingleConfirmationCompletesImmediately() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 1))
        XCTAssertNotNil(session.ingest(fullFrame, at: frame(0)))
    }

    func testWaitsForExpiryThenTimesOut() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 2, expiryTimeout: 5))
        XCTAssertNil(session.ingest(numberOnlyFrame, at: frame(0)))
        XCTAssertNil(session.ingest(numberOnlyFrame, at: frame(0.1)))
        XCTAssertEqual(session.phase, .searchingForExpiry(CardNumberMatch(number: "4111111111111111", brand: .visa)))

        XCTAssertNil(session.ingest(numberOnlyFrame, at: frame(3)))
        let card = session.ingest([], at: frame(5.2))
        XCTAssertEqual(card?.number, "4111111111111111")
        XCTAssertNil(card?.expiry)
    }

    func testExpiryFoundAfterNumber() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 2))
        XCTAssertNil(session.ingest(numberOnlyFrame, at: frame(0)))
        XCTAssertNil(session.ingest(numberOnlyFrame, at: frame(0.1)))
        XCTAssertNil(session.ingest(["09/27"], at: frame(0.2)))
        XCTAssertEqual(session.ingest(["09/27"], at: frame(0.3))?.expiry, CardExpiry(month: 9, year: 2027))
    }

    func testExpiryNotRequired() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 2, requiresExpiry: false))
        XCTAssertNil(session.ingest(numberOnlyFrame, at: frame(0)))
        let card = session.ingest(numberOnlyFrame, at: frame(0.1))
        XCTAssertEqual(card?.number, "4111111111111111")
        XCTAssertNil(card?.expiry)
    }

    func testExpiryNotRequiredStillAttachesBestEffortExpiry() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 2, requiresExpiry: false))
        XCTAssertNil(session.ingest(["4111 1111 1111 1111", "09/27"], at: frame(0)))
        XCTAssertEqual(session.ingest(numberOnlyFrame, at: frame(0.1))?.expiry, CardExpiry(month: 9, year: 2027))
    }

    func testMisreadsDoNotWin() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 3))
        // Two frames of a different (valid) card, three of the real one.
        session.ingest(["5555 5555 5555 4444", "09/27"], at: frame(0))
        session.ingest(["5555 5555 5555 4444", "09/27"], at: frame(0.1))
        session.ingest(fullFrame, at: frame(0.2))
        session.ingest(fullFrame, at: frame(0.3))
        let card = session.ingest(fullFrame, at: frame(0.4))
        XCTAssertEqual(card?.brand, .visa)
    }

    func testLaterExpiryWinsOverValidFromWhenVotesTie() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 2))
        let frameText = ["4111 1111 1111 1111", "05/22", "05/27"]
        session.ingest(frameText, at: frame(0))
        XCTAssertEqual(session.ingest(frameText, at: frame(0.1))?.expiry, CardExpiry(month: 5, year: 2027))
    }

    func testReset() {
        var session = ScanSession(configuration: ScannerConfiguration(requiredConfirmations: 1))
        XCTAssertNotNil(session.ingest(fullFrame, at: frame(0)))
        session.reset()
        XCTAssertEqual(session.phase, .searchingForNumber)
        XCTAssertNil(session.card)
        XCTAssertNotNil(session.ingest(fullFrame, at: frame(1)))
    }

    func testRequiredConfirmationsNeverBelowOne() {
        var configuration = ScannerConfiguration(requiredConfirmations: 0)
        XCTAssertEqual(configuration.requiredConfirmations, 1)
        configuration.requiredConfirmations = -4
        XCTAssertEqual(configuration.requiredConfirmations, 1)
    }
}

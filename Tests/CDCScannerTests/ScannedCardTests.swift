import XCTest
@testable import CDCScanner

final class ScannedCardTests: XCTestCase {
    func testVisaFormatting() {
        let card = ScannedCard(number: "4111111111111111", brand: .visa, expiry: nil)
        XCTAssertEqual(card.formattedNumber, "4111 1111 1111 1111")
        XCTAssertEqual(card.maskedNumber, "•••• •••• •••• 1111")
        XCTAssertEqual(card.lastFour, "1111")
    }

    func testAmexFormatting() {
        let card = ScannedCard(number: "378282246310005", brand: .americanExpress, expiry: nil)
        XCTAssertEqual(card.formattedNumber, "3782 822463 10005")
        XCTAssertEqual(card.maskedNumber, "•••• •••••• •0005")
    }

    func testDinersFourteenFormatting() {
        let card = ScannedCard(number: "30569309025904", brand: .dinersClub, expiry: nil)
        XCTAssertEqual(card.formattedNumber, "3056 930902 5904")
    }

    func testNineteenDigitFormatting() {
        let card = ScannedCard(number: "6799990100000000019", brand: .maestro, expiry: nil)
        XCTAssertEqual(card.formattedNumber, "6799 9901 0000 0000 019")
    }

    func testCodableRoundTrip() throws {
        let card = ScannedCard(number: "4111111111111111", brand: .custom("Loyalty"), expiry: CardExpiry(month: 9, year: 2027))
        let data = try JSONEncoder().encode(card)
        XCTAssertEqual(try JSONDecoder().decode(ScannedCard.self, from: data), card)
    }
}

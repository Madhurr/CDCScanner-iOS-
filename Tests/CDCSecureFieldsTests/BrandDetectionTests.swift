import XCTest
@testable import CDCSecureFields

final class BrandDetectionTests: XCTestCase {
    let rules = CardBrandRule.defaults

    func testSingleDigitPrefixes() {
        XCTAssertEqual(rules.detectedBrand(forPrefix: "4"), .visa)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "1"), .uatp)
        XCTAssertNil(rules.detectedBrand(forPrefix: "5"), "could be Mastercard, Maestro, Dankort or RuPay")
        XCTAssertNil(rules.detectedBrand(forPrefix: "3"), "could be Amex, Diners, JCB or T-Union")
        XCTAssertNil(rules.detectedBrand(forPrefix: ""))
    }

    func testCandidatesNarrowAsDigitsArrive() {
        XCTAssertTrue(rules.candidateBrands(forPrefix: "3").contains(.americanExpress))
        XCTAssertTrue(rules.candidateBrands(forPrefix: "3").contains(.jcb))
        XCTAssertEqual(rules.candidateBrands(forPrefix: "37"), [.americanExpress])
        XCTAssertEqual(rules.detectedBrand(forPrefix: "37"), .americanExpress)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "35"), .jcb, "only JCB (3528–3589) starts with 35")
        XCTAssertEqual(rules.detectedBrand(forPrefix: "30"), .dinersClub)
    }

    func testRangePrefixDetection() {
        XCTAssertEqual(rules.detectedBrand(forPrefix: "2221"), .mastercard)
        XCTAssertNil(rules.detectedBrand(forPrefix: "22"), "22 could be Mastercard (2221–2720) or Mir (2200–2204)")
        XCTAssertEqual(rules.candidateBrands(forPrefix: "22").sorted(by: { $0.displayName < $1.displayName }), [.mastercard, .mir])
        XCTAssertEqual(rules.detectedBrand(forPrefix: "2200"), .mir)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "27"), .mastercard)
        XCTAssertTrue(rules.candidateBrands(forPrefix: "28").isEmpty)
    }

    func testMostSpecificPrefixWinsEarly() {
        XCTAssertEqual(rules.detectedBrand(forPrefix: "62"), .unionPay)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "622126"), .discover)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "65"), .discover)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "6521"), .ruPay)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "6011"), .discover)
        XCTAssertEqual(rules.detectedBrand(forPrefix: "60"), .ruPay)
    }

    func testMaxLengthFollowsCandidates() {
        XCTAssertEqual(rules.maxLength(forPrefix: "37"), 15)
        XCTAssertEqual(rules.maxLength(forPrefix: "4"), 19)
        XCTAssertEqual(rules.maxLength(forPrefix: "51"), 16)
        XCTAssertEqual(rules.maxLength(forPrefix: ""), 19)
    }

    func testCouldMatchRejectsTooLongAndNonDigits() {
        let visa = rules.first { $0.brand == .visa }!
        XCTAssertTrue(visa.couldMatch(prefix: "4111"))
        XCTAssertFalse(visa.couldMatch(prefix: "5"))
        XCTAssertFalse(visa.couldMatch(prefix: "41111111111111111111"))
        XCTAssertFalse(visa.couldMatch(prefix: "4a"))
    }
}

import XCTest
@testable import CDCScanner

final class CardBrandRuleTests: XCTestCase {
    let rules = CardBrandRule.defaults

    func testEveryStandardBrandHasARule() {
        let covered = Set(rules.map(\.brand))
        for brand in CardBrand.standard {
            XCTAssertTrue(covered.contains(brand), "\(brand) has no default rule")
        }
    }

    func testBrandResolution() {
        let expectations: [(String, CardBrand)] = [
            ("4111111111111111", .visa),
            ("4222222222222", .visa),
            ("4000000000000000006", .visa),
            ("5555555555554444", .mastercard),
            ("2221000000000009", .mastercard),
            ("378282246310005", .americanExpress),
            ("6011111111111117", .discover),
            ("30569309025904", .dinersClub),
            ("3000000000000004", .dinersClub),
            ("3528000000000007", .jcb),
            ("6200000000000005", .unionPay),
            ("6200000000000000000", .unionPay),
            ("6759649826438453", .maestro),
            ("501800000009", .maestro),
            ("6000000000000007", .ruPay),
            ("8100000000000002", .ruPay),
            ("2200000000000004", .mir),
            ("5019717010103742", .dankort),
            ("3100000000000000005", .chinaTUnion),
            ("6360000000000001", .interPayment),
            ("100000000000009", .uatp),
            ("6054740000000003", .npsPridnestrovie),
        ]
        for (number, brand) in expectations {
            XCTAssertEqual(rules.brand(for: number), brand, number)
        }
    }

    func testMoreSpecificPrefixWins() {
        // 622126–622925 is Discover even though 62 is UnionPay.
        XCTAssertEqual(rules.brand(for: "6221260000000000"), .discover)
        // 6521–6522 is RuPay even though 65 is Discover.
        XCTAssertEqual(rules.brand(for: "6521000000000007"), .ruPay)
        // 6054740 is NPS even though 60 is RuPay.
        XCTAssertEqual(rules.brand(for: "6054740000000003"), .npsPridnestrovie)
        // 5019 is Dankort, sitting between Maestro's 5018 and 5020.
        XCTAssertEqual(rules.brand(for: "5019717010103742"), .dankort)
    }

    func testLengthMustMatch() {
        // 14 digits starting with 4 is not a Visa length.
        XCTAssertNil(rules.brand(for: "41111111111111"))
        // Amex is 15 digits only.
        XCTAssertNil(rules.brand(for: "3782822463100050"))
        XCTAssertNil(rules.brand(for: "9999000000000004"))
    }

    func testRestrictingToBrands() {
        let visaOnly = CardBrandRule.defaults(for: [.visa])
        XCTAssertEqual(visaOnly.brand(for: "4111111111111111"), .visa)
        XCTAssertNil(visaOnly.brand(for: "5555555555554444"))
    }

    func testCustomRule() {
        let loyalty = CardBrandRule(brand: .custom("Loyalty"), prefix: 9000, lengths: [16])
        XCTAssertTrue(loyalty.matches("9000000000000001"))
        XCTAssertFalse(loyalty.matches("900000000000001"))
        XCTAssertEqual((rules + [loyalty]).brand(for: "9000000000000001"), .custom("Loyalty"))
        XCTAssertEqual(CardBrand.custom("Loyalty").displayName, "Loyalty")
    }
}

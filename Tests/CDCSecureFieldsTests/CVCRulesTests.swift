import XCTest
@testable import CDCSecureFields

final class CVCRulesTests: XCTestCase {
    func testLengths() {
        XCTAssertEqual(CVCRules.length(for: .americanExpress), 4)
        XCTAssertEqual(CVCRules.length(for: .visa), 3)
        XCTAssertEqual(CVCRules.length(for: nil), 4)
    }

    func testStates() {
        XCTAssertTrue(CVCRules.state(digits: "123", brand: .visa).isComplete)
        XCTAssertFalse(CVCRules.state(digits: "12", brand: .visa).isComplete)
        XCTAssertFalse(CVCRules.state(digits: "123", brand: .americanExpress).isComplete)
        XCTAssertTrue(CVCRules.state(digits: "1234", brand: .americanExpress).isComplete)
        XCTAssertTrue(CVCRules.state(digits: "123", brand: nil).isComplete)
        XCTAssertTrue(CVCRules.state(digits: "1234", brand: nil).isComplete)
        XCTAssertEqual(CVCRules.state(digits: "", brand: nil), .empty)
    }
}

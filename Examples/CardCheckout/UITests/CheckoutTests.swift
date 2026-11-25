import XCTest

final class CheckoutTests: XCTestCase {
    @MainActor func testCreateTestToken() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertFalse(app.buttons["Create test token"].isEnabled)
        app.buttons["Use test card"].tap()
        let secure = app.secureTextFields["Security code"]
        let cvc = secure.exists ? secure : app.textFields["Security code"]
        cvc.tap()
        cvc.typeText("123")
        if app.buttons["Done"].isHittable { app.buttons["Done"].tap() }
        app.buttons["Create test token"].tap()
        XCTAssertTrue(app.buttons["Try another card"].waitForExistence(timeout: 5))
        let receipt = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "tok_demo_visa", "tok_demo_visa")
        )
        XCTAssertTrue(receipt.firstMatch.exists)
        app.buttons["Try another card"].tap()
        XCTAssertFalse(app.buttons["Create test token"].isEnabled)
    }
}

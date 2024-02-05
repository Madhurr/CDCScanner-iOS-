import XCTest
@testable import CDCScanner

@available(iOS 13.0, *)
class CDCScannerTests: XCTestCase {

    var scanner: CDCScanner!
    var mockDelegate: MockCDCScannerDelegate!

    override func setUp() {
        super.setUp()
        scanner = CDCScanner()
        mockDelegate = MockCDCScannerDelegate()
        scanner.delegate = mockDelegate
    }

    override func tearDown() {
        scanner = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testAddCustomCards() {
        // Assuming `addCustomCards` modifies `customCards` in your scanner
        let customCard = Card(binRange: "1234", lengthRange: "16")
        scanner.addCustomCards(cards: [customCard])

        // Test if custom cards are added correctly
        XCTAssertNotNil(scanner.customCards["1234"])
        XCTAssertEqual(scanner.customCards["1234"], "16")
    }

    func testRecognitionLevelChange() {
        // Test if changing recognition level updates loops correctly
        scanner.recognitionLevel = .fastest
        scanner.setupCardOptions()
        XCTAssertEqual(scanner.ccPassLoops, 1)
    }

    func testProcessImage() {
        // This test might require a mock image or a way to simulate image processing
        // Replace with your actual image processing test logic
    }

    func testHandleDetectedText() {
        // Simulate detected text and test the handling
        // Replace with your actual text handling test logic
    }

    func testDelegateCallOnScanCompletion() {
        // Simulate a scenario where scanning is complete
        // Call the required methods on your scanner object
        // Test if the delegate method is called
        // Example:
        scanner.finalCardNumber = "1234567890123456"
        scanner.finalExpDate = "12/24"
        scanner.foundType = .visa
        scanner.callDelegate()

        XCTAssertEqual(mockDelegate.cardNumber, "1234567890123456")
        XCTAssertEqual(mockDelegate.expDate, "12/24")
        XCTAssertEqual(mockDelegate.cardType, "Visa")
    }

    // Add more tests as needed
}

class MockCDCScannerDelegate: UIViewController, CDCScannerDelegate {
    var cardNumber: String?
    var expDate: String?
    var cardType: String?

    func ccScannerCompleted(cardNumber: String, expDate: String, cardType: String) {
        self.cardNumber = cardNumber
        self.expDate = expDate
        self.cardType = cardType
    }
}

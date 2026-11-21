import XCTest
@testable import CDCSecureFields

/// Produces `relay/testdata/swift_jwe.json` for the Go relay's interop test. Skipped unless the
/// environment names an output path and a recipient key.
final class RelayFixtureExportTests: XCTestCase {
    func testExportTokenizerRequestBody() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["CDC_RELAY_FIXTURE_OUT"], let keyPath = env["CDC_RELAY_PUBLIC_JWK"] else { return }
        let recipient = try ECPublicJWK(json: try Data(contentsOf: URL(fileURLWithPath: keyPath)))
        let card = SecureCardData(number: "4111111111111111", expiry: CardExpiry(month: 9, year: 2027), securityCode: "123", cardholderName: "Jane Doe")
        let tokenizer = EncryptingTokenizer(url: URL(string: "https://relay.example.com/v1/tokenize")!, recipients: StaticRecipientKeys(recipient))
        let request = try tokenizer.makeRequest(for: card, recipients: [recipient], now: Date(timeIntervalSince1970: 1_800_000_000))
        try request.httpBody!.write(to: URL(fileURLWithPath: out))
    }
}

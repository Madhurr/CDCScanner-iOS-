import CDCSecureFields
import Foundation

/// The example's session handles every request in-process. Its token cannot be charged.
enum TestVault {
    static let number = "4111111111111111"
    static let expiry = CardExpiry(month: 12, year: Calendar(identifier: .gregorian).component(.year, from: Date()) + 3)!
    static let endpoint = URL(string: "https://vault.invalid/v1/tokens")!
    static let tokenizer: HTTPTokenizer = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LocalVaultProtocol.self]
        return HTTPTokenizer(url: endpoint, session: URLSession(configuration: configuration))
    }()
}

private final class LocalVaultProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url == TestVault.endpoint, request.httpMethod == "POST" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let fields: [String: String]?
        if let body = request.httpBody {
            fields = try? JSONDecoder().decode([String: String].self, from: body)
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            fields = (try? JSONSerialization.jsonObject(with: stream)) as? [String: String]
        } else {
            fields = nil
        }
        let accepted = fields?["number"] == TestVault.number && fields?["cvc"] == "123"
        let response = HTTPURLResponse(url: TestVault.endpoint, statusCode: accepted ? 200 : 422,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let json = accepted ? #"{"token":"tok_demo_visa"}"# : #"{"error":"test_card_only"}"#
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

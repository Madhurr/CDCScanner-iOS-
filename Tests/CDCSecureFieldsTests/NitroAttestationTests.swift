import XCTest
@testable import CDCSecureFields

/// Fixtures: a Nitro-shaped attestation document (COSE_Sign1, ES384, P-384 root → intermediate → leaf)
/// produced by Python `cbor2` and `cryptography`, independent of the Swift implementation.
final class NitroAttestationTests: XCTestCase {
    static let document = Data(base64Encoded: "0oREoQE4IqBZB5ipaW1vZHVsZV9pZHgYaS0wMTIzNDU2Nzg5YWJjZGVmMC1lbmMwZmRpZ2VzdGZTSEEzODRpdGltZXN0YW1wGwAAAaH9VXqAZHBjcnOmAFgwq1S3Uv7+LZ9Z2dHmniRKPicvjj4CHE7wPvmx29uG6n57leUjvtfzL1yhVlnoqwx9AVgw4WhbZCbZxb6Gkf+PlerNwRdTNVZnOUqiMSRXCxS69oqzIqOq6zxZnESK1QFscJpJAlgweHhHA5yRWyrA39S98cz2A2QMX97dgcouvSCGeivEhVGH4n/L3CzYW4PPvcsd5jL3A1gwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAa2NlcnRpZmljYXRlWQG8MIIBuDCCAT6gAwIBAgIBAzAKBggqhkjOPQQDAzA6MQswCQYDVQQGEwJVUzEQMA4GA1UECgwHRXhhbXBsZTEZMBcGA1UEAwwQZGV2LWludGVybWVkaWF0ZTAeFw0yNjExMjEwODAwMDBaFw0yNjExMjIwOTAwMDBaMEIxCzAJBgNVBAYTAlVTMRAwDgYDVQQKDAdFeGFtcGxlMSEwHwYDVQQDDBhpLTAxMjM0NTY3ODlhYmNkZWYwLWVuYzAwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAATaG2FJsfRNBRLN+kRb29GohiVUxapFx6grVOR5YO8L6j0SkOMFKfuA/D2lUdqW9//4aptbYDQCIfXb+0LGZg3BAFRc2slpx14aHQheiJETAxryou/aH0/pSxe3TxHTVlSjEDAOMAwGA1UdEwEB/wQCMAAwCgYIKoZIzj0EAwMDaAAwZQIwVRbi+0rFphB23zIYg209GgnwfnUbGvf3Ntkv+1EQ/jvO9Eztf2XKUrFYZ62SKWKYAjEAnefdxJdepCBbe2Bc125JTY32kSclAy7GBC6PseS5DmXgWogb0dPKdGGussdHbEnfaGNhYnVuZGxlglkBvTCCAbkwggE/oAMCAQICAQEwCgYIKoZIzj0EAwMwPDELMAkGA1UEBhMCVVMxEDAOBgNVBAoMB0V4YW1wbGUxGzAZBgNVBAMMEmRldi5uaXRyby1lbmNsYXZlczAgFw0yNjExMjEwODAwMDBaGA8yMDU2MTExMzA5MDAwMFowPDELMAkGA1UEBhMCVVMxEDAOBgNVBAoMB0V4YW1wbGUxGzAZBgNVBAMMEmRldi5uaXRyby1lbmNsYXZlczB2MBAGByqGSM49AgEGBSuBBAAiA2IABJ5q0NShHiRn6pcHwkVN/ano1H/TOQZ/d9PHdGnPly+c7O7bmwdZuelk7FDWqKRb+fF6qhcQ6vTlQ7ExYExB4C1pj+MYDfqyEWrWqepmZS9RRGJvRchQqN3FQOVrzvc/MaMTMBEwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjEAlkEk5xL6dBEh2DDDx2Jy3HO6b7vhYHNAcsuwq3ToU8Dg1nC/DK1jySBUF3Qg001bAjAxyvYrHfyN5Pu83yRNnAcXA3wFW3OB8wAsP4J5nxY8F1caEkFGIXhqX3L0TWEQivdZAbkwggG1MIIBO6ADAgECAgECMAoGCCqGSM49BAMDMDwxCzAJBgNVBAYTAlVTMRAwDgYDVQQKDAdFeGFtcGxlMRswGQYDVQQDDBJkZXYubml0cm8tZW5jbGF2ZXMwHhcNMjYxMTIxMDgwMDAwWhcNMjcxMTIxMDkwMDAwWjA6MQswCQYDVQQGEwJVUzEQMA4GA1UECgwHRXhhbXBsZTEZMBcGA1UEAwwQZGV2LWludGVybWVkaWF0ZTB2MBAGByqGSM49AgEGBSuBBAAiA2IABEkIPcWv6ropxw0UqdVSNoXQdMn5ZONDYdJmA+sP42gpSsf1R+JZ2Ko+iqt7VEin4JATVs0VQKJX0I9K61cw6qAz68oM9BoAlxqWPHgSBrIJx1owk5kY7xCU6mbLhk+xwaMTMBEwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjA4VPJxwVgok/FxQNsy71jTJ+JHjrkHqluycfgdQ5aZqWfJ0XHVklPohJwHM0ACc20CMQD0LX2WxdvF1dK4UHtFgo13bFm/eNnod083Tq09P/uwM6XyQBvr10GWs4n6wd+yviBqcHVibGljX2tleViOeyJrdHkiOiJFQyIsImNydiI6IlAtMjU2IiwieCI6IlBlWUdPd21oOEhfdlNLeGw4S2lwUWl4SVQzVU1kSGFLSnNKay1BZFljdjAiLCJ5IjoiM2tDY3NYTURzcVR0YXcteG50TzVxZlkwWnViQWRnRldVWXR4Z1BscGxzTSIsImtpZCI6ImVuY2xhdmUifWl1c2VyX2RhdGFNY2RjLXJlbGF5LzAuMWVub25jZU9jbGllbnQtbm9uY2UtNDJYYLS50dkadsdDYOQN+Vb2JWDP7PaLicIgn9ibDYaF6GOL0MW9LClLmSQF9yaOfaQ3enteBYkn+wfaj+AcWIzuQlNcjzAoZc1Nj/CPcIZ5Rq3LM0PheCBMUjzE90WaGA78MQ==")!
    static let tampered = Data(base64Encoded: "0oREoQE4IqBZB5ipaW1vZHVsZV9pZHgYaS0wMTIzNDU2Nzg5YWJjZGVmMC1lbmMwZmRpZ2VzdGZTSEEzODRpdGltZXN0YW1wGwAAAaH9VXqAZHBjcnOmAFgwq1S3Uv7+LZ9Z2dHmniRKPicvjj4CHE7wPvmx29uG6n57leUjvtfzL1yhVlnoqwx9AVgw4WhbZCbZxb6Gkf+PlerNwRdTNVZnOUqiMSRXCxS69oqzIqOq6zxZnESK1QFscJpJAlgweHhHA5yRWyrA39S98cz2A2QMX97dgcouvSCGeivEhVGH4n/L3CzYW4PPvcsd5jL3A1gwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAa2NlcnRpZmljYXRlWQG8MIIBuDCCAT6gAwIBAgIBAzAKBggqhkjOPQQDAzA6MQswCQYDVQQGEwJVUzEQMA4GA1UECgwHRXhhbXBsZTEZMBcGA1UEAwwQZGV2LWludGVybWVkaWF0ZTAeFw0yNjExMjEwODAwMDBaFw0yNjExMjIwOTAwMDBaMEIxCzAJBgNVBAYTAlVTMRAwDgYDVQQKDAdFeGFtcGxlMSEwHwYDVQQDDBhpLTAxMjM0NTY3ODlhYmNkZWYwLWVuYzAwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAATaG2FJsfRNBRLN+kRb29GohiVUxapFx6grVOR5YO8L6j0SkOMFKfuA/D2lUdqW9//4aptbYDQCIfXb+0LGZg3BAFRc2slpx14aHQheiJETAxryou/aH0/pSxe3TxHTVlSjEDAOMAwGA1UdEwEB/wQCMAAwCgYIKoZIzj0EAwMDaAAwZQIwVRbi+0rFphB23zIYg209GgnwfnUbGvf3Ntkv+1EQ/jvO9Eztf2XKUrFYZ62SKWKYAjEAnefdxJdepCBbe2Bc125JTY32kSclAy7GBC6PseS5DmXgWogb0dPKdGGussdHbEnfaGNhYnVuZGxlglkBvTCCAbkwggE/oAMCAQICAQEwCgYIKoZIzj0EAwMwPDELMAkGA1UEBhMCVVMxEDAOBgNVBAoMB0V4YW1wbGUxGzAZBgNVBAMMEmRldi5uaXRyby1lbmNsYXZlczAgFw0yNjExMjEwODAwMDBaGA8yMDU2MTExMzA5MDAwMFowPDELMAkGA1UEBhMCVVMxEDAOBgNVBAoMB0V4YW1wbGUxGzAZBgNVBAMMEmRldi5uaXRyby1lbmNsYXZlczB2MBAGByqGSM49AgEGBSuBBAAiA2IABJ5q0NShHiRn6pcHwkVN/ano1H/TOQZ/d9PHdGnPly+c7O7bmwdZuelk7FDWqKRb+fF6qhcQ6vTlQ7ExYExB4C1pj+MYDfqyEWrWqepmZS9RRGJvRchQqN3FQOVrzvc/MaMTMBEwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjEAlkEk5xL6dBEh2DDDx2Jy3HO6b7vhYHNAcsuwq3ToU8Dg1nC/DK1jySBUF3Qg001bAjAxyvYrHfyN5Pu83yRNnAcXA3wFW3OB8wAsP4J5nxY8F1caEkFGIXhqX3L0TWEQivdZAbkwggG1MIIBO6ADAgECAgECMAoGCCqGSM49BAMDMDwxCzAJBgNVBAYTAlVTMRAwDgYDVQQKDAdFeGFtcGxlMRswGQYDVQQDDBJkZXYubml0cm8tZW5jbGF2ZXMwHhcNMjYxMTIxMDgwMDAwWhcNMjcxMTIxMDkwMDAwWjA6MQswCQYDVQQGEwJVUzEQMA4GA1UECgwHRXhhbXBsZTEZMBcGA1UEAwwQZGV2LWludGVybWVkaWF0ZTB2MBAGByqGSM49AgEGBSuBBAAiA2IABEkIPcWv6ropxw0UqdVSNoXQdMn5ZONDYdJmA+sP42gpSsf1R+JZ2Ko+iqt7VEin4JATVs0VQKJX0I9K61cw6qAz68oM9BoAlxqWPHgSBrIJx1owk5kY7xCU6mbLhk+xwaMTMBEwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjA4VPJxwVgok/FxQNsy71jTJ+JHjrkHqluycfgdQ5aZqWfJ0XHVklPohJwHM0ACc20CMQD0LX2WxdvF1dK4UHtFgo13bFm/eNnod083Tq09P/uwM6XyQBvr10GWs4n6wd+yviBqcHVibGljX2tleViOeyJrdHkiOiJFQyIsImNydiI6IlAtMjU2IiwieCI6IlBlWUdPd21oOEhfdlNLeGw4S2lwUWl4SVQzVU1kSGFLSnNKay1BZFljdjAiLCJ5IjoiM2tDY3NYTURzcVR0YXcteG50TzVxZlkwWnViQWRnRldVWXR4Z1BscGxzTSIsImtpZCI6ImVuY21hdmUifWl1c2VyX2RhdGFNY2RjLXJlbGF5LzAuMWVub25jZU9jbGllbnQtbm9uY2UtNDJYYLS50dkadsdDYOQN+Vb2JWDP7PaLicIgn9ibDYaF6GOL0MW9LClLmSQF9yaOfaQ3enteBYkn+wfaj+AcWIzuQlNcjzAoZc1Nj/CPcIZ5Rq3LM0PheCBMUjzE90WaGA78MQ==")!
    static let debugModeDocument = Data(base64Encoded: "0oREoQE4IqBZB5ipaW1vZHVsZV9pZHgYaS0wMTIzNDU2Nzg5YWJjZGVmMC1lbmMwZmRpZ2VzdGZTSEEzODRpdGltZXN0YW1wGwAAAaH9VXqAZHBjcnOmAFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVgw4WhbZCbZxb6Gkf+PlerNwRdTNVZnOUqiMSRXCxS69oqzIqOq6zxZnESK1QFscJpJAlgweHhHA5yRWyrA39S98cz2A2QMX97dgcouvSCGeivEhVGH4n/L3CzYW4PPvcsd5jL3A1gwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACFgwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAa2NlcnRpZmljYXRlWQG8MIIBuDCCAT6gAwIBAgIBAzAKBggqhkjOPQQDAzA6MQswCQYDVQQGEwJVUzEQMA4GA1UECgwHRXhhbXBsZTEZMBcGA1UEAwwQZGV2LWludGVybWVkaWF0ZTAeFw0yNjExMjEwODAwMDBaFw0yNjExMjIwOTAwMDBaMEIxCzAJBgNVBAYTAlVTMRAwDgYDVQQKDAdFeGFtcGxlMSEwHwYDVQQDDBhpLTAxMjM0NTY3ODlhYmNkZWYwLWVuYzAwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAATaG2FJsfRNBRLN+kRb29GohiVUxapFx6grVOR5YO8L6j0SkOMFKfuA/D2lUdqW9//4aptbYDQCIfXb+0LGZg3BAFRc2slpx14aHQheiJETAxryou/aH0/pSxe3TxHTVlSjEDAOMAwGA1UdEwEB/wQCMAAwCgYIKoZIzj0EAwMDaAAwZQIwVRbi+0rFphB23zIYg209GgnwfnUbGvf3Ntkv+1EQ/jvO9Eztf2XKUrFYZ62SKWKYAjEAnefdxJdepCBbe2Bc125JTY32kSclAy7GBC6PseS5DmXgWogb0dPKdGGussdHbEnfaGNhYnVuZGxlglkBvTCCAbkwggE/oAMCAQICAQEwCgYIKoZIzj0EAwMwPDELMAkGA1UEBhMCVVMxEDAOBgNVBAoMB0V4YW1wbGUxGzAZBgNVBAMMEmRldi5uaXRyby1lbmNsYXZlczAgFw0yNjExMjEwODAwMDBaGA8yMDU2MTExMzA5MDAwMFowPDELMAkGA1UEBhMCVVMxEDAOBgNVBAoMB0V4YW1wbGUxGzAZBgNVBAMMEmRldi5uaXRyby1lbmNsYXZlczB2MBAGByqGSM49AgEGBSuBBAAiA2IABJ5q0NShHiRn6pcHwkVN/ano1H/TOQZ/d9PHdGnPly+c7O7bmwdZuelk7FDWqKRb+fF6qhcQ6vTlQ7ExYExB4C1pj+MYDfqyEWrWqepmZS9RRGJvRchQqN3FQOVrzvc/MaMTMBEwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjEAlkEk5xL6dBEh2DDDx2Jy3HO6b7vhYHNAcsuwq3ToU8Dg1nC/DK1jySBUF3Qg001bAjAxyvYrHfyN5Pu83yRNnAcXA3wFW3OB8wAsP4J5nxY8F1caEkFGIXhqX3L0TWEQivdZAbkwggG1MIIBO6ADAgECAgECMAoGCCqGSM49BAMDMDwxCzAJBgNVBAYTAlVTMRAwDgYDVQQKDAdFeGFtcGxlMRswGQYDVQQDDBJkZXYubml0cm8tZW5jbGF2ZXMwHhcNMjYxMTIxMDgwMDAwWhcNMjcxMTIxMDkwMDAwWjA6MQswCQYDVQQGEwJVUzEQMA4GA1UECgwHRXhhbXBsZTEZMBcGA1UEAwwQZGV2LWludGVybWVkaWF0ZTB2MBAGByqGSM49AgEGBSuBBAAiA2IABEkIPcWv6ropxw0UqdVSNoXQdMn5ZONDYdJmA+sP42gpSsf1R+JZ2Ko+iqt7VEin4JATVs0VQKJX0I9K61cw6qAz68oM9BoAlxqWPHgSBrIJx1owk5kY7xCU6mbLhk+xwaMTMBEwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjA4VPJxwVgok/FxQNsy71jTJ+JHjrkHqluycfgdQ5aZqWfJ0XHVklPohJwHM0ACc20CMQD0LX2WxdvF1dK4UHtFgo13bFm/eNnod083Tq09P/uwM6XyQBvr10GWs4n6wd+yviBqcHVibGljX2tleViOeyJrdHkiOiJFQyIsImNydiI6IlAtMjU2IiwieCI6IlBlWUdPd21oOEhfdlNLeGw4S2lwUWl4SVQzVU1kSGFLSnNKay1BZFljdjAiLCJ5IjoiM2tDY3NYTURzcVR0YXcteG50TzVxZlkwWnViQWRnRldVWXR4Z1BscGxzTSIsImtpZCI6ImVuY2xhdmUifWl1c2VyX2RhdGFNY2RjLXJlbGF5LzAuMWVub25jZU9jbGllbnQtbm9uY2UtNDJYYB9DkjgwOi09dw6RVpiunUNw1LGrMwhAZmkeeRPQ4Y1XN71TH8i/0aVIofMLmQZ4t/zgNT2UudbP8ye39F6wFl1RuZX8rGseM3YNHEbMl0zkUMbkB4N0uUsvn4pcb/d76w==")!
    static let rootSHA256 = Data(hexString: "b82bdba6487113d083ad897f11f5b637a58ed9453792bbcb83611b5deb4d6f80")!
    static let pcr0 = Data(hexString: "ab54b752fefe2d9f59d9d1e69e244a3e272f8e3e021c4ef03ef9b1dbdb86ea7e7b95e523bed7f32f5ca15659e8ab0c7d")!
    static let now = Date(timeIntervalSince1970: 1795251600000 / 1000.0 + 30)

    var policy: NitroAttestationPolicy {
        NitroAttestationPolicy(trustedRootSHA256: Self.rootSHA256, expectedPCRs: [0: [Self.pcr0]], expectedNonce: Data("client-nonce-42".utf8))
    }

    func testVerifiesGenuineDocument() throws {
        let doc = try NitroAttestationVerifier(policy: policy).verify(Self.document, now: Self.now)
        XCTAssertEqual(doc.moduleID, "i-0123456789abcdef0-enc0")
        XCTAssertEqual(doc.digest, "SHA384")
        XCTAssertEqual(doc.pcrs.count, 6)
        XCTAssertEqual(doc.pcrs[0], Self.pcr0)
        XCTAssertEqual(doc.cabundle.count, 2)
        XCTAssertEqual(doc.userData, Data("cdc-relay/0.1".utf8))
        let key = try doc.recipientKey()
        XCTAssertEqual(key.kid, "enclave")
        XCTAssertEqual(key.x, "PeYGOwmh8H_vSKxl8KipQixIT3UMdHaKJsJk-AdYcv0")
        XCTAssertNoThrow(try key.keyAgreementKey)
    }

    func testRejectsTamperedPayload() {
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.tampered, now: Self.now)) { error in
            XCTAssertNotNil(error as? AttestationError)
        }
    }

    func testRejectsUntrustedRoot() {
        var policy = self.policy
        policy.trustedRootSHA256 = NitroAttestationPolicy.awsNitroRootSHA256
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.document, now: Self.now)) { error in
            XCTAssertEqual(error as? AttestationError, .untrustedRoot)
        }
    }

    func testRejectsWrongPCR() {
        var policy = self.policy
        policy.expectedPCRs = [0: [Data(repeating: 0xab, count: 48)]]
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.document, now: Self.now)) { error in
            XCTAssertEqual(error as? AttestationError, .pcrMismatch(index: 0))
        }
        policy.expectedPCRs = [0: [Self.pcr0], 2: [Self.pcr0]]
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.document, now: Self.now)) { error in
            XCTAssertEqual(error as? AttestationError, .pcrMismatch(index: 2))
        }
    }

    func testRequiresProductionImagePin() {
        var policy = self.policy
        policy.expectedPCRs = [:]
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.document, now: Self.now)) {
            XCTAssertEqual($0 as? AttestationError, .pcrMismatch(index: 0))
        }
    }

    func testRejectsDebugModeUnlessAllowed() throws {
        var policy = self.policy
        policy.expectedPCRs = [:]
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.debugModeDocument, now: Self.now)) { error in
            XCTAssertEqual(error as? AttestationError, .debugMode)
        }
        policy.allowsDebugMode = true
        XCTAssertNoThrow(try NitroAttestationVerifier(policy: policy).verify(Self.debugModeDocument, now: Self.now))
    }

    func testRejectsWrongNonceAndStaleDocument() {
        var policy = self.policy
        policy.expectedNonce = Data("other".utf8)
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.document, now: Self.now)) { error in
            XCTAssertEqual(error as? AttestationError, .nonceMismatch)
        }
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: self.policy).verify(Self.document, now: Self.now.addingTimeInterval(3600))) { error in
            guard case .stale = error as? AttestationError else { return XCTFail("expected stale, got \(error)") }
        }
    }

    func testRejectsExpiredLeafCertificate() {
        let afterLeafExpiry = Date(timeIntervalSince1970: 1795338000000 / 1000.0 + 60)
        var policy = self.policy
        policy.maxDocumentAge = .greatestFiniteMagnitude
        XCTAssertThrowsError(try NitroAttestationVerifier(policy: policy).verify(Self.document, now: afterLeafExpiry)) { error in
            XCTAssertEqual(error as? AttestationError, .certificateNotValid(index: 0))
        }
    }

    func testAWSRootConstantMatchesEmbeddedPEM() throws {
        let root = try X509Certificate(pem: NitroAttestationPolicy.awsNitroRootPEM)
        XCTAssertEqual(root.sha256Fingerprint, NitroAttestationPolicy.awsNitroRootSHA256)
        XCTAssertEqual(root.curve, .p384)
        XCTAssertTrue(root.isSigned(by: root), "the AWS root is self-signed")
        XCTAssertTrue(root.isValid(at: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testCBORRoundTrip() throws {
        let value: CBORValue = .array([.text("Signature1"), .bytes(Data([1, 2, 3])), .unsigned(300), .negative(9), .map([.unsigned(1): .negative(34)]), .bool(true), .null])
        XCTAssertEqual(try CBORDecoder.decode(CBOREncoder.encode(value)), value)
        XCTAssertEqual(CBOREncoder.encode(.map([.unsigned(1): .negative(34)])), Data([0xa1, 0x01, 0x38, 0x22]))
        XCTAssertThrowsError(try CBORDecoder.decode(Data([0x82, 0x01])))
    }
}

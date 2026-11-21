// CryptoKit on Apple platforms; swift-crypto (same API) on Linux, for tests and tooling.
#if canImport(CryptoKit)
@_exported import CryptoKit
#else
@_exported import Crypto
#endif

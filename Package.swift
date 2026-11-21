// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CDCScanner",
    platforms: [
        .iOS(.v16),
        // CDCCore and the tokenisation transport build on macOS; the UI products are iOS only.
        .macOS(.v12),
    ],
    products: [
        /// Camera scanning of payment cards, built on VisionKit. Re-exports CDCCore.
        .library(name: "CDCScanner", targets: ["CDCScanner"]),
        /// Hardened card-entry fields and tokenisation transport for PCI-conscious checkout. Re-exports CDCCore.
        .library(name: "CDCSecureFields", targets: ["CDCSecureFields"]),
        /// Brand rules, Luhn and parsing with no UI dependency.
        .library(name: "CDCCore", targets: ["CDCCore"]),
    ],
    dependencies: [
        // CryptoKit is used on Apple platforms. swift-crypto, Apple's open-source implementation of the
        // same API, is linked only when building on Linux so the encryption code can be tested there.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "CDCCore"
        ),
        .target(
            name: "CDCScanner",
            dependencies: ["CDCCore"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "CDCSecureFields",
            dependencies: [
                "CDCCore",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "CDCCoreTests",
            dependencies: ["CDCCore"]
        ),
        .testTarget(
            name: "CDCScannerTests",
            dependencies: ["CDCScanner"]
        ),
        .testTarget(
            name: "CDCSecureFieldsTests",
            dependencies: ["CDCSecureFields"]
        ),
    ]
)

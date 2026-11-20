// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CDCScanner",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "CDCScanner", targets: ["CDCScanner"])
    ],
    targets: [
        .target(
            name: "CDCScanner",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "CDCScannerTests",
            dependencies: ["CDCScanner"]
        )
    ]
)

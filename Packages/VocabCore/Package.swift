// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VocabCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "VocabCore", targets: ["VocabCore"])
    ],
    targets: [
        .target(name: "VocabCore"),
        .testTarget(name: "VocabCoreTests", dependencies: ["VocabCore"], resources: [.copy("Resources")]),
    ]
)

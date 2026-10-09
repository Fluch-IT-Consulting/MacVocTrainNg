// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "writer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/VocabCore")],
    targets: [.executableTarget(name: "writer", dependencies: ["VocabCore"])]
)

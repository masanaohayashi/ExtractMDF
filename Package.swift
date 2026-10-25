// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExtractMDF",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ExtractMDF", targets: ["ExtractMDF"]),
               .executable(name: "lzmtool", targets: ["lzmtool"])],
    targets: [
        .target(name: "LZMCore", resources: [.process("Resources")]),
        .executableTarget(name: "ExtractMDF", dependencies: ["LZMCore"]),
        .executableTarget(name: "lzmtool", dependencies: ["LZMCore"]),
        .testTarget(name: "LZMCoreTests", dependencies: ["LZMCore"], resources: [.copy("Fixtures")])
    ]
)

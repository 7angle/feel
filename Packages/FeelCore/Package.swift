// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FeelCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FeelCore", targets: ["FeelCore"])],
    targets: [
        .target(name: "FeelCore"),
        .testTarget(name: "FeelCoreTests", dependencies: ["FeelCore"]),
    ],
    swiftLanguageModes: [.v5]
)

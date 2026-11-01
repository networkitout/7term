// swift-tools-version:6.0
// Pure logic with no UI: connection targets, child environment, and later the
// log writer and hashing. Kept separate so it can be tested with `swift test`.
import PackageDescription

let package = Package(
    name: "ThreeTermCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThreeTermCore", targets: ["ThreeTermCore"]),
    ],
    targets: [
        .target(name: "ThreeTermCore"),
        .testTarget(name: "ThreeTermCoreTests", dependencies: ["ThreeTermCore"]),
    ]
)

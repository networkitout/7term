// swift-tools-version:6.0
// Logic with no UI: connection targets, the child environment, the saved host
// library and ssh_config import. Later: the log writer and hashing.
// Kept separate so it can be tested with `swift test`.
import PackageDescription

let package = Package(
    name: "ThreeTermCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThreeTermCore", targets: ["ThreeTermCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
    ],
    targets: [
        .target(
            name: "ThreeTermCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "ThreeTermCoreTests", dependencies: ["ThreeTermCore"]),
    ]
)

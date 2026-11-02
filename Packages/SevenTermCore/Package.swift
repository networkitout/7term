// swift-tools-version:6.0
// Logic with no UI: connection targets, the child environment, the saved host
// library and ssh_config import. Later: the log writer and hashing.
// Kept separate so it can be tested with `swift test`.
import PackageDescription

let package = Package(
    name: "SevenTermCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SevenTermCore", targets: ["SevenTermCore"]),
    ],
    dependencies: [
        // Exact, so builds are reproducible. Package.resolved is committed.
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.12.0"),
    ],
    targets: [
        .target(
            name: "SevenTermCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "SevenTermCoreTests", dependencies: ["SevenTermCore"]),
    ]
)

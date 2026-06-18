// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmberCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "EmberCore",
            targets: ["EmberCore"]
        ),
    ],
    targets: [
        .target(
            name: "EmberCore",
            path: "Sources/EmberCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "EmberCoreTests",
            dependencies: ["EmberCore"],
            path: "Tests/EmberCoreTests"
        ),
    ]
)

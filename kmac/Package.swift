// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "kmac-cli",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "kmac",
            targets: ["kmac"]
        ),
        .library(
            name: "KMacCore",
            targets: ["KMacCore"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "kmac",
            dependencies: ["KMacCore"],
            path: "Sources/kmac"
        ),
        .target(
            name: "KMacCore",
            dependencies: [],
            path: "Sources/KMacCore"
        ),
        .testTarget(
            name: "KMacCoreTests",
            dependencies: ["KMacCore"],
            path: "Tests/KMacCoreTests"
        )
    ]
)

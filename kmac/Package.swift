// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "kmac-cli",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "kmac",
            targets: ["kmac"]
        ),
        .executable(
            name: "kmac-app",
            targets: ["KMacApp"]
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
        .executableTarget(
            name: "KMacApp",
            dependencies: ["KMacCore"],
            path: "Sources/KMacApp"
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

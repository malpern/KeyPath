// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyPathCoreHarness",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "KeyPath", path: "../..")
    ],
    targets: [
        .testTarget(
            name: "KeyPathIsolatedCoreTests",
            dependencies: [
                .product(name: "KeyPathCore", package: "KeyPath")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

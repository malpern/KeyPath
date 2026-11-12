// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyPathCoreHarness",
    platforms: [
        .macOS("27.0")
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

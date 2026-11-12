// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyPathSmokeHarness",
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(name: "KeyPath", path: "../..")
    ],
    targets: [
        .testTarget(
            name: "KeyPathIsolatedSmokeTests",
            dependencies: [
                .product(name: "KeyPathCore", package: "KeyPath"),
                .product(name: "KeyPathPermissions", package: "KeyPath")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

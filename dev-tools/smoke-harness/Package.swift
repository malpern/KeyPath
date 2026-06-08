// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyPathSmokeHarness",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
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

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyPath",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The main executable that users will run
        .executable(
            name: "KeyPath",
            targets: ["KeyPathCLI"]
        ),
        // Library containing the SwiftUI app and core functionality
        .library(
            name: "KeyPathLib",
            targets: ["KeyPath"]
        )
    ],
    dependencies: [
        // Add any dependencies here
    ],
    targets: [
        // The executable target - just launches the app
        .executableTarget(
            name: "KeyPathCLI",
            dependencies: ["KeyPath"],
            path: "Sources/KeyPathCLI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The main app library with all SwiftUI code
        .target(
            name: "KeyPath",
            dependencies: [],
            path: "Sources/KeyPath",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Tests
        .testTarget(
            name: "KeyPathTests",
            dependencies: ["KeyPath"],
            path: "Tests/KeyPathTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

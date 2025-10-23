// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyPath",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "KeyPath",
            targets: ["KeyPath"]
        )
    ],
    dependencies: [
        // Add any dependencies here
    ],
    targets: [
        // Single executable target with all code
        .executableTarget(
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
                .swiftLanguageMode(.v6),
                // Surface concurrency issues clearly in Debug builds
                .unsafeFlags(["-Xfrontend","-warn-concurrency","-Xfrontend","-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // Tests
        .testTarget(
            name: "KeyPathTests",
            dependencies: ["KeyPath"],
            path: "Tests/KeyPathTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend","-warn-concurrency","-Xfrontend","-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        )
    ]
)

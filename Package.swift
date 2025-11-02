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
        ),
        .executable(
            name: "KeyPathHelper",
            targets: ["KeyPathHelper"]
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
                "Info.plist",
                "InstallationWizard/README.md"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Surface concurrency issues clearly in Debug builds
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // Privileged helper executable
        .executableTarget(
            name: "KeyPathHelper",
            dependencies: [],
            path: "Sources/KeyPathHelper",
            exclude: [
                "Info.plist",
                "com.keypath.helper.plist",
                "KeyPathHelper.entitlements"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // Tests
        .testTarget(
            name: "KeyPathTests",
            dependencies: ["KeyPath"],
            path: "Tests/KeyPathTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        )
    ]
)

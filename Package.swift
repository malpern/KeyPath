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
        // Core library with shared types/utilities
        .target(
            name: "KeyPathCore",
            path: "Sources/KeyPathCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // Permissions library (Oracle)
        .target(
            name: "KeyPathPermissions",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathPermissions",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // Daemon lifecycle library
        .target(
            name: "KeyPathDaemonLifecycle",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathDaemonLifecycle",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // Wizard core library (pure models/types)
        .target(
            name: "KeyPathWizardCore",
            dependencies: ["KeyPathCore", "KeyPathPermissions", "KeyPathDaemonLifecycle"],
            path: "Sources/KeyPathWizardCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // Single executable target with app code
        .executableTarget(
            name: "KeyPath",
            dependencies: [
                "KeyPathCore",
                "KeyPathPermissions",
                "KeyPathDaemonLifecycle",
                "KeyPathWizardCore"
            ],
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
            dependencies: ["KeyPath", "KeyPathCore", "KeyPathPermissions", "KeyPathDaemonLifecycle", "KeyPathWizardCore"],
            path: "Tests/KeyPathTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        )
    ]
)

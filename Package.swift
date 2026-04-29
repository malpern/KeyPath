// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyPath",
    defaultLocalization: "en",
    platforms: [
        // Keep CI compatible with GitHub-hosted Xcode versions while still supporting modern macOS.
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "KeyPathCore",
            targets: ["KeyPathCore"]
        ),
        .library(
            name: "KeyPathPermissions",
            targets: ["KeyPathPermissions"]
        ),
        .library(
            name: "KeyPathDaemonLifecycle",
            targets: ["KeyPathDaemonLifecycle"]
        ),
        .library(
            name: "KeyPathWizardCore",
            targets: ["KeyPathWizardCore"]
        ),
        .library(
            name: "KeyPathInstallationWizard",
            targets: ["KeyPathInstallationWizard"]
        ),
        .library(
            name: "KeyPathAppKit",
            targets: ["KeyPathAppKit"]
        ),
        .executable(
            name: "KeyPath",
            targets: ["KeyPath"]
        ),
        .executable(
            name: "KeyPathHelper",
            targets: ["KeyPathHelper"]
        ),
        .executable(
            name: "KeyPathKanataLauncher",
            targets: ["KeyPathKanataLauncher"]
        ),
        .library(
            name: "KeyPathLayoutTracerKit",
            targets: ["KeyPathLayoutTracerKit"]
        ),
        .executable(
            name: "KeyPathLayoutTracer",
            targets: ["KeyPathLayoutTracer"]
        ),
        .executable(
            name: "smappservice-poc",
            targets: ["SMAppServicePOC"]
        ),
        .library(
            name: "KeyPathPluginKit",
            targets: ["KeyPathPluginKit"]
        ),
        .executable(
            name: "keypath-cli",
            targets: ["KeyPathCLI"]
        ),
        .library(
            name: "KeyPathInsights",
            type: .dynamic,
            targets: ["KeyPathInsights"]
        )
    ],
    dependencies: [
        // Sparkle for automatic updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        // Snapshot testing for visual regression tests
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // ArgumentParser for CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // Core library with shared types/utilities
        .target(
            name: "KeyPathCore",
            path: "Sources/KeyPathCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Permissions library (Oracle)
        .target(
            name: "KeyPathPermissions",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathPermissions",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Daemon lifecycle library
        .target(
            name: "KeyPathDaemonLifecycle",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathDaemonLifecycle",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Wizard core library (pure models/types)
        .target(
            name: "KeyPathWizardCore",
            dependencies: ["KeyPathCore", "KeyPathPermissions", "KeyPathDaemonLifecycle"],
            path: "Sources/KeyPathWizardCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Plugin protocol shared library (linked by both host and plugins)
        .target(
            name: "KeyPathPluginKit",
            path: "Sources/KeyPathPluginKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Installation wizard (extracted from KeyPathAppKit for incremental compilation)
        .target(
            name: "KeyPathInstallationWizard",
            dependencies: ["KeyPathCore", "KeyPathPermissions", "KeyPathDaemonLifecycle", "KeyPathWizardCore"],
            path: "Sources/KeyPathInstallationWizard",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Main app library with UI and business logic
        .target(
            name: "KeyPathAppKit",
            dependencies: [
                "KeyPathCore",
                "KeyPathPermissions",
                "KeyPathDaemonLifecycle",
                "KeyPathWizardCore",
                "KeyPathInstallationWizard",
                "KeyPathPluginKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/KeyPathAppKit",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // Main executable entry point
        .executableTarget(
            name: "KeyPath",
            dependencies: [
                "KeyPathAppKit"
            ],
            path: "Sources/KeyPathApp",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources"),
                .copy("com.keypath.kanata.plist")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Privileged helper executable
        .executableTarget(
            name: "KeyPathHelper",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathHelper",
            exclude: [
                "Info.plist",
                "com.keypath.helper.plist",
                "KeyPathHelper.entitlements"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "KeyPathKanataLauncher",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathKanataLauncher",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "KeyPathLayoutTracerKit",
            path: "Sources/KeyPathLayoutTracerKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "KeyPathLayoutTracer",
            dependencies: ["KeyPathLayoutTracerKit"],
            path: "Sources/KeyPathLayoutTracer",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // SMAppService POC test utility
        .executableTarget(
            name: "SMAppServicePOC",
            dependencies: [],
            path: "dev-tools/debug",
            exclude: [
                "debug-admin-dialog.swift",
                "debug-admin-prompt.swift",
                "debug-current-wizard.swift",
                "debug-fix-button-execution.swift",
                "debug-fix-button-immediate.swift",
                "debug-launchdaemon-command.sh",
                "debug-plist-validation.sh",
                "debug-service-conflicts.sh",
                "debug-service-detection.swift",
                "debug-service-install.swift",
                "debug-unhealthy-services-fix.swift",
                "debug-wizard-detection.swift",
                "debug-wizard-fix-button.swift",
                "test-migration-scenarios.swift",
                "test-smappservice-simple.swift",
                "test-smappservice-standalone.swift",
                "test-tcc-stability.swift"
            ],
            sources: ["smappservice-poc.swift"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Standalone CLI binary
        .executableTarget(
            name: "KeyPathCLI",
            dependencies: [
                "KeyPathAppKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/KeyPathCLI",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // KeyPath Insights plugin bundle (activity logging, analytics)
        .target(
            name: "KeyPathInsights",
            dependencies: [
                "KeyPathCore",
                "KeyPathPluginKit"
            ],
            path: "Sources/KeyPathInsights",
            exclude: [
                "Info.plist"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Tests
        .testTarget(
            name: "KeyPathTests",
            dependencies: [
                "KeyPathAppKit",
                "KeyPathCore",
                "KeyPathPermissions",
                "KeyPathDaemonLifecycle",
                "KeyPathWizardCore",
                "KeyPathInstallationWizard"
            ],
            path: "Tests/KeyPathTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // Visual snapshot tests for help documentation screenshots
        .testTarget(
            name: "KeyPathSnapshotTests",
            dependencies: [
                "KeyPathAppKit",
                "KeyPathCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/KeyPathSnapshotTests",
            exclude: ["__Snapshots__"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KeyPathLayoutTracerTests",
            dependencies: [
                "KeyPathLayoutTracerKit"
            ],
            path: "Tests/KeyPathLayoutTracerTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

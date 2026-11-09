// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyPath",
    defaultLocalization: "en",
    platforms: [
        // KeyPath supports only the latest macOS (ADR-047).
        .macOS("27.0")
    ],
    products: [
        .library(
            name: "KeyPathCore",
            targets: ["KeyPathCore"]
        ),
        .library(
            name: "KeyPathSystemProbes",
            targets: ["KeyPathSystemProbes"]
        ),
        .library(
            name: "KeyPathPermissions",
            targets: ["KeyPathPermissions"]
        ),
        .library(
            name: "KeyPathRulesCore",
            targets: ["KeyPathRulesCore"]
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
        .library(
            name: "KeyPathLayoutTracerKit",
            targets: ["KeyPathLayoutTracerKit"]
        ),
        .executable(
            name: "KeyPathLayoutTracer",
            targets: ["KeyPathLayoutTracer"]
        ),
        .library(
            name: "KeyPathPluginKit",
            targets: ["KeyPathPluginKit"]
        ),
        .library(
            name: "KeyPathCLISupport",
            targets: ["KeyPathCLISupport"]
        ),
        .executable(
            name: "keypath-cli",
            targets: ["KeyPathCLIMain"]
        ),
        .library(
            name: "KeyPathInsights",
            type: .dynamic,
            targets: ["KeyPathInsights"]
        )
    ],
    dependencies: [
        // Sparkle for automatic updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
        // Snapshot testing for visual regression tests
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // ArgumentParser for CLI
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // Public C APIs/macros not exposed by the Swift Darwin/IOKit importer.
        .target(
            name: "KeyPathSessionNative",
            path: "Sources/KeyPathSessionNative",
            publicHeadersPath: "include"
        ),
        // Core library with shared types/utilities
        .target(
            name: "KeyPathSystemProbes",
            path: "Sources/KeyPathSystemProbes",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "KeyPathCore",
            dependencies: ["KeyPathSystemProbes"],
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
        // Pure rule/configuration domain models.
        .target(
            name: "KeyPathRulesCore",
            dependencies: ["KeyPathCore"],
            path: "Sources/KeyPathRulesCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Wizard core library (pure models/types)
        .target(
            name: "KeyPathWizardCore",
            dependencies: ["KeyPathCore", "KeyPathPermissions"],
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
        .target(
            name: "KeyPathCLISupport",
            dependencies: ["KeyPathInstallationWizard"],
            path: "Sources/KeyPathCLISupport",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Foundation-only CLI argument and presentation contracts.
        .target(
            name: "KeyPathCLICommon",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/KeyPathCLICommon",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Installation wizard (extracted from KeyPathAppKit for incremental compilation)
        .target(
            name: "KeyPathInstallationWizard",
            dependencies: ["KeyPathCore", "KeyPathPermissions", "KeyPathWizardCore"],
            path: "Sources/KeyPathInstallationWizard",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Main app library with UI and business logic
        .target(
            name: "KeyPathAppKit",
            dependencies: [
                "KeyPathSessionNative",
                "KeyPathCore",
                "KeyPathPermissions",
                "KeyPathRulesCore",
                "KeyPathWizardCore",
                "KeyPathInstallationWizard",
                "KeyPathPluginKit",
                "KeyPathCLISupport",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/KeyPathAppKit",
            exclude: [
                "InstallationWizard/README.md",
                // Compiled into default.metallib by CompileKeyboardStageMetal.
                "UI/KeyboardStage/Metal/KeyboardStage.metal"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit")
            ],
            plugins: [
                .plugin(name: "CompileKeyboardStageMetal")
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
                .process("Resources")
            ],
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
        // CLI library (testable)
        .target(
            name: "KeyPathCLIHelp",
            dependencies: [
                "KeyPathCLICommon",
                "KeyPathRulesCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/KeyPathCLI/Commands/Help",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "KeyPathCLI",
            dependencies: [
                "KeyPathCLISupport",
                "KeyPathCLICommon",
                "KeyPathCLIHelp",
                "KeyPathAppKit",
                "KeyPathRulesCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/KeyPathCLI",
            exclude: ["Commands/Help"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // CLI binary entry point
        .executableTarget(
            name: "KeyPathCLIMain",
            dependencies: ["KeyPathCLI"],
            path: "Sources/KeyPathCLIMain",
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
        .plugin(
            name: "CompileKeyboardStageMetal",
            capability: .buildTool(),
            path: "Plugins/CompileKeyboardStageMetal"
        ),
        // Tests
        .testTarget(
            name: "KeyPathSmokeTests",
            dependencies: [
                "KeyPathCore",
                "KeyPathPermissions"
            ],
            path: "Tests/KeyPathSmokeTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KeyPathCLISupportTests",
            dependencies: [
                "KeyPathCLISupport",
                "KeyPathInstallationWizard"
            ],
            path: "Tests/KeyPathCLISupportTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KeyPathTests",
            dependencies: [
                "KeyPathAppKit",
                "KeyPathCLI",
                "KeyPathCore",
                "KeyPathInsights",
                "KeyPathPermissions",
                "KeyPathRulesCore",
                "KeyPathWizardCore",
                "KeyPathInstallationWizard"
            ],
            path: "Tests/KeyPathTests",
            exclude: [
                "Integration/GoldenConfigs"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "KeyPathRulesCoreTests",
            dependencies: [
                "KeyPathRulesCore",
                "KeyPathCore"
            ],
            path: "Tests/KeyPathRulesCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "KeyPathCLIHelpTests",
            dependencies: [
                "KeyPathCLIHelp",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Tests/KeyPathCLIHelpTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Visual snapshot tests for help documentation screenshots
        .testTarget(
            name: "KeyPathSnapshotTests",
            dependencies: [
                "KeyPathAppKit",
                "KeyPathCore",
                "KeyPathRulesCore",
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

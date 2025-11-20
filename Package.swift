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
        ),
        .executable(
            name: "smappservice-poc",
            targets: ["SMAppServicePOC"]
        ),
        .executable(
            name: "KeyPathCLI",
            targets: ["KeyPathCLI"]
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
        // Shared app code (SwiftUI + installer engine)
        .target(
            name: "KeyPathAppKit",
            dependencies: [
                "KeyPathCore",
                "KeyPathPermissions",
                "KeyPathDaemonLifecycle",
                "KeyPathWizardCore"
            ],
            path: "Sources/KeyPathAppKit",
            exclude: [
                "InstallationWizard/README.md"
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
        // GUI executable target (bridges CLI + SwiftUI app)
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
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-strict-concurrency=complete"], .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        // Standalone CLI executable
        .executableTarget(
            name: "KeyPathCLI",
            dependencies: [
                "KeyPathAppKit"
            ],
            path: "Sources/KeyPathCLI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
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
        // Tests
        .testTarget(
            name: "KeyPathTests",
            dependencies: ["KeyPathAppKit", "KeyPathCore", "KeyPathPermissions", "KeyPathDaemonLifecycle", "KeyPathWizardCore"],
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

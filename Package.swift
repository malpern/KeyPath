// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyPath",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // The main executable (SwiftUI app)
        .executable(
            name: "KeyPath",
            targets: ["KeyPathApp"]
        ),
        // Library exposing the core (non‑UI) APIs
        .library(
            name: "KeyPathLib",
            targets: ["KeyPath"]
        )
    ],
    dependencies: [
        // Add any dependencies here
    ],
    targets: [
        // Core library (non-UI) with managers, services, models, utilities
        .target(
            name: "KeyPath",
            dependencies: [],
            path: "Sources/KeyPath",
            exclude: [
                "Info.plist",
                "UI",
                "InstallationWizard/UI",
                "InstallationWizard/Components",
                "App.swift",
                "Resources"
            ],
            resources: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // Surface concurrency issues clearly in Debug builds
                .unsafeFlags(["-Xfrontend","-warn-concurrency","-Xfrontend","-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        ),
        // App/UI target (SwiftUI + Installer) depending on the core
        .target(
            name: "KeyPathApp",
            dependencies: ["KeyPath"],
            path: "Sources/KeyPath",
            exclude: [
                "Info.plist",
                "Core",
                "Managers",
                "Services",
                "Infrastructure",
                "Utilities",
                "Models",
                "InstallationWizard/Core"
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
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xfrontend","-warn-concurrency","-Xfrontend","-strict-concurrency=complete"], .when(configuration: .debug))
            ]
        )
    ]
)

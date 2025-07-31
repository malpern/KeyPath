// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyPath",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "KeyPath",
            targets: ["KeyPath"]
        ),
    ],
    dependencies: [
        // Add any dependencies here
    ],
    targets: [
        .executableTarget(
            name: "KeyPath",
            dependencies: [],
            path: "Sources/KeyPath",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KeyPathTests",
            dependencies: ["KeyPath"],
            path: "Tests/KeyPathTests"
        ),
        .testTarget(
            name: "InstallationWizardTests",
            dependencies: ["KeyPath"],
            path: "Tests/InstallationWizardTests"
        ),
    ]
)
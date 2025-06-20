// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyPath",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "KeyPath",
            targets: ["KeyPath"]
        )
    ],
    dependencies: [
        // Add any external dependencies here
    ],
    targets: [
        .executableTarget(
            name: "KeyPath",
            path: "KeyPath",
            exclude: [
                "ContentView.swift.original"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "KeyPathTests",
            dependencies: ["KeyPath"],
            path: "KeyPathTests",
        )
    ]
)

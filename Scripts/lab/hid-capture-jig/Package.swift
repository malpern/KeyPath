// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KeyPathHIDCaptureJig",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HIDCaptureCore", targets: ["HIDCaptureCore"]),
        .executable(name: "HIDCaptureJig", targets: ["HIDCaptureJig"]),
    ],
    targets: [
        .target(name: "HIDCaptureCore"),
        .executableTarget(
            name: "HIDCaptureJig",
            dependencies: ["HIDCaptureCore"]
        ),
        .testTarget(
            name: "HIDCaptureCoreTests",
            dependencies: ["HIDCaptureCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)

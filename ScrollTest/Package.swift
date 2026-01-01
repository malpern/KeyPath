// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScrollTest",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScrollTest",
            path: "."
        )
    ]
)

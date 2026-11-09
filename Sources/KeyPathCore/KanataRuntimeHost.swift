import Foundation

/// Shared description of the app-bundled Kanata runtime layout: the host
/// bridge library the session worker loads, and the bundled Kanata engine.
/// Callers use this model instead of hardcoding the paths.
public struct KanataRuntimeHost: Sendable, Equatable {
    public let bridgeLibraryPath: String
    public let bundledCorePath: String

    /// Path to the Kanata Engine.app bundle wrapping the kanata binary.
    /// macOS TCC tracks this by CFBundleIdentifier instead of raw path.
    public let kanataEngineBundlePath: String

    public init(
        bridgeLibraryPath: String,
        bundledCorePath: String,
        kanataEngineBundlePath: String
    ) {
        self.bridgeLibraryPath = bridgeLibraryPath
        self.bundledCorePath = bundledCorePath
        self.kanataEngineBundlePath = kanataEngineBundlePath
    }

    /// The canonical kanata binary path. Always returns the bundled binary.
    public func preferredCoreBinaryPath() -> String {
        bundledCorePath
    }

    public static func current(
        bundlePath: String = Bundle.main.bundlePath
    ) -> KanataRuntimeHost {
        let resolvedBundlePath = appBundlePath(containing: bundlePath)
        let engineBundlePath = "\(resolvedBundlePath)/Contents/Library/KeyPath/Kanata Engine.app"
        return KanataRuntimeHost(
            bridgeLibraryPath: "\(resolvedBundlePath)/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "\(engineBundlePath)/Contents/MacOS/kanata",
            kanataEngineBundlePath: engineBundlePath
        )
    }

    public static func appBundlePath(containing bundlePath: String) -> String {
        let normalizedPath = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        if let appBoundary = normalizedPath.range(of: ".app/", options: .backwards) {
            return String(normalizedPath[..<appBoundary.upperBound].dropLast())
        }
        if normalizedPath.hasSuffix(".app") {
            return normalizedPath
        }
        let suffixes = [
            "/Contents/Library/KeyPath",
            "/Contents/MacOS"
        ]

        for suffix in suffixes where normalizedPath.hasSuffix(suffix) {
            return String(normalizedPath.dropLast(suffix.count))
        }

        return normalizedPath
    }
}

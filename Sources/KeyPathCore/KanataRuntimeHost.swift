import Foundation

/// Shared description of the current macOS Kanata runtime host layout.
///
/// This centralizes the app-bundled runtime host identity (`kanata-launcher`)
/// and the core binary paths it can execute. The current architecture still
/// hands off to the raw kanata binary, but callers should stop hardcoding
/// those paths independently so the eventual in-process host migration only
/// needs to change this model.
public struct KanataRuntimeHost: Sendable, Equatable {
    public let launcherPath: String
    public let bridgeLibraryPath: String
    public let bundledCorePath: String

    /// Deprecated: system binary is no longer installed. Returns bundledCorePath.
    @available(*, deprecated, message: "System binary removed; use bundledCorePath directly")
    public var systemCorePath: String {
        bundledCorePath
    }

    public init(
        launcherPath: String,
        bridgeLibraryPath: String,
        bundledCorePath: String
    ) {
        self.launcherPath = launcherPath
        self.bridgeLibraryPath = bridgeLibraryPath
        self.bundledCorePath = bundledCorePath
    }

    /// The canonical kanata binary path. Always returns the bundled binary.
    public func preferredCoreBinaryPath() -> String {
        bundledCorePath
    }

    public static func current(
        bundlePath: String = Bundle.main.bundlePath
    ) -> KanataRuntimeHost {
        let resolvedBundlePath = resolveAppBundlePath(from: bundlePath)
        return KanataRuntimeHost(
            launcherPath: "\(resolvedBundlePath)/Contents/Library/KeyPath/kanata-launcher",
            bridgeLibraryPath: "\(resolvedBundlePath)/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "\(resolvedBundlePath)/Contents/Library/KeyPath/kanata"
        )
    }

    private static func resolveAppBundlePath(from bundlePath: String) -> String {
        let normalizedPath = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
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

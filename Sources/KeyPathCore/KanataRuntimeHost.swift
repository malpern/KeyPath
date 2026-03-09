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
    public let systemCorePath: String

    public init(
        launcherPath: String,
        bridgeLibraryPath: String,
        bundledCorePath: String,
        systemCorePath: String
    ) {
        self.launcherPath = launcherPath
        self.bridgeLibraryPath = bridgeLibraryPath
        self.bundledCorePath = bundledCorePath
        self.systemCorePath = systemCorePath
    }

    public func preferredCoreBinaryPath(
        fileManager: FileManager = .default
    ) -> String {
        if fileManager.isExecutableFile(atPath: systemCorePath) {
            return systemCorePath
        }
        return bundledCorePath
    }

    public static func current(
        bundlePath: String = Bundle.main.bundlePath,
        systemRoot: String? = nil
    ) -> KanataRuntimeHost {
        let resolvedBundlePath = resolveAppBundlePath(from: bundlePath)
        return KanataRuntimeHost(
            launcherPath: "\(resolvedBundlePath)/Contents/Library/KeyPath/kanata-launcher",
            bridgeLibraryPath: "\(resolvedBundlePath)/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib",
            bundledCorePath: "\(resolvedBundlePath)/Contents/Library/KeyPath/kanata",
            systemCorePath: remapSystemPath("/Library/KeyPath/bin/kanata", under: systemRoot)
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

    private static func remapSystemPath(_ path: String, under systemRoot: String?) -> String {
        guard let systemRoot, !systemRoot.isEmpty, path.hasPrefix("/") else {
            return path
        }

        let trimmedRoot = systemRoot.hasSuffix("/") ? String(systemRoot.dropLast()) : systemRoot
        if path.hasPrefix(trimmedRoot) {
            return path
        }
        return trimmedRoot + path
    }
}

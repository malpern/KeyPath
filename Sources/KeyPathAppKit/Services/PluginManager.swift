import Foundation
import KeyPathCore
import KeyPathPluginKit
import SwiftUI

/// Entry in the plugin catalog describing an available (not yet installed) plugin.
@MainActor
public struct PluginCatalogEntry: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let downloadURL: URL
    public let estimatedSize: String
}

/// Discovers, loads, and manages KeyPath plugin bundles at runtime.
///
/// Plugins are `.bundle` files whose `NSPrincipalClass` conforms to `KeyPathPlugin`.
/// Two search paths are scanned:
/// 1. `~/Library/Application Support/KeyPath/Plugins/` (user-installed)
/// 2. `Contents/PlugIns/` inside the app bundle (bundled for dev)
@Observable
@MainActor
public final class PluginManager {
    // MARK: - Singleton

    public static let shared = PluginManager()

    // MARK: - State

    /// Currently loaded and active plugins
    public private(set) var plugins: [any KeyPathPlugin] = []

    /// Known plugins available for download
    public private(set) var availablePlugins: [PluginCatalogEntry] = []

    /// Whether a plugin install is in progress
    public private(set) var isInstalling = false

    /// Current install progress message
    public private(set) var installProgressMessage: String?

    // MARK: - Private

    private var loadedBundlePaths: Set<String> = []

    private var userPluginsDirectory: URL {
        let appSupport = Foundation.FileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("KeyPath/Plugins", isDirectory: true)
    }

    private init() {
        // Hardcoded catalog — just Insights for now
        availablePlugins = [
            PluginCatalogEntry(
                id: "com.keypath.insights",
                displayName: "Activity Insights",
                description: "Tracks keyboard usage patterns, shortcuts, and app switches.",
                downloadURL: URL(string: "https://github.com/malpern/KeyPath/releases/latest/download/Insights.bundle.zip")!,
                estimatedSize: "~2 MB"
            ),
        ]
    }

    // MARK: - Discovery & Loading

    /// Scans plugin directories and loads all discovered bundles.
    public func discoverAndLoadPlugins() {
        AppLogger.shared.info("🔌 [PluginManager] Discovering plugins...")

        var searchPaths: [URL] = [userPluginsDirectory]

        // Also scan app bundle's PlugIns directory
        if let builtInPlugIns = Bundle.main.builtInPlugInsURL {
            searchPaths.append(builtInPlugIns)
        }

        for searchPath in searchPaths {
            guard Foundation.FileManager().fileExists(atPath: searchPath.path) else {
                AppLogger.shared.debug("🔌 [PluginManager] Plugin path does not exist: \(searchPath.path)")
                continue
            }

            do {
                let contents = try Foundation.FileManager().contentsOfDirectory(
                    at: searchPath,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )

                for bundleURL in contents where bundleURL.pathExtension == "bundle" {
                    loadPlugin(from: bundleURL)
                }
            } catch {
                AppLogger.shared.error("🔌 [PluginManager] Failed to scan \(searchPath.path): \(error)")
            }
        }

        // Remove catalog entries for plugins that are already loaded
        let loadedIdentifiers = Set(plugins.map { type(of: $0).identifier })
        availablePlugins = availablePlugins.filter { !loadedIdentifiers.contains($0.id) }

        AppLogger.shared.info("🔌 [PluginManager] Loaded \(plugins.count) plugin(s)")
    }

    /// Load a single plugin bundle from a URL.
    public func loadPlugin(from bundleURL: URL) {
        let path = bundleURL.path
        guard !loadedBundlePaths.contains(path) else {
            AppLogger.shared.debug("🔌 [PluginManager] Already loaded: \(bundleURL.lastPathComponent)")
            return
        }

        guard let bundle = Bundle(url: bundleURL) else {
            AppLogger.shared.error("🔌 [PluginManager] Failed to create Bundle for: \(bundleURL.lastPathComponent)")
            return
        }

        guard bundle.load() else {
            AppLogger.shared.error("🔌 [PluginManager] Failed to load bundle: \(bundleURL.lastPathComponent)")
            return
        }

        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            AppLogger.shared.error(
                "🔌 [PluginManager] NSPrincipalClass is not NSObject: \(bundleURL.lastPathComponent)"
            )
            return
        }

        let instance = principalClass.init()

        guard let plugin = instance as? any KeyPathPlugin else {
            AppLogger.shared.error(
                "🔌 [PluginManager] NSPrincipalClass does not conform to KeyPathPlugin: \(bundleURL.lastPathComponent)"
            )
            return
        }

        plugins.append(plugin)
        loadedBundlePaths.insert(path)

        let identifier = type(of: plugin).identifier
        let displayName = type(of: plugin).displayName
        AppLogger.shared.info("🔌 [PluginManager] Loaded plugin: \(displayName) (\(identifier))")

        // Activate synchronously (plugin dispatches async work internally)
        plugin.activate()
        AppLogger.shared.info("🔌 [PluginManager] Activated plugin: \(displayName)")

        // Remove from available catalog
        availablePlugins.removeAll { $0.id == identifier }
    }

    // MARK: - Action Broadcasting

    /// Forward an action event to all loaded plugins.
    public func broadcastActionEvent(action: String, target: String?, uri: String) {
        for plugin in plugins {
            plugin.didReceiveActionEvent?(action: action, target: target, uri: uri)
        }
    }

    // MARK: - Install / Remove

    /// Downloads and installs a plugin bundle from a URL.
    public func installPlugin(from url: URL) async -> Bool {
        isInstalling = true
        installProgressMessage = "Downloading\u{2026}"

        defer {
            isInstalling = false
            installProgressMessage = nil
        }

        do {
            // Download
            let (tempFileURL, _) = try await URLSession.shared.download(from: url)

            installProgressMessage = "Installing\u{2026}"

            // Ensure plugins directory exists
            try Foundation.FileManager().createDirectory(at: userPluginsDirectory, withIntermediateDirectories: true)

            // Unzip
            let unzipDir = Foundation.FileManager().temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Foundation.FileManager().createDirectory(at: unzipDir, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", tempFileURL.path, unzipDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                AppLogger.shared.error("🔌 [PluginManager] Unzip failed with status \(process.terminationStatus)")
                return false
            }

            // Find the .bundle in unzipped contents
            let unzippedContents = try Foundation.FileManager().contentsOfDirectory(
                at: unzipDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            guard let bundleSource = unzippedContents.first(where: { $0.pathExtension == "bundle" }) else {
                AppLogger.shared.error("🔌 [PluginManager] No .bundle found in downloaded archive")
                return false
            }

            let destination = userPluginsDirectory.appendingPathComponent(bundleSource.lastPathComponent)

            // Remove existing if present
            if Foundation.FileManager().fileExists(atPath: destination.path) {
                try Foundation.FileManager().removeItem(at: destination)
            }

            try Foundation.FileManager().moveItem(at: bundleSource, to: destination)

            // Clean up temp files
            try? Foundation.FileManager().removeItem(at: tempFileURL)
            try? Foundation.FileManager().removeItem(at: unzipDir)

            // Load immediately
            loadPlugin(from: destination)

            AppLogger.shared.info("🔌 [PluginManager] Plugin installed from: \(url.lastPathComponent)")
            return true
        } catch {
            AppLogger.shared.error("🔌 [PluginManager] Install failed: \(error)")
            return false
        }
    }

    /// Removes a plugin by its identifier: deactivates, deletes bundle from disk.
    public func removePlugin(identifier: String) -> Bool {
        guard let index = plugins.firstIndex(where: { type(of: $0).identifier == identifier }) else {
            AppLogger.shared.warn("🔌 [PluginManager] Cannot remove unknown plugin: \(identifier)")
            return false
        }

        let plugin = plugins[index]
        let displayName = type(of: plugin).displayName

        // Deactivate
        plugin.deactivate?()

        plugins.remove(at: index)

        // Find and delete the bundle file
        let bundlePath = loadedBundlePaths.first { path in
            if let bundle = Bundle(path: path),
               let cls = bundle.principalClass as? NSObject.Type,
               let check = cls.init() as? any KeyPathPlugin,
               type(of: check).identifier == identifier
            {
                return true
            }
            return false
        }

        if let path = bundlePath {
            loadedBundlePaths.remove(path)
            do {
                try Foundation.FileManager().removeItem(atPath: path)
                AppLogger.shared.info("🔌 [PluginManager] Deleted bundle: \(path)")
            } catch {
                AppLogger.shared.error("🔌 [PluginManager] Failed to delete bundle: \(error)")
            }
        }

        // Re-add to catalog
        let catalogEntry = PluginCatalogEntry(
            id: identifier,
            displayName: displayName,
            description: "Tracks keyboard usage patterns, shortcuts, and app switches.",
            downloadURL: URL(string: "https://github.com/malpern/KeyPath/releases/latest/download/Insights.bundle.zip")!,
            estimatedSize: "~2 MB"
        )
        availablePlugins.append(catalogEntry)

        AppLogger.shared.info("🔌 [PluginManager] Removed plugin: \(displayName)")
        return true
    }

    /// Check if a specific plugin is loaded by identifier.
    public func isPluginLoaded(identifier: String) -> Bool {
        plugins.contains { type(of: $0).identifier == identifier }
    }
}

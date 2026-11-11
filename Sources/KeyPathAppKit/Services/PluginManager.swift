import Foundation
import KeyPathCore
import KeyPathPluginKit
import SwiftUI

/// Loads the plugins that ship inside KeyPath.app and forwards events to them.
///
/// Plugins are `.bundle` files in the app's `Contents/PlugIns/` whose
/// `NSPrincipalClass` conforms to `KeyPathPlugin`; today that is Insights. They
/// are built and signed with the app. KeyPath no longer downloads plugins or
/// loads them from a user directory (project review 2026-11-09, O6): code it
/// runs comes only from its own signed bundle.
@Observable
@MainActor
public final class PluginManager {
    // MARK: - Singleton

    public static let shared = PluginManager()

    // MARK: - State

    /// Currently loaded and active plugins
    public private(set) var plugins: [any KeyPathPlugin] = []

    // MARK: - Private

    private var loadedBundlePaths: Set<String> = []

    #if DEBUG
        var testPluginInstance: ((URL) throws -> NSObject)?
    #endif

    init() {}

    // MARK: - Discovery & Loading

    /// Loads every plugin bundle in the app's `Contents/PlugIns/`.
    public func discoverAndLoadPlugins() {
        guard let builtInPlugIns = Bundle.main.builtInPlugInsURL,
              FileManager.default.fileExists(atPath: builtInPlugIns.path)
        else {
            AppLogger.shared.debug("🔌 [PluginManager] No built-in plugins directory")
            return
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: builtInPlugIns, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
            for bundleURL in contents where bundleURL.pathExtension == "bundle" {
                loadPlugin(from: bundleURL)
            }
        } catch {
            AppLogger.shared.error("🔌 [PluginManager] Failed to scan \(builtInPlugIns.path): \(error)")
        }
        AppLogger.shared.info("🔌 [PluginManager] Loaded \(plugins.count) plugin(s)")
    }

    /// Load a single plugin bundle from a URL.
    @discardableResult
    func loadPlugin(from bundleURL: URL) -> Bool {
        let path = bundleURL.path
        guard !loadedBundlePaths.contains(path) else {
            AppLogger.shared.debug("🔌 [PluginManager] Already loaded: \(bundleURL.lastPathComponent)")
            return true
        }
        guard let instance = pluginInstance(from: bundleURL) else {
            AppLogger.shared.error("🔌 [PluginManager] Failed to load plugin: \(bundleURL.lastPathComponent)")
            return false
        }
        guard let plugin = instance as? any KeyPathPlugin else {
            AppLogger.shared.error(
                "🔌 [PluginManager] NSPrincipalClass does not conform to KeyPathPlugin: \(bundleURL.lastPathComponent)"
            )
            return false
        }
        plugins.append(plugin)
        loadedBundlePaths.insert(path)
        AppLogger.shared.info("🔌 [PluginManager] Loaded plugin: \(type(of: plugin).displayName) (\(type(of: plugin).identifier))")
        // Activate synchronously (plugin dispatches async work internally)
        plugin.activate()
        return true
    }

    private func pluginInstance(from bundleURL: URL) -> NSObject? {
        #if DEBUG
            if let testPluginInstance { return try? testPluginInstance(bundleURL) }
        #endif
        guard let bundle = Bundle(url: bundleURL), bundle.load(),
              let principalClass = bundle.principalClass as? NSObject.Type
        else { return nil }
        return principalClass.init()
    }

    // MARK: - Action Broadcasting

    /// Forward an action event to all loaded plugins.
    public func broadcastActionEvent(action: String, target: String?, uri: String) {
        for plugin in plugins {
            plugin.didReceiveActionEvent?(action: action, target: target, uri: uri)
        }
    }

    /// Ask all loaded plugins to flush buffered state before app termination,
    /// invoking `completion` once every plugin has finished (or immediately if
    /// none implement the hook). Each plugin's cleanup is async; the caller is
    /// responsible for bounding the overall wait with a timeout.
    public func prepareForTerminationAll(completion: @escaping @MainActor () -> Void) {
        let participating = plugins.filter { $0.responds(to: #selector(KeyPathPlugin.prepareForTermination(completion:))) }
        guard !participating.isEmpty else {
            completion()
            return
        }

        var remaining = participating.count
        AppLogger.shared.info("🔌 [PluginManager] Flushing \(remaining) plugin(s) for termination")
        for plugin in participating {
            plugin.prepareForTermination? {
                // Dispatch to MainActor rather than asserting — plugins may legally
                // call their completion from any thread or actor context.
                Task { @MainActor in
                    remaining -= 1
                    if remaining == 0 {
                        completion()
                    }
                }
            }
        }
    }
}

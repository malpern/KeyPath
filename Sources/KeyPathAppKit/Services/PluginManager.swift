import Foundation
import KeyPathCore
import KeyPathInsights
import KeyPathPluginKit
import SwiftUI

/// Holds KeyPath's built-in plugins and forwards events to them.
///
/// Insights is linked into the app (project review 2026-11-09, O6) and
/// registered at startup. KeyPath never loads plugin code from a bundle,
/// a user directory or a download.
@Observable
@MainActor
public final class PluginManager {
    // MARK: - Singleton

    public static let shared = PluginManager()

    // MARK: - State

    /// Currently registered and active plugins
    public private(set) var plugins: [any KeyPathPlugin] = []

    init() {}

    // MARK: - Registration

    /// Registers the plugins compiled into KeyPath, once.
    public func registerBuiltInPlugins() {
        Self.removeLegacyDownloadedPlugins()
        register(InsightsPlugin())
        AppLogger.shared.info("🔌 [PluginManager] Registered \(plugins.count) built-in plugin(s)")
    }

    /// Adds and activates a plugin; a second plugin with the same identifier is ignored.
    @discardableResult
    func register(_ plugin: any KeyPathPlugin) -> Bool {
        let identifier = type(of: plugin).identifier
        guard !plugins.contains(where: { type(of: $0).identifier == identifier }) else { return false }
        plugins.append(plugin)
        plugin.activate()
        AppLogger.shared.info("🔌 [PluginManager] Registered plugin: \(type(of: plugin).displayName) (\(identifier))")
        return true
    }

    /// Where 1.0.1 and earlier installed downloaded plugins. It held only the
    /// downloaded code (activity data lives in `KeyPath/ActivityLog`), and
    /// nothing loads from it now, so stale copies are removed.
    static func removeLegacyDownloadedPlugins(
        directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KeyPath/Plugins", isDirectory: true)
    ) {
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            AppLogger.shared.info("🔌 [PluginManager] Removed legacy downloaded plugins at \(directory.path)")
        } catch {
            AppLogger.shared.warn("🔌 [PluginManager] Could not remove legacy plugins directory: \(error)")
        }
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

import SwiftUI

/// Protocol that all KeyPath plugins must conform to.
///
/// Plugins are loaded dynamically from `.bundle` files at runtime.
/// The host app discovers bundles, loads their `NSPrincipalClass`, and
/// casts to `KeyPathPlugin` to integrate with Settings and action forwarding.
///
/// **Important:** This protocol lives in a shared dynamic library (`KeyPathPluginKit`)
/// so that both the host app and plugin bundles link against the same copy.
/// This ensures Swift protocol conformance checks (`as? KeyPathPlugin`) work
/// across bundle boundaries.
@MainActor
public protocol KeyPathPlugin: AnyObject {
    /// Reverse-DNS plugin identifier (e.g., `com.keypath.insights`)
    nonisolated static var identifier: String { get }

    /// Human-readable name shown in Settings
    nonisolated static var displayName: String { get }

    /// SwiftUI view rendered in the Settings panel when this plugin is loaded
    func settingsView() -> AnyView

    /// Called after the plugin is loaded and cast successfully
    func activate() async

    /// Called before the plugin is unloaded (default no-op)
    func deactivate() async

    /// Called when a `keypath://` action URI is dispatched.
    /// Plugins can use this to record analytics, trigger side effects, etc.
    func didReceiveActionEvent(action: String, target: String?, uri: String)
}

// MARK: - Default Implementations

public extension KeyPathPlugin {
    func deactivate() async {}
    func didReceiveActionEvent(action _: String, target _: String?, uri _: String) {}
}

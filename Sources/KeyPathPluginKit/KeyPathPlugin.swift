import AppKit

/// Protocol that all KeyPath plugins must conform to.
///
/// Plugins are loaded dynamically from `.bundle` files at runtime.
/// The host app discovers bundles, loads their `NSPrincipalClass`, and
/// casts to `KeyPathPlugin` to integrate with Settings and action forwarding.
///
/// **Important:** This is an `@objc` protocol so that the ObjC runtime
/// resolves conformance by *name* (not descriptor address). This allows
/// the protocol to work across bundle boundaries even when statically
/// linked into both host and plugin.
@objc public protocol KeyPathPlugin: NSObjectProtocol {
    /// Reverse-DNS plugin identifier (e.g., `com.keypath.insights`)
    @objc static var identifier: String { get }

    /// Human-readable name shown in Settings
    @objc static var displayName: String { get }

    /// Returns an NSViewController for the plugin's settings UI.
    /// Typically an `NSHostingController` wrapping a SwiftUI view.
    @objc func makeSettingsViewController() -> NSViewController

    /// Called after the plugin is loaded and cast successfully.
    /// Plugin can dispatch async work internally via `Task {}`.
    @objc func activate()

    /// Called before the plugin is unloaded (optional, default no-op).
    @objc optional func deactivate()

    /// Called when a `keypath://` action URI is dispatched.
    /// Plugins can use this to record analytics, trigger side effects, etc.
    @objc optional func didReceiveActionEvent(action: String, target: String?, uri: String)
}

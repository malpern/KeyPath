import AppKit
import Foundation
import KeyPathPluginKit
import SwiftUI

/// Plugin entry point for KeyPath Insights.
///
/// Loaded dynamically by the host app via `NSPrincipalClass`.
/// Provides activity logging settings UI and forwards action events
/// to `ActivityLogger` for usage analytics.
@objc(InsightsPlugin)
public class InsightsPlugin: NSObject, KeyPathPlugin {
    // MARK: - KeyPathPlugin

    public static let identifier = "com.keypath.insights"
    public static let displayName = "Activity Insights"

    public func makeSettingsViewController() -> NSViewController {
        // Always called from the main thread (UI layer), safe to assume MainActor
        MainActor.assumeIsolated {
            NSHostingController(rootView: ActivityLoggingSettingsSection())
        }
    }

    public func activate() {
        Task { @MainActor in
            if InsightsPreferences.activityLoggingEnabled {
                await ActivityLogger.shared.enable()
            }
        }
    }

    public func deactivate() {
        Task { @MainActor in
            await ActivityLogger.shared.disable()
        }
    }

    public func didReceiveActionEvent(action: String, target: String?, uri: String) {
        Task { @MainActor in
            ActivityLogger.shared.recordKeyPathAction(action: action, target: target, uri: uri)
        }
    }
}

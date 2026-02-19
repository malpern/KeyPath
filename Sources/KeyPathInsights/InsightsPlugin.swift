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

    public func settingsView() -> AnyView {
        AnyView(ActivityLoggingSettingsSection())
    }

    public func activate() async {
        if InsightsPreferences.activityLoggingEnabled {
            await ActivityLogger.shared.enable()
        }
    }

    public func deactivate() async {
        await ActivityLogger.shared.disable()
    }

    public func didReceiveActionEvent(action: String, target: String?, uri: String) {
        ActivityLogger.shared.recordKeyPathAction(action: action, target: target, uri: uri)
    }
}

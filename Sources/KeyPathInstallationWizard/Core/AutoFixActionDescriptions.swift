import KeyPathWizardCore

// MARK: - Auto-Fix Action Descriptions

/// User-friendly descriptions for auto-fix actions
///
/// Keep this free of logging so it can be called from SwiftUI view updates.
public enum AutoFixActionDescriptions {
    public static func describe(_ action: AutoFixAction) -> String {
        switch action {
        case .startSessionRuntime:
            String(localized: "Start KeyPath's remapping engine")
        }
    }

    /// Get detailed error message for specific auto-fix failures
    public static func errorMessage(for action: AutoFixAction) -> String {
        // One whole sentence per action, so it can be translated.
        switch action {
        case .startSessionRuntime:
            String(localized: "Failed to start KeyPath's remapping engine. Check logs for details and try again.")
        }
    }
}

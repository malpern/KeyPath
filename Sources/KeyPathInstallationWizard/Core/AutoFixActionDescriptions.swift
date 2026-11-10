import KeyPathWizardCore

// MARK: - Auto-Fix Action Descriptions

/// User-friendly descriptions for auto-fix actions
///
/// Keep this free of logging so it can be called from SwiftUI view updates.
public enum AutoFixActionDescriptions {
    public static func describe(_ action: AutoFixAction) -> String {
        switch action {
        case .synchronizeConfigPaths:
            "Fix config path mismatch between KeyPath and Kanata"
        case .restartCommServer:
            "Start KeyPath's remapping engine"
        }
    }

    /// Get detailed error message for specific auto-fix failures
    public static func errorMessage(for action: AutoFixAction) -> String {
        let description = describe(action)
        // Lowercase only the first letter, so names like KeyPath keep their case.
        let phrase = description.prefix(1).lowercased() + description.dropFirst()
        return "Failed to \(phrase). Check logs for details and try again."
    }
}

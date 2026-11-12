import Foundation

/// Save operation status for UI feedback
enum SaveStatus: Equatable, Sendable {
    case idle
    case saving
    case validating
    case success
    case failed(String)

    var message: String {
        switch self {
        case .idle: ""
        case .saving: String(localized: "Saving...")
        case .validating: String(localized: "Validating...")
        case .success: String(localized: "✅ Done")
        case let .failed(error): String(localized: "❌ Config Invalid: \(error)")
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .success: false
        default: true
        }
    }
}

/// Snapshot of RuntimeCoordinator state for UI updates
struct KanataUIState: Sendable {
    // Core Status
    let lastError: String?
    let lastWarning: String?
    let currentLayerName: String

    /// Validation
    let validationError: ConfigValidationError?

    /// Rule conflict resolution
    let pendingRuleConflict: RuleConflictContext?

    /// Save-time mapping conflict resolution (#460)
    let pendingMappingConflict: MappingConflictContext?

    /// Enable/save prerequisite resolution (#869)
    let pendingPrerequisiteResolution: RulePrerequisiteDialogModel?

    /// Disable-time dependent resolution (#868)
    let pendingDependentResolution: RuleDependentResolutionDialogModel?

    /// Why the running session leaves Caps Lock rules inactive, if it does.
    var capsPausedMessage: String?

    /// Empty state for initialization fallback
    static let empty = KanataUIState(
        lastError: nil,
        lastWarning: nil,
        currentLayerName: "base",
        validationError: nil,
        pendingRuleConflict: nil,
        pendingMappingConflict: nil,
        pendingPrerequisiteResolution: nil,
        pendingDependentResolution: nil
    )
}

/// Error state for configuration validation to be handled by UI
enum ConfigValidationError: Equatable, Sendable {
    case invalidStartup(errors: [String], backupPath: String)
    case saveFailed(title: String, errors: [String])
}

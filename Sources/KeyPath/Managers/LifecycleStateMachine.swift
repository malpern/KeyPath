import Foundation

/// Lightweight namespace that hosts the lifecycle enum used by UI and tests.
///
/// The previous "state machine" implementation (events, transition table, helpers)
/// is intentionally removed. Only the `KanataState` type remains to preserve
/// the public symbol path `LifecycleStateMachine.KanataState` and avoid churn.
///
/// Rationale:
/// - The app does not instantiate or drive a `LifecycleStateMachine` object.
/// - Call sites only use the nested enum for status plumbing and tests.
/// - Keeping the path avoids touching callers; behavior is unchanged.
enum LifecycleStateMachine {
    /// Comprehensive lifecycle states for Kanata.
    enum KanataState: String, CaseIterable, Equatable {
        case uninitialized
        case initializing
        case requirementsCheck = "requirements_check"
        case requirementsFailed = "requirements_failed"
        case installing
        case installationFailed = "installation_failed"
        case starting
        case running
        case stopping
        case stopped
        case restarting
        case error
        case configuring
        case configurationError = "configuration_error"

        /// Human-readable description for UI display.
        var displayName: String {
            switch self {
            case .uninitialized: "Not Started"
            case .initializing: "Initializing..."
            case .requirementsCheck: "Checking Requirements"
            case .requirementsFailed: "Requirements Failed"
            case .installing: "Installing..."
            case .installationFailed: "Installation Failed"
            case .starting: "Starting..."
            case .running: "Running"
            case .stopping: "Stopping..."
            case .stopped: "Stopped"
            case .restarting: "Restarting..."
            case .error: "Error"
            case .configuring: "Configuring..."
            case .configurationError: "Configuration Error"
            }
        }

        /// Whether this state indicates Kanata is operational.
        var isOperational: Bool { self == .running }

        /// Whether this state indicates an error condition.
        var isError: Bool {
            switch self {
            case .requirementsFailed, .installationFailed, .error, .configurationError: true
            default: false
            }
        }

        /// Whether this state indicates a transitional operation in progress.
        var isTransitioning: Bool {
            switch self {
            case .initializing, .requirementsCheck, .installing, .starting, .stopping, .restarting, .configuring: true
            default: false
            }
        }

        /// Whether the user can initiate actions from this state.
        var allowsUserActions: Bool { !isTransitioning }
    }
}

// Optional alias for future readability without changing call sites.
typealias KanataLifecycleState = LifecycleStateMachine.KanataState

import Foundation
import KeyPathCore
import KeyPathWizardCore

// MARK: - Service Process Status

public enum ServiceProcessStatus: Equatable {
    case running
    case stopped
    case failed(message: String?)
}

// MARK: - Service Status Evaluator

/// Single source of truth for service status evaluation across all wizard pages
/// Pure function approach - no side effects, consistent results
public enum ServiceStatusEvaluator {
    /// Evaluates a fresh runtime observation after an explicit lifecycle action.
    ///
    /// A successful operation suppresses daemon issues captured before the action
    /// began, while the fresh process observation still has to match the requested
    /// result. Permission issues cannot be repaired by a service action and remain
    /// visible. Failed operations retain all current issues to explain the failure.
    public static func evaluateAfterAction(
        operationSucceeded: Bool,
        kanataIsRunning: Bool,
        systemState: WizardSystemState,
        issuesBeforeAction: [WizardIssue]
    ) -> ServiceProcessStatus {
        let effectiveIssues = operationSucceeded ? issuesBeforeAction.filter { issue in
            if case .daemon = issue.identifier { return false }
            return true
        } : issuesBeforeAction

        return evaluate(
            kanataIsRunning: kanataIsRunning,
            systemState: systemState,
            issues: effectiveIssues
        )
    }

    /// Evaluates service status using the same logic for both summary and detail pages
    /// - Parameters:
    ///   - kanataIsRunning: Whether kanata process is currently running
    ///   - systemState: Current wizard system state
    ///   - issues: Issues detected by SystemStatusChecker (already Oracle-integrated)
    /// - Returns: Service process status classification
    public static func evaluate(
        kanataIsRunning: Bool,
        systemState: WizardSystemState,
        issues: [WizardIssue]
    ) -> ServiceProcessStatus {
        // If system is initializing, treat as stopped (UI will map to in-progress)
        if systemState == .initializing {
            return .stopped
        }

        // If process isn't running, it's stopped
        guard kanataIsRunning else {
            return .stopped
        }

        // Process is running - check if Oracle detected permission blocking issues
        if let blockingMessage = blockingIssueMessage(from: issues) {
            return .failed(message: blockingMessage)
        }

        // Process running and no Oracle-detected blocking issues
        return .running
    }

    /// Maps service process status to InstallationStatus for summary page
    /// - Parameters:
    ///   - status: Service process status from evaluate()
    ///   - systemState: Current wizard system state
    /// - Returns: InstallationStatus for UI display
    public static func toInstallationStatus(
        _ status: ServiceProcessStatus,
        systemState: WizardSystemState
    ) -> InstallationStatus {
        switch status {
        case .running:
            .completed
        case .failed:
            .failed
        case .stopped:
            systemState == .initializing ? .inProgress : .notStarted
        }
    }

    /// Extracts blocking permission issue message from Oracle results
    /// - Parameter issues: Issues array from SystemStatusChecker (Oracle-integrated)
    /// - Returns: Human-readable blocking issue message or nil
    public static func blockingIssueMessage(from issues: [WizardIssue]) -> String? {
        for issue in issues {
            // Only treat true failures as blocking. Warnings (e.g. "not verified" without FDA)
            // should not mark the service as failed.
            guard issue.severity == .critical || issue.severity == .error else { continue }
            if case let .permission(permission) = issue.identifier {
                switch permission {
                case .kanataInputMonitoring:
                    return "Input Monitoring permission required"
                case .kanataAccessibility:
                    return "Accessibility permission required"
                default:
                    continue
                }
            }
            // Any error/critical daemon issue is a true service failure (e.g. the
            // #624 grab failure: kanata running but not capturing input) — the
            // service must not render "running" green over it. The severity filter
            // above keeps warning-level daemon issues (e.g. status-check timeout)
            // from blocking.
            if case .daemon = issue.identifier {
                return issue.title
            }
        }
        return nil
    }
}

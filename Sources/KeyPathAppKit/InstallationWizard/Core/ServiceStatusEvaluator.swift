import Foundation
import KeyPathCore
import KeyPathWizardCore

// MARK: - Service Process Status

enum ServiceProcessStatus: Equatable {
  case running
  case stopped
  case failed(message: String?)
}

// MARK: - Service Status Evaluator

/// Single source of truth for service status evaluation across all wizard pages
/// Pure function approach - no side effects, consistent results
enum ServiceStatusEvaluator {
  /// Evaluates service status using the same logic for both summary and detail pages
  /// - Parameters:
  ///   - kanataIsRunning: Whether kanata process is currently running
  ///   - systemState: Current wizard system state
  ///   - issues: Issues detected by SystemStatusChecker (already Oracle-integrated)
  /// - Returns: Service process status classification
  static func evaluate(
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
  static func toInstallationStatus(
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
  static func blockingIssueMessage(from issues: [WizardIssue]) -> String? {
    for issue in issues {
      if case .permission(let permission) = issue.identifier {
        switch permission {
        case .kanataInputMonitoring:
          return "Input Monitoring permission required"
        case .kanataAccessibility:
          return "Accessibility permission required"
        default:
          continue
        }
      }
    }
    return nil
  }
}

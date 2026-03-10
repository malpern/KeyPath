import Foundation
import KeyPathCore
import KeyPathWizardCore

// MARK: - Karabiner Component Types

/// Individual Karabiner components that can be checked independently
enum KarabinerComponent {
    case driver // Karabiner VirtualHID driver and related components
}

// MARK: - Karabiner Components Status Evaluator

/// Single source of truth for Karabiner Components status evaluation across all wizard pages
/// Follows the same pattern as ServiceStatusEvaluator for consistency
enum KarabinerComponentsStatusEvaluator {
    /// Evaluates overall Karabiner Components status using comprehensive logic
    /// - Parameters:
    ///   - systemState: Current wizard system state
    ///   - issues: Issues detected by SystemStatusChecker
    /// - Returns: Overall installation status for Karabiner Components
    static func evaluate(
        systemState: WizardSystemState,
        issues: [WizardIssue]
    ) -> InstallationStatus {
        // If system is still initializing, don't show completed status
        if systemState == .initializing {
            return .notStarted
        }

        // Use WizardStateInterpreter to check for comprehensive Karabiner-related component issues
        let hasKarabinerIssues = issues.contains { issue in
            // Check for installation issues related to Karabiner/VHID only.
            // Legacy recovery services are no longer part of normal Karabiner readiness.
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.vhidDaemonMisconfigured),
                     .component(.vhidDriverVersionMismatch):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        return hasKarabinerIssues ? .failed : .completed
    }

    /// Get status of individual Karabiner component for detailed breakdown
    /// - Parameters:
    ///   - component: The specific component to check
    ///   - issues: Issues detected by SystemStatusChecker
    /// - Returns: Installation status for the individual component
    static func getIndividualComponentStatus(
        _ component: KarabinerComponent,
        in issues: [WizardIssue]
    ) -> InstallationStatus {
        switch component {
        case .driver:
            // Check for driver-related component issues
            let hasDriverIssues = issues.contains { issue in
                if issue.category == .installation {
                    switch issue.identifier {
                    case .component(.karabinerDriver),
                         .component(.vhidDeviceManager),
                         .component(.vhidDeviceActivation),
                         .component(.vhidDeviceRunning),
                         .component(.vhidDaemonMisconfigured),
                         .component(.vhidDriverVersionMismatch):
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
            return hasDriverIssues ? .failed : .completed
        }
    }

    /// Get all Karabiner-related issues for detailed error display
    /// - Parameter issues: Issues detected by SystemStatusChecker
    /// - Returns: Array of issues related to Karabiner components
    static func getKarabinerRelatedIssues(from issues: [WizardIssue]) -> [WizardIssue] {
        issues.filter { issue in
            // Include installation issues related to Karabiner/VHID only.
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.vhidDaemonMisconfigured),
                     .component(.vhidDriverVersionMismatch):
                    return true
                default:
                    return false
                }
            }
            return false
        }
    }

    /// Check if there are any issues that can be auto-fixed
    /// - Parameter issues: Issues detected by SystemStatusChecker
    /// - Returns: True if any Karabiner issues have auto-fix actions available
    static func hasAutoFixableIssues(in issues: [WizardIssue]) -> Bool {
        let karabinerIssues = getKarabinerRelatedIssues(from: issues)
        return karabinerIssues.contains { $0.autoFixAction != nil }
    }
}

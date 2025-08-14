import Foundation
import SwiftUI

/// Centralized interpreter for wizard state to ensure consistent UI status across all components
/// Eliminates direct KanataManager queries in UI and provides single source of truth
@MainActor
class WizardStateInterpreter: ObservableObject {
    // MARK: - Permission Status

    /// Get the status of a specific permission requirement
    func getPermissionStatus(_ permission: PermissionRequirement, in issues: [WizardIssue])
        -> InstallationStatus {
        let hasIssue = issues.contains { $0.identifier == .permission(permission) }
        return hasIssue ? .failed : .completed
    }

    /// Check if any permission issues exist
    func hasAnyPermissionIssues(in issues: [WizardIssue]) -> Bool {
        issues.contains { $0.identifier.isPermission }
    }

    /// Get all permission issues
    func getPermissionIssues(in issues: [WizardIssue]) -> [WizardIssue] {
        issues.filter(\.identifier.isPermission)
    }

    /// Check if a specific permission is granted
    func isPermissionGranted(_ permission: PermissionRequirement, in issues: [WizardIssue]) -> Bool {
        !issues.contains { $0.identifier == .permission(permission) }
    }

    // MARK: - Component Status

    /// Get the status of a specific component requirement
    func getComponentStatus(_ component: ComponentRequirement, in issues: [WizardIssue])
        -> InstallationStatus {
        let hasIssue = issues.contains { $0.identifier == .component(component) }
        return hasIssue ? .failed : .completed
    }

    /// Check if any component issues exist
    func hasAnyComponentIssues(in issues: [WizardIssue]) -> Bool {
        issues.contains { $0.identifier.isComponent }
    }

    /// Get all component issues
    func getComponentIssues(in issues: [WizardIssue]) -> [WizardIssue] {
        issues.filter(\.identifier.isComponent)
    }

    // MARK: - Conflict Status

    /// Check if any conflicts exist
    func hasAnyConflicts(in issues: [WizardIssue]) -> Bool {
        issues.contains { $0.identifier.isConflict }
    }

    /// Get all conflict issues
    func getConflictIssues(in issues: [WizardIssue]) -> [WizardIssue] {
        issues.filter(\.identifier.isConflict)
    }

    /// Check if there are Karabiner-related conflicts specifically
    func hasKarabinerConflict(in issues: [WizardIssue]) -> Bool {
        issues.contains { issue in
            if case let .conflict(conflict) = issue.identifier {
                if case .karabinerGrabberRunning = conflict {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Daemon Status

    /// Check if daemon is running (no daemon issues present)
    func isDaemonRunning(in issues: [WizardIssue]) -> Bool {
        !issues.contains { $0.identifier.isDaemon }
    }

    /// Get daemon issues
    func getDaemonIssues(in issues: [WizardIssue]) -> [WizardIssue] {
        issues.filter(\.identifier.isDaemon)
    }

    // MARK: - Background Services Status

    /// Check if background services are enabled (no background service issues present)
    func areBackgroundServicesEnabled(in issues: [WizardIssue]) -> Bool {
        !issues.contains { $0.category == .backgroundServices }
    }

    /// Get background service issues
    func getBackgroundServiceIssues(in issues: [WizardIssue]) -> [WizardIssue] {
        issues.filter { $0.category == .backgroundServices }
    }

    // MARK: - Overall Status Computation

    /// Determine if all requirements are met (no issues)
    func areAllRequirementsMet(in issues: [WizardIssue]) -> Bool {
        issues.isEmpty
    }

    /// Determine if there are any blocking issues (critical or error severity)
    func hasBlockingIssues(in issues: [WizardIssue]) -> Bool {
        issues.contains { $0.severity == .critical || $0.severity == .error }
    }

    /// Get the most critical issue severity present
    func getMostCriticalSeverity(in issues: [WizardIssue]) -> WizardIssue.IssueSeverity? {
        if issues.contains(where: { $0.severity == .critical }) {
            return .critical
        } else if issues.contains(where: { $0.severity == .error }) {
            return .error
        } else if issues.contains(where: { $0.severity == .warning }) {
            return .warning
        } else if issues.contains(where: { $0.severity == .info }) {
            return .info
        }
        return nil
    }

    // MARK: - Page-Specific Status

    /// Get issues relevant to a specific wizard page
    func getRelevantIssues(for page: WizardPage, in issues: [WizardIssue]) -> [WizardIssue] {
        switch page {
        case .conflicts:
            getConflictIssues(in: issues)
        case .inputMonitoring:
            // Input Monitoring permission page
            issues.filter {
                $0.identifier == .permission(.kanataInputMonitoring)
                    || $0.identifier == .permission(.keyPathInputMonitoring)
            }
        case .accessibility:
            // Accessibility permission page
            issues.filter {
                $0.identifier == .permission(.kanataAccessibility)
                    || $0.identifier == .permission(.keyPathAccessibility)
                    || $0.identifier == .permission(.driverExtensionEnabled)
            }
        case .karabinerComponents:
            // Karabiner-related components and background services
            issues.filter { issue in
                // Installation issues related to Karabiner
                if issue.category == .installation {
                    switch issue.identifier {
                    case .component(.karabinerDriver),
                         .component(.karabinerDaemon),
                         .component(.vhidDeviceManager),
                         .component(.vhidDeviceActivation),
                         .component(.vhidDeviceRunning),
                         .component(.launchDaemonServices),
                         .component(.vhidDaemonMisconfigured):
                        return true
                    default:
                        return false
                    }
                }
                // Include daemon and background services issues
                return issue.category == .daemon || issue.category == .backgroundServices
            }
        case .kanataComponents:
            // Kanata-related components
            issues.filter { issue in
                if issue.category == .installation {
                    switch issue.identifier {
                    case .component(.kanataBinary),
                         .component(.kanataService),
                         .component(.packageManager):
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
        case .service:
            [] // Service page doesn't use issues, it shows real-time status
        case .fullDiskAccess:
            [] // FDA page doesn't use issues, it's optional
        case .summary:
            issues // Summary shows all issues
        }
    }

    /// Determine the overall status for a wizard page
    func getPageStatus(for page: WizardPage, in issues: [WizardIssue]) -> InstallationStatus {
        let relevantIssues = getRelevantIssues(for: page, in: issues)

        if relevantIssues.isEmpty {
            return .completed
        } else if relevantIssues.contains(where: { $0.severity == .critical || $0.severity == .error }) {
            return .failed
        } else {
            return .failed // Warnings also indicate incomplete status
        }
    }

    // MARK: - UI Helper Methods

    /// Get the appropriate color for a status
    func getStatusColor(_ status: InstallationStatus) -> Color {
        switch status {
        case .notStarted:
            .secondary
        case .inProgress:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }

    /// Get the appropriate icon for a status
    func getStatusIcon(_ status: InstallationStatus) -> String {
        switch status {
        case .notStarted:
            "circle"
        case .inProgress:
            "clock"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.circle.fill"
        }
    }
}

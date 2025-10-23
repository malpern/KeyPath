import Foundation
import SwiftUI

// MARK: - Core Types

/// Represents the current page in the installation wizard
enum WizardPage: String, CaseIterable {
    case summary = "Summary"
    case fullDiskAccess = "Full Disk Access"
    case conflicts = "Resolve Conflicts"
    case inputMonitoring = "Input Monitoring"
    case accessibility = "Accessibility"
    case communication = "Communication"
    case karabinerComponents = "Karabiner Components"
    case kanataComponents = "Kanata Components"
    case service = "Start Service"

    /// User-friendly display name for accessibility and UI
    var displayName: String {
        switch self {
        case .summary: "Setup Overview"
        case .fullDiskAccess: "Full Disk Access (Optional)"
        case .conflicts: "Resolve System Conflicts"
        case .inputMonitoring: "Input Monitoring Permission"
        case .accessibility: "Accessibility Permission"
        case .karabinerComponents: "Karabiner Driver Setup"
        case .kanataComponents: "Kanata Engine Setup"
        case .communication: "Communication Protocol"
        case .service: "Start Keyboard Service"
        }
    }

    /// Stable identifier for automation and testing tools
    var accessibilityIdentifier: String {
        switch self {
        case .summary: "overview"
        case .fullDiskAccess: "full-disk-access"
        case .conflicts: "conflicts"
        case .inputMonitoring: "input-monitoring"
        case .accessibility: "accessibility"
        case .karabinerComponents: "karabiner-components"
        case .kanataComponents: "kanata-components"
        case .communication: "communication"
        case .service: "service"
        }
    }
}

// Explicit, user-facing ordering for wizard navigation and bullets.
// This matches the Summary order shown in WizardSystemStatusOverview.
extension WizardPage {
    static let orderedPages: [WizardPage] = [
        .summary,
        .fullDiskAccess,
        .conflicts,
        .inputMonitoring,
        .accessibility,
        .karabinerComponents,
        .kanataComponents,
        .service,
        .communication
    ]
}

/// Status of individual installation or check components
enum InstallationStatus {
    case notStarted
    case inProgress
    case completed
    case failed
}

/// Launch failure status for Kanata service failures
/// Decoupled from manager types to avoid UI-Manager coupling
enum LaunchFailureStatus: Equatable {
    case permissionDenied(String)
    case configError(String)
    case serviceFailure(String)
    case missingDependency(String)

    var shortMessage: String {
        switch self {
        case .permissionDenied:
            "Kanata needs permissions"
        case .configError:
            "Configuration error"
        case .serviceFailure:
            "Kanata service failed"
        case .missingDependency:
            "Kanata not installed"
        }
    }
}

// MARK: - Consolidated State Models

/// Represents the overall system state for the wizard
enum WizardSystemState: Equatable {
    case initializing
    case conflictsDetected(conflicts: [SystemConflict])
    case missingPermissions(missing: [PermissionRequirement])
    case missingComponents(missing: [ComponentRequirement])
    case daemonNotRunning
    case serviceNotRunning
    case ready
    case active
}

/// Types of system conflicts that prevent Kanata from running
enum SystemConflict: Equatable {
    case kanataProcessRunning(pid: Int, command: String)
    case karabinerGrabberRunning(pid: Int)
    case karabinerVirtualHIDDeviceRunning(pid: Int, processName: String)
    case karabinerVirtualHIDDaemonRunning(pid: Int)
    case exclusiveDeviceAccess(device: String)
}

/// Permission requirements for the system
enum PermissionRequirement: Equatable {
    case kanataInputMonitoring
    case kanataAccessibility
    case keyPathInputMonitoring
    case keyPathAccessibility
    case driverExtensionEnabled
    case backgroundServicesEnabled
}

/// Component requirements that need installation
enum ComponentRequirement: Equatable {
    case kanataBinaryMissing // Kanata binary needs to be installed to system location
    case kanataService
    case karabinerDriver
    case karabinerDaemon
    case vhidDeviceManager
    case vhidDeviceActivation
    case vhidDeviceRunning
    case launchDaemonServices
    case launchDaemonServicesUnhealthy // Services loaded but crashed/failing
    case vhidDaemonMisconfigured
    case vhidDriverVersionMismatch // Karabiner driver version incompatible with kanata version
    case kanataUDPServer // UDP server for Kanata communication and config validation
    case orphanedKanataProcess // Kanata running but not managed by LaunchDaemon
    case communicationServerConfiguration // Communication server enabled but not configured in service
    case communicationServerNotResponding // Communication server configured but not responding
    case udpServerConfiguration // UDP enabled but not configured in service
    case udpServerNotResponding // UDP configured but not responding
    case logRotation // Log rotation service to manage Kanata logs
}

/// Actions that can be automatically fixed by the wizard
enum AutoFixAction: Equatable {
    case terminateConflictingProcesses
    case startKarabinerDaemon
    case restartVirtualHIDDaemon
    case installMissingComponents
    case createConfigDirectories
    case activateVHIDDeviceManager
    case installLaunchDaemonServices
    case installBundledKanata // Install bundled kanata binary to system location
    case repairVHIDDaemonServices
    case synchronizeConfigPaths // Fix config path mismatches
    case restartUnhealthyServices // Restart services that are loaded but crashed
    case adoptOrphanedProcess // Install LaunchDaemon to manage existing process
    case replaceOrphanedProcess // Kill orphaned process and start managed one
    case installLogRotation // Install log rotation service to keep logs under 10MB
    case replaceKanataWithBundled // Replace system kanata with bundled Developer ID signed binary
    case enableUDPServer // Enable UDP server for communication
    case setupUDPAuthentication // Generate and configure UDP authentication token
    case regenerateCommServiceConfiguration // Update LaunchDaemon plist with UDP settings
    case restartCommServer // Restart service to enable UDP functionality
    case fixDriverVersionMismatch // Download and install correct Karabiner driver version (v5 for kanata v1.9.0)
}

/// Structured identifier for wizard issues to enable type-safe navigation
enum IssueIdentifier: Equatable {
    case permission(PermissionRequirement)
    case component(ComponentRequirement)
    case conflict(SystemConflict)
    case daemon

    /// Check if this identifier represents a conflict
    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }

    /// Check if this identifier represents a permission issue
    var isPermission: Bool {
        if case .permission = self { return true }
        return false
    }

    /// Check if this identifier represents a component issue
    var isComponent: Bool {
        if case .component = self { return true }
        return false
    }

    /// Check if this identifier represents a daemon issue
    var isDaemon: Bool {
        if case .daemon = self { return true }
        return false
    }
    
    /// Check if this identifier is related to VirtualHIDDevice issues
    var isVHIDRelated: Bool {
        switch self {
        case .component(let component):
            switch component {
            case .vhidDeviceManager, .vhidDeviceActivation, .vhidDeviceRunning, .vhidDaemonMisconfigured, .vhidDriverVersionMismatch:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

/// Issue detected by the wizard that requires attention
struct WizardIssue: Identifiable {
    let id = UUID()
    let identifier: IssueIdentifier
    let severity: IssueSeverity
    let category: IssueCategory
    let title: String
    let description: String
    let autoFixAction: AutoFixAction?
    let userAction: String?

    enum IssueSeverity {
        case info
        case warning
        case error
        case critical

        var color: Color {
            switch self {
            case .info: .blue
            case .warning: .orange
            case .error: .red
            case .critical: .purple
            }
        }

        var icon: String {
            switch self {
            case .info: "info.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.circle"
            case .critical: "exclamationmark.octagon"
            }
        }
    }

    enum IssueCategory {
        case conflicts
        case permissions
        case backgroundServices
        case installation
        case daemon
        case systemRequirements
    }
}

/// Navigation state for the wizard
struct WizardNavigationState {
    let currentPage: WizardPage
    let availablePages: [WizardPage]
    let canNavigateNext: Bool
    let canNavigatePrevious: Bool
    let shouldAutoNavigate: Bool
}

// MARK: - Detection Results

/// Result of system state detection
struct SystemStateResult {
    let state: WizardSystemState
    let issues: [WizardIssue]
    let autoFixActions: [AutoFixAction]
    let detectionTimestamp: Date

    var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .critical || $0.severity == .error }
    }

    var canAutoFix: Bool {
        !autoFixActions.isEmpty
    }
}

/// Result of conflict detection
struct ConflictDetectionResult {
    let conflicts: [SystemConflict]
    let canAutoResolve: Bool
    let description: String
    let managedProcesses: [ProcessLifecycleManager.ProcessInfo]

    var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    init(
        conflicts: [SystemConflict], canAutoResolve: Bool, description: String,
        managedProcesses: [ProcessLifecycleManager.ProcessInfo] = []
    ) {
        self.conflicts = conflicts
        self.canAutoResolve = canAutoResolve
        self.description = description
        self.managedProcesses = managedProcesses
    }
}

/// Result of permission checks
struct PermissionCheckResult {
    let missing: [PermissionRequirement]
    let granted: [PermissionRequirement]
    let needsUserAction: Bool

    var allGranted: Bool {
        missing.isEmpty
    }
}

/// Result of component installation checks
struct ComponentCheckResult {
    let missing: [ComponentRequirement]
    let installed: [ComponentRequirement]
    let canAutoInstall: Bool

    var allInstalled: Bool {
        missing.isEmpty
    }
}

/// Result of config path mismatch detection
struct ConfigPathMismatchResult {
    let mismatches: [ConfigPathMismatch]
    let canAutoResolve: Bool

    var hasMismatches: Bool {
        !mismatches.isEmpty
    }
}

/// Represents a config path mismatch between Kanata process and KeyPath expectations
struct ConfigPathMismatch {
    let processPID: pid_t
    let processCommand: String
    let actualConfigPath: String
    let expectedConfigPath: String
}

// MARK: - Constants

/// Constants for consistent wizard titles and messages
enum WizardConstants {
    enum Titles {
        static let inputMonitoring = "Input Monitoring"
        static let accessibility = "Accessibility"
        static let kanataInputMonitoring = "Kanata Input Monitoring"
        static let kanataAccessibility = "Kanata Accessibility"
        static let conflictingProcesses = "Conflicting Processes Detected"
        static let karabinerGrabberConflict = "Karabiner Grabber Conflict"
        static let daemonNotRunning = "Karabiner Daemon Not Running"
        static let driverExtensionDisabled = "Driver Extension Disabled"
        static let backgroundServicesDisabled = "Background Services Disabled"
        static let kanataBinaryMissing = "Kanata Binary Missing"
        static let karabinerDriverMissing = "Karabiner Driver Missing"
    }

    enum Messages {
        static let permissionRequired = "Permission required for keyboard remapping"
        static let conflictDetected = "Conflicting process detected"
        static let componentMissing = "Required component is missing"
        static let daemonRequired = "Daemon required for virtual HID functionality"
    }

    enum Actions {
        static let fixInSetup = "Fix in Setup"
    }
}

// MARK: - Protocols

// SystemStateDetecting protocol removed - SystemStatusChecker is now the single detection system

/// Protocol for objects that can automatically fix issues
protocol AutoFixCapable {
    func canAutoFix(_ action: AutoFixAction) -> Bool
    func performAutoFix(_ action: AutoFixAction) async -> Bool
}

/// Protocol for wizard navigation management
protocol WizardNavigating {
    /// Primary navigation method using structured issue identifiers for type-safe navigation
    func determineCurrentPage(for state: WizardSystemState, issues: [WizardIssue]) -> WizardPage
    func canNavigate(from: WizardPage, to: WizardPage, given state: WizardSystemState) -> Bool
    func nextPage(from current: WizardPage, given state: WizardSystemState, issues: [WizardIssue])
        -> WizardPage?
}

// MARK: - Helper Extensions

extension Array where Element == WizardIssue {
    /// Formats issues into a tooltip-friendly string for hover text
    /// Returns empty string if no issues, single issue details if one issue,
    /// or numbered list if multiple issues
    func asTooltipText() -> String {
        guard !isEmpty else { return "" }

        if count == 1 {
            let issue = self[0]
            return """
            \(issue.title)

            \(issue.description)
            """
        }

        // Multiple issues - show numbered list
        return self.enumerated()
            .map { index, issue in
                """
                \(index + 1). \(issue.title)
                   \(issue.description)
                """
            }
            .joined(separator: "\n\n")
    }
}

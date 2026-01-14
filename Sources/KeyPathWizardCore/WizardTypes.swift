import Foundation
import KeyPathDaemonLifecycle
import SwiftUI

// MARK: - Core Types

/// Represents the current page in the installation wizard
public enum WizardPage: String, CaseIterable, Sendable, Identifiable {
    public var id: String { rawValue }
    case summary = "Summary"
    case helper = "Privileged Helper"
    case fullDiskAccess = "Full Disk Access"
    case conflicts = "Resolve Conflicts"
    case inputMonitoring = "Input Monitoring"
    case accessibility = "Accessibility"
    case karabinerComponents = "Karabiner Components"
    case kanataComponents = "Kanata Components"
    case kanataMigration = "Kanata Migration"
    case stopExternalKanata = "Stop External Kanata"
    case service = "Start Service"
    case communication = "Communication"

    /// User-friendly display name for accessibility and UI
    public var displayName: String {
        switch self {
        case .summary: "Setup Overview"
        case .helper: "Privileged Helper Installation"
        case .fullDiskAccess: "Full Disk Access (Optional)"
        case .conflicts: "Resolve System Conflicts"
        case .inputMonitoring: "Input Monitoring Permission"
        case .accessibility: "Accessibility Permission"
        case .karabinerComponents: "Karabiner Driver Setup"
        case .kanataComponents: "Kanata Setup"
        case .kanataMigration: "Migrate Existing Kanata Config"
        case .stopExternalKanata: "Stop External Kanata"
        case .communication: "Communication Protocol"
        case .service: "Start Keyboard Service"
        }
    }

    /// Stable identifier for automation and testing tools
    public var accessibilityIdentifier: String {
        switch self {
        case .summary: "overview"
        case .fullDiskAccess: "full-disk-access"
        case .conflicts: "conflicts"
        case .inputMonitoring: "input-monitoring"
        case .accessibility: "accessibility"
        case .karabinerComponents: "karabiner-components"
        case .kanataComponents: "kanata-components"
        case .kanataMigration: "kanata-migration"
        case .stopExternalKanata: "stop-external-kanata"
        case .helper: "privileged-helper"
        case .communication: "communication"
        case .service: "service"
        }
    }
}

// Explicit, user-facing ordering for wizard navigation and bullets.
// This matches the Summary order shown in WizardSystemStatusOverview.
// NOTE: Helper is FIRST (after summary) because it's required for privileged operations
public extension WizardPage {
    static let orderedPages: [WizardPage] = [
        .summary,
        .kanataMigration,
        .stopExternalKanata,
        .helper,
        .conflicts,
        .accessibility,
        .inputMonitoring,
        .karabinerComponents,
        .fullDiskAccess,
        .kanataComponents
    ]
}

/// Status of individual installation or check components
public enum InstallationStatus {
    case notStarted
    case inProgress
    case completed
    case warning // Partial success or degraded state (e.g., installed but unhealthy)
    case failed
}

/// Launch failure status for Kanata service failures
/// Decoupled from manager types to avoid UI-Manager coupling
public enum LaunchFailureStatus: Equatable {
    case permissionDenied(String)
    case configError(String)
    case serviceFailure(String)
    case missingDependency(String)

    public var shortMessage: String {
        switch self {
        case let .permissionDenied(reason):
            // Preserve specific reason when provided for better deduping; fallback to generic
            reason.isEmpty ? "Kanata needs permissions" : reason
        case let .configError(reason):
            reason.isEmpty ? "Configuration error" : reason
        case let .serviceFailure(reason):
            reason.isEmpty ? "Kanata service failed" : reason
        case let .missingDependency(detail):
            detail.isEmpty ? "Kanata not installed" : detail
        }
    }
}

// MARK: - Consolidated State Models

/// Represents the overall system state for the wizard
public enum WizardSystemState: Equatable, Sendable {
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
public enum SystemConflict: Equatable, Sendable {
    case kanataProcessRunning(pid: Int, command: String)
    case karabinerGrabberRunning(pid: Int)
    case karabinerVirtualHIDDeviceRunning(pid: Int, processName: String)
    case karabinerVirtualHIDDaemonRunning(pid: Int)
    case exclusiveDeviceAccess(device: String)
}

/// Permission requirements for the system
public enum PermissionRequirement: Equatable, Sendable {
    case kanataInputMonitoring
    case kanataAccessibility
    case keyPathInputMonitoring
    case keyPathAccessibility
    case driverExtensionEnabled
    case backgroundServicesEnabled
}

/// Component requirements that need installation
public enum ComponentRequirement: Equatable, Sendable {
    case privilegedHelper // Privileged helper for system-level operations
    case privilegedHelperUnhealthy // Helper installed but not responding/working
    case kanataBinaryMissing // Kanata binary needs to be installed to system location
    case bundledKanataMissing // CRITICAL: Bundled kanata binary missing from app bundle (packaging issue)
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
    case kanataTCPServer // TCP server for Kanata communication and config validation
    case orphanedKanataProcess // Kanata running but not managed by LaunchDaemon
    case communicationServerConfiguration // Communication server enabled but not configured in service
    case communicationServerNotResponding // Communication server configured but not responding
    case tcpServerConfiguration // TCP enabled but not configured in service
    case tcpServerNotResponding // TCP configured but not responding
    case logRotation // Log rotation service to manage Kanata logs
}

/// Actions that can be automatically fixed by the wizard
public enum AutoFixAction: Equatable, Sendable {
    case installPrivilegedHelper // Install and register privileged helper
    case reinstallPrivilegedHelper // Reinstall helper if unhealthy
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
    case enableTCPServer // Enable TCP server for communication
    case setupTCPAuthentication // Generate and configure TCP authentication token
    case regenerateCommServiceConfiguration // Update LaunchDaemon plist with TCP settings
    case regenerateServiceConfiguration // Regenerate service configuration (plists + settings)
    case restartCommServer // Restart service to enable TCP functionality
    case fixDriverVersionMismatch // Download and install correct Karabiner driver version (v5 for kanata v1.9.0)
    case installCorrectVHIDDriver // Download and install the correct driver when missing (helper-first)
}

/// Structured identifier for wizard issues to enable type-safe navigation
public enum IssueIdentifier: Equatable, Sendable {
    case permission(PermissionRequirement)
    case component(ComponentRequirement)
    case conflict(SystemConflict)
    case daemon

    /// Check if this identifier represents a conflict
    public var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }

    /// Check if this identifier represents a permission issue
    public var isPermission: Bool {
        if case .permission = self { return true }
        return false
    }

    /// Check if this identifier represents a component issue
    public var isComponent: Bool {
        if case .component = self { return true }
        return false
    }

    /// Check if this identifier represents a daemon issue
    public var isDaemon: Bool {
        if case .daemon = self { return true }
        return false
    }

    /// Check if this identifier is related to VirtualHIDDevice issues
    public var isVHIDRelated: Bool {
        switch self {
        case let .component(component):
            switch component {
            case .vhidDeviceManager, .vhidDeviceActivation, .vhidDeviceRunning, .vhidDaemonMisconfigured,
                 .vhidDriverVersionMismatch:
                true
            default:
                false
            }
        default:
            false
        }
    }
}

/// Issue detected by the wizard that requires attention
public struct WizardIssue: Identifiable, Sendable {
    public let id = UUID()
    public let identifier: IssueIdentifier
    public let severity: IssueSeverity
    public let category: IssueCategory
    public let title: String
    public let description: String
    public let autoFixAction: AutoFixAction?
    public let userAction: String?

    public init(
        identifier: IssueIdentifier,
        severity: IssueSeverity,
        category: IssueCategory,
        title: String,
        description: String,
        autoFixAction: AutoFixAction?,
        userAction: String?
    ) {
        self.identifier = identifier
        self.severity = severity
        self.category = category
        self.title = title
        self.description = description
        self.autoFixAction = autoFixAction
        self.userAction = userAction
    }

    public enum IssueSeverity: Sendable {
        case info
        case warning
        case error
        case critical

        public var color: Color {
            switch self {
            case .info: .blue
            case .warning: .orange
            case .error: .red
            case .critical: .purple
            }
        }

        public var icon: String {
            switch self {
            case .info: "info.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.circle"
            case .critical: "exclamationmark.octagon"
            }
        }
    }

    public enum IssueCategory: Sendable {
        case conflicts
        case permissions
        case backgroundServices
        case installation
        case daemon
        case systemRequirements
    }
}

/// Navigation state for the wizard
public struct WizardNavigationState: Sendable {
    public let currentPage: WizardPage
    public let availablePages: [WizardPage]
    public let canNavigateNext: Bool
    public let canNavigatePrevious: Bool
    public let shouldAutoNavigate: Bool

    public init(
        currentPage: WizardPage, availablePages: [WizardPage], canNavigateNext: Bool,
        canNavigatePrevious: Bool, shouldAutoNavigate: Bool
    ) {
        self.currentPage = currentPage
        self.availablePages = availablePages
        self.canNavigateNext = canNavigateNext
        self.canNavigatePrevious = canNavigatePrevious
        self.shouldAutoNavigate = shouldAutoNavigate
    }
}

// MARK: - Detection Results

/// Result of system state detection
public struct SystemStateResult: Sendable {
    public let state: WizardSystemState
    public let issues: [WizardIssue]
    public let autoFixActions: [AutoFixAction]
    public let detectionTimestamp: Date

    public init(
        state: WizardSystemState, issues: [WizardIssue], autoFixActions: [AutoFixAction],
        detectionTimestamp: Date
    ) {
        self.state = state
        self.issues = issues
        self.autoFixActions = autoFixActions
        self.detectionTimestamp = detectionTimestamp
    }

    public var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .critical || $0.severity == .error }
    }

    public var canAutoFix: Bool {
        !autoFixActions.isEmpty
    }
}

/// Result of conflict detection
public struct ConflictDetectionResult {
    public let conflicts: [SystemConflict]
    public let canAutoResolve: Bool
    public let description: String
    public let managedProcesses: [ProcessLifecycleManager.ProcessInfo]

    public init(
        conflicts: [SystemConflict], canAutoResolve: Bool, description: String,
        managedProcesses: [ProcessLifecycleManager.ProcessInfo] = []
    ) {
        self.conflicts = conflicts
        self.canAutoResolve = canAutoResolve
        self.description = description
        self.managedProcesses = managedProcesses
    }

    public var hasConflicts: Bool {
        !conflicts.isEmpty
    }
}

/// Result of permission checks
public struct PermissionCheckResult {
    public let missing: [PermissionRequirement]
    public let granted: [PermissionRequirement]
    public let needsUserAction: Bool

    public init(
        missing: [PermissionRequirement], granted: [PermissionRequirement], needsUserAction: Bool
    ) {
        self.missing = missing
        self.granted = granted
        self.needsUserAction = needsUserAction
    }

    public var allGranted: Bool {
        missing.isEmpty
    }
}

/// Result of component installation checks
public struct ComponentCheckResult {
    public let missing: [ComponentRequirement]
    public let installed: [ComponentRequirement]
    public let canAutoInstall: Bool

    public init(
        missing: [ComponentRequirement], installed: [ComponentRequirement], canAutoInstall: Bool
    ) {
        self.missing = missing
        self.installed = installed
        self.canAutoInstall = canAutoInstall
    }

    public var allInstalled: Bool {
        missing.isEmpty
    }
}

/// Result of config path mismatch detection
public struct ConfigPathMismatchResult {
    public let mismatches: [ConfigPathMismatch]
    public let canAutoResolve: Bool

    public init(mismatches: [ConfigPathMismatch], canAutoResolve: Bool) {
        self.mismatches = mismatches
        self.canAutoResolve = canAutoResolve
    }

    public var hasMismatches: Bool {
        !mismatches.isEmpty
    }
}

/// Represents a config path mismatch between Kanata process and KeyPath expectations
public struct ConfigPathMismatch {
    public let processPID: pid_t
    public let processCommand: String
    public let actualConfigPath: String
    public let expectedConfigPath: String

    public init(
        processPID: pid_t, processCommand: String, actualConfigPath: String, expectedConfigPath: String
    ) {
        self.processPID = processPID
        self.processCommand = processCommand
        self.actualConfigPath = actualConfigPath
        self.expectedConfigPath = expectedConfigPath
    }
}

// MARK: - Constants

public enum WizardConstants {
    public enum Titles {
        public static let inputMonitoring = "Input Monitoring"
        public static let accessibility = "Accessibility"
        public static let kanataInputMonitoring = "Kanata Input Monitoring"
        public static let kanataAccessibility = "Kanata Accessibility"
        public static let conflictingProcesses = "Conflicting Processes Detected"
        public static let karabinerGrabberConflict = "Karabiner Grabber Conflict"
        public static let daemonNotRunning = "Karabiner Daemon Not Running"
        public static let driverExtensionDisabled = "Driver Extension Disabled"
        public static let backgroundServicesDisabled = "Background Services Disabled"
        public static let kanataBinaryMissing = "Kanata Binary Missing"
        public static let karabinerDriverMissing = "Karabiner Driver Missing"
    }

    public enum Messages {
        public static let permissionRequired = "Permission required for keyboard remapping"
        public static let conflictDetected = "Conflicting process detected"
        public static let componentMissing = "Required component is missing"
        public static let daemonRequired = "Daemon required for virtual HID functionality"
    }

    public enum Actions {
        public static let fixInSetup = "Fix in Setup"
    }
}

// MARK: - Protocols

/// Protocol for objects that can automatically fix issues
public protocol AutoFixCapable {
    func canAutoFix(_ action: AutoFixAction) -> Bool
    func performAutoFix(_ action: AutoFixAction) async -> Bool
}

/// Protocol for wizard navigation management
@MainActor
public protocol WizardNavigating {
    /// Primary navigation method using structured issue identifiers for type-safe navigation
    func determineCurrentPage(for state: WizardSystemState, issues: [WizardIssue]) async -> WizardPage
    func canNavigate(from: WizardPage, to: WizardPage, given state: WizardSystemState) -> Bool
    func nextPage(from current: WizardPage, given state: WizardSystemState, issues: [WizardIssue])
        async -> WizardPage?
}

// MARK: - Helper Extensions

public extension [WizardIssue] {
    /// Concise tooltip text: short and readable.
    /// - Single issue: "Title — short description"
    /// - Multiple issues: bullet list of up to 3 titles, then "… and N more"
    /// Descriptions are truncated to ~90 chars to keep tooltips compact.
    func asTooltipText() -> String {
        guard !isEmpty else { return "" }

        func truncate(_ s: String, limit: Int = 90) -> String {
            if s.count <= limit { return s }
            let end = s.index(s.startIndex, offsetBy: limit)
            return String(s[s.startIndex ..< end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        if count == 1 {
            let issue = self[0]
            let summary = truncate(issue.description)
            return summary.isEmpty ? issue.title : "\(issue.title) — \(summary)"
        }

        let maxItems = 3
        let lines = prefix(maxItems).map { "• " + $0.title }
        let remaining = count - lines.count
        if remaining > 0 {
            return (lines + ["… and \(remaining) more"]).joined(separator: "\n")
        } else {
            return lines.joined(separator: "\n")
        }
    }
}

import Foundation
import SwiftUI

// MARK: - Core Types

/// Represents the current page in the installation wizard
enum WizardPage: String, CaseIterable {
    case summary = "Summary"
    case conflicts = "Resolve Conflicts"
    case inputMonitoring = "Input Monitoring Permission"
    case accessibility = "Accessibility Permission"
    case backgroundServices = "Background Services"
    case installation = "Install Components"
    case daemon = "Karabiner Daemon"
}

/// Status of individual installation or check components
enum InstallationStatus {
    case notStarted
    case inProgress
    case completed
    case failed
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
    case exclusiveDeviceAccess(device: String)
}

/// Permission requirements for the system
enum PermissionRequirement: Equatable {
    case kanataInputMonitoring
    case kanataAccessibility
    case driverExtensionEnabled
    case backgroundServicesEnabled
}

/// Component requirements that need installation
enum ComponentRequirement: Equatable {
    case kanataBinary
    case kanataService
    case karabinerDriver
    case karabinerDaemon
}

/// Actions that can be automatically fixed by the wizard
enum AutoFixAction: Equatable {
    case terminateConflictingProcesses
    case startKarabinerDaemon
    case restartVirtualHIDDaemon
    case installMissingComponents
    case createConfigDirectories
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
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .critical: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .critical: return "exclamationmark.octagon"
            }
        }
    }
    
    enum IssueCategory {
        case conflicts
        case permissions
        case backgroundServices
        case installation
        case daemon
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
    
    var hasConflicts: Bool {
        !conflicts.isEmpty
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
}

// MARK: - Protocols

/// Protocol for objects that can detect system state
protocol SystemStateDetecting {
    func detectCurrentState() async -> SystemStateResult
    func detectConflicts() async -> ConflictDetectionResult
    func checkPermissions() async -> PermissionCheckResult
    func checkComponents() async -> ComponentCheckResult
}

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
    func nextPage(from current: WizardPage, given state: WizardSystemState, issues: [WizardIssue]) -> WizardPage?
}
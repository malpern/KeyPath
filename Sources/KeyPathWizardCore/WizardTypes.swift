import Foundation
import KeyPathCore
import KeyPathPermissions
import SwiftUI

// MARK: - Core Types

/// Represents the current page in the installation wizard
public enum WizardPage: String, CaseIterable, Sendable, Identifiable {
    public var id: String {
        rawValue
    }

    case welcome = "Welcome"
    case summary = "Summary"
    case accessibility = "Accessibility"
    case kanataMigration = "Kanata Migration"
    case stopExternalKanata = "Stop External Kanata"
    case karabinerImport = "Karabiner Import"
    case service = "Start Service"

    /// User-friendly display name for accessibility and UI
    public var displayName: String {
        switch self {
        case .welcome: "Welcome to KeyPath"
        case .summary: "Setup Overview"
        case .accessibility: "\(AccessibilityPermissionPresentation.current.name) Permission"
        case .kanataMigration: "Migrate Existing Kanata Config"
        case .stopExternalKanata: "Stop External Kanata"
        case .karabinerImport: "Import Karabiner Rules"
        case .service: "Start Keyboard Service"
        }
    }

    /// Stable identifier for automation and testing tools
    public var accessibilityIdentifier: String {
        switch self {
        case .welcome: "welcome"
        case .summary: "overview"
        case .accessibility: "accessibility"
        case .kanataMigration: "kanata-migration"
        case .stopExternalKanata: "stop-external-kanata"
        case .karabinerImport: "karabiner-import"
        case .service: "service"
        }
    }
}

/// Explicit, user-facing ordering for wizard navigation and bullets.
/// This matches the Summary order shown in WizardSystemStatusOverview.
public extension WizardPage {
    static let orderedPages: [WizardPage] = [
        .summary,
        .kanataMigration,
        .stopExternalKanata,
        .karabinerImport,
        .accessibility,
        .service
    ]

    /// "Step X of Y" position of a page within a wizard navigation sequence.
    /// Summary is the overview page, not a numbered step, so it's excluded
    /// from both the step number and the total; a page that isn't part of
    /// `sequence` (or `.summary` itself) has no step info.
    struct StepPosition: Equatable {
        public let step: Int
        public let total: Int

        public init(step: Int, total: Int) {
            self.step = step
            self.total = total
        }
    }

    /// Compute this page's "Step X of Y" position within the given sequence
    /// (defaults to `orderedPages`). Returns `nil` for `.summary` or for a
    /// page not present in `sequence`.
    func stepPosition(in sequence: [WizardPage] = WizardPage.orderedPages) -> StepPosition? {
        guard self != .summary else { return nil }
        let steps = sequence.filter { $0 != .summary }
        guard let index = steps.firstIndex(of: self) else { return nil }
        return StepPosition(step: index + 1, total: steps.count)
    }
}

/// Status of individual installation or check components
public enum InstallationStatus {
    case notStarted
    case inProgress
    case completed
    case warning // Partial success or degraded state (e.g., installed but unhealthy)
    case failed
    case unverified // Permission evidence is unavailable
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
    case missingPermissions(missing: [PermissionRequirement])
    case missingComponents(missing: [ComponentRequirement])
    case serviceNotRunning
    case ready
    case active
}

/// Types of system conflicts that prevent Kanata from running
public enum SystemConflict: Equatable, Sendable {
    case kanataProcessRunning(pid: Int, command: String)
    case karabinerGrabberRunning(pid: Int)
    case exclusiveDeviceAccess(device: String)
}

/// Permission requirements for the system
public enum PermissionRequirement: Equatable, Sendable {
    /// KeyPath.app's own Accessibility grant (Device Control and Data Access on macOS 27).
    case keyPathAccessibility
    /// The session runtime reports it cannot read or post keys; it needs a fresh launch.
    case runtimeKeyAccess
}

/// Component requirements that need installation
public enum ComponentRequirement: Equatable, Sendable {
    case bundledKanataMissing // CRITICAL: Bundled kanata binary missing from app bundle (packaging issue)
    case keyPathRuntime
}

/// Actions that can be automatically fixed by the wizard
public enum AutoFixAction: Equatable, Sendable {
    /// Start the user-session runtime.
    case startSessionRuntime
}

/// Structured identifier for wizard issues to enable type-safe navigation
public enum IssueIdentifier: Equatable, Sendable {
    case permission(PermissionRequirement)
    case component(ComponentRequirement)
    case daemon
    case validationTimeout

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
}

/// Issue detected by the wizard that requires attention
public struct WizardIssue: Identifiable, Equatable, Sendable {
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

    public enum IssueSeverity: Equatable, Sendable {
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

    public enum IssueCategory: Equatable, Sendable {
        case permissions
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
    public let stateMatrixRow: String?
    public let stateMatrixPlan: [String]
    public let captureStatus: SystemSnapshotCaptureStatus
    /// Permission facts from the same canonical capture as `state` and `issues`.
    /// Optional for synthetic/error results that have no permission snapshot.
    public let permissions: PermissionOracle.Snapshot?

    public init(
        state: WizardSystemState, issues: [WizardIssue], autoFixActions: [AutoFixAction],
        detectionTimestamp: Date,
        stateMatrixRow: String? = nil,
        stateMatrixPlan: [String] = [],
        captureStatus: SystemSnapshotCaptureStatus = .complete,
        permissions: PermissionOracle.Snapshot? = nil
    ) {
        self.state = state
        self.issues = issues
        self.autoFixActions = autoFixActions
        self.detectionTimestamp = detectionTimestamp
        self.stateMatrixRow = stateMatrixRow
        self.stateMatrixPlan = stateMatrixPlan
        self.captureStatus = captureStatus
        self.permissions = permissions
    }

    public var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .critical || $0.severity == .error }
    }

    public var canAutoFix: Bool {
        !autoFixActions.isEmpty
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
    public enum Actions {
        public static let fixInSetup = "Fix in Setup"
    }
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

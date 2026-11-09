import Foundation
import KeyPathCore
import KeyPathPermissions

public enum SystemSnapshotCaptureStatus: String, Sendable, Equatable {
    case complete
    case failed
    case cancelled
    case timedOut

    public var isComplete: Bool {
        self == .complete
    }
}

public struct SystemCompatibilityStatus: Sendable, Equatable {
    public let macOSVersion: String

    public init(macOSVersion: String) {
        self.macOSVersion = macOSVersion
    }

    public static let unknown = SystemCompatibilityStatus(macOSVersion: "unknown")
}

/// Complete snapshot of system state at a point in time
/// This is a pure data structure with no side effects - just state and computed properties
public struct SystemSnapshot: Sendable {
    /// Stable identity for correlating the evidence across planning and reports.
    public let id: UUID
    public let permissions: PermissionOracle.Snapshot
    public let components: ComponentStatus
    public let conflicts: ConflictStatus
    public let health: HealthStatus
    public let compatibility: SystemCompatibilityStatus
    public let timestamp: Date
    public let captureStatus: SystemSnapshotCaptureStatus

    public init(
        id: UUID = UUID(),
        permissions: PermissionOracle.Snapshot,
        components: ComponentStatus,
        conflicts: ConflictStatus,
        health: HealthStatus,
        compatibility: SystemCompatibilityStatus = .unknown,
        timestamp: Date,
        captureStatus: SystemSnapshotCaptureStatus = .complete
    ) {
        self.id = id
        self.permissions = permissions
        self.components = components
        self.conflicts = conflicts
        self.health = health
        self.compatibility = compatibility
        self.timestamp = timestamp
        self.captureStatus = captureStatus
    }

    // MARK: - Computed Properties for UI

    /// The session runtime is ready when the capture completed, KeyPath can
    /// remap keys, nothing conflicts, the bundled runtime is present, and the
    /// runtime reports it is running and responding.
    public var isReady: Bool {
        captureStatus.isComplete && permissions.isSystemReady && !conflicts.hasConflicts
            && components.requiredRuntimePayloadPresent && health.kanataRuntimeReadiness.isReady
    }

    /// Issues that prevent the system from working
    public var blockingIssues: [Issue] {
        var issues: [Issue] = []
        if let permissionIssue {
            issues.append(permissionIssue)
        }
        if !components.requiredRuntimePayloadPresent {
            issues.append(.componentMissing(name: "Bundled session runtime", autoFix: false))
        }
        if !health.kanataRuntimeReadiness.isReady {
            issues.append(.componentUnhealthy(name: "Session keyboard runtime", autoFix: true))
        }
        return issues
    }

    /// The single permission issue, if KeyPath or its runtime cannot remap keys.
    private var permissionIssue: Issue? {
        guard !permissions.isSystemReady else { return nil }
        return .permissionMissing(
            app: "KeyPath", permission: AccessibilityPermissionPresentation.current.name,
            action: permissions.blockingIssue
                ?? "Grant \(AccessibilityPermissionPresentation.current.name) first, then retry the current-process check"
        )
    }

    /// All issues including non-blocking warnings
    public var allIssues: [Issue] {
        // For now, same as blocking issues
        // Could add warnings here later
        blockingIssues
    }

    /// Age of this snapshot (for staleness detection)
    public var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    public func isStale(maxAge: TimeInterval) -> Bool {
        age > maxAge
    }

    /// Validate snapshot freshness - catches stale state bugs
    public func validate() {
        // Assertion: Catch stale state in UI
        assert(
            age < 30.0,
            "🚨 STALE STATE: Snapshot is \(String(format: "%.1f", age))s old - UI showing outdated state!"
        )

        if age > 10.0 {
            AppLogger.shared.log(
                "⚠️ [SystemSnapshot] Snapshot is \(String(format: "%.1f", age))s old - consider refreshing"
            )
        }
    }

    public static func unavailable(
        captureStatus: SystemSnapshotCaptureStatus,
        source: String,
        timestamp: Date = Date()
    ) -> SystemSnapshot {
        precondition(!captureStatus.isComplete, "Unavailable snapshot must be incomplete")
        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot(
                accessibility: .unknown,
                runtimeKeyAccess: .init(status: .unknown, source: source, confidence: .low, timestamp: timestamp),
                timestamp: timestamp
            ),
            components: .empty,
            conflicts: .empty,
            health: .empty,
            compatibility: .unknown,
            timestamp: timestamp,
            captureStatus: captureStatus
        )
    }
}

// MARK: - Component Status

public struct ComponentStatus: Sendable {
    public let kanataBinaryInstalled: Bool
    /// True when the app bundle contains the session runtime payload (the
    /// Kanata host bridge and the KeyPath executable that hosts the worker).
    /// This is intentionally separate from `kanataBinaryInstalled`.
    public let requiredRuntimePayloadPresent: Bool

    public init(kanataBinaryInstalled: Bool, requiredRuntimePayloadPresent: Bool = true) {
        self.kanataBinaryInstalled = kanataBinaryInstalled
        self.requiredRuntimePayloadPresent = requiredRuntimePayloadPresent
    }

    /// Convenience factory for empty/fallback state
    public static var empty: ComponentStatus {
        ComponentStatus(kanataBinaryInstalled: false, requiredRuntimePayloadPresent: false)
    }
}

// MARK: - Conflict Status

public struct ConflictStatus: Sendable {
    public let conflicts: [SystemConflict]
    public let canAutoResolve: Bool

    public init(conflicts: [SystemConflict], canAutoResolve: Bool) {
        self.conflicts = conflicts
        self.canAutoResolve = canAutoResolve
    }

    public var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    public var conflictCount: Int {
        conflicts.count
    }

    /// Convenience factory for empty/fallback state
    public static var empty: ConflictStatus {
        ConflictStatus(conflicts: [], canAutoResolve: false)
    }
}

// MARK: - Runtime Readiness

/// Canonical evidence that the Kanata runtime can currently remap input.
///
/// Registration and startup grace periods are deliberately not represented here:
/// they are lifecycle policy, not proof that the runtime is ready.
public struct KanataRuntimeReadiness: Sendable, Equatable {
    public let isRunning: Bool
    public let isResponding: Bool
    public let inputCaptureReady: Bool

    public init(isRunning: Bool, isResponding: Bool, inputCaptureReady: Bool = true) {
        self.isRunning = isRunning
        self.isResponding = isResponding
        self.inputCaptureReady = inputCaptureReady
    }

    public var isReady: Bool {
        isRunning && isResponding && inputCaptureReady
    }
}

// MARK: - Health Status

public struct HealthStatus: Sendable {
    /// True when current process evidence shows the Kanata runtime process
    /// exists. This must not be collapsed with TCP or input-capture readiness.
    public let kanataProcessRunning: Bool?
    /// True when the Kanata TCP health endpoint responds.
    public let kanataTCPResponding: Bool?
    public let kanataRunning: Bool
    public let kanataInputCaptureReady: Bool
    public let kanataInputCaptureIssue: String?
    public let activeRuntimePathTitle: String?
    public let activeRuntimePathDetail: String?
    /// True when the runtime reports it was rejected by macOS despite an
    /// earlier permission grant (e.g., after a rebuild/move/upgrade).
    public let kanataPermissionRejected: Bool
    /// Non-nil when the runtime reports a configuration parse error
    /// (e.g., duplicate alias, syntax error). The string is a user-facing error message.
    public let configParseError: String?

    public init(
        kanataProcessRunning: Bool? = nil,
        kanataTCPResponding: Bool? = nil,
        kanataRunning: Bool,
        kanataInputCaptureReady: Bool = true,
        kanataInputCaptureIssue: String? = nil,
        activeRuntimePathTitle: String? = nil,
        activeRuntimePathDetail: String? = nil,
        kanataPermissionRejected: Bool = false,
        configParseError: String? = nil
    ) {
        self.kanataProcessRunning = kanataProcessRunning
        self.kanataTCPResponding = kanataTCPResponding
        self.kanataRunning = kanataRunning
        self.kanataInputCaptureReady = kanataInputCaptureReady
        self.kanataInputCaptureIssue = kanataInputCaptureIssue
        self.activeRuntimePathTitle = activeRuntimePathTitle
        self.activeRuntimePathDetail = activeRuntimePathDetail
        self.kanataPermissionRejected = kanataPermissionRejected
        self.configParseError = configParseError
    }

    /// Overall health of the session runtime.
    public var isHealthy: Bool {
        kanataRuntimeReadiness.isReady
    }

    /// Project the broader system snapshot onto the canonical runtime-readiness contract.
    /// Snapshots that lack explicit process/TCP evidence fall back to `kanataRunning`.
    public var kanataRuntimeReadiness: KanataRuntimeReadiness {
        KanataRuntimeReadiness(
            isRunning: kanataProcessRunning ?? kanataRunning,
            isResponding: kanataTCPResponding ?? kanataRunning,
            inputCaptureReady: kanataInputCaptureReady
        )
    }

    /// Convenience factory for empty/fallback state
    public static var empty: HealthStatus {
        HealthStatus(kanataRunning: false)
    }
}

// MARK: - Issue Types

public enum Issue: Equatable {
    case permissionMissing(app: String, permission: String, action: String)
    case componentMissing(name: String, autoFix: Bool)
    case componentUnhealthy(name: String, autoFix: Bool)
    case conflict(SystemConflict)
    /// Kanata refuses to start because the generated config has errors.
    /// `detail` is the user-facing error message (e.g., "Duplicate alias: beh_base_;").
    case configParseError(detail: String)

    public var title: String {
        displayTitle(accessibility: .current)
    }

    public func displayTitle(accessibility: AccessibilityPermissionPresentation) -> String {
        switch self {
        case let .permissionMissing(app, permission, _):
            "\(app) needs \(accessibility.displayName(for: permission)) permission"
        case let .componentMissing(name, _):
            "\(name) not installed"
        case let .componentUnhealthy(name, _):
            "\(name) unhealthy"
        case let .conflict(conflict):
            switch conflict {
            case let .kanataProcessRunning(pid, _):
                "Conflicting Kanata process (PID \(pid))"
            case let .karabinerGrabberRunning(pid):
                "Karabiner Grabber running (PID \(pid))"
            case let .exclusiveDeviceAccess(device):
                "Device \(device) in use"
            }
        case .configParseError:
            "Configuration error prevents remapping"
        }
    }

    public var canAutoFix: Bool {
        switch self {
        case .permissionMissing:
            false // User must grant permissions
        case let .componentMissing(_, autoFix),
             let .componentUnhealthy(_, autoFix):
            autoFix
        case .conflict:
            true // Can terminate conflicting processes
        case .configParseError:
            false // Requires user decision — reset is destructive
        }
    }

    public var action: String {
        switch self {
        case let .permissionMissing(_, _, action):
            action
        case .componentMissing:
            "Install via wizard"
        case .componentUnhealthy:
            "Restart component"
        case .conflict:
            "Terminate conflicting process"
        case .configParseError:
            "Reset to default config"
        }
    }
}

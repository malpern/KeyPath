import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions

/// Complete snapshot of system state at a point in time
/// This is a pure data structure with no side effects - just state and computed properties
public struct SystemSnapshot: Sendable {
    public let permissions: PermissionOracle.Snapshot
    public let components: ComponentStatus
    public let conflicts: ConflictStatus
    public let health: HealthStatus
    public let helper: HelperStatus
    public let timestamp: Date

    public init(
        permissions: PermissionOracle.Snapshot,
        components: ComponentStatus,
        conflicts: ConflictStatus,
        health: HealthStatus,
        helper: HelperStatus,
        timestamp: Date
    ) {
        self.permissions = permissions
        self.components = components
        self.conflicts = conflicts
        self.health = health
        self.helper = helper
        self.timestamp = timestamp
    }

    // MARK: - Computed Properties for UI

    /// System is ready when all critical components are operational
    public var isReady: Bool {
        helper.isReady && permissions.isSystemReady && !conflicts.hasConflicts
            && components.hasAllRequired && health.isHealthy
    }

    /// Issues that prevent the system from working
    public var blockingIssues: [Issue] {
        var issues: [Issue] = []

        // Helper issues (check first - required for system operations)
        if !helper.isInstalled {
            issues.append(.componentMissing(name: "Privileged Helper", autoFix: true))
        } else if !helper.isWorking {
            issues.append(.componentUnhealthy(name: "Privileged Helper", autoFix: true))
        }

        // Permission issues
        if !permissions.keyPath.hasAllPermissions {
            if !permissions.keyPath.accessibility.isReady {
                issues.append(
                    .permissionMissing(
                        app: "KeyPath",
                        permission: "Accessibility",
                        action: "Enable in System Settings > Privacy & Security > Accessibility"
                    )
                )
            }
            if !permissions.keyPath.inputMonitoring.isReady {
                issues.append(
                    .permissionMissing(
                        app: "KeyPath",
                        permission: "Input Monitoring",
                        action: "Enable in System Settings > Privacy & Security > Input Monitoring"
                    )
                )
            }
        }

        if !permissions.kanata.hasAllPermissions {
            if !permissions.kanata.accessibility.isReady {
                issues.append(
                    .permissionMissing(
                        app: "Kanata",
                        permission: "Accessibility",
                        action: "Grant permission via Installation Wizard"
                    )
                )
            }
            if !permissions.kanata.inputMonitoring.isReady {
                issues.append(
                    .permissionMissing(
                        app: "Kanata",
                        permission: "Input Monitoring",
                        action: "Grant permission via Installation Wizard"
                    )
                )
            }
        }
        if !health.kanataInputCaptureReady {
            issues.append(
                .permissionMissing(
                    app: "Kanata",
                    permission: "Input Monitoring",
                    action:
                    "Regrant Input Monitoring permission for Kanata in System Settings and ensure it can open the built-in keyboard"
                )
            )
        }

        // Conflict issues
        for conflict in conflicts.conflicts {
            issues.append(.conflict(conflict))
        }

        // Component issues
        if !components.kanataBinaryInstalled {
            issues.append(.componentMissing(name: "Kanata binary", autoFix: true))
        }
        if !components.karabinerDriverInstalled {
            issues.append(.componentMissing(name: "Karabiner driver", autoFix: true))
        }
        // ⭐ Check version mismatch BEFORE health check (mismatch causes health issues)
        if components.vhidVersionMismatch {
            issues.append(.componentVersionMismatch(name: "Karabiner driver", autoFix: true))
        }
        if !components.vhidDeviceHealthy {
            issues.append(.componentUnhealthy(name: "VirtualHID Device", autoFix: true))
        }

        // Health issues
        if !health.isHealthy {
            if !health.kanataRunning, let configError = health.configParseError {
                issues.append(.configParseError(detail: configError))
            } else if !health.kanataRunning, health.kanataPermissionRejected {
                issues.append(
                    .permissionMissing(
                        app: "Kanata",
                        permission: "Accessibility",
                        action: "Re-grant Accessibility permission after rebuild — remove and re-add Kanata Engine in System Settings"
                    )
                )
            } else if !health.kanataRunning {
                issues.append(.serviceNotRunning(name: "Kanata Service", autoFix: true))
            }
            if !health.karabinerDaemonRunning {
                issues.append(.serviceNotRunning(name: "Karabiner Daemon", autoFix: true))
            }
        }

        return issues
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
}

// MARK: - Component Status

public struct ComponentStatus: Sendable {
    public let kanataBinaryInstalled: Bool
    public let karabinerDriverInstalled: Bool
    public let karabinerDaemonRunning: Bool
    public let vhidDeviceInstalled: Bool
    public let vhidDeviceHealthy: Bool
    /// VHID services health (daemon + manager) independent of Kanata service
    /// Use for Karabiner Components page which should only care about VHID, not Kanata
    public let vhidServicesHealthy: Bool
    /// True when the installed VHID daemon plist exists but predates the
    /// MAL-57 fix (wrong program path or missing ProcessType=Interactive).
    /// The daemon may be running fine, but it is vulnerable to starvation
    /// under CPU load and the plist should be rewritten via repair.
    public let vhidDaemonPlistMisconfigured: Bool
    public let vhidVersionMismatch: Bool

    public init(
        kanataBinaryInstalled: Bool,
        karabinerDriverInstalled: Bool,
        karabinerDaemonRunning: Bool,
        vhidDeviceInstalled: Bool,
        vhidDeviceHealthy: Bool,
        vhidServicesHealthy: Bool,
        vhidDaemonPlistMisconfigured: Bool = false,
        vhidVersionMismatch: Bool
    ) {
        self.kanataBinaryInstalled = kanataBinaryInstalled
        self.karabinerDriverInstalled = karabinerDriverInstalled
        self.karabinerDaemonRunning = karabinerDaemonRunning
        self.vhidDeviceInstalled = vhidDeviceInstalled
        self.vhidDeviceHealthy = vhidDeviceHealthy
        self.vhidServicesHealthy = vhidServicesHealthy
        self.vhidDaemonPlistMisconfigured = vhidDaemonPlistMisconfigured
        self.vhidVersionMismatch = vhidVersionMismatch
    }

    /// Required components for the normal split-runtime architecture.
    /// Deliberately excludes `vhidDaemonPlistMisconfigured`: a stale plist
    /// still runs day-to-day, so it surfaces as a repairable wizard issue
    /// rather than a missing component that would fail readiness app-wide.
    public var hasAllRequired: Bool {
        kanataBinaryInstalled && karabinerDriverInstalled && karabinerDaemonRunning && vhidDeviceHealthy
            && vhidServicesHealthy && !vhidVersionMismatch
    }

    /// The VHID runtime services need (re)installation: either they are
    /// unhealthy, or the installed daemon plist predates the MAL-57 fix and
    /// must be rewritten. Single source for the installRequiredRuntimeServices
    /// trigger so repair and install plans cannot drift apart.
    public var vhidRuntimeServicesNeedRepair: Bool {
        !vhidServicesHealthy || vhidDaemonPlistMisconfigured
    }

    /// Convenience factory for empty/fallback state
    public static var empty: ComponentStatus {
        ComponentStatus(
            kanataBinaryInstalled: false,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: false,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: false,
            vhidVersionMismatch: false
        )
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

// MARK: - Health Status

public struct HealthStatus: Sendable {
    /// True when launchd can find/load the Kanata job. This is distinct from
    /// the runtime being usable: launchd can know about a job whose process is
    /// stopped or whose TCP server is not responding.
    public let kanataLaunchdLoaded: Bool?
    /// True when current process evidence shows the Kanata runtime process
    /// exists. This must not be collapsed with TCP or input-capture readiness.
    public let kanataProcessRunning: Bool?
    /// True when the Kanata TCP health endpoint responds.
    public let kanataTCPResponding: Bool?
    public let kanataRunning: Bool
    public let karabinerDaemonRunning: Bool
    public let vhidHealthy: Bool
    public let kanataInputCaptureReady: Bool
    public let kanataInputCaptureIssue: String?
    public let activeRuntimePathTitle: String?
    public let activeRuntimePathDetail: String?
    /// True when the daemon stderr log shows kanata was rejected by macOS
    /// at runtime despite the TCC database reporting permissions as granted
    /// (stale grant after a rebuild/move/upgrade).
    public let kanataPermissionRejected: Bool
    /// Non-nil when kanata's stderr contains a configuration parse error
    /// (e.g., duplicate alias, syntax error). This causes kanata to exit
    /// immediately and crash-loop. The string is a user-facing error message.
    public let configParseError: String?
    /// True when SMAppService reports enabled but launchd/runtime evidence
    /// cannot prove the submitted job exists or can load.
    public let staleEnabledRegistration: Bool

    public init(
        kanataLaunchdLoaded: Bool? = nil,
        kanataProcessRunning: Bool? = nil,
        kanataTCPResponding: Bool? = nil,
        kanataRunning: Bool,
        karabinerDaemonRunning: Bool,
        vhidHealthy: Bool,
        kanataInputCaptureReady: Bool = true,
        kanataInputCaptureIssue: String? = nil,
        activeRuntimePathTitle: String? = nil,
        activeRuntimePathDetail: String? = nil,
        kanataPermissionRejected: Bool = false,
        configParseError: String? = nil,
        staleEnabledRegistration: Bool = false
    ) {
        self.kanataLaunchdLoaded = kanataLaunchdLoaded
        self.kanataProcessRunning = kanataProcessRunning
        self.kanataTCPResponding = kanataTCPResponding
        self.kanataRunning = kanataRunning
        self.karabinerDaemonRunning = karabinerDaemonRunning
        self.vhidHealthy = vhidHealthy
        self.kanataInputCaptureReady = kanataInputCaptureReady
        self.kanataInputCaptureIssue = kanataInputCaptureIssue
        self.activeRuntimePathTitle = activeRuntimePathTitle
        self.activeRuntimePathDetail = activeRuntimePathDetail
        self.kanataPermissionRejected = kanataPermissionRejected
        self.configParseError = configParseError
        self.staleEnabledRegistration = staleEnabledRegistration
    }

    /// Overall health (includes Kanata runtime)
    public var isHealthy: Bool {
        kanataRunning && karabinerDaemonRunning && vhidHealthy && kanataInputCaptureReady
    }

    /// Health of background services only (Karabiner daemon + VHID driver)
    public var backgroundServicesHealthy: Bool {
        karabinerDaemonRunning && vhidHealthy
    }

    /// Convenience factory for empty/fallback state
    public static var empty: HealthStatus {
        HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: false)
    }
}

// MARK: - Helper Status

public struct HelperStatus: Sendable {
    public let isInstalled: Bool
    public let version: String?
    public let isWorking: Bool

    public init(isInstalled: Bool, version: String?, isWorking: Bool) {
        self.isInstalled = isInstalled
        self.version = version
        self.isWorking = isWorking
    }

    public var isReady: Bool {
        isInstalled && isWorking
    }

    public var displayVersion: String {
        version ?? "Unknown"
    }

    /// Convenience factory for empty/fallback state
    public static var empty: HelperStatus {
        HelperStatus(isInstalled: false, version: nil, isWorking: false)
    }
}

// MARK: - Issue Types

public enum Issue: Equatable {
    case permissionMissing(app: String, permission: String, action: String)
    case componentMissing(name: String, autoFix: Bool)
    case componentUnhealthy(name: String, autoFix: Bool)
    case componentVersionMismatch(name: String, autoFix: Bool)
    case serviceNotRunning(name: String, autoFix: Bool)
    case conflict(SystemConflict)
    /// Kanata refuses to start because the generated config has errors.
    /// `detail` is the user-facing error message (e.g., "Duplicate alias: beh_base_;").
    case configParseError(detail: String)

    public var title: String {
        switch self {
        case let .permissionMissing(app, permission, _):
            "\(app) needs \(permission) permission"
        case let .componentMissing(name, _):
            "\(name) not installed"
        case let .componentUnhealthy(name, _):
            "\(name) unhealthy"
        case let .componentVersionMismatch(name, _):
            "\(name) version incompatible"
        case let .serviceNotRunning(name, _):
            "\(name) not running"
        case let .conflict(conflict):
            switch conflict {
            case let .kanataProcessRunning(pid, _):
                "Conflicting Kanata process (PID \(pid))"
            case let .karabinerGrabberRunning(pid):
                "Karabiner Grabber running (PID \(pid))"
            case let .karabinerVirtualHIDDeviceRunning(pid, _):
                "Karabiner VirtualHID running (PID \(pid))"
            case let .karabinerVirtualHIDDaemonRunning(pid):
                "Karabiner VirtualHID Daemon running (PID \(pid))"
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
             let .componentUnhealthy(_, autoFix),
             let .componentVersionMismatch(_, autoFix),
             let .serviceNotRunning(_, autoFix):
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
        case .componentVersionMismatch:
            "Install correct version"
        case .serviceNotRunning:
            "Start service"
        case .conflict:
            "Terminate conflicting process"
        case .configParseError:
            "Reset to default config"
        }
    }
}

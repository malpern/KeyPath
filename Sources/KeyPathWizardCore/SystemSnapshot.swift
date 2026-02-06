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
            if !health.kanataRunning {
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
    public let launchDaemonServicesHealthy: Bool
    /// VHID services health (daemon + manager) independent of Kanata service
    /// Use for Karabiner Components page which should only care about VHID, not Kanata
    public let vhidServicesHealthy: Bool
    public let vhidVersionMismatch: Bool

    public init(
        kanataBinaryInstalled: Bool,
        karabinerDriverInstalled: Bool,
        karabinerDaemonRunning: Bool,
        vhidDeviceInstalled: Bool,
        vhidDeviceHealthy: Bool,
        launchDaemonServicesHealthy: Bool,
        vhidServicesHealthy: Bool,
        vhidVersionMismatch: Bool
    ) {
        self.kanataBinaryInstalled = kanataBinaryInstalled
        self.karabinerDriverInstalled = karabinerDriverInstalled
        self.karabinerDaemonRunning = karabinerDaemonRunning
        self.vhidDeviceInstalled = vhidDeviceInstalled
        self.vhidDeviceHealthy = vhidDeviceHealthy
        self.launchDaemonServicesHealthy = launchDaemonServicesHealthy
        self.vhidServicesHealthy = vhidServicesHealthy
        self.vhidVersionMismatch = vhidVersionMismatch
    }

    public var hasAllRequired: Bool {
        kanataBinaryInstalled && karabinerDriverInstalled && karabinerDaemonRunning && vhidDeviceHealthy
            && launchDaemonServicesHealthy && !vhidVersionMismatch
    }

    /// Convenience factory for empty/fallback state
    public static var empty: ComponentStatus {
        ComponentStatus(
            kanataBinaryInstalled: false,
            karabinerDriverInstalled: false,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: false,
            vhidDeviceHealthy: false,
            launchDaemonServicesHealthy: false,
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
    public let kanataRunning: Bool
    public let karabinerDaemonRunning: Bool
    public let vhidHealthy: Bool

    public init(kanataRunning: Bool, karabinerDaemonRunning: Bool, vhidHealthy: Bool) {
        self.kanataRunning = kanataRunning
        self.karabinerDaemonRunning = karabinerDaemonRunning
        self.vhidHealthy = vhidHealthy
    }

    /// Overall health (includes Kanata runtime)
    public var isHealthy: Bool {
        kanataRunning && karabinerDaemonRunning && vhidHealthy
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
        }
    }
}

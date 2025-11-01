import Foundation

/// Complete snapshot of system state at a point in time
/// This is a pure data structure with no side effects - just state and computed properties
struct SystemSnapshot {
    let permissions: PermissionOracle.Snapshot
    let components: ComponentStatus
    let conflicts: ConflictStatus
    let health: HealthStatus
    let helper: HelperStatus
    let timestamp: Date

    // MARK: - Computed Properties for UI

    /// System is ready when all critical components are operational
    var isReady: Bool {
        helper.isReady &&
            permissions.isSystemReady &&
            !conflicts.hasConflicts &&
            components.hasAllRequired &&
            health.isHealthy
    }

    /// Issues that prevent the system from working
    var blockingIssues: [Issue] {
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
                issues.append(.permissionMissing(
                    app: "KeyPath",
                    permission: "Accessibility",
                    action: "Enable in System Settings > Privacy & Security > Accessibility"
                ))
            }
            if !permissions.keyPath.inputMonitoring.isReady {
                issues.append(.permissionMissing(
                    app: "KeyPath",
                    permission: "Input Monitoring",
                    action: "Enable in System Settings > Privacy & Security > Input Monitoring"
                ))
            }
        }

        if !permissions.kanata.hasAllPermissions {
            if !permissions.kanata.accessibility.isReady {
                issues.append(.permissionMissing(
                    app: "Kanata",
                    permission: "Accessibility",
                    action: "Grant permission via Installation Wizard"
                ))
            }
            if !permissions.kanata.inputMonitoring.isReady {
                issues.append(.permissionMissing(
                    app: "Kanata",
                    permission: "Input Monitoring",
                    action: "Grant permission via Installation Wizard"
                ))
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
            if !health.karabinerDaemonRunning {
                issues.append(.serviceNotRunning(name: "Karabiner Daemon", autoFix: true))
            }
        }

        return issues
    }

    /// All issues including non-blocking warnings
    var allIssues: [Issue] {
        // For now, same as blocking issues
        // Could add warnings here later
        blockingIssues
    }

    /// Age of this snapshot (for staleness detection)
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    /// Validate snapshot freshness - catches stale state bugs
    func validate() {
        // Assertion: Catch stale state in UI
        assert(age < 30.0, "🚨 STALE STATE: Snapshot is \(String(format: "%.1f", age))s old - UI showing outdated state!")

        if age > 10.0 {
            AppLogger.shared.log("⚠️ [SystemSnapshot] Snapshot is \(String(format: "%.1f", age))s old - consider refreshing")
        }
    }
}

// MARK: - Component Status

struct ComponentStatus {
    let kanataBinaryInstalled: Bool
    let karabinerDriverInstalled: Bool
    let karabinerDaemonRunning: Bool
    let vhidDeviceInstalled: Bool
    let vhidDeviceHealthy: Bool
    let launchDaemonServicesHealthy: Bool
    let vhidVersionMismatch: Bool

    var hasAllRequired: Bool {
        kanataBinaryInstalled &&
            karabinerDriverInstalled &&
            karabinerDaemonRunning &&
            vhidDeviceHealthy &&
            launchDaemonServicesHealthy &&
            !vhidVersionMismatch // Version must match (false means no mismatch)
    }
}

// MARK: - Conflict Status

struct ConflictStatus {
    let conflicts: [SystemConflict]
    let canAutoResolve: Bool

    var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    var conflictCount: Int {
        conflicts.count
    }
}

// MARK: - Health Status

struct HealthStatus {
    let kanataRunning: Bool
    let karabinerDaemonRunning: Bool
    let vhidHealthy: Bool

    var isHealthy: Bool {
        kanataRunning && karabinerDaemonRunning && vhidHealthy
    }
}

// MARK: - Helper Status

struct HelperStatus {
    let isInstalled: Bool
    let version: String?
    let isWorking: Bool

    var isReady: Bool {
        isInstalled && isWorking
    }

    var displayVersion: String {
        version ?? "Unknown"
    }
}

// MARK: - Issue Types

enum Issue: Equatable {
    case permissionMissing(app: String, permission: String, action: String)
    case componentMissing(name: String, autoFix: Bool)
    case componentUnhealthy(name: String, autoFix: Bool)
    case componentVersionMismatch(name: String, autoFix: Bool)
    case serviceNotRunning(name: String, autoFix: Bool)
    case conflict(SystemConflict)

    var title: String {
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

    var canAutoFix: Bool {
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

    var action: String {
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

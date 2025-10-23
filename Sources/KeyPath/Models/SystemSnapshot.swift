import Foundation

/// Complete snapshot of system state at a point in time
/// This is a pure data structure with no side effects - just state and computed properties
struct SystemSnapshot {
    let permissions: PermissionOracle.Snapshot
    let components: ComponentStatus
    let conflicts: ConflictStatus
    let health: HealthStatus
    let timestamp: Date

    // MARK: - Computed Properties for UI

    /// System is ready when all critical components are operational
    var isReady: Bool {
        permissions.isSystemReady &&
        !conflicts.hasConflicts &&
        components.hasAllRequired &&
        health.isHealthy
    }

    /// Issues that prevent the system from working
    var blockingIssues: [Issue] {
        var issues: [Issue] = []

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
        !vhidVersionMismatch  // Version must match (false means no mismatch)
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
            return "\(app) needs \(permission) permission"
        case let .componentMissing(name, _):
            return "\(name) not installed"
        case let .componentUnhealthy(name, _):
            return "\(name) unhealthy"
        case let .componentVersionMismatch(name, _):
            return "\(name) version incompatible"
        case let .serviceNotRunning(name, _):
            return "\(name) not running"
        case .conflict(let conflict):
            switch conflict {
            case .kanataProcessRunning(let pid, _):
                return "Conflicting Kanata process (PID \(pid))"
            case .karabinerGrabberRunning(let pid):
                return "Karabiner Grabber running (PID \(pid))"
            case .karabinerVirtualHIDDeviceRunning(let pid, _):
                return "Karabiner VirtualHID running (PID \(pid))"
            case .karabinerVirtualHIDDaemonRunning(let pid):
                return "Karabiner VirtualHID Daemon running (PID \(pid))"
            case .exclusiveDeviceAccess(let device):
                return "Device \(device) in use"
            }
        }
    }

    var canAutoFix: Bool {
        switch self {
        case .permissionMissing:
            return false // User must grant permissions
        case let .componentMissing(_, autoFix),
             let .componentUnhealthy(_, autoFix),
             let .componentVersionMismatch(_, autoFix),
             let .serviceNotRunning(_, autoFix):
            return autoFix
        case .conflict:
            return true // Can terminate conflicting processes
        }
    }

    var action: String {
        switch self {
        case let .permissionMissing(_, _, action):
            return action
        case .componentMissing:
            return "Install via wizard"
        case .componentUnhealthy:
            return "Restart component"
        case .componentVersionMismatch:
            return "Install correct version"
        case .serviceNotRunning:
            return "Start service"
        case .conflict:
            return "Terminate conflicting process"
        }
    }
}
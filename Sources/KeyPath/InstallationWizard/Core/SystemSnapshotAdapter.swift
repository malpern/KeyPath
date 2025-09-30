import Foundation

/// Adapter to convert SystemSnapshot (new) to SystemStateResult (old wizard format)
/// This allows testing the new SystemValidator in the existing wizard without rewriting all pages
@MainActor
struct SystemSnapshotAdapter {

    /// Convert SystemSnapshot to SystemStateResult for backward compatibility
    static func adapt(_ snapshot: SystemSnapshot) -> SystemStateResult {
        // Convert to wizard system state
        let wizardState = adaptSystemState(snapshot)

        // Convert issues
        let wizardIssues = adaptIssues(snapshot)

        // Determine auto-fix actions
        let autoFixActions = determineAutoFixActions(snapshot)

        return SystemStateResult(
            state: wizardState,
            issues: wizardIssues,
            autoFixActions: autoFixActions,
            detectionTimestamp: snapshot.timestamp
        )
    }

    private static func adaptSystemState(_ snapshot: SystemSnapshot) -> WizardSystemState {
        // If conflicts exist, that's highest priority
        if snapshot.conflicts.hasConflicts {
            return .conflictsDetected(conflicts: snapshot.conflicts.conflicts)
        }

        // Check permissions
        let missingPerms = getMissingPermissions(snapshot)
        if !missingPerms.isEmpty {
            return .missingPermissions(missing: missingPerms)
        }

        // Check components
        let missingComponents = getMissingComponents(snapshot)
        if !missingComponents.isEmpty {
            return .missingComponents(missing: missingComponents)
        }

        // Check health
        if !snapshot.health.karabinerDaemonRunning {
            return .daemonNotRunning
        }

        if !snapshot.health.kanataRunning {
            return .serviceNotRunning
        }

        // System is ready
        if snapshot.health.kanataRunning {
            return .active
        }

        return .ready
    }

    private static func getMissingPermissions(_ snapshot: SystemSnapshot) -> [PermissionRequirement] {
        var missing: [PermissionRequirement] = []

        // KeyPath permissions
        if !snapshot.permissions.keyPath.inputMonitoring.isReady {
            missing.append(.keyPathInputMonitoring)
        }
        if !snapshot.permissions.keyPath.accessibility.isReady {
            missing.append(.keyPathAccessibility)
        }

        // Kanata permissions
        if !snapshot.permissions.kanata.inputMonitoring.isReady {
            missing.append(.kanataInputMonitoring)
        }
        if !snapshot.permissions.kanata.accessibility.isReady {
            missing.append(.kanataAccessibility)
        }

        return missing
    }

    private static func getMissingComponents(_ snapshot: SystemSnapshot) -> [ComponentRequirement] {
        var missing: [ComponentRequirement] = []

        if !snapshot.components.kanataBinaryInstalled {
            missing.append(.kanataBinaryMissing)
        }
        if !snapshot.components.karabinerDriverInstalled {
            missing.append(.karabinerDriver)
        }
        if !snapshot.components.karabinerDaemonRunning {
            missing.append(.karabinerDaemon)
        }
        if !snapshot.components.vhidDeviceHealthy {
            missing.append(.vhidDeviceRunning)
        }
        if !snapshot.components.launchDaemonServicesHealthy {
            missing.append(.launchDaemonServices)
        }

        return missing
    }

    private static func adaptIssues(_ snapshot: SystemSnapshot) -> [WizardIssue] {
        snapshot.blockingIssues.map { issue in
            switch issue {
            case let .permissionMissing(app, permission, action):
                let req: PermissionRequirement = {
                    if app == "KeyPath" && permission == "Input Monitoring" {
                        return .keyPathInputMonitoring
                    } else if app == "KeyPath" && permission == "Accessibility" {
                        return .keyPathAccessibility
                    } else if app == "Kanata" && permission == "Input Monitoring" {
                        return .kanataInputMonitoring
                    } else {
                        return .kanataAccessibility
                    }
                }()

                return WizardIssue(
                    identifier: .permission(req),
                    severity: .error,
                    category: .permissions,
                    title: issue.title,
                    description: action,
                    autoFixAction: nil,
                    userAction: action
                )

            case let .componentMissing(name, autoFix):
                let comp: ComponentRequirement = {
                    if name.contains("Kanata") {
                        return .kanataBinaryMissing
                    } else if name.contains("Karabiner driver") {
                        return .karabinerDriver
                    } else {
                        return .vhidDeviceRunning
                    }
                }()

                return WizardIssue(
                    identifier: .component(comp),
                    severity: .error,
                    category: .installation,
                    title: issue.title,
                    description: "Install \(name)",
                    autoFixAction: autoFix ? .installMissingComponents : nil,
                    userAction: "Install via wizard"
                )

            case let .componentUnhealthy(name, autoFix):
                return WizardIssue(
                    identifier: .component(.vhidDeviceRunning),
                    severity: .error,
                    category: .installation,
                    title: issue.title,
                    description: "Restart \(name)",
                    autoFixAction: autoFix ? .startKarabinerDaemon : nil,
                    userAction: "Restart component"
                )

            case let .serviceNotRunning(name, autoFix):
                return WizardIssue(
                    identifier: .daemon,
                    severity: .error,
                    category: .daemon,
                    title: issue.title,
                    description: "Start \(name)",
                    autoFixAction: autoFix ? .startKarabinerDaemon : nil,
                    userAction: "Start service"
                )

            case let .conflict(systemConflict):
                return WizardIssue(
                    identifier: .conflict(systemConflict),
                    severity: .error,
                    category: .conflicts,
                    title: issue.title,
                    description: "Terminate conflicting process",
                    autoFixAction: .terminateConflictingProcesses,
                    userAction: "Terminate process"
                )
            }
        }
    }

    private static func determineAutoFixActions(_ snapshot: SystemSnapshot) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        if snapshot.conflicts.hasConflicts, snapshot.conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        let missingComponents = getMissingComponents(snapshot)
        if !missingComponents.isEmpty {
            if missingComponents.contains(.kanataBinaryMissing) {
                actions.append(.installBundledKanata)
            }
            actions.append(.installMissingComponents)
        }

        if !snapshot.health.karabinerDaemonRunning {
            actions.append(.startKarabinerDaemon)
        }

        return actions
    }
}
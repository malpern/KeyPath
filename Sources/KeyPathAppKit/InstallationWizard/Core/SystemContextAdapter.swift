import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Adapter to convert SystemContext (InstallerEngine façade) to SystemStateResult (old wizard format)
/// This allows the GUI to use InstallerEngine.inspectSystem() while maintaining backward compatibility
@MainActor
struct SystemContextAdapter {
    /// Convert SystemContext to SystemStateResult for backward compatibility
    static func adapt(_ context: SystemContext) -> SystemStateResult {
        // Convert to wizard system state
        let wizardState = adaptSystemState(context)

        // Convert issues
        let wizardIssues = adaptIssues(context)

        // Determine auto-fix actions (reuse InstallerEngine logic)
        let autoFixActions = determineAutoFixActions(context)

        return SystemStateResult(
            state: wizardState,
            issues: wizardIssues,
            autoFixActions: autoFixActions,
            detectionTimestamp: context.timestamp
        )
    }

    private static func adaptSystemState(_ context: SystemContext) -> WizardSystemState {
        AppLogger.shared.log("📊 [SystemContextAdapter] === ADAPTER STATE DETERMINATION ===")

        // 1. If conflicts exist, that's highest priority
        if context.conflicts.hasConflicts {
            AppLogger.shared.log("📊 [SystemContextAdapter] Decision: CONFLICTS DETECTED")
            return .conflictsDetected(conflicts: context.conflicts.conflicts)
        }

        // 2. Check if Kanata is running FIRST
        if context.services.kanataRunning {
            AppLogger.shared.log("📊 [SystemContextAdapter] Decision: ACTIVE (kanata running)")
            return .active
        }

        AppLogger.shared.log("📊 [SystemContextAdapter] Kanata NOT running, checking prerequisites...")

        // 3. Check permissions if kanata is NOT running
        let missingPerms = getMissingPermissions(context)
        if !missingPerms.isEmpty {
            AppLogger.shared.log(
                "📊 [SystemContextAdapter] Decision: MISSING PERMISSIONS (\(missingPerms.count) missing)")
            return .missingPermissions(missing: missingPerms)
        }

        // 4. Check components
        let missingComponents = getMissingComponents(context)
        if !missingComponents.isEmpty {
            AppLogger.shared.log(
                "📊 [SystemContextAdapter] Decision: MISSING COMPONENTS (\(missingComponents.count) missing)"
            )
            return .missingComponents(missing: missingComponents)
        }

        // 5. Check daemon health
        if !context.services.karabinerDaemonRunning {
            AppLogger.shared.log("📊 [SystemContextAdapter] Decision: DAEMON NOT RUNNING")
            return .daemonNotRunning
        }

        // 6. All components ready but kanata not running
        AppLogger.shared.log("📊 [SystemContextAdapter] Decision: SERVICE NOT RUNNING")
        return .serviceNotRunning
    }

    private static func getMissingPermissions(_ context: SystemContext) -> [PermissionRequirement] {
        var missing: [PermissionRequirement] = []

        // KeyPath permissions (use isBlocking)
        if context.permissions.keyPath.inputMonitoring.isBlocking {
            missing.append(.keyPathInputMonitoring)
        }
        if context.permissions.keyPath.accessibility.isBlocking {
            missing.append(.keyPathAccessibility)
        }

        // Kanata permissions (use isBlocking)
        if context.permissions.kanata.inputMonitoring.isBlocking {
            missing.append(.kanataInputMonitoring)
        }
        if context.permissions.kanata.accessibility.isBlocking {
            missing.append(.kanataAccessibility)
        }

        return missing
    }

    private static func getMissingComponents(_ context: SystemContext) -> [ComponentRequirement] {
        var missing: [ComponentRequirement] = []

        if !context.components.kanataBinaryInstalled {
            missing.append(.kanataBinaryMissing)
        }
        if !context.components.karabinerDriverInstalled {
            missing.append(.karabinerDriver)
        }
        if !context.components.karabinerDaemonRunning {
            missing.append(.karabinerDaemon)
        }
        if context.components.vhidVersionMismatch {
            missing.append(.vhidDriverVersionMismatch)
        }
        if !context.components.vhidDeviceHealthy {
            missing.append(.vhidDeviceRunning)
        }
        if !context.components.launchDaemonServicesHealthy {
            missing.append(.launchDaemonServices)
        }

        return missing
    }

    private static func adaptIssues(_ context: SystemContext) -> [WizardIssue] {
        var issues: [WizardIssue] = []

        // Permission issues
        if context.permissions.keyPath.inputMonitoring.isBlocking {
            issues.append(
                WizardIssue(
                    identifier: .permission(.keyPathInputMonitoring),
                    severity: .error,
                    category: .installation,
                    title: "Input Monitoring Permission Required",
                    description: "KeyPath needs Input Monitoring permission to function",
                    autoFixAction: nil,
                    userAction: "Grant Input Monitoring permission in System Settings"
                ))
        }
        if context.permissions.keyPath.accessibility.isBlocking {
            issues.append(
                WizardIssue(
                    identifier: .permission(.keyPathAccessibility),
                    severity: .error,
                    category: .installation,
                    title: "Accessibility Permission Required",
                    description: "KeyPath needs Accessibility permission to function",
                    autoFixAction: nil,
                    userAction: "Grant Accessibility permission in System Settings"
                ))
        }
        if context.permissions.kanata.inputMonitoring.isBlocking {
            issues.append(
                WizardIssue(
                    identifier: .permission(.kanataInputMonitoring),
                    severity: .error,
                    category: .installation,
                    title: "Kanata Input Monitoring Permission Required",
                    description: "Kanata needs Input Monitoring permission",
                    autoFixAction: nil,
                    userAction: "Grant Input Monitoring permission to Kanata in System Settings"
                ))
        }
        if context.permissions.kanata.accessibility.isBlocking {
            issues.append(
                WizardIssue(
                    identifier: .permission(.kanataAccessibility),
                    severity: .error,
                    category: .installation,
                    title: "Kanata Accessibility Permission Required",
                    description: "Kanata needs Accessibility permission",
                    autoFixAction: nil,
                    userAction: "Grant Accessibility permission to Kanata in System Settings"
                ))
        }

        // Component issues
        if !context.components.kanataBinaryInstalled {
            issues.append(
                WizardIssue(
                    identifier: .component(.kanataBinaryMissing),
                    severity: .error,
                    category: .installation,
                    title: "Kanata Binary Missing",
                    description: "Kanata binary is not installed",
                    autoFixAction: .installBundledKanata,
                    userAction: nil
                ))
        }
        if !context.components.karabinerDriverInstalled {
            issues.append(
                WizardIssue(
                    identifier: .component(.karabinerDriver),
                    severity: .error,
                    category: .installation,
                    title: "Karabiner Driver Missing",
                    description: "Karabiner VirtualHID driver is not installed",
                    autoFixAction: .installMissingComponents,
                    userAction: nil
                ))
        }
        if context.components.vhidVersionMismatch {
            issues.append(
                WizardIssue(
                    identifier: .component(.vhidDriverVersionMismatch),
                    severity: .error,
                    category: .installation,
                    title: "Driver Version Mismatch",
                    description: "Karabiner VirtualHID driver version mismatch",
                    autoFixAction: .fixDriverVersionMismatch,
                    userAction: nil
                ))
        }
        if !context.components.vhidDeviceHealthy {
            issues.append(
                WizardIssue(
                    identifier: .component(.vhidDeviceRunning),
                    severity: .error,
                    category: .installation,
                    title: "VirtualHID Device Unhealthy",
                    description: "Karabiner VirtualHID device is not healthy",
                    autoFixAction: .restartVirtualHIDDaemon,
                    userAction: nil
                ))
        }
        if !context.components.launchDaemonServicesHealthy {
            issues.append(
                WizardIssue(
                    identifier: .component(.launchDaemonServices),
                    severity: .error,
                    category: .installation,
                    title: "LaunchDaemon Services Unhealthy",
                    description: "LaunchDaemon services are not healthy",
                    autoFixAction: .installLaunchDaemonServices,
                    userAction: nil
                ))
        }

        // Conflict issues
        if context.conflicts.hasConflicts {
            for conflict in context.conflicts.conflicts {
                issues.append(
                    WizardIssue(
                        identifier: .conflict(conflict),
                        severity: .error,
                        category: .conflicts,
                        title: "Process Conflict",
                        description: "Terminate conflicting process",
                        autoFixAction: context.conflicts.canAutoResolve ? .terminateConflictingProcesses : nil,
                        userAction: "Terminate process"
                    ))
            }
        }

        // Service issues
        if !context.services.karabinerDaemonRunning {
            issues.append(
                WizardIssue(
                    identifier: .component(.karabinerDaemon),
                    severity: .error,
                    category: .daemon,
                    title: "Karabiner Daemon Not Running",
                    description: "Karabiner daemon is not running",
                    autoFixAction: .startKarabinerDaemon,
                    userAction: nil
                ))
        }
        // Background services should only depend on Karabiner daemon + VHID, not Kanata runtime
        if !context.services.backgroundServicesHealthy {
            issues.append(
                WizardIssue(
                    identifier: .component(.launchDaemonServices),
                    severity: .warning,
                    category: .backgroundServices,
                    title: "Services Unhealthy",
                    description: "Some services are not healthy",
                    autoFixAction: .restartUnhealthyServices,
                    userAction: nil
                ))
        }

        // Helper issues
        if !context.helper.isReady {
            issues.append(
                WizardIssue(
                    identifier: .component(
                        context.helper.isInstalled ? .privilegedHelperUnhealthy : .privilegedHelper),
                    severity: .error,
                    category: .backgroundServices,
                    title: "Privileged Helper Not Ready",
                    description: "Privileged helper is not installed or not working",
                    autoFixAction: context.helper.isInstalled
                        ? .reinstallPrivilegedHelper : .installPrivilegedHelper,
                    userAction: nil
                ))
        }

        return issues
    }

    private static func determineAutoFixActions(_ context: SystemContext) -> [AutoFixAction] {
        // Use shared ActionDeterminer for repair actions (SystemContextAdapter is used for repair scenarios)
        ActionDeterminer.determineRepairActions(context: context)
    }
}

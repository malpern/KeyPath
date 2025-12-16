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

        // Kanata Input Monitoring depends on having a stable, system-installed kanata binary path.
        // If kanata is not installed yet, we surface the install issue first to avoid sending
        // users into the Input Monitoring file picker (they can't pick the correct path yet).
        if context.components.kanataBinaryInstalled, !context.permissions.kanata.inputMonitoring.isReady {
            missing.append(.kanataInputMonitoring)
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
        // Use vhidServicesHealthy for Karabiner-related missing components
        // (Kanata service health is checked separately on the Kanata Components page)
        if !context.components.vhidServicesHealthy {
            missing.append(.launchDaemonServices)
        }
        if context.components.kanataStartupBlocked {
            missing.append(.kanataStartupBlocked)
        }

        return missing
    }

    private static func adaptIssues(_ context: SystemContext) -> [WizardIssue] {
        var issues: [WizardIssue] = []

        // Permission issues - use .permissions category so detail pages can filter correctly
        if context.permissions.keyPath.inputMonitoring.isBlocking {
            issues.append(
                WizardIssue(
                    identifier: .permission(.keyPathInputMonitoring),
                    severity: .error,
                    category: .permissions,
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
                    category: .permissions,
                    title: "Accessibility Permission Required",
                    description: "KeyPath needs Accessibility permission to function",
                    autoFixAction: nil,
                    userAction: "Grant Accessibility permission in System Settings"
                ))
        }
        if context.components.kanataBinaryInstalled, !context.permissions.kanata.inputMonitoring.isReady {
            let source = context.permissions.kanata.source
            let (title, description, userAction): (String, String, String) = {
                if source.contains("iohid-denied") {
                    return (
                        "Kanata Can't Read Keyboard Input",
                        "Kanata is running, but it cannot open the keyboard device (Input Monitoring is not effective). Remapping (e.g., 1 → 2) will not work until this is fixed.",
                        "Open System Settings > Privacy & Security > Input Monitoring, ensure the enabled entry is the exact kanata binary inside KeyPath, then restart the Kanata service."
                    )
                }
                if source.contains("no-events") {
                    return (
                        "Kanata Not Receiving Key Events",
                        "KeyPath requires proof that Kanata is receiving real key events (not just keepalive). Press a few keys, then click Refresh. If it stays red, Input Monitoring is still not working.",
                        "Press keys to validate; if it stays red, open System Settings > Privacy & Security > Input Monitoring and add/enable the kanata binary inside KeyPath, then restart the Kanata service."
                    )
                }
                if source.contains("daemon-unverifiable") {
                    return (
                        "Kanata Input Monitoring Not Verified Yet",
                        "KeyPath can see the Input Monitoring grant in TCC, but it has not yet observed kanata processing real key events. Make sure the Kanata service is running, then press a few keys and click Refresh.",
                        "Start the Kanata service, press keys to validate, then click Refresh. If it stays red, re-add/enable the exact kanata binary in System Settings > Privacy & Security > Input Monitoring."
                    )
                }
                return (
                    "Kanata Input Monitoring Required",
                    "Kanata needs Input Monitoring permission to capture your keystrokes for remapping.",
                    "Grant Input Monitoring permission in System Settings and restart the Kanata service."
                )
            }()

            issues.append(
                WizardIssue(
                    identifier: .permission(.kanataInputMonitoring),
                    severity: .error,
                    category: .permissions,
                    title: title,
                    description: description,
                    autoFixAction: nil,
                    userAction: userAction
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
        // Use vhidServicesHealthy for the issue shown on Karabiner Components page
        // (Kanata service health is handled separately - see kanataService issue below)
        if !context.components.vhidServicesHealthy {
            issues.append(
                WizardIssue(
                    identifier: .component(.launchDaemonServices),
                    severity: .error,
                    category: .installation,
                    title: "VHID Services Unhealthy",
                    description: "Karabiner VirtualHID services (daemon and manager) are not healthy",
                    autoFixAction: .installLaunchDaemonServices,
                    userAction: nil
                ))
        }
        // Startup blocked: kanata-launcher gave up after max retries (VHID not ready at boot)
        if context.components.kanataStartupBlocked {
            issues.append(
                WizardIssue(
                    identifier: .component(.kanataStartupBlocked),
                    severity: .error,
                    category: .daemon,
                    title: "Kanata Startup Blocked",
                    description:
                        "Kanata launcher gave up after the VirtualHID daemon wasn't available at boot. This can happen if the driver wasn't fully activated when your Mac started.",
                    autoFixAction: .clearStartupBlockedState,
                    userAction: "Click 'Fix' to clear the retry state and restart Kanata"
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

        // Kanata service health issue - separate from VHID services (shown on Kanata Components page)
        if !context.services.kanataRunning, context.components.vhidServicesHealthy {
            // Only show if VHID is healthy but Kanata isn't running
            // (if VHID is unhealthy, that's the primary issue to fix first)
            issues.append(
                WizardIssue(
                    identifier: .component(.kanataService),
                    severity: .error,
                    category: .daemon,
                    title: "Kanata Service Not Running",
                    description: "Kanata keyboard remapping service is not running",
                    autoFixAction: .installLaunchDaemonServices,
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

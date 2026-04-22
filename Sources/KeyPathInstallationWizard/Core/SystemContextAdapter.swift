import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

/// Adapter to convert SystemContext (InstallerEngine façade) to SystemStateResult (old wizard format)
/// This allows the GUI to use InstallerEngine.inspectSystem() while maintaining backward compatibility
@MainActor
public struct SystemContextAdapter {
    /// Convert SystemContext to SystemStateResult for backward compatibility
    public static func adapt(_ context: SystemContext) -> SystemStateResult {
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

        // 2. Check components FIRST - can't be active if binary doesn't exist
        let missingComponents = getMissingComponents(context)
        if !missingComponents.isEmpty {
            AppLogger.shared.log(
                "📊 [SystemContextAdapter] Decision: MISSING COMPONENTS (\(missingComponents.count) missing)"
            )
            return .missingComponents(missing: missingComponents)
        }

        // 3. Check permissions - components exist, but need permissions to run
        let missingPerms = getMissingPermissions(context)
        if !missingPerms.isEmpty {
            AppLogger.shared.log(
                "📊 [SystemContextAdapter] Decision: MISSING PERMISSIONS (\(missingPerms.count) missing)"
            )
            return .missingPermissions(missing: missingPerms)
        }

        if !context.services.kanataInputCaptureReady {
            AppLogger.shared.log(
                "📊 [SystemContextAdapter] Decision: MISSING PERMISSIONS (Kanata cannot open built-in keyboard)"
            )
            return .missingPermissions(missing: [.kanataInputMonitoring])
        }

        // 4. Check if Kanata is running - components exist and permissions granted
        if context.services.kanataRunning {
            AppLogger.shared.log("📊 [SystemContextAdapter] Decision: ACTIVE (kanata running)")
            return .active
        }

        AppLogger.shared.log("📊 [SystemContextAdapter] Kanata NOT running, checking daemon health...")

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

        // KeyPath permissions:
        // - `.unknown` is treated as "checking" (startup mode) and should not route the wizard
        //   into permission pages or mark the system as missing permissions.
        // - Only hard failures (`.denied`/`.error`) should block.
        if context.permissions.keyPath.inputMonitoring.isBlocking {
            missing.append(.keyPathInputMonitoring)
        }
        if context.permissions.keyPath.accessibility.isBlocking {
            missing.append(.keyPathAccessibility)
        }

        // Kanata permissions:
        // - `.unknown` means "not verified" (commonly due to missing Full Disk Access to read TCC.db).
        //   This should surface as a warning, but NOT be treated as a blocking "missing permission"
        //   for routing/state purposes.
        // - Only hard failures (`.denied`/`.error`) should block the wizard state.
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
        // The privileged output-bridge companion ships inside the app bundle
        // but must be copied to /Library/LaunchDaemons by the helper. When the
        // helper hasn't done that yet, kanata cannot start — surface it as a
        // missing component so the wizard routes to .karabinerComponents
        // (where the .installRequiredRuntimeServices auto-fix lives) instead
        // of falling through to the service page that can't recover on its own.
        if let bridge = context.system.outputBridgeStatus,
           bridge.requiresPrivilegedBridge,
           !bridge.available,
           !missing.contains(.vhidDeviceManager)
        {
            missing.append(.vhidDeviceManager)
        }
        return missing
    }

    private static func adaptIssues(_ context: SystemContext) -> [WizardIssue] {
        var issues: [WizardIssue] = []

        /// Permission issues
        ///
        /// IMPORTANT UI SEMANTICS:
        /// - `.denied` is a hard failure (red).
        /// - `.unknown` means "not verified" (often because TCC cannot be read without Full Disk Access).
        ///   We surface this as a warning so we don't mislead users into thinking permission was denied.
        func appendPermissionIssue(
            _ status: PermissionOracle.Status,
            identifier: IssueIdentifier,
            title: String,
            deniedDescription: String,
            userAction: String,
            includeUnknown: Bool
        ) {
            let shouldInclude: Bool = switch status {
            case .granted:
                false
            case .denied, .error:
                true
            case .unknown:
                includeUnknown
            }
            guard shouldInclude else { return }

            let severity: WizardIssue.IssueSeverity = (status == .unknown) ? .warning : .error
            let description: String = {
                if status == .unknown {
                    // Standardize language: unknown means "not verified", not denied.
                    // This commonly occurs when KeyPath lacks Full Disk Access and cannot read TCC.db for Kanata.
                    return switch identifier {
                    case .permission(.kanataInputMonitoring):
                        "Not verified (grant Full Disk Access to verify). If remapping doesn’t work, add the KeyPath runtime binary in System Settings > Privacy & Security > Input Monitoring."
                    case .permission(.kanataAccessibility):
                        "Not verified (grant Full Disk Access to verify). If remapping doesn’t work, add the KeyPath runtime binary in System Settings > Privacy & Security > Accessibility."
                    default:
                        "Not verified (grant Full Disk Access to verify)."
                    }
                }
                return deniedDescription
            }()
            let userActionText: String = (status == .unknown)
                ? "Add kanata manually in System Settings, or enable Enhanced Diagnostics to verify"
                : userAction
            issues.append(
                WizardIssue(
                    identifier: identifier,
                    severity: severity,
                    category: .permissions,
                    title: title,
                    description: description,
                    autoFixAction: nil,
                    userAction: userActionText
                )
            )
        }

        appendPermissionIssue(
            context.permissions.keyPath.inputMonitoring,
            identifier: .permission(.keyPathInputMonitoring),
            title: "Input Monitoring Permission Required",
            deniedDescription: "KeyPath needs Input Monitoring permission to function",
            userAction: "Grant Input Monitoring permission in System Settings",
            includeUnknown: false
        )
        appendPermissionIssue(
            context.permissions.keyPath.accessibility,
            identifier: .permission(.keyPathAccessibility),
            title: "Accessibility Permission Required",
            deniedDescription: "KeyPath needs Accessibility permission to function",
            userAction: "Grant Accessibility permission in System Settings",
            includeUnknown: false
        )
        appendPermissionIssue(
            context.permissions.kanata.inputMonitoring,
            identifier: .permission(.kanataInputMonitoring),
            title: "Kanata Engine Input Monitoring Permission",
            deniedDescription: "The Kanata engine used by KeyPath needs Input Monitoring permission",
            userAction: "Grant Input Monitoring permission to the Kanata engine binary in System Settings",
            includeUnknown: true
        )
        appendPermissionIssue(
            context.permissions.kanata.accessibility,
            identifier: .permission(.kanataAccessibility),
            title: "Kanata Engine Accessibility Permission",
            deniedDescription: "The Kanata engine used by KeyPath needs Accessibility permission",
            userAction: "Grant Accessibility permission to the Kanata engine binary in System Settings",
            includeUnknown: true
        )
        if !context.services.kanataInputCaptureReady,
           !issues.contains(where: { $0.identifier == .permission(.kanataInputMonitoring) })
        {
            issues.append(
                WizardIssue(
                    identifier: .permission(.kanataInputMonitoring),
                    severity: .error,
                    category: .permissions,
                    title: "KeyPath Runtime Cannot Open Built-In Keyboard",
                    description:
                    "KeyPath Runtime is running but cannot open the built-in keyboard device, so remapping will not work on this laptop.",
                    autoFixAction: nil,
                    userAction:
                    "Regrant Input Monitoring for the KeyPath runtime binary and restart KeyPath"
                )
            )
        }

        // Component issues
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
                )
            )
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
                )
            )
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
                )
            )
        }
        // Use a VHID-specific issue for the Karabiner Components page.
        // Legacy recovery services are reported separately and should not be the primary signal here.
        if !context.components.vhidServicesHealthy {
            issues.append(
                WizardIssue(
                    identifier: .component(.vhidDeviceManager),
                    severity: .error,
                    category: .installation,
                    title: "VHID Services Unhealthy",
                    description: "Karabiner VirtualHID services (daemon and manager) are not healthy",
                    autoFixAction: .installRequiredRuntimeServices,
                    userAction: nil
                )
            )
        } else if let bridge = context.system.outputBridgeStatus,
                  bridge.requiresPrivilegedBridge,
                  !bridge.available
        {
            // Bridge is missing but VHID is otherwise healthy — surface a
            // dedicated issue so the user understands what's actually wrong.
            // Routes to .karabinerComponents via the existing identifier.
            issues.append(
                WizardIssue(
                    identifier: .component(.vhidDeviceManager),
                    severity: .error,
                    category: .installation,
                    title: "Privileged Output Bridge Missing",
                    description: bridge.detail
                        ?? "The privileged output companion LaunchDaemon is not installed. Kanata cannot start without it.",
                    autoFixAction: .installRequiredRuntimeServices,
                    userAction: nil
                )
            )
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
                    )
                )
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
                )
            )
        }
        // Kanata service health issue - separate from VHID services (shown on Kanata Components page)
        if !context.services.kanataRunning, context.components.vhidServicesHealthy,
           context.services.kanataInputCaptureReady
        {
            // Only show if VHID is healthy but Kanata isn't running
            // (if VHID is unhealthy, that's the primary issue to fix first)
            issues.append(
                WizardIssue(
                    identifier: .component(.keyPathRuntime),
                    severity: .error,
                    category: .daemon,
                    title: "KeyPath Runtime Not Running",
                    description: "KeyPath keyboard remapping runtime is not running",
                    autoFixAction: nil,
                    userAction: "Start KeyPath Runtime from the wizard or app status controls"
                )
            )
        }

        // Helper issues
        if !context.helper.isReady {
            issues.append(
                WizardIssue(
                    identifier: .component(
                        context.helper.isInstalled ? .privilegedHelperUnhealthy : .privilegedHelper
                    ),
                    severity: .error,
                    category: .backgroundServices,
                    title: "Privileged Helper Not Ready",
                    description: "Privileged helper is not installed or not working",
                    autoFixAction: context.helper.isInstalled
                        ? .reinstallPrivilegedHelper : .installPrivilegedHelper,
                    userAction: nil
                )
            )
        }

        return issues
    }

    private static func determineAutoFixActions(_ context: SystemContext) -> [AutoFixAction] {
        // Use shared ActionDeterminer for repair actions (SystemContextAdapter is used for repair scenarios)
        ActionDeterminer.determineRepairActions(context: context)
    }
}

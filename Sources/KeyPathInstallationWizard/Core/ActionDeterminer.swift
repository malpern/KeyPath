import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Utility for determining auto-fix actions from system context
/// Consolidates logic previously duplicated across InstallerEngine, SystemContextAdapter, and SystemSnapshotAdapter
@MainActor
public enum ActionDeterminer {
    /// Determine actions needed based on intent and system context
    /// - Parameters:
    ///   - intent: The installation intent (install, repair, etc.)
    ///   - context: Current system state
    /// - Returns: Array of actions needed to achieve the intent
    public static func determineActions(
        for intent: InstallIntent,
        context: SystemContext
    ) -> [AutoFixAction] {
        switch intent {
        case .install:
            determineInstallActions(context: context)
        case .repair:
            determineRepairActions(context: context)
        case .uninstall:
            determineUninstallActions(context: context)
        case .inspectOnly:
            []
        }
    }

    /// Determine actions for repair (general auto-fix)
    /// Used by both InstallerEngine and SystemContextAdapter
    public static func determineRepairActions(context: SystemContext) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        // Check conflicts first (highest priority)
        if context.conflicts.hasConflicts, context.conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check for driver version mismatch (high priority for driver issues)
        if context.components.vhidVersionMismatch {
            actions.append(.fixDriverVersionMismatch)
        }

        // Check missing installable components. Keep health/runtime failures on
        // the narrower repair paths below instead of treating them as absent.
        if hasMissingInstallableComponents(context.components) {
            actions.append(.installMissingComponents)

            // CRITICAL: Activate manager BEFORE starting daemon
            // Per Karabiner documentation, manager activation must happen before daemon startup
            if !context.components.karabinerDriverInstalled {
                actions.append(.activateVHIDDeviceManager)
            }
        }

        if context.requiresManualVHIDDriverApproval {
            return actions
        }

        // Covers a pre-MAL-57 plist (missing ProcessType=Interactive) too:
        // it needs the rewrite even when the daemon is otherwise healthy.
        if context.components.vhidRuntimeServicesNeedRepair {
            actions.append(.installRequiredRuntimeServices)
        }

        appendVHIDActivationRepairIfNeeded(context: context, actions: &actions)

        if !context.services.kanataRunning, !actions.contains(.installRequiredRuntimeServices) {
            actions.append(.installRequiredRuntimeServices)
        }

        // Check if daemon needs starting
        if !context.services.karabinerDaemonRunning {
            // Ensure manager is activated before starting daemon
            if !context.components.karabinerDriverInstalled, !actions.contains(.activateVHIDDeviceManager) {
                actions.append(.activateVHIDDeviceManager)
            }
            actions.append(.startKarabinerDaemon)
        }

        // Reinstall helper if unhealthy (use reinstall for repair)
        if !context.helper.isReady {
            actions.append(
                context.helper.isInstalled ? .reinstallPrivilegedHelper : .installPrivilegedHelper
            )
        }

        return actions
    }

    /// Determine actions for fresh installation
    public static func determineInstallActions(context: SystemContext) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        // Check conflicts first
        if context.conflicts.hasConflicts, context.conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check for driver version mismatch (highest priority for driver issues)
        if context.components.vhidVersionMismatch {
            actions.append(.fixDriverVersionMismatch)
        }

        // Check missing installable components. Keep health/runtime failures on
        // the narrower repair paths below instead of treating them as absent.
        if hasMissingInstallableComponents(context.components) {
            actions.append(.installMissingComponents)

            // CRITICAL: Activate manager BEFORE installing daemon services
            // Per Karabiner documentation, manager activation must happen before daemon startup
            if !context.components.karabinerDriverInstalled {
                actions.append(.activateVHIDDeviceManager)
            }
        }

        if context.requiresManualVHIDDriverApproval {
            return actions
        }

        // Check if daemon needs starting
        if !context.services.karabinerDaemonRunning {
            // Ensure manager is activated before starting daemon
            if !context.components.karabinerDriverInstalled, !actions.contains(.activateVHIDDeviceManager) {
                actions.append(.activateVHIDDeviceManager)
            }
            actions.append(.startKarabinerDaemon)
        }

        // Always install helper for fresh install (not reinstall)
        if !context.helper.isReady {
            actions.append(.installPrivilegedHelper)
        }

        if context.components.vhidRuntimeServicesNeedRepair {
            actions.append(.installRequiredRuntimeServices)
        }

        appendVHIDActivationRepairIfNeeded(context: context, actions: &actions)

        if !context.services.kanataRunning, !actions.contains(.installRequiredRuntimeServices) {
            actions.append(.installRequiredRuntimeServices)
        }

        return actions
    }

    /// Determine actions for uninstall
    public static func determineUninstallActions(context _: SystemContext) -> [AutoFixAction] {
        // Uninstall is handled differently - logic is in UninstallCoordinator
        []
    }

    private static func hasMissingInstallableComponents(_ components: ComponentStatus) -> Bool {
        !components.kanataBinaryInstalled ||
            !components.karabinerDriverInstalled ||
            !components.vhidDeviceInstalled
    }

    private static func appendVHIDActivationRepairIfNeeded(
        context: SystemContext,
        actions: inout [AutoFixAction]
    ) {
        guard context.services.kanataInputCaptureIssue ==
            ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
        else { return }

        if !actions.contains(.activateVHIDDeviceManager) {
            actions.append(.activateVHIDDeviceManager)
        }
        if !actions.contains(.repairVHIDDaemonServices) {
            actions.append(.repairVHIDDaemonServices)
        }
    }
}

extension SystemContext {
    var requiresManualVHIDDriverApproval: Bool {
        components.karabinerDriverInstalled
            && services.kanataInputCaptureIssue == ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
    }
}

import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Utility for determining auto-fix actions from system context
/// Consolidates logic previously duplicated across InstallerEngine, SystemContextAdapter, and SystemSnapshotAdapter
@MainActor
enum ActionDeterminer {
    /// Determine actions needed based on intent and system context
    /// - Parameters:
    ///   - intent: The installation intent (install, repair, etc.)
    ///   - context: Current system state
    /// - Returns: Array of actions needed to achieve the intent
    static func determineActions(
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
    static func determineRepairActions(context: SystemContext) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        // Check conflicts first (highest priority)
        if context.conflicts.hasConflicts, context.conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check for driver version mismatch (high priority for driver issues)
        if context.components.vhidVersionMismatch {
            actions.append(.fixDriverVersionMismatch)
        }

        // Check missing components
        if !context.components.hasAllRequired {
            if !context.components.kanataBinaryInstalled {
                actions.append(.installBundledKanata)
            }
            actions.append(.installMissingComponents)

            // CRITICAL: Activate manager BEFORE starting daemon
            // Per Karabiner documentation, manager activation must happen before daemon startup
            if !context.components.karabinerDriverInstalled {
                actions.append(.activateVHIDDeviceManager)
            }
        }

        // If the SMAppService/launchd jobs are missing or Kanata isn't running, reinstall services
        if !context.components.launchDaemonServicesHealthy || !context.services.kanataRunning {
            actions.append(.installLaunchDaemonServices)
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
                context.helper.isInstalled ? .reinstallPrivilegedHelper : .installPrivilegedHelper)
        }

        // Restart unhealthy services
        if !context.services.backgroundServicesHealthy {
            actions.append(.restartUnhealthyServices)
        }

        return actions
    }

    /// Determine actions for fresh installation
    static func determineInstallActions(context: SystemContext) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        // Check conflicts first
        if context.conflicts.hasConflicts, context.conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check for driver version mismatch (highest priority for driver issues)
        if context.components.vhidVersionMismatch {
            actions.append(.fixDriverVersionMismatch)
        }

        // Check missing components
        if !context.components.hasAllRequired {
            if !context.components.kanataBinaryInstalled {
                actions.append(.installBundledKanata)
            }
            actions.append(.installMissingComponents)

            // CRITICAL: Activate manager BEFORE installing daemon services
            // Per Karabiner documentation, manager activation must happen before daemon startup
            if !context.components.karabinerDriverInstalled {
                actions.append(.activateVHIDDeviceManager)
            }
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

        // Always install services for fresh install
        // NOTE: Manager activation must happen first (added above if needed)
        actions.append(.installLaunchDaemonServices)

        return actions
    }

    /// Determine actions for uninstall
    static func determineUninstallActions(context _: SystemContext) -> [AutoFixAction] {
        // Uninstall is handled differently - logic is in UninstallCoordinator
        []
    }
}

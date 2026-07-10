import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Pure assessment and planning result shared by InstallerEngine and wizard projections.
public struct InstallerDecision: Sendable, Equatable {
    public let intent: InstallIntent
    public let assessment: InstallerStateMatrixRow
    public let matrixActions: [InstallerStateMatrixAction]
    public let autoFixActions: [AutoFixAction]

    public init(
        intent: InstallIntent,
        assessment: InstallerStateMatrixRow,
        matrixActions: [InstallerStateMatrixAction],
        autoFixActions: [AutoFixAction]
    ) {
        self.intent = intent
        self.assessment = assessment
        self.matrixActions = matrixActions
        self.autoFixActions = autoFixActions
    }
}

/// Canonical pure decision path from one captured context plus intent to one
/// assessment and one executable action plan.
@MainActor
public enum InstallerDecisionPipeline {
    public static func decide(
        for intent: InstallIntent,
        context: SystemContext
    ) -> InstallerDecision {
        let assessment = context.installerStateMatrixRow
        return InstallerDecision(
            intent: intent,
            assessment: assessment,
            matrixActions: InstallerStateMatrixPlanner.plan(for: assessment),
            autoFixActions: determineActions(for: intent, context: context)
        )
    }

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
    /// Used by both InstallerEngine and the wizard presentation projection.
    public static func determineRepairActions(context: SystemContext) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        // Every repair action below may need privileged XPC. Establish a working
        // helper before planning any operation that routes through the broker.
        if !context.helper.isReady {
            actions.append(
                context.helper.isInstalled ? .reinstallPrivilegedHelper : .installPrivilegedHelper
            )
        }

        // Resolve conflicts before component and service mutations.
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
            if !context.components.vhidDeviceInstalled,
               !context.requiresManualVHIDDriverApproval
            {
                actions.append(.activateVHIDDeviceManager)
            }
        }

        // Matrix row: DriverKit approval pending. This is a terminal manual
        // action for the attempt, not a retryable runtime/VHID repair loop.
        if context.requiresManualVHIDDriverApproval {
            return actions
        }

        // Covers a pre-MAL-57 plist (missing ProcessType=Interactive) too:
        // it needs the rewrite even when the daemon is otherwise healthy.
        if context.components.vhidRuntimeServicesNeedRepair {
            actions.append(.installRequiredRuntimeServices)
        }

        appendVHIDActivationRepairIfNeeded(context: context, actions: &actions)

        // Matrix row: stopped Kanata plus non-approval stale input-capture
        // evidence. Runtime install/start wins; old diagnostics are revisited
        // only after the runtime is ready again.
        if !context.services.kanataRunning, !actions.contains(.installRequiredRuntimeServices) {
            actions.append(.installRequiredRuntimeServices)
        }

        // Check if daemon needs starting
        if !context.services.karabinerDaemonRunning {
            // Ensure manager is activated before starting daemon
            if !context.components.vhidDeviceInstalled,
               !context.requiresManualVHIDDriverApproval,
               !actions.contains(.activateVHIDDeviceManager)
            {
                actions.append(.activateVHIDDeviceManager)
            }
            actions.append(.startKarabinerDaemon)
        }

        return actions
    }

    /// Determine actions for fresh installation
    public static func determineInstallActions(context: SystemContext) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        // Clean installs have no XPC endpoint yet. Install the helper before any
        // component, activation, or service recipe attempts privileged work.
        if !context.helper.isReady {
            actions.append(.installPrivilegedHelper)
        }

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
            if !context.components.vhidDeviceInstalled,
               !context.requiresManualVHIDDriverApproval
            {
                actions.append(.activateVHIDDeviceManager)
            }
        }

        // Matrix row: DriverKit approval pending. This is a terminal manual
        // action for the attempt, not a retryable runtime/VHID repair loop.
        if context.requiresManualVHIDDriverApproval {
            return actions
        }

        // Check if daemon needs starting
        if !context.services.karabinerDaemonRunning {
            // Ensure manager is activated before starting daemon
            if !context.components.vhidDeviceInstalled,
               !context.requiresManualVHIDDriverApproval,
               !actions.contains(.activateVHIDDeviceManager)
            {
                actions.append(.activateVHIDDeviceManager)
            }
            actions.append(.startKarabinerDaemon)
        }

        if context.components.vhidRuntimeServicesNeedRepair {
            actions.append(.installRequiredRuntimeServices)
        }

        appendVHIDActivationRepairIfNeeded(context: context, actions: &actions)

        // Matrix row: stopped Kanata plus non-approval stale input-capture
        // evidence. Runtime install/start wins; old diagnostics are revisited
        // only after the runtime is ready again.
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

/// Compatibility façade for existing tests and callers during Milestone 2.
/// Production planning must use `InstallerDecisionPipeline.decide` so matrix
/// metadata and executable actions come from the same captured context.
@MainActor
public enum ActionDeterminer {
    public static func determineActions(
        for intent: InstallIntent,
        context: SystemContext
    ) -> [AutoFixAction] {
        InstallerDecisionPipeline.decide(for: intent, context: context).autoFixActions
    }

    public static func determineRepairActions(context: SystemContext) -> [AutoFixAction] {
        InstallerDecisionPipeline.decide(for: .repair, context: context).autoFixActions
    }

    public static func determineInstallActions(context: SystemContext) -> [AutoFixAction] {
        InstallerDecisionPipeline.decide(for: .install, context: context).autoFixActions
    }

    public static func determineUninstallActions(context: SystemContext) -> [AutoFixAction] {
        InstallerDecisionPipeline.decide(for: .uninstall, context: context).autoFixActions
    }
}

public extension SystemContext {
    var requiresManualVHIDDriverApproval: Bool {
        // Matrix row: DriverKit approval pending. The specific activation
        // reason is treated as current macOS approval state when the driver is
        // installed, even if Kanata is also stopped.
        components.karabinerDriverInstalled
            && !services.vhidHealthy
            && services.kanataInputCaptureIssue == ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
    }
}

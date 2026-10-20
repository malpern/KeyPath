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
        context.services.kanataRuntimeReadiness.isReady ? [] : [.restartCommServer]
    }

    /// Determine actions for fresh installation
    public static func determineInstallActions(context: SystemContext) -> [AutoFixAction] {
        context.services.kanataRuntimeReadiness.isReady ? [] : [.restartCommServer]
    }

    /// Determine actions for uninstall
    public static func determineUninstallActions(context _: SystemContext) -> [AutoFixAction] {
        // Uninstall is handled differently - logic is in UninstallCoordinator
        []
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

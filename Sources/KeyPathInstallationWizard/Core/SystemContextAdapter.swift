import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

/// Adapter to convert SystemContext (InstallerEngine façade) to SystemStateResult (old wizard format)
/// This allows the GUI to use InstallerEngine.inspectSystem() while maintaining backward compatibility
@MainActor
public struct SystemContextAdapter {
    /// Convert SystemContext to SystemStateResult for backward compatibility.
    /// Delegates to SystemInspector for state determination and issue generation.
    public static func adapt(_ context: SystemContext) -> SystemStateResult {
        let (wizardState, wizardIssues) = SystemInspector.inspect(context: context)
        let decision = InstallerDecisionPipeline.decide(for: .repair, context: context)

        return SystemStateResult(
            state: wizardState,
            issues: wizardIssues,
            autoFixActions: decision.autoFixActions,
            detectionTimestamp: context.timestamp,
            stateMatrixRow: decision.assessment.rawValue,
            stateMatrixPlan: decision.matrixActions.map(\.rawValue),
            captureStatus: context.captureStatus,
            helperInstalled: context.helper.isInstalled,
            helperNeedsApproval: context.helper.requiresApproval
        )
    }
}

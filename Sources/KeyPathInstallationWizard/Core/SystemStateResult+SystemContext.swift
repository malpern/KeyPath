import KeyPathWizardCore

public extension SystemStateResult {
    /// Projects one canonical installer context into the wizard's presentation result.
    @MainActor
    static func projecting(_ context: SystemContext) -> SystemStateResult {
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

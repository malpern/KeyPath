import KeyPathWizardCore

public extension SystemStateResult {
    /// Projects one canonical installer context into the wizard's presentation result.
    @MainActor
    static func projecting(_ context: SystemContext) -> SystemStateResult {
        let (wizardState, wizardIssues) = SystemInspector.inspect(context: context)

        return SystemStateResult(
            state: wizardState,
            issues: wizardIssues,
            autoFixActions: InstallerEngine.actions(for: .repair, context: context),
            detectionTimestamp: context.timestamp,
            stateMatrixRow: context.installerStateMatrixRow.rawValue,
            stateMatrixPlan: context.installerStateMatrixPlan.map(\.rawValue),
            captureStatus: context.captureStatus,
            permissions: context.captureStatus.isComplete ? context.permissions : nil
        )
    }
}

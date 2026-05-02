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
        let autoFixActions = determineAutoFixActions(context)

        return SystemStateResult(
            state: wizardState,
            issues: wizardIssues,
            autoFixActions: autoFixActions,
            detectionTimestamp: context.timestamp
        )
    }

    private static func determineAutoFixActions(_ context: SystemContext) -> [AutoFixAction] {
        // Use shared ActionDeterminer for repair actions (SystemContextAdapter is used for repair scenarios)
        ActionDeterminer.determineRepairActions(context: context)
    }
}

import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

// MARK: - Recipe Generation Extension

public extension InstallerEngine {
    // MARK: - Action Determination

    /// Determine which actions are needed based on intent and context
    func determineActions(for intent: InstallIntent, context: SystemContext)
        -> [AutoFixAction]
    {
        InstallerDecisionPipeline.decide(for: intent, context: context).autoFixActions
    }

    // MARK: - Recipe Generation

    /// Generate ServiceRecipes from AutoFixActions
    func generateRecipes(from actions: [AutoFixAction], context: SystemContext)
        -> [ServiceRecipe]
    {
        var recipes: [ServiceRecipe] = []

        for action in actions {
            if let recipe = recipeForAction(action, context: context) {
                recipes.append(recipe)
            }
        }

        return recipes
    }

    /// Convert an AutoFixAction to a ServiceRecipe
    func recipeForAction(_ action: AutoFixAction, context _: SystemContext) -> ServiceRecipe? {
        switch action {
        case .restartCommServer:
            ServiceRecipe(
                id: "start-session-runtime", type: .installComponent,
                expectedPostconditions: [.runtimeReadyOrApprovalPending]
            )
        case .synchronizeConfigPaths:
            ServiceRecipe(id: InstallerRecipeID.synchronizeConfigPaths, type: .checkRequirement)
        default:
            nil // Legacy helper, DriverKit, and system-service actions are unavailable.
        }
    }

    // MARK: - Recipe Ordering

    /// Order recipes respecting dependencies
    ///
    /// Design Decision: Simple ordering is intentionally used instead of complex dependency resolution.
    ///
    /// **Why this works:**
    /// 1. Recipes are designed to be order-independent or self-contained
    /// 2. InstallerDecisionPipeline already adds recipes in roughly correct order
    /// 3. No current recipes declare explicit dependencies (all use empty dependencies array)
    /// 4. Service health checks after each recipe provide implicit ordering guarantees
    ///
    /// **When dependency resolution would be needed:**
    /// - If recipes start declaring explicit dependencies via the `dependencies` field
    /// - If recipes require complex inter-dependencies (e.g., A requires B AND C, B requires D)
    /// - If we need to parallelize recipe execution while respecting constraints
    ///
    /// For now, this simple approach keeps the codebase maintainable and easier to understand.
    /// If complex dependencies emerge, implement topological sort here.
    ///
    /// Related: Linear MAL-35, MAL-16 (duplicate issues resolved by documenting design)
    func orderRecipes(_ recipes: [ServiceRecipe]) -> [ServiceRecipe] {
        // Validate design assumption: no recipe should currently declare dependencies
        assert(
            recipes.allSatisfy(\.dependencies.isEmpty),
            "Recipe declared dependencies but orderRecipes() does not implement dependency resolution. " +
                "Either remove the dependencies or implement topological sort."
        )

        // Return recipes in the order produced by InstallerDecisionPipeline.
        return recipes
    }

    /// Map AutoFixAction to recipe ID
    func recipeIDForAction(_ action: AutoFixAction) -> String {
        switch action {
        case .installRequiredRuntimeServices:
            InstallerRecipeID.installRequiredRuntimeServices
        case .installCorrectVHIDDriver:
            InstallerRecipeID.installCorrectVHIDDriver
        case .installLogRotation:
            InstallerRecipeID.installLogRotation
        case .installPrivilegedHelper:
            InstallerRecipeID.installPrivilegedHelper
        case .reinstallPrivilegedHelper:
            InstallerRecipeID.reinstallPrivilegedHelper
        case .startKarabinerDaemon:
            InstallerRecipeID.startKarabinerDaemon
        case .terminateConflictingProcesses:
            InstallerRecipeID.terminateConflictingProcesses
        case .fixDriverVersionMismatch:
            InstallerRecipeID.fixDriverVersionMismatch
        case .installMissingComponents:
            InstallerRecipeID.installMissingComponents
        case .restartVirtualHIDDaemon:
            InstallerRecipeID.repairVHIDDaemonServices
        case .createConfigDirectories:
            InstallerRecipeID.createConfigDirectories
        case .activateVHIDDeviceManager:
            InstallerRecipeID.activateVHIDManager
        case .repairVHIDDaemonServices:
            InstallerRecipeID.repairVHIDDaemonServices
        case .enableTCPServer:
            InstallerRecipeID.enableTCPServer
        case .setupTCPAuthentication:
            InstallerRecipeID.setupTCPAuthentication
        case .regenerateCommServiceConfiguration:
            InstallerRecipeID.regenerateCommServiceConfig
        case .regenerateServiceConfiguration:
            InstallerRecipeID.regenerateServiceConfig
        case .restartCommServer:
            "start-session-runtime"
        case .synchronizeConfigPaths:
            InstallerRecipeID.synchronizeConfigPaths
        }
    }
}

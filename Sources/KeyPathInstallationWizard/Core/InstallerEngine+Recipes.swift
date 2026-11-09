import Foundation
import KeyPathCore
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
        actions.map { recipeForAction($0, context: context) }
    }

    /// Convert an AutoFixAction to a ServiceRecipe
    func recipeForAction(_ action: AutoFixAction, context _: SystemContext) -> ServiceRecipe {
        switch action {
        case .restartCommServer:
            ServiceRecipe(
                id: InstallerRecipeID.startSessionRuntime, type: .installComponent,
                expectedPostconditions: [.runtimeReadyOrApprovalPending]
            )
        case .synchronizeConfigPaths:
            ServiceRecipe(id: InstallerRecipeID.synchronizeConfigPaths, type: .checkRequirement)
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
        case .restartCommServer:
            InstallerRecipeID.startSessionRuntime
        case .synchronizeConfigPaths:
            InstallerRecipeID.synchronizeConfigPaths
        }
    }
}

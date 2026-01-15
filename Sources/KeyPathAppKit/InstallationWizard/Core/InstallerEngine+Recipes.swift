import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

// MARK: - Recipe Generation Extension

extension InstallerEngine {
    // MARK: - Action Determination

    /// Determine which actions are needed based on intent and context
    func determineActions(for intent: InstallIntent, context: SystemContext)
        -> [AutoFixAction] {
        // Use shared ActionDeterminer to avoid duplication
        ActionDeterminer.determineActions(for: intent, context: context)
    }

    // MARK: - Recipe Generation

    /// Generate ServiceRecipes from AutoFixActions
    func generateRecipes(from actions: [AutoFixAction], context: SystemContext)
        -> [ServiceRecipe] {
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
        case .installLaunchDaemonServices:
            ServiceRecipe(
                id: InstallerRecipeID.installLaunchDaemonServices,
                type: .installService,
                serviceID: nil,
                launchctlActions: [
                    .bootstrap(serviceID: KeyPathConstants.Bundle.daemonID),
                    .bootstrap(serviceID: KeyPathConstants.Bundle.vhidDaemonID),
                    .bootstrap(serviceID: KeyPathConstants.Bundle.vhidManagerID)
                ],
                healthCheck: HealthCheckCriteria(serviceID: KeyPathConstants.Bundle.daemonID, shouldBeRunning: true)
            )

        case .installBundledKanata:
            ServiceRecipe(
                id: InstallerRecipeID.installBundledKanata,
                type: .installComponent,
                serviceID: nil
            )

        case .installCorrectVHIDDriver:
            ServiceRecipe(
                id: InstallerRecipeID.installCorrectVHIDDriver,
                type: .installComponent,
                serviceID: nil
            )

        case .installLogRotation:
            ServiceRecipe(
                id: InstallerRecipeID.installLogRotation,
                type: .installComponent,
                serviceID: nil
            )

        case .installPrivilegedHelper:
            ServiceRecipe(
                id: InstallerRecipeID.installPrivilegedHelper,
                type: .installService,
                serviceID: KeyPathConstants.Bundle.helperID
            )

        case .reinstallPrivilegedHelper:
            ServiceRecipe(
                id: InstallerRecipeID.reinstallPrivilegedHelper,
                type: .installService,
                serviceID: KeyPathConstants.Bundle.helperID
            )

        case .startKarabinerDaemon:
            ServiceRecipe(
                id: InstallerRecipeID.startKarabinerDaemon,
                type: .restartService,
                serviceID: KeyPathConstants.Bundle.daemonID,
                launchctlActions: [.kickstart(serviceID: KeyPathConstants.Bundle.daemonID)],
                healthCheck: HealthCheckCriteria(serviceID: KeyPathConstants.Bundle.daemonID, shouldBeRunning: true)
            )

        case .restartUnhealthyServices:
            ServiceRecipe(
                id: InstallerRecipeID.restartUnhealthyServices,
                type: .restartService,
                serviceID: nil
            )

        case .restartVirtualHIDDaemon:
            // Same recipe as restartUnhealthyServices (verified restart path)
            ServiceRecipe(
                id: InstallerRecipeID.restartUnhealthyServices,
                type: .restartService,
                serviceID: nil
            )

        case .terminateConflictingProcesses:
            ServiceRecipe(
                id: InstallerRecipeID.terminateConflictingProcesses,
                type: .checkRequirement,
                serviceID: nil
            )

        case .fixDriverVersionMismatch:
            ServiceRecipe(
                id: InstallerRecipeID.fixDriverVersionMismatch,
                type: .installComponent,
                serviceID: nil
            )

        case .installMissingComponents:
            ServiceRecipe(
                id: InstallerRecipeID.installMissingComponents,
                type: .installComponent,
                serviceID: nil
            )

        case .createConfigDirectories:
            ServiceRecipe(
                id: InstallerRecipeID.createConfigDirectories,
                type: .installComponent,
                serviceID: nil
            )

        case .activateVHIDDeviceManager:
            ServiceRecipe(
                id: InstallerRecipeID.activateVHIDManager,
                type: .installComponent,
                serviceID: nil
            )

        case .repairVHIDDaemonServices:
            ServiceRecipe(
                id: InstallerRecipeID.repairVHIDDaemonServices,
                type: .installComponent,
                serviceID: nil
            )

        case .enableTCPServer:
            ServiceRecipe(
                id: InstallerRecipeID.enableTCPServer,
                type: .installComponent,
                serviceID: nil
            )

        case .setupTCPAuthentication:
            ServiceRecipe(
                id: InstallerRecipeID.setupTCPAuthentication,
                type: .installComponent,
                serviceID: nil
            )

        case .regenerateCommServiceConfiguration:
            ServiceRecipe(
                id: InstallerRecipeID.regenerateCommServiceConfig,
                type: .installComponent,
                serviceID: nil
            )

        case .regenerateServiceConfiguration:
            ServiceRecipe(
                id: InstallerRecipeID.regenerateServiceConfig,
                type: .installComponent,
                serviceID: nil
            )

        case .restartCommServer:
            ServiceRecipe(
                id: InstallerRecipeID.restartCommServer,
                type: .installComponent,
                serviceID: nil
            )

        case .adoptOrphanedProcess:
            ServiceRecipe(
                id: InstallerRecipeID.adoptOrphanedProcess,
                type: .installComponent,
                serviceID: nil
            )

        case .replaceOrphanedProcess:
            ServiceRecipe(
                id: InstallerRecipeID.replaceOrphanedProcess,
                type: .installComponent,
                serviceID: nil
            )

        case .replaceKanataWithBundled:
            ServiceRecipe(
                id: InstallerRecipeID.replaceKanataWithBundled,
                type: .installComponent,
                serviceID: nil
            )

        case .synchronizeConfigPaths:
            ServiceRecipe(
                id: InstallerRecipeID.synchronizeConfigPaths,
                type: .checkRequirement,
                serviceID: nil
            )
        }
    }

    // MARK: - Recipe Ordering

    /// Order recipes respecting dependencies
    ///
    /// Design Decision: Simple ordering is intentionally used instead of complex dependency resolution.
    ///
    /// **Why this works:**
    /// 1. Recipes are designed to be order-independent or self-contained
    /// 2. ActionDeterminer already adds recipes in roughly correct order
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

        // Return recipes in the order they were added (ActionDeterminer already provides correct ordering)
        return recipes
    }

    /// Map AutoFixAction to recipe ID
    func recipeIDForAction(_ action: AutoFixAction) -> String {
        switch action {
        case .installLaunchDaemonServices:
            InstallerRecipeID.installLaunchDaemonServices
        case .installBundledKanata:
            InstallerRecipeID.installBundledKanata
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
        case .restartUnhealthyServices:
            InstallerRecipeID.restartUnhealthyServices
        case .terminateConflictingProcesses:
            InstallerRecipeID.terminateConflictingProcesses
        case .fixDriverVersionMismatch:
            InstallerRecipeID.fixDriverVersionMismatch
        case .installMissingComponents:
            InstallerRecipeID.installMissingComponents
        case .restartVirtualHIDDaemon:
            // restartVirtualHIDDaemon maps to restartUnhealthyServices recipe
            InstallerRecipeID.restartUnhealthyServices
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
            InstallerRecipeID.restartCommServer
        case .adoptOrphanedProcess:
            InstallerRecipeID.adoptOrphanedProcess
        case .replaceOrphanedProcess:
            InstallerRecipeID.replaceOrphanedProcess
        case .replaceKanataWithBundled:
            InstallerRecipeID.replaceKanataWithBundled
        case .synchronizeConfigPaths:
            InstallerRecipeID.synchronizeConfigPaths
        }
    }
}

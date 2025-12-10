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
        -> [AutoFixAction]
    {
        // Use shared ActionDeterminer to avoid duplication
        ActionDeterminer.determineActions(for: intent, context: context)
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
        case .installLaunchDaemonServices:
            ServiceRecipe(
                id: "install-launch-daemon-services",
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
                id: "install-bundled-kanata",
                type: .installComponent,
                serviceID: nil
            )

        case .installCorrectVHIDDriver:
            ServiceRecipe(
                id: "install-correct-vhid-driver",
                type: .installComponent,
                serviceID: nil
            )

        case .installLogRotation:
            ServiceRecipe(
                id: "install-log-rotation",
                type: .installComponent,
                serviceID: nil
            )

        case .installPrivilegedHelper:
            ServiceRecipe(
                id: "install-privileged-helper",
                type: .installService,
                serviceID: KeyPathConstants.Bundle.helperID
            )

        case .reinstallPrivilegedHelper:
            ServiceRecipe(
                id: "reinstall-privileged-helper",
                type: .installService,
                serviceID: KeyPathConstants.Bundle.helperID
            )

        case .startKarabinerDaemon:
            ServiceRecipe(
                id: "start-karabiner-daemon",
                type: .restartService,
                serviceID: KeyPathConstants.Bundle.daemonID,
                launchctlActions: [.kickstart(serviceID: KeyPathConstants.Bundle.daemonID)],
                healthCheck: HealthCheckCriteria(serviceID: KeyPathConstants.Bundle.daemonID, shouldBeRunning: true)
            )

        case .restartUnhealthyServices:
            ServiceRecipe(
                id: "restart-unhealthy-services",
                type: .restartService,
                serviceID: nil
            )

        case .restartVirtualHIDDaemon:
            // Same recipe as restartUnhealthyServices (verified restart path)
            ServiceRecipe(
                id: "restart-unhealthy-services",
                type: .restartService,
                serviceID: nil
            )

        case .terminateConflictingProcesses:
            ServiceRecipe(
                id: "terminate-conflicting-processes",
                type: .checkRequirement,
                serviceID: nil
            )

        case .fixDriverVersionMismatch:
            ServiceRecipe(
                id: "fix-driver-version-mismatch",
                type: .installComponent,
                serviceID: nil
            )

        case .installMissingComponents:
            ServiceRecipe(
                id: "install-missing-components",
                type: .installComponent,
                serviceID: nil
            )

        case .createConfigDirectories:
            ServiceRecipe(
                id: "create-config-directories",
                type: .installComponent,
                serviceID: nil
            )

        case .activateVHIDDeviceManager:
            ServiceRecipe(
                id: "activate-vhid-manager",
                type: .installComponent,
                serviceID: nil
            )

        case .repairVHIDDaemonServices:
            ServiceRecipe(
                id: "repair-vhid-daemon-services",
                type: .installComponent,
                serviceID: nil
            )

        case .enableTCPServer:
            ServiceRecipe(
                id: "enable-tcp-server",
                type: .installComponent,
                serviceID: nil
            )

        case .setupTCPAuthentication:
            ServiceRecipe(
                id: "setup-tcp-authentication",
                type: .installComponent,
                serviceID: nil
            )

        case .regenerateCommServiceConfiguration:
            ServiceRecipe(
                id: "regenerate-comm-service-config",
                type: .installComponent,
                serviceID: nil
            )

        case .restartCommServer:
            ServiceRecipe(
                id: "restart-comm-server",
                type: .installComponent,
                serviceID: nil
            )

        case .adoptOrphanedProcess:
            ServiceRecipe(
                id: "adopt-orphaned-process",
                type: .installComponent,
                serviceID: nil
            )

        case .replaceOrphanedProcess:
            ServiceRecipe(
                id: "replace-orphaned-process",
                type: .installComponent,
                serviceID: nil
            )

        case .replaceKanataWithBundled:
            ServiceRecipe(
                id: "replace-kanata-with-bundled",
                type: .installComponent,
                serviceID: nil
            )

        case .synchronizeConfigPaths:
            ServiceRecipe(
                id: "synchronize-config-paths",
                type: .checkRequirement,
                serviceID: nil
            )
        }
    }

    // MARK: - Recipe Ordering

    /// Order recipes respecting dependencies
    func orderRecipes(_ recipes: [ServiceRecipe]) -> [ServiceRecipe] {
        // Simple topological sort - for now, just return in order
        // TODO: Implement proper dependency resolution if needed
        recipes
    }

    /// Map AutoFixAction to recipe ID
    func recipeIDForAction(_ action: AutoFixAction) -> String {
        switch action {
        case .installLaunchDaemonServices:
            "install-launch-daemon-services"
        case .installBundledKanata:
            "install-bundled-kanata"
        case .installCorrectVHIDDriver:
            "install-correct-vhid-driver"
        case .installLogRotation:
            "install-log-rotation"
        case .installPrivilegedHelper:
            "install-privileged-helper"
        case .reinstallPrivilegedHelper:
            "reinstall-privileged-helper"
        case .startKarabinerDaemon:
            "start-karabiner-daemon"
        case .restartUnhealthyServices:
            "restart-unhealthy-services"
        case .terminateConflictingProcesses:
            "terminate-conflicting-processes"
        case .fixDriverVersionMismatch:
            "fix-driver-version-mismatch"
        case .installMissingComponents:
            "install-missing-components"
        case .restartVirtualHIDDaemon:
            // restartVirtualHIDDaemon maps to restartUnhealthyServices recipe
            "restart-unhealthy-services"
        case .createConfigDirectories:
            "create-config-directories"
        case .activateVHIDDeviceManager:
            "activate-vhid-manager"
        case .repairVHIDDaemonServices:
            "repair-vhid-daemon-services"
        case .enableTCPServer:
            "enable-tcp-server"
        case .setupTCPAuthentication:
            "setup-tcp-authentication"
        case .regenerateCommServiceConfiguration:
            "regenerate-comm-service-config"
        case .restartCommServer:
            "restart-comm-server"
        case .adoptOrphanedProcess:
            "adopt-orphaned-process"
        case .replaceOrphanedProcess:
            "replace-orphaned-process"
        case .replaceKanataWithBundled:
            "replace-kanata-with-bundled"
        case .synchronizeConfigPaths:
            "synchronize-config-paths"
        }
    }
}

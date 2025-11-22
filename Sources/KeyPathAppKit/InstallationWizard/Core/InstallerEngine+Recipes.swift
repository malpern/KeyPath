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
      return ServiceRecipe(
        id: "install-launch-daemon-services",
        type: .installService,
        serviceID: nil,
        launchctlActions: [
          .bootstrap(serviceID: "com.keypath.kanata"),
          .bootstrap(serviceID: "com.keypath.vhid-daemon"),
          .bootstrap(serviceID: "com.keypath.vhid-manager")
        ],
        healthCheck: HealthCheckCriteria(serviceID: "com.keypath.kanata", shouldBeRunning: true)
      )

    case .installBundledKanata:
      return ServiceRecipe(
        id: "install-bundled-kanata",
        type: .installComponent,
        serviceID: nil
      )

    case .installCorrectVHIDDriver:
      return ServiceRecipe(
        id: "install-correct-vhid-driver",
        type: .installComponent,
        serviceID: nil
      )

    case .installLogRotation:
      return ServiceRecipe(
        id: "install-log-rotation",
        type: .installComponent,
        serviceID: nil
      )

    case .installPrivilegedHelper:
      return ServiceRecipe(
        id: "install-privileged-helper",
        type: .installService,
        serviceID: "com.keypath.KeyPath.helper"
      )

    case .reinstallPrivilegedHelper:
      return ServiceRecipe(
        id: "reinstall-privileged-helper",
        type: .installService,
        serviceID: "com.keypath.KeyPath.helper"
      )

    case .startKarabinerDaemon:
      return ServiceRecipe(
        id: "start-karabiner-daemon",
        type: .restartService,
        serviceID: "com.keypath.kanata",
        launchctlActions: [.kickstart(serviceID: "com.keypath.kanata")],
        healthCheck: HealthCheckCriteria(serviceID: "com.keypath.kanata", shouldBeRunning: true)
      )

    case .restartUnhealthyServices:
      return ServiceRecipe(
        id: "restart-unhealthy-services",
        type: .restartService,
        serviceID: nil
      )
    case .restartVirtualHIDDaemon:
      // Same recipe as restartUnhealthyServices (verified restart path)
      return ServiceRecipe(
        id: "restart-unhealthy-services",
        type: .restartService,
        serviceID: nil
      )

    case .terminateConflictingProcesses:
      return ServiceRecipe(
        id: "terminate-conflicting-processes",
        type: .checkRequirement,
        serviceID: nil
      )

    case .fixDriverVersionMismatch:
      return ServiceRecipe(
        id: "fix-driver-version-mismatch",
        type: .installComponent,
        serviceID: nil
      )

    case .installMissingComponents:
      return ServiceRecipe(
        id: "install-missing-components",
        type: .installComponent,
        serviceID: nil
      )

    case .createConfigDirectories:
      return ServiceRecipe(
        id: "create-config-directories",
        type: .installComponent,
        serviceID: nil
      )

    case .activateVHIDDeviceManager:
      return ServiceRecipe(
        id: "activate-vhid-manager",
        type: .installComponent,
        serviceID: nil
      )

    case .repairVHIDDaemonServices:
      return ServiceRecipe(
        id: "repair-vhid-daemon-services",
        type: .installComponent,
        serviceID: nil
      )

    case .enableTCPServer:
      return ServiceRecipe(
        id: "enable-tcp-server",
        type: .installComponent,
        serviceID: nil
      )

    case .setupTCPAuthentication:
      return ServiceRecipe(
        id: "setup-tcp-authentication",
        type: .installComponent,
        serviceID: nil
      )

    case .regenerateCommServiceConfiguration:
      return ServiceRecipe(
        id: "regenerate-comm-service-config",
        type: .installComponent,
        serviceID: nil
      )

    case .restartCommServer:
      return ServiceRecipe(
        id: "restart-comm-server",
        type: .installComponent,
        serviceID: nil
      )

    case .adoptOrphanedProcess:
      return ServiceRecipe(
        id: "adopt-orphaned-process",
        type: .installComponent,
        serviceID: nil
      )

    case .replaceOrphanedProcess:
      return ServiceRecipe(
        id: "replace-orphaned-process",
        type: .installComponent,
        serviceID: nil
      )

    case .replaceKanataWithBundled:
      return ServiceRecipe(
        id: "replace-kanata-with-bundled",
        type: .installComponent,
        serviceID: nil
      )

    case .synchronizeConfigPaths:
      return ServiceRecipe(
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
      return "install-launch-daemon-services"
    case .installBundledKanata:
      return "install-bundled-kanata"
    case .installCorrectVHIDDriver:
      return "install-correct-vhid-driver"
    case .installLogRotation:
      return "install-log-rotation"
    case .installPrivilegedHelper:
      return "install-privileged-helper"
    case .reinstallPrivilegedHelper:
      return "reinstall-privileged-helper"
    case .startKarabinerDaemon:
      return "start-karabiner-daemon"
    case .restartUnhealthyServices:
      return "restart-unhealthy-services"
    case .terminateConflictingProcesses:
      return "terminate-conflicting-processes"
    case .fixDriverVersionMismatch:
      return "fix-driver-version-mismatch"
    case .installMissingComponents:
      return "install-missing-components"
    case .restartVirtualHIDDaemon:
      // restartVirtualHIDDaemon maps to restartUnhealthyServices recipe
      return "restart-unhealthy-services"
    case .createConfigDirectories:
      return "create-config-directories"
    case .activateVHIDDeviceManager:
      return "activate-vhid-manager"
    case .repairVHIDDaemonServices:
      return "repair-vhid-daemon-services"
    case .enableTCPServer:
      return "enable-tcp-server"
    case .setupTCPAuthentication:
      return "setup-tcp-authentication"
    case .regenerateCommServiceConfiguration:
      return "regenerate-comm-service-config"
    case .restartCommServer:
      return "restart-comm-server"
    case .adoptOrphanedProcess:
      return "adopt-orphaned-process"
    case .replaceOrphanedProcess:
      return "replace-orphaned-process"
    case .replaceKanataWithBundled:
      return "replace-kanata-with-bundled"
    case .synchronizeConfigPaths:
      return "synchronize-config-paths"
    }
  }
}

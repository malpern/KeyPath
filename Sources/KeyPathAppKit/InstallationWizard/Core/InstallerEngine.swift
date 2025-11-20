import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

/// Façade for installer operations
/// Provides a simple, unified API for installation, repair, and uninstallation
/// Wraps existing installer logic (LaunchDaemonInstaller, WizardAutoFixer, etc.)
@MainActor
public final class InstallerEngine {
  // MARK: - Dependencies

  /// System validator for detecting current system state
  private let systemValidator: SystemValidator

  /// System requirements checker for compatibility info
  private let systemRequirements: SystemRequirements

  /// Create a new installer engine
  /// No DI initially - calls singletons directly
  public init() {
    // Create ProcessLifecycleManager for SystemValidator
    let processManager = ProcessLifecycleManager()

    // Create SystemValidator (stateless, can be reused)
    systemValidator = SystemValidator(processLifecycleManager: processManager)

    // Create SystemRequirements instance
    systemRequirements = SystemRequirements()

    AppLogger.shared.log("🔧 [InstallerEngine] Initialized")
  }

  // MARK: - Public API

  /// Capture current system state
  /// Returns: Read-only snapshot of service states, file/permission status, and helper availability
  public func inspectSystem() async -> SystemContext {
    AppLogger.shared.log("🔍 [InstallerEngine] Starting inspectSystem()")

    // Phase 2: Wire up SystemValidator to get system snapshot
    let snapshot = await systemValidator.checkSystem()

    // Get system compatibility info from SystemRequirements
    let systemInfo = systemRequirements.getSystemInfo()

    // Convert SystemInfo to EngineSystemInfo
    let engineSystemInfo = EngineSystemInfo(
      macOSVersion: systemInfo.macosVersion.versionString,
      driverCompatible: systemInfo.compatibilityResult.isCompatible
    )

    // Convert SystemSnapshot to SystemContext
    let context = SystemContext(
      permissions: snapshot.permissions,
      services: snapshot.health,
      conflicts: snapshot.conflicts,
      components: snapshot.components,
      helper: snapshot.helper,
      system: engineSystemInfo,
      timestamp: snapshot.timestamp
    )

    AppLogger.shared.log(
      "✅ [InstallerEngine] inspectSystem() complete - ready=\(snapshot.isReady), blocking=\(snapshot.blockingIssues.count)"
    )
    return context
  }

  /// Create an execution plan without running it
  /// Returns: Ordered list of operations tailored to the observed context.
  /// If prerequisites are unmet, the plan will be marked as `.blocked` with details about missing requirements.
  public func makePlan(for intent: InstallIntent, context: SystemContext) async -> InstallPlan {
    AppLogger.shared.log("📋 [InstallerEngine] Starting makePlan(for: \(intent), context:)")

    // Phase 3: Check requirements first
    if let blockingRequirement = await checkRequirements(for: intent, context: context) {
      AppLogger.shared.log(
        "⚠️ [InstallerEngine] Plan blocked by requirement: \(blockingRequirement.name)")
      return InstallPlan(
        recipes: [],
        status: .blocked(requirement: blockingRequirement),
        intent: intent,
        blockedBy: blockingRequirement,
        metadata: PlanMetadata()
      )
    }

    // Determine actions needed based on intent and context
    let actions = determineActions(for: intent, context: context)
    AppLogger.shared.log(
      "📋 [InstallerEngine] Determined \(actions.count) actions for intent: \(intent)")

    // Generate recipes from actions
    let recipes = generateRecipes(from: actions, context: context)
    AppLogger.shared.log("📋 [InstallerEngine] Generated \(recipes.count) recipes")

    // Order recipes respecting dependencies
    let orderedRecipes = orderRecipes(recipes)

    let plan = InstallPlan(
      recipes: orderedRecipes,
      status: .ready,
      intent: intent,
      blockedBy: nil,
      metadata: PlanMetadata(promptsNeeded: actions.contains { actionNeedsPrompt($0) })
    )

    AppLogger.shared.log(
      "✅ [InstallerEngine] makePlan() complete - status: \(plan.status), recipes: \(plan.recipes.count)"
    )
    return plan
  }

  // MARK: - Requirement Checking

  /// Check if requirements are met for the given intent
  /// Returns: Blocking requirement if any, nil if all requirements met
  private func checkRequirements(for intent: InstallIntent, context: SystemContext) async
    -> Requirement?
  {
    // For inspectOnly, no requirements needed
    if intent == .inspectOnly {
      return nil
    }

    // Check admin privileges availability (can we request them?)
    // Note: We don't actually request them here, just check if we can
    // Authorization Services will prompt when needed

    // Check that system directories exist (not writable - installation uses admin privileges)
    let launchDaemonsDir = "/Library/LaunchDaemons"
    if !FileManager.default.fileExists(atPath: launchDaemonsDir) {
      return Requirement(
        name: "LaunchDaemons directory missing",
        status: .blocked
      )
    }

    // Check helper registration (for install/repair)
    if intent == .install || intent == .repair {
      if !context.helper.isReady {
        // Helper not ready - check if SMAppService approval is needed
        // This is a soft requirement - we can proceed but may need approval
      }
    }

    // All requirements met
    return nil
  }

  // MARK: - Action Determination

  /// Determine which actions are needed based on intent and context
  private func determineActions(for intent: InstallIntent, context: SystemContext)
    -> [AutoFixAction]
  {
    // Use shared ActionDeterminer to avoid duplication
    ActionDeterminer.determineActions(for: intent, context: context)
  }

  // MARK: - Recipe Generation

  /// Generate ServiceRecipes from AutoFixActions
  private func generateRecipes(from actions: [AutoFixAction], context: SystemContext)
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
  private func recipeForAction(_ action: AutoFixAction, context _: SystemContext) -> ServiceRecipe?
  {
    switch action {
    case .installLaunchDaemonServices:
      return ServiceRecipe(
        id: "install-launch-daemon-services",
        type: .installService,
        serviceID: nil,
        launchctlActions: [
          .bootstrap(serviceID: "com.keypath.kanata"),
          .bootstrap(serviceID: "com.keypath.vhid-daemon"),
          .bootstrap(serviceID: "com.keypath.vhid-manager"),
        ],
        healthCheck: HealthCheckCriteria(serviceID: "com.keypath.kanata", shouldBeRunning: true)
      )

    case .installBundledKanata:
      return ServiceRecipe(
        id: "install-bundled-kanata",
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
    case .installCorrectVHIDDriver:
      return ServiceRecipe(
        id: "install-correct-vhid-driver",
        type: .installComponent,
        serviceID: nil
      )

    case .installMissingComponents:
      return ServiceRecipe(
        id: "install-missing-components",
        type: .installComponent,
        serviceID: nil
      )

    default:
      // For now, skip actions we haven't mapped yet
      AppLogger.shared.log("⚠️ [InstallerEngine] Action not yet mapped to recipe: \(action)")
      return nil
    }
  }

  // MARK: - Recipe Ordering

  /// Order recipes respecting dependencies
  private func orderRecipes(_ recipes: [ServiceRecipe]) -> [ServiceRecipe] {
    // Simple topological sort - for now, just return in order
    // TODO: Implement proper dependency resolution if needed
    recipes
  }

  // MARK: - Helper Methods

  /// Check if an action needs user prompts
  private func actionNeedsPrompt(_ action: AutoFixAction) -> Bool {
    switch action {
    case .installPrivilegedHelper, .reinstallPrivilegedHelper:
      true  // May need SMAppService approval
    default:
      false
    }
  }

  /// Execute the planned operations
  /// Returns: Structured report with success/failure details and final state.
  /// If the plan was blocked by unmet requirements, execution stops immediately and the report indicates which requirement failed.
  public func execute(plan: InstallPlan, using broker: PrivilegeBroker) async -> InstallerReport {
    AppLogger.shared.log("⚙️ [InstallerEngine] Starting execute(plan:, using:)")

    // Check if plan is blocked
    if case .blocked(let requirement) = plan.status {
      AppLogger.shared.log(
        "⚠️ [InstallerEngine] Plan is blocked by requirement: \(requirement.name)")
      return InstallerReport(
        success: false,
        failureReason: "Plan blocked by requirement: \(requirement.name)",
        unmetRequirements: [requirement],
        executedRecipes: []
      )
    }

    // Execute recipes in order
    var executedRecipes: [RecipeResult] = []
    var firstFailure: (recipe: ServiceRecipe, error: Error)?

    for recipe in plan.recipes {
      AppLogger.shared.log(
        "⚙️ [InstallerEngine] Executing recipe: \(recipe.id) (type: \(recipe.type))")

      let startTime = Date()
      var recipeError: String?

      do {
        // Execute recipe based on type
        try await executeRecipe(recipe, using: broker)

        // Perform health check if specified
        if let healthCheck = recipe.healthCheck {
          let isHealthy = await verifyHealthCheck(healthCheck)
          if !isHealthy {
            throw InstallerError.healthCheckFailed(
              "Health check failed for service: \(healthCheck.serviceID)"
            )
          }
        }

        let duration = Date().timeIntervalSince(startTime)
        executedRecipes.append(
          RecipeResult(
            recipeID: recipe.id,
            success: true,
            error: nil,
            duration: duration
          ))
        AppLogger.shared.log("✅ [InstallerEngine] Recipe \(recipe.id) completed successfully")

      } catch {
        // Stop on first failure
        let duration = Date().timeIntervalSince(startTime)
        recipeError = error.localizedDescription
        executedRecipes.append(
          RecipeResult(
            recipeID: recipe.id,
            success: false,
            error: recipeError,
            duration: duration
          ))

        AppLogger.shared.log(
          "❌ [InstallerEngine] Recipe \(recipe.id) failed: \(recipeError ?? "Unknown error")")

        firstFailure = (recipe, error)
        break  // Stop execution on first failure
      }
    }

    // Generate report
    let success = firstFailure == nil
    let report = InstallerReport(
      success: success,
      failureReason: firstFailure.map {
        "Recipe '\($0.recipe.id)' failed: \($0.error.localizedDescription)"
      },
      unmetRequirements: success ? [] : plan.blockedBy.map { [$0] } ?? [],
      executedRecipes: executedRecipes
    )

    AppLogger.shared.log(
      "✅ [InstallerEngine] execute() complete - success: \(success), recipes executed: \(executedRecipes.count)"
    )
    return report
  }

  // MARK: - Recipe Execution

  /// Execute a single recipe
  private func executeRecipe(_ recipe: ServiceRecipe, using broker: PrivilegeBroker) async throws {
    switch recipe.type {
    case .installService:
      try await executeInstallService(recipe, using: broker)

    case .restartService:
      try await executeRestartService(recipe, using: broker)

    case .installComponent:
      try await executeInstallComponent(recipe, using: broker)

    case .writeConfig:
      try await executeWriteConfig(recipe, using: broker)

    case .checkRequirement:
      try await executeCheckRequirement(recipe, using: broker)
    }
  }

  /// Execute installService recipe
  private func executeInstallService(_: ServiceRecipe, using broker: PrivilegeBroker) async throws {
    // Install all LaunchDaemon services
    // Note: Individual service installation would require plistPath, which isn't in recipe yet
    try await broker.installAllLaunchDaemonServices()
  }

  /// Execute restartService recipe
  private func executeRestartService(_ recipe: ServiceRecipe, using broker: PrivilegeBroker)
    async throws
  {
    if let serviceID = recipe.serviceID, serviceID == "com.keypath.kanata" {
      // Restart Karabiner daemon with verification
      let success = try await broker.restartKarabinerDaemonVerified()
      if !success {
        throw InstallerError.healthCheckFailed("Karabiner daemon restart verification failed")
      }
    } else {
      // Restart all unhealthy services
      try await broker.restartUnhealthyServices()
    }
  }

  /// Execute installComponent recipe
  private func executeInstallComponent(_ recipe: ServiceRecipe, using broker: PrivilegeBroker)
    async throws
  {
    // Map recipe ID to component installation method
    switch recipe.id {
    case "install-bundled-kanata":
      try await broker.installBundledKanata()

    case "install-correct-vhid-driver":
      try await broker.downloadAndInstallCorrectVHIDDriver()

    case "fix-driver-version-mismatch":
      try await broker.downloadAndInstallCorrectVHIDDriver()

    case "install-missing-components":
      // Install all missing components (Kanata + drivers)
      try await broker.installBundledKanata()
      try await broker.downloadAndInstallCorrectVHIDDriver()

    default:
      // Unknown component recipe
      AppLogger.shared.log("⚠️ [InstallerEngine] Unknown component recipe: \(recipe.id)")
      throw InstallerError.unknownRecipe("Unknown component recipe: \(recipe.id)")
    }
  }

  /// Execute writeConfig recipe
  private func executeWriteConfig(_ recipe: ServiceRecipe, using _: PrivilegeBroker) async throws {
    // Write config recipes not yet implemented
    // Would write plistContent to appropriate location
    AppLogger.shared.log("⚠️ [InstallerEngine] writeConfig recipe not yet implemented: \(recipe.id)")
    throw InstallerError.unknownRecipe("writeConfig recipe not yet implemented: \(recipe.id)")
  }

  /// Execute checkRequirement recipe
  private func executeCheckRequirement(_ recipe: ServiceRecipe, using broker: PrivilegeBroker)
    async throws
  {
    // Check requirement recipes (e.g., terminate conflicting processes)
    switch recipe.id {
    case "terminate-conflicting-processes":
      // Kill all Kanata processes (conflict resolution)
      try await broker.killAllKanataProcesses()

    default:
      AppLogger.shared.log("⚠️ [InstallerEngine] Unknown requirement check recipe: \(recipe.id)")
      throw InstallerError.unknownRecipe("Unknown requirement check recipe: \(recipe.id)")
    }
  }

  /// Verify health check criteria
  private func verifyHealthCheck(_ criteria: HealthCheckCriteria) async -> Bool {
    // Use LaunchDaemonInstaller to check service health
    let installer = LaunchDaemonInstaller()
    return installer.isServiceHealthy(serviceID: criteria.serviceID)
  }

  /// Convenience wrapper that chains inspectSystem() → makePlan() → execute() internally
  /// Useful for CLI "one-button repair" automation or simple GUI flows
  public func run(intent: InstallIntent, using broker: PrivilegeBroker) async -> InstallerReport {
    AppLogger.shared.log("🚀 [InstallerEngine] Starting run(intent: \(intent), using:)")

    if intent == .uninstall {
      AppLogger.shared.log(
        "🗑️ [InstallerEngine] Delegating uninstall intent to uninstall(deleteConfig:, using:)")
      return await uninstall(deleteConfig: false, using: broker)
    }

    // Chain the steps
    let context = await inspectSystem()
    let plan = await makePlan(for: intent, context: context)
    let report = await execute(plan: plan, using: broker)

    AppLogger.shared.log("✅ [InstallerEngine] run() complete - success: \(report.success)")
    return report
  }

  /// Execute uninstall via the existing coordinator (placeholder until uninstall recipes exist)
  public func uninstall(deleteConfig: Bool, using broker: PrivilegeBroker) async -> InstallerReport
  {
    AppLogger.shared.log("🗑️ [InstallerEngine] Starting uninstall (deleteConfig: \(deleteConfig))")
    _ = broker  // Reserved for future privileged uninstall steps

    let start = Date()
    let coordinator = UninstallCoordinator()
    let success = await coordinator.uninstall(deleteConfig: deleteConfig)
    let duration = Date().timeIntervalSince(start)
    let failure = coordinator.lastError ?? "Uninstall failed"

    let recipeID = deleteConfig ? "uninstall-with-config" : "uninstall"
    let recipeResult = RecipeResult(
      recipeID: recipeID,
      success: success,
      error: success ? nil : failure,
      duration: duration
    )

    let report = InstallerReport(
      success: success,
      failureReason: success ? nil : failure,
      executedRecipes: [recipeResult],
      logs: coordinator.logLines
    )

    AppLogger.shared.log("🗑️ [InstallerEngine] uninstall complete - success: \(success)")
    return report
  }

  /// Execute a single AutoFixAction by generating a plan that includes that specific action
  /// This is useful for GUI single-action fixes where the user clicks a specific "Fix" button
  /// Note: Some actions (like installLaunchDaemonServices) are only in install plans, not repair plans
  public func runSingleAction(_ action: AutoFixAction, using broker: PrivilegeBroker) async
    -> InstallerReport
  {
    AppLogger.shared.log("🔧 [InstallerEngine] runSingleAction(\(action), using:) starting")
    let context = await inspectSystem()
    
    // Determine which intent would include this action
    // installLaunchDaemonServices is install-specific, others are typically repair
    let intent: InstallIntent = action == .installLaunchDaemonServices ? .install : .repair
    
    let basePlan = await makePlan(for: intent, context: context)

    // Filter recipes to only include ones matching the action
    let actionRecipeID = recipeIDForAction(action)
    let filteredRecipes = basePlan.recipes.filter { $0.id == actionRecipeID }

    let finalRecipes: [ServiceRecipe]
    if filteredRecipes.isEmpty {
      // If not found in the plan, generate a recipe directly for this action
      // This handles edge cases where the action isn't included in the intent's plan
      if let directRecipe = recipeForAction(action, context: context) {
        AppLogger.shared.log("🔧 [InstallerEngine] Generating direct recipe for action: \(action)")
        finalRecipes = [directRecipe]
      } else {
        AppLogger.shared.log("⚠️ [InstallerEngine] No recipe available for action: \(action)")
        return InstallerReport(
          success: false,
          failureReason: "No recipe available for action: \(action)",
          executedRecipes: [],
          logs: []
        )
      }
    } else {
      finalRecipes = filteredRecipes
    }

    // Create a filtered plan with just the matching recipes
    // If we generated a direct recipe (because it wasn't in the base plan), use .ready status
    // The base plan might be blocked due to requirements, but we can still attempt the action
    // with admin privileges (which will be requested during execution)
    let planStatus: PlanStatus = filteredRecipes.isEmpty && !finalRecipes.isEmpty
      ? .ready  // Direct recipe generated - allow execution
      : basePlan.status  // Use base plan status for filtered recipes
    let filteredPlan = InstallPlan(
      recipes: finalRecipes,
      status: planStatus,
      intent: basePlan.intent,
      blockedBy: filteredRecipes.isEmpty && !finalRecipes.isEmpty ? nil : basePlan.blockedBy,
      metadata: basePlan.metadata
    )

    let report = await execute(plan: filteredPlan, using: broker)
    AppLogger.shared.log(
      "✅ [InstallerEngine] runSingleAction(\(action), using:) complete - success: \(report.success)"
    )
    return report
  }

  /// Map AutoFixAction to recipe ID
  private func recipeIDForAction(_ action: AutoFixAction) -> String {
    switch action {
    case .installLaunchDaemonServices:
      return "install-launch-daemon-services"
    case .installBundledKanata:
      return "install-bundled-kanata"
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
    case .installCorrectVHIDDriver:
      return "install-correct-vhid-driver"
    case .installMissingComponents:
      return "install-missing-components"
    case .restartVirtualHIDDaemon:
      // restartVirtualHIDDaemon maps to restartUnhealthyServices recipe
      return "restart-unhealthy-services"
    case .createConfigDirectories:
      return "install-missing-components"
    case .activateVHIDDeviceManager:
      return "install-missing-components"
    case .repairVHIDDaemonServices:
      return "install-launch-daemon-services"
    default:
      AppLogger.shared.log("⚠️ [InstallerEngine] Unknown action for recipe mapping: \(action)")
      return "unknown-action"
    }
  }
}

// MARK: - Installer Errors

enum InstallerError: LocalizedError {
  case healthCheckFailed(String)
  case unknownRecipe(String)

  var errorDescription: String? {
    switch self {
    case .healthCheckFailed(let message):
      message
    case .unknownRecipe(let message):
      message
    }
  }
}

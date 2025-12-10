import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

// Protocol for privileged routing used by Services to allow test stubs
public protocol InstallerEnginePrivilegedRouting: AnyObject {
    func uninstallVirtualHIDDrivers(using broker: PrivilegeBroker) async throws
    func disableKarabinerGrabber(using broker: PrivilegeBroker) async throws
    func restartKarabinerDaemon(using broker: PrivilegeBroker) async throws -> Bool
}

/// Façade for installer operations.
///
/// - Provides a stable, unified API for install/repair/uninstall flows.
/// - Wraps existing installer logic (LaunchDaemonInstaller, WizardAutoFixer, etc.).
/// - Backward-compatible with legacy wizard outputs (SystemContext/SystemContextAdapter).
@MainActor
public final class InstallerEngine {
    // MARK: - Dependencies

    /// System validator for detecting current system state
    private let systemValidator: SystemValidator

    /// System requirements checker for compatibility info
    private let systemRequirements: SystemRequirements

    /// Internal designated initializer to share construction logic
    init(
        processLifecycleManager: ProcessLifecycleManager,
        kanataManager: RuntimeCoordinator? = nil
    ) {
        // Create SystemValidator (stateless, can be reused)
        systemValidator = SystemValidator(
            processLifecycleManager: processLifecycleManager,
            kanataManager: kanataManager
        )

        // Create SystemRequirements instance
        systemRequirements = SystemRequirements()
        AppLogger.shared.log("🔧 [InstallerEngine] Initialized")
    }

    /// Public initializer for app/CLI callers (no DI needed).
    public convenience init() {
        self.init(processLifecycleManager: ProcessLifecycleManager(), kanataManager: nil)
    }

    /// Internal convenience initializer used by the wizard to surface live Kanata health.
    convenience init(kanataManager: RuntimeCoordinator) {
        self.init(processLifecycleManager: ProcessLifecycleManager(), kanataManager: kanataManager)
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

    /// Create an execution plan without running it.
    /// Returns an ordered list of operations tailored to the observed context. If prerequisites are unmet, the plan
    /// is marked `.blocked` with the missing requirement.
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
        -> Requirement? {
        // For inspectOnly, no requirements needed
        if intent == .inspectOnly {
            return nil
        }

        // Check admin privileges availability (can we request them?)
        // Note: We don't actually request them here, just check if we can
        // Authorization Services will prompt when needed

        // Check that system directories exist (not writable - installation uses admin privileges)
        let launchDaemonsDir = KeyPathConstants.System.launchDaemonsDir
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

    // Note: Action determination logic is in InstallerEngine+Recipes.swift

    // MARK: - Recipe Generation

    // Note: Recipe generation logic is in InstallerEngine+Recipes.swift

    // MARK: - Recipe Ordering

    // Note: Recipe ordering logic is in InstallerEngine+Recipes.swift

    // MARK: - Helper Methods

    /// Check if an action needs user prompts
    private func actionNeedsPrompt(_ action: AutoFixAction) -> Bool {
        switch action {
        case .installPrivilegedHelper, .reinstallPrivilegedHelper:
            true // May need SMAppService approval
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
        if case let .blocked(requirement) = plan.status {
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
        var allLogs: [String] = []

        for recipe in plan.recipes {
            AppLogger.shared.log(
                "⚙️ [InstallerEngine] Executing recipe: \(recipe.id) (type: \(recipe.type))")

            let startTime = Date()
            var recipeError: String?
            var recipeLogs: [String] = []
            var commandsRun: [String] = []

            recipeLogs.append("[\(recipe.id)] Starting execution...")

            do {
                // Execute recipe based on type, capturing execution details
                let executionResult = try await executeRecipeWithDetails(recipe, using: broker)
                recipeLogs.append(contentsOf: executionResult.logs)
                commandsRun.append(contentsOf: executionResult.commands)

                // Perform health check if specified
                if let healthCheck = recipe.healthCheck {
                    recipeLogs.append("[\(recipe.id)] Running health check for \(healthCheck.serviceID)...")
                    let isHealthy = await verifyHealthCheck(healthCheck)
                    if !isHealthy {
                        throw InstallerError.healthCheckFailed(
                            "Health check failed for service: \(healthCheck.serviceID)"
                        )
                    }
                    recipeLogs.append("[\(recipe.id)] Health check passed")
                }

                let duration = Date().timeIntervalSince(startTime)
                recipeLogs.append("[\(recipe.id)] Completed in \(String(format: "%.2f", duration))s")
                allLogs.append(contentsOf: recipeLogs)

                executedRecipes.append(
                    RecipeResult(
                        recipeID: recipe.id,
                        success: true,
                        error: nil,
                        duration: duration,
                        logs: recipeLogs,
                        commandsRun: commandsRun
                    ))
                AppLogger.shared.log("✅ [InstallerEngine] Recipe \(recipe.id) completed successfully")

            } catch {
                // Stop on first failure
                let duration = Date().timeIntervalSince(startTime)
                recipeError = error.localizedDescription
                recipeLogs.append("[\(recipe.id)] FAILED: \(recipeError ?? "Unknown error")")
                allLogs.append(contentsOf: recipeLogs)

                executedRecipes.append(
                    RecipeResult(
                        recipeID: recipe.id,
                        success: false,
                        error: recipeError,
                        duration: duration,
                        logs: recipeLogs,
                        commandsRun: commandsRun
                    ))

                AppLogger.shared.log(
                    "❌ [InstallerEngine] Recipe \(recipe.id) failed: \(recipeError ?? "Unknown error")")

                firstFailure = (recipe, error)
                break // Stop execution on first failure
            }
        }

        // Generate report with aggregated logs
        let success = firstFailure == nil
        let report = InstallerReport(
            success: success,
            failureReason: firstFailure.map {
                "Recipe '\($0.recipe.id)' failed: \($0.error.localizedDescription)"
            },
            unmetRequirements: success ? [] : plan.blockedBy.map { [$0] } ?? [],
            executedRecipes: executedRecipes,
            logs: allLogs
        )

        AppLogger.shared.log(
            "✅ [InstallerEngine] execute() complete - success: \(success), recipes executed: \(executedRecipes.count)"
        )
        return report
    }

    // MARK: - Recipe Execution

    /// Result of executing a recipe with detailed logs
    private struct RecipeExecutionResult {
        let logs: [String]
        let commands: [String]
    }

    /// Execute a single recipe and capture execution details
    private func executeRecipeWithDetails(_ recipe: ServiceRecipe, using broker: PrivilegeBroker) async throws -> RecipeExecutionResult {
        var logs: [String] = []
        var commands: [String] = []

        switch recipe.type {
        case .installService:
            logs.append("Checking VHID Manager activation status...")
            let vhidManager = VHIDDeviceManager()
            if !vhidManager.detectActivation() {
                logs.append("VHID Manager not activated - will activate first")
            }
            logs.append("Installing LaunchDaemon services...")
            commands.append("launchctl bootstrap system /Library/LaunchDaemons/com.keypath.*")
            try await executeInstallService(recipe, using: broker)
            logs.append("LaunchDaemon services installed")

        case .restartService:
            logs.append("Checking VHID Manager activation status...")
            if let serviceID = recipe.serviceID {
                logs.append("Restarting service: \(serviceID)")
                commands.append("launchctl kickstart -k system/\(serviceID)")
            } else {
                logs.append("Restarting unhealthy services...")
                commands.append("launchctl kickstart -k system/com.keypath.*")
            }
            try await executeRestartService(recipe, using: broker)
            logs.append("Service restart completed")

        case .installComponent:
            logs.append("Installing component: \(recipe.id)")
            try await executeInstallComponent(recipe, using: broker)
            logs.append("Component installed: \(recipe.id)")

        case .writeConfig:
            logs.append("Writing configuration: \(recipe.id)")
            try await executeWriteConfig(recipe, using: broker)
            logs.append("Configuration written")

        case .checkRequirement:
            logs.append("Checking requirement: \(recipe.id)")
            try await executeCheckRequirement(recipe, using: broker)
            logs.append("Requirement satisfied")
        }

        return RecipeExecutionResult(logs: logs, commands: commands)
    }

    /// Execute a single recipe (legacy method for backward compatibility)
    private func executeRecipe(_ recipe: ServiceRecipe, using broker: PrivilegeBroker) async throws {
        _ = try await executeRecipeWithDetails(recipe, using: broker)
    }

    /// Execute installService recipe
    /// Includes pre-check for VHID Manager activation (per Karabiner documentation)
    private func executeInstallService(_: ServiceRecipe, using broker: PrivilegeBroker) async throws {
        // CRITICAL: Ensure VHID Manager is activated BEFORE installing daemon services
        // Per Karabiner documentation, manager activation must happen before daemon startup
        let vhidManager = VHIDDeviceManager()
        if !vhidManager.detectActivation() {
            AppLogger.shared.log(
                "⚠️ [InstallerEngine] VirtualHID Manager not activated - activating before daemon install")
            try await broker.activateVirtualHIDManager()
            // Wait for activation to take effect
            _ = await WizardSleep.ms(1000) // 1 second

            // Verify activation
            if !vhidManager.detectActivation() {
                AppLogger.shared.log(
                    "⚠️ [InstallerEngine] Manager activation may need user approval - proceeding anyway")
            } else {
                AppLogger.shared.log("✅ [InstallerEngine] Manager activated successfully")
            }
        }

        // Install all LaunchDaemon services
        try await broker.installAllLaunchDaemonServices()
    }

    /// Execute restartService recipe
    /// Includes pre-check for VHID Manager activation (per Karabiner documentation)
    private func executeRestartService(_ recipe: ServiceRecipe, using broker: PrivilegeBroker)
        async throws {
        // Special case: clear startup blocked state before restarting
        if recipe.id == "clear-startup-blocked-state" {
            AppLogger.shared.log("🧹 [InstallerEngine] Clearing startup blocked state files")
            try await broker.clearKanataStartupBlockedState()
        }

        // CRITICAL: Ensure VHID Manager is activated before restarting services
        let vhidManager = VHIDDeviceManager()
        if !vhidManager.detectActivation() {
            AppLogger.shared.log(
                "⚠️ [InstallerEngine] VirtualHID Manager not activated - activating before restart")
            try await broker.activateVirtualHIDManager()
            _ = await WizardSleep.ms(1000) // 1 second
        }

        if let serviceID = recipe.serviceID, serviceID == KeyPathConstants.Bundle.daemonID {
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
        async throws {
        // Map recipe ID to component installation method
        switch recipe.id {
        case "install-bundled-kanata":
            try await broker.installBundledKanata()

        case "install-correct-vhid-driver":
            try await broker.installCorrectVHIDDriver()

        case "install-log-rotation":
            try await broker.installLogRotation()

        case "fix-driver-version-mismatch":
            try await broker.installCorrectVHIDDriver()

        case "install-missing-components":
            // Install all missing components (Kanata + drivers)
            try await broker.installBundledKanata()
            try await broker.installCorrectVHIDDriver()

        case "create-config-directories":
            // No privileged work needed; treated as success (idempotent)
            return

        case "activate-vhid-manager":
            try await broker.activateVirtualHIDManager()

        case "repair-vhid-daemon-services":
            try await broker.repairVHIDDaemonServices()

        case "enable-tcp-server", "setup-tcp-authentication", "regenerate-comm-service-config":
            try await broker.regenerateServiceConfiguration()
            // Keep Kanata running after regeneration so the summary stays green.
            // SMAppService registration often leaves the job unloaded until explicitly kicked.
            _ = await PrivilegedOperationsProvider.shared.startKanataService()

        case "restart-comm-server":
            try await broker.restartUnhealthyServices()
            // Explicitly start Kanata after a restart/fix; without this the daemon may stay
            // unloaded (SMAppService pending) and the summary page bounces the user back.
            _ = await PrivilegedOperationsProvider.shared.startKanataService()

        case "adopt-orphaned-process":
            try await broker.installLaunchDaemonServicesWithoutLoading()

        case "replace-orphaned-process":
            try await broker.killAllKanataProcesses()
            try await broker.installLaunchDaemonServicesWithoutLoading()

        case "replace-kanata-with-bundled":
            try await broker.installBundledKanata()

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
        async throws {
        // Check requirement recipes (e.g., terminate conflicting processes)
        switch recipe.id {
        case "terminate-conflicting-processes":
            // Kill all Kanata processes (conflict resolution)
            try await broker.killAllKanataProcesses()

        case "synchronize-config-paths":
            // No privileged action required; treat as satisfied
            return

        default:
            AppLogger.shared.log("⚠️ [InstallerEngine] Unknown requirement check recipe: \(recipe.id)")
            throw InstallerError.unknownRecipe("Unknown requirement check recipe: \(recipe.id)")
        }
    }

    /// Verify health check criteria
    private func verifyHealthCheck(_ criteria: HealthCheckCriteria) async -> Bool {
        await isServiceHealthy(serviceID: criteria.serviceID)
    }

    // MARK: - Public Health Check API

    /// Check if a specific service is healthy (running and responsive)
    /// Delegates to ServiceHealthChecker (extracted from LaunchDaemonInstaller)
    public func isServiceHealthy(serviceID: String) async -> Bool {
        await ServiceHealthChecker.shared.isServiceHealthy(serviceID: serviceID)
    }

    /// Check if a specific service is loaded (registered with launchd)
    public func isServiceLoaded(serviceID: String) async -> Bool {
        await ServiceHealthChecker.shared.isServiceLoaded(serviceID: serviceID)
    }

    /// Get aggregated status of all KeyPath services
    public func getServiceStatus() async -> LaunchDaemonStatus {
        await ServiceHealthChecker.shared.getServiceStatus()
    }

    /// Check Kanata service health (running + TCP responsive)
    public func checkKanataServiceHealth(tcpPort: Int = 37001) async -> KanataHealthSnapshot {
        let health = await ServiceHealthChecker.shared.checkKanataServiceHealth(tcpPort: tcpPort)
        return KanataHealthSnapshot(isRunning: health.isRunning, isResponding: health.isResponding)
    }

    /// Convenience wrapper that chains inspectSystem() → makePlan() → execute() internally.
    /// Useful for CLI "one-button repair" automation or simple GUI flows.
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
    public func uninstall(deleteConfig: Bool, using broker: PrivilegeBroker) async -> InstallerReport {
        AppLogger.shared.log("🗑️ [InstallerEngine] Starting uninstall (deleteConfig: \(deleteConfig))")
        _ = broker // Reserved for future privileged uninstall steps

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
        -> InstallerReport {
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
        let planStatus: PlanStatus =
            filteredRecipes.isEmpty && !finalRecipes.isEmpty
                ? .ready // Direct recipe generated - allow execution
                : basePlan.status // Use base plan status for filtered recipes
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

    // MARK: - Direct Broker Operations (for operations without AutoFixAction mapping)

    /// Uninstall VirtualHID drivers (removes VHID daemon plists)
    /// Routes via InstallerEngine per AGENTS.md
    public func uninstallVirtualHIDDrivers(using broker: PrivilegeBroker) async throws {
        AppLogger.shared.log("🗑️ [InstallerEngine] Uninstalling VirtualHID drivers")
        try await broker.uninstallVirtualHIDDrivers()
    }

    /// Disable Karabiner grabber (stops conflicting processes)
    /// Routes via InstallerEngine per AGENTS.md
    public func disableKarabinerGrabber(using broker: PrivilegeBroker) async throws {
        AppLogger.shared.log("🔧 [InstallerEngine] Disabling Karabiner grabber")
        try await broker.disableKarabinerGrabber()
    }

    /// Restart Karabiner daemon with verification
    /// Routes via InstallerEngine per AGENTS.md
    public func restartKarabinerDaemon(using broker: PrivilegeBroker) async throws -> Bool {
        AppLogger.shared.log("🔄 [InstallerEngine] Restarting Karabiner daemon")
        return try await broker.restartKarabinerDaemonVerified()
    }

    /// Execute a privileged command via sudo/osascript
    /// Routes via InstallerEngine per AGENTS.md
    public func sudoExecuteCommand(
        _ command: String,
        description: String,
        using broker: PrivilegeBroker
    ) async throws {
        AppLogger.shared.log("🔐 [InstallerEngine] Executing privileged command: \(description)")
        try await broker.sudoExecuteCommand(command, description: description)
    }
}

extension InstallerEngine: InstallerEnginePrivilegedRouting {}

// MARK: - Installer Errors

enum InstallerError: LocalizedError {
    case healthCheckFailed(String)
    case unknownRecipe(String)

    var errorDescription: String? {
        switch self {
        case let .healthCheckFailed(message):
            message
        case let .unknownRecipe(message):
            message
        }
    }
}

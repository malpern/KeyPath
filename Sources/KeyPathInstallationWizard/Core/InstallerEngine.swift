import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore

actor InstallerTransactionGate {
    static let shared = InstallerTransactionGate()

    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isOccupied else {
            isOccupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !waiters.isEmpty else {
            isOccupied = false
            return
        }
        waiters.removeFirst().resume()
    }
}

private enum InstallerTransactionContext {
    @TaskLocal static var isOwned = false
}

/// Protocol for privileged routing used by Services to allow test stubs
public protocol InstallerEnginePrivilegedRouting: AnyObject {
    func uninstallVirtualHIDDrivers(using broker: PrivilegeBroker) async throws
    func disableKarabinerGrabber(using broker: PrivilegeBroker) async throws
    func restartKarabinerDaemon(using broker: PrivilegeBroker) async throws -> Bool
}

/// Façade for installer operations.
///
/// - Provides a stable, unified API for install/repair/uninstall flows.
/// - Wraps extracted services (ServiceBootstrapper, ServiceHealthChecker, etc.).
/// - Projects canonical system evidence into the planner's SystemContext input.
@MainActor
public final class InstallerEngine {
    // MARK: - Dependencies

    /// System validator for detecting current system state.
    /// Lazily resolved: prefers an injected validator, then falls back to
    /// WizardDependencies.systemValidator at call-time (not init-time) so that
    /// InstallerEngine can be created before WizardDependencies is configured.
    private let injectedValidator: (any WizardSystemValidating)?
    private var systemValidator: (any WizardSystemValidating)? {
        injectedValidator ?? WizardDependencies.systemValidator
    }

    /// Internal designated initializer to share construction logic
    public init(
        processLifecycleManager _: ProcessLifecycleManager,
        systemValidator injectedValidator: (any WizardSystemValidating)? = nil
    ) {
        self.injectedValidator = injectedValidator

        AppLogger.shared.log("🔧 [InstallerEngine] Initialized")
    }

    /// Public initializer for app/CLI callers (no DI needed).
    public convenience init() {
        self.init(processLifecycleManager: ProcessLifecycleManager())
    }

    private func withInstallerTransaction<T>(
        _ operation: () async throws -> T
    ) async rethrows -> T {
        if InstallerTransactionContext.isOwned {
            return try await operation()
        }

        await InstallerTransactionGate.shared.acquire()
        return try await InstallerTransactionContext.$isOwned.withValue(true) {
            do {
                let result = try await operation()
                await InstallerTransactionGate.shared.release()
                return result
            } catch {
                await InstallerTransactionGate.shared.release()
                throw error
            }
        }
    }

    // MARK: - Public API

    /// Capture current system state
    /// Returns: Read-only snapshot of service states, file/permission status, and helper availability
    public func inspectSystem(
        freshness: WizardSystemSnapshotFreshness = .fresh
    ) async -> SystemContext {
        AppLogger.shared.log("🔍 [InstallerEngine] Starting inspectSystem()")

        // Phase 2: Wire up SystemValidator to get system snapshot
        guard let validatorInstance = systemValidator else {
            AppLogger.shared.log("⚠️ [InstallerEngine] systemValidator not configured — returning empty context")
            return SystemContext.empty
        }
        let snapshot = await validatorInstance.checkSystem(freshness: freshness)

        let context = SystemContext(snapshot: snapshot)

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
        let decision = InstallerDecisionPipeline.decide(for: intent, context: context)
        let stateMatrixRow = decision.assessment.rawValue
        let stateMatrixPlan = decision.matrixActions.map(\.rawValue)
        let baseMetadata = PlanMetadata(
            stateMatrixRow: stateMatrixRow,
            stateMatrixPlan: stateMatrixPlan
        )

        // Phase 3: Check requirements from the captured context only.
        if let blockingRequirement = checkRequirements(for: intent, context: context) {
            AppLogger.shared.log(
                "⚠️ [InstallerEngine] Plan blocked by requirement: \(blockingRequirement.name)"
            )
            return InstallPlan(
                sourceSnapshotID: context.snapshotID,
                recipes: [],
                status: .blocked(requirement: blockingRequirement),
                intent: intent,
                blockedBy: blockingRequirement,
                metadata: baseMetadata
            )
        }

        // Determine actions needed based on intent and context
        let actions = decision.autoFixActions
        AppLogger.shared.log(
            "📋 [InstallerEngine] Determined \(actions.count) actions for intent: \(intent)"
        )

        // Generate recipes from actions
        let recipes = generateRecipes(from: actions, context: context)
        AppLogger.shared.log("📋 [InstallerEngine] Generated \(recipes.count) recipes")

        // Order recipes respecting dependencies
        let orderedRecipes = orderRecipes(recipes)

        let plan = InstallPlan(
            sourceSnapshotID: context.snapshotID,
            recipes: orderedRecipes,
            status: .ready,
            intent: intent,
            blockedBy: nil,
            metadata: PlanMetadata(
                promptsNeeded: actions.contains { actionNeedsPrompt($0) },
                stateMatrixRow: stateMatrixRow,
                stateMatrixPlan: stateMatrixPlan
            ),
            initialPostconditionStates: postconditionBaseline(
                for: orderedRecipes,
                context: context
            )
        )

        AppLogger.shared.log(
            "✅ [InstallerEngine] makePlan() complete - status: \(plan.status), recipes: \(plan.recipes.count)"
        )
        return plan
    }

    private func postconditionBaseline(
        for recipes: [ServiceRecipe],
        context: SystemContext
    ) -> [InstallerPostcondition: Bool]? {
        guard context.captureStatus.isComplete else { return nil }
        let postconditions = Set(recipes.flatMap(\.expectedPostconditions))
        return Dictionary(uniqueKeysWithValues: postconditions.map { postcondition in
            (postcondition, sessionPostconditionSatisfied(postcondition, by: context))
        })
    }

    // MARK: - Requirement Checking

    /// Check if requirements are met for the given intent
    /// Returns: Blocking requirement if any, nil if all requirements met
    private func checkRequirements(for intent: InstallIntent, context _: SystemContext) -> Requirement? {
        if intent == .uninstall {
            return Requirement(name: "System uninstall is unavailable in the driverless build", status: .blocked)
        }
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
    private func actionNeedsPrompt(_: AutoFixAction) -> Bool {
        false
    }

    /// Execute the planned operations
    /// Returns: Structured report with success/failure details and final state.
    /// If the plan was blocked by unmet requirements, execution stops immediately and the report indicates which requirement failed.
    public func execute(
        plan: InstallPlan,
        using broker: PrivilegeBroker,
        trigger: InstallerRepairTelemetryTrigger = .executePlan
    ) async -> InstallerReport {
        await withInstallerTransaction {
            await executeWithinTransaction(plan: plan, using: broker, trigger: trigger)
        }
    }

    private func executeWithinTransaction(
        plan: InstallPlan,
        using broker: PrivilegeBroker,
        trigger: InstallerRepairTelemetryTrigger
    ) async -> InstallerReport {
        AppLogger.shared.log("⚙️ [InstallerEngine] Starting execute(plan:, using:)")
        let runID = UUID()

        if plan.intent == .uninstall || (plan.intent == .inspectOnly && !plan.recipes.isEmpty) {
            return InstallerReport(
                runID: runID, planID: plan.id, beforeSnapshotID: plan.sourceSnapshotID,
                success: false, completionState: .executionFailed,
                failureReason: "Mutating recipes are unavailable for this intent in the driverless build"
            )
        }

        // Check if plan is blocked
        if case let .blocked(requirement) = plan.status {
            AppLogger.shared.log(
                "⚠️ [InstallerEngine] Plan is blocked by requirement: \(requirement.name)"
            )
            let telemetry = InstallerRepairTelemetryEvent(
                runID: runID,
                planID: plan.id,
                beforeSnapshotID: plan.sourceSnapshotID,
                trigger: trigger,
                intent: plan.intent.telemetryValue,
                stateMatrixRow: plan.metadata.stateMatrixRow,
                stateMatrixPlan: plan.metadata.stateMatrixPlan,
                action: nil,
                recipeID: nil,
                recipeType: nil,
                postconditionResult: .blocked,
                error: requirement.name
            )
            return InstallerReport(
                runID: runID,
                planID: plan.id,
                beforeSnapshotID: plan.sourceSnapshotID,
                success: false,
                completionState: .blocked,
                failureReason: "Plan blocked by requirement: \(requirement.name)",
                unmetRequirements: [requirement],
                executedRecipes: [],
                repairTelemetry: [telemetry]
            )
        }

        // Execute recipes in order
        var executedRecipes: [RecipeResult] = []
        var firstFailure: (recipe: ServiceRecipe, error: Error)?
        var allLogs: [String] = []
        var repairTelemetry: [InstallerRepairTelemetryEvent] = []

        for recipe in plan.recipes {
            AppLogger.shared.log(
                "⚙️ [InstallerEngine] Executing recipe: \(recipe.id) (type: \(recipe.type))"
            )

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
                        commandsRun: commandsRun,
                        expectedPostconditions: recipe.expectedPostconditions
                    )
                )
                repairTelemetry.append(
                    makeRepairTelemetryEvent(
                        trigger: trigger,
                        plan: plan,
                        recipe: recipe,
                        result: .succeeded
                    )
                )
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
                        commandsRun: commandsRun,
                        expectedPostconditions: recipe.expectedPostconditions
                    )
                )

                AppLogger.shared.log(
                    "❌ [InstallerEngine] Recipe \(recipe.id) failed: \(recipeError ?? "Unknown error")"
                )
                repairTelemetry.append(
                    makeRepairTelemetryEvent(
                        trigger: trigger,
                        plan: plan,
                        recipe: recipe,
                        result: .failed,
                        error: recipeError
                    )
                )

                firstFailure = (recipe, error)
                break // Stop execution on first failure
            }
        }

        // Own the final observation inside the transaction. A fresh capture
        // invalidates validator/component/health caches before collecting the
        // post-execution evidence, so clients do not race a second observer.
        let finalContext: SystemContext? = if plan.intent == .inspectOnly {
            nil
        } else {
            await captureFreshContext()
        }

        var seenPostconditions = Set<InstallerPostcondition>()
        let executedPostconditions = executedRecipes
            .flatMap(\.expectedPostconditions)
            .filter { seenPostconditions.insert($0).inserted }

        let failedPostconditions: [InstallerPostcondition] = if let finalContext {
            executedPostconditions.filter { !sessionPostconditionSatisfied($0, by: finalContext) }
        } else {
            executedPostconditions
        }
        let postconditionVerificationFailure = failedPostconditions.isEmpty
            ? nil
            : "Postcondition verification failed: \(failedPostconditions.map(\.rawValue).joined(separator: ", "))"

        let noOpVerificationFailure = await verifyNoOpPlan(
            plan,
            finalContext: finalContext
        )
        let verificationFailure = postconditionVerificationFailure ?? noOpVerificationFailure

        if !executedPostconditions.isEmpty {
            let verificationSucceeded = failedPostconditions.isEmpty
            allLogs.append(
                verificationSucceeded
                    ? "[\(InstallerRecipeID.verifyPostconditions)] Executed recipe postconditions satisfied"
                    : "[\(InstallerRecipeID.verifyPostconditions)] \(verificationFailure ?? "Verification failed")"
            )
            repairTelemetry.append(
                InstallerRepairTelemetryEvent(
                    trigger: trigger,
                    intent: plan.intent.telemetryValue,
                    stateMatrixRow: plan.metadata.stateMatrixRow,
                    stateMatrixPlan: plan.metadata.stateMatrixPlan,
                    action: InstallerRecipeID.verifyPostconditions,
                    recipeID: nil,
                    recipeType: nil,
                    postconditionResult: verificationSucceeded ? .succeeded : .failed,
                    error: verificationFailure
                )
            )
        }

        if plan.recipes.isEmpty {
            let noOpVerified = verificationFailure == nil && plan.intent != .inspectOnly
            allLogs.append(
                noOpVerified
                    ? "[\(InstallerRecipeID.verifyPostconditions)] Final state confirms no work is required"
                    : "[\(InstallerRecipeID.verifyPostconditions)] \(verificationFailure ?? "Inspection completed without mutations")"
            )
            repairTelemetry.append(
                InstallerRepairTelemetryEvent(
                    trigger: trigger,
                    intent: plan.intent.telemetryValue,
                    stateMatrixRow: plan.metadata.stateMatrixRow,
                    stateMatrixPlan: plan.metadata.stateMatrixPlan,
                    action: InstallerRecipeID.verifyPostconditions,
                    recipeID: nil,
                    recipeType: nil,
                    postconditionResult: plan.intent == .inspectOnly
                        ? .skipped
                        : (noOpVerified ? .succeeded : .failed),
                    error: verificationFailure
                )
            )
        }

        let recoveryPlan: InstallPlan? = if verificationFailure != nil,
                                            let finalContext,
                                            plan.intent == .install || plan.intent == .repair
        {
            await makePlan(for: .repair, context: finalContext)
        } else {
            nil
        }

        // A declared, satisfied postcondition is stronger evidence than an
        // operation reply. This lets a lost helper/XPC reply become verified
        // success while a failed recipe without its own declarations still
        // honors its operation error.
        let earlierExecutedPostconditions = Set(
            executedRecipes.dropLast().flatMap(\.expectedPostconditions)
        )
        let failedRecipePostconditionsProveSuccess: Bool = if let firstFailure,
                                                              let finalContext,
                                                              let initialStates = plan.initialPostconditionStates
        {
            isSupportedSessionRecipe(firstFailure.recipe)
                && !firstFailure.recipe.expectedPostconditions.isEmpty
                && firstFailure.recipe.expectedPostconditions.allSatisfy {
                    !earlierExecutedPostconditions.contains($0)
                }
                && firstFailure.recipe.expectedPostconditions.allSatisfy {
                    initialStates[$0] == false && sessionPostconditionSatisfied($0, by: finalContext)
                }
        } else {
            false
        }
        let success = verificationFailure == nil
            && (firstFailure == nil || failedRecipePostconditionsProveSuccess)
        let operationFailure = firstFailure.map {
            "Recipe '\($0.recipe.id)' failed: \($0.error.localizedDescription)"
        }
        let failureReason: String? = if success {
            nil
        } else if let operationFailure, let verificationFailure {
            "\(operationFailure). \(verificationFailure)"
        } else {
            operationFailure ?? verificationFailure
        }

        let completionState: InstallerCompletionState = if success {
            if finalContext.map(requiresManualApproval) == true {
                .awaitingApproval
            } else if firstFailure != nil {
                .verifiedAfterOperationError
            } else if plan.recipes.isEmpty, plan.intent != .inspectOnly {
                .verifiedNoOp
            } else {
                .completed
            }
        } else if verificationFailure != nil {
            .verificationFailed
        } else {
            .executionFailed
        }
        let afterSnapshotID = finalContext?.snapshotID
        let telemetryWithEvidence = repairTelemetry.map { event in
            event.attachingRunEvidence(
                runID: runID,
                planID: plan.id,
                beforeSnapshotID: plan.sourceSnapshotID,
                afterSnapshotID: afterSnapshotID
            )
        }

        // Generate report with aggregated logs
        let report = InstallerReport(
            runID: runID,
            planID: plan.id,
            beforeSnapshotID: plan.sourceSnapshotID,
            afterSnapshotID: afterSnapshotID,
            success: success,
            completionState: completionState,
            failureReason: failureReason,
            unmetRequirements: success ? [] : plan.blockedBy.map { [$0] } ?? [],
            executedRecipes: executedRecipes,
            finalContext: finalContext,
            logs: allLogs,
            repairTelemetry: telemetryWithEvidence,
            recoveryPlan: recoveryPlan,
            failedPostconditions: failedPostconditions
        )

        AppLogger.shared.log(
            "✅ [InstallerEngine] execute() complete - success: \(success), recipes executed: \(executedRecipes.count)"
        )
        return report
    }

    private func requiresManualApproval(_: SystemContext) -> Bool {
        false // Session readiness never depends on privileged service approval.
    }

    private func verifyNoOpPlan(
        _ plan: InstallPlan,
        finalContext: SystemContext?
    ) async -> String? {
        guard plan.recipes.isEmpty, plan.intent != .inspectOnly else { return nil }
        guard let finalContext, finalContext.captureStatus.isComplete else {
            return "No-op verification failed: final system evidence is incomplete"
        }

        let finalPlan = await makePlan(for: plan.intent, context: finalContext)
        switch finalPlan.status {
        case let .blocked(requirement):
            return "No-op verification failed: final state is blocked by \(requirement.name)"
        case .ready where !finalPlan.recipes.isEmpty:
            return "No-op verification failed: final state requires \(finalPlan.recipes.map(\.id).joined(separator: ", "))"
        case .ready:
            return nil
        }
    }

    private func captureFreshContext() async -> SystemContext {
        systemValidator?.invalidateCaches()
        return await inspectSystem(freshness: .fresh)
    }

    private func makeRepairTelemetryEvent(
        trigger: InstallerRepairTelemetryTrigger,
        plan: InstallPlan,
        recipe: ServiceRecipe,
        result: InstallerRepairTelemetryResult,
        error: String? = nil
    ) -> InstallerRepairTelemetryEvent {
        InstallerRepairTelemetryEvent(
            trigger: trigger,
            intent: plan.intent.telemetryValue,
            stateMatrixRow: plan.metadata.stateMatrixRow,
            stateMatrixPlan: plan.metadata.stateMatrixPlan,
            action: recipe.id,
            recipeID: recipe.id,
            recipeType: recipe.type.telemetryValue,
            postconditionResult: result,
            error: error
        )
    }

    // MARK: - Recipe Execution

    /// Result of executing a recipe with detailed logs
    private struct RecipeExecutionResult {
        let logs: [String]
        let commands: [String]
    }

    /// Only exact user-session recipe shapes may execute, including caller-built plans.
    private func isSupportedSessionRecipe(_ recipe: ServiceRecipe) -> Bool {
        guard recipe.serviceID == nil, recipe.plistContent == nil,
              recipe.launchctlActions.isEmpty, recipe.healthCheck == nil,
              recipe.dependencies.isEmpty, recipe.conflictsToResolve.isEmpty
        else { return false }
        switch recipe.id {
        case "start-session-runtime":
            return recipe.type == .installComponent
                && recipe.expectedPostconditions == [.runtimeReadyOrApprovalPending]
        case InstallerRecipeID.synchronizeConfigPaths:
            return recipe.type == .checkRequirement && recipe.expectedPostconditions.isEmpty
        default:
            return false
        }
    }

    private func sessionPostconditionSatisfied(
        _ postcondition: InstallerPostcondition, by context: SystemContext
    ) -> Bool {
        if postcondition == .runtimeReadyOrApprovalPending {
            return context.captureStatus.isComplete && context.services.kanataRuntimeReadiness.isReady
        }
        return postcondition.isSatisfied(by: context)
    }

    /// Execute without a privileged broker or any system-service fallback.
    private func executeRecipeWithDetails(_ recipe: ServiceRecipe, using _: PrivilegeBroker) async throws -> RecipeExecutionResult {
        guard isSupportedSessionRecipe(recipe) else {
            throw InstallerError.unknownRecipe("Recipe unavailable in the driverless build: \(recipe.id)")
        }
        switch recipe.id {
        case "start-session-runtime":
            guard await WizardDependencies.runtimeCoordinator?.startKanata(reason: "Driverless setup") == true else {
                throw InstallerError.healthCheckFailed("Session runtime did not become ready")
            }
        case InstallerRecipeID.synchronizeConfigPaths:
            guard FileManager.default.fileExists(atPath: KeyPathConstants.Config.mainConfigPath) else {
                throw InstallerError.healthCheckFailed("User configuration is missing")
            }
        default:
            throw InstallerError.unknownRecipe("Recipe unavailable in the driverless build: \(recipe.id)")
        }
        return RecipeExecutionResult(logs: ["[\(recipe.id)] Session operation completed"], commands: [])
    }

    /// Caller-supplied health checks cannot route to privileged service metadata.
    private func verifyHealthCheck(_: HealthCheckCriteria) async -> Bool {
        false
    }

    // MARK: - Public Health Check API

    /// Check if a specific service is healthy (running and responsive)
    /// Delegates to ServiceHealthChecker
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
    public func checkKanataServiceHealth(tcpPort: Int = KeyPathConstants.Networking.defaultTCPPort) async -> KanataRuntimeReadiness {
        let runtimeSnapshot = await ServiceHealthChecker.shared.checkKanataServiceRuntimeSnapshot(
            tcpPort: tcpPort
        )
        return runtimeSnapshot.readiness
    }

    /// Convenience wrapper that chains inspectSystem() → makePlan() → execute() internally.
    /// Useful for CLI "one-button repair" automation or simple GUI flows.
    public func run(intent: InstallIntent, using broker: PrivilegeBroker) async -> InstallerReport {
        await withInstallerTransaction {
            await runWithinTransaction(intent: intent, using: broker)
        }
    }

    private func runWithinTransaction(
        intent: InstallIntent,
        using broker: PrivilegeBroker
    ) async -> InstallerReport {
        AppLogger.shared.log("🚀 [InstallerEngine] Starting run(intent: \(intent), using:)")

        if intent == .uninstall {
            AppLogger.shared.log(
                "🗑️ [InstallerEngine] Delegating uninstall intent to uninstall(deleteConfig:, using:)"
            )
            return await uninstallWithinTransaction(
                deleteConfig: false,
                removeVirtualHID: false,
                allowAdminFallback: false
            )
        }

        // Chain the steps
        let context = await inspectSystem()
        let plan = await makePlan(for: intent, context: context)
        let report = await executeWithinTransaction(plan: plan, using: broker, trigger: .run)

        AppLogger.shared.log("✅ [InstallerEngine] run() complete - success: \(report.success)")
        return report
    }

    /// Execute uninstall via the existing coordinator.
    /// - Parameter removeVirtualHID: when true, also tears down the Karabiner VirtualHID
    ///   driver. Off by default because the driver is a shared component other tools may use.
    public func uninstall(
        deleteConfig: Bool,
        removeVirtualHID: Bool = false,
        allowAdminFallback: Bool = false,
        using _: PrivilegeBroker
    ) async -> InstallerReport {
        await withInstallerTransaction {
            await uninstallWithinTransaction(
                deleteConfig: deleteConfig,
                removeVirtualHID: removeVirtualHID,
                allowAdminFallback: allowAdminFallback
            )
        }
    }

    private func uninstallWithinTransaction(
        deleteConfig _: Bool,
        removeVirtualHID _: Bool,
        allowAdminFallback _: Bool
    ) async -> InstallerReport {
        let runID = UUID()
        let context = await captureFreshContext()
        let failure = "System uninstall is unavailable in the driverless build; no services or user configuration were removed"
        let telemetry = InstallerRepairTelemetryEvent(
            runID: runID, beforeSnapshotID: context.snapshotID, afterSnapshotID: context.snapshotID,
            trigger: .uninstall, intent: InstallIntent.uninstall.telemetryValue,
            stateMatrixRow: nil, stateMatrixPlan: [], action: "uninstall", recipeID: nil,
            recipeType: "uninstall", postconditionResult: .failed, error: failure
        )
        return InstallerReport(
            runID: runID, beforeSnapshotID: context.snapshotID, afterSnapshotID: context.snapshotID,
            success: false, completionState: .executionFailed, failureReason: failure,
            executedRecipes: [], finalContext: context, logs: [failure], repairTelemetry: [telemetry]
        )
    }

    /// Execute a single AutoFixAction by generating a plan that includes that specific action
    /// This is useful for GUI single-action fixes where the user clicks a specific "Fix" button
    /// Note: Some actions (like installRequiredRuntimeServices) are only in install plans, not repair plans.
    public func runSingleAction(_ action: AutoFixAction, using broker: PrivilegeBroker) async
        -> InstallerReport
    {
        await withInstallerTransaction {
            await runSingleActionWithinTransaction(action, using: broker)
        }
    }

    private func runSingleActionWithinTransaction(
        _ action: AutoFixAction,
        using broker: PrivilegeBroker
    ) async -> InstallerReport {
        AppLogger.shared.log("🔧 [InstallerEngine] runSingleAction(\(action), using:) starting")
        let context = await inspectSystem()

        // Determine which intent would include this action.
        let intent: InstallIntent = action == .installRequiredRuntimeServices ? .install : .repair

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
                let runID = UUID()
                let error = "No recipe available for action: \(action)"
                let telemetry = InstallerRepairTelemetryEvent(
                    runID: runID,
                    planID: basePlan.id,
                    beforeSnapshotID: context.snapshotID,
                    trigger: .singleAction,
                    intent: basePlan.intent.telemetryValue,
                    stateMatrixRow: basePlan.metadata.stateMatrixRow,
                    stateMatrixPlan: basePlan.metadata.stateMatrixPlan,
                    action: String(describing: action),
                    recipeID: nil,
                    recipeType: nil,
                    postconditionResult: .failed,
                    error: error
                )
                return InstallerReport(
                    runID: runID,
                    planID: basePlan.id,
                    beforeSnapshotID: context.snapshotID,
                    success: false,
                    completionState: .executionFailed,
                    failureReason: error,
                    executedRecipes: [],
                    logs: [],
                    repairTelemetry: [telemetry]
                )
            }
        } else {
            finalRecipes = filteredRecipes
        }

        // Create a filtered plan with just the matching recipes. If the recipe came from a
        // direct single-action fallback, do not inherit a broad install/repair blocker that
        // can belong to a different wizard step; the recipe execution still enforces its
        // own failure and postcondition checks.
        let shouldPreserveBaseBlocker = !filteredRecipes.isEmpty
        let filteredPlan = InstallPlan(
            sourceSnapshotID: context.snapshotID,
            recipes: finalRecipes,
            status: shouldPreserveBaseBlocker ? basePlan.status : .ready,
            intent: basePlan.intent,
            blockedBy: shouldPreserveBaseBlocker ? basePlan.blockedBy : nil,
            metadata: basePlan.metadata,
            initialPostconditionStates: postconditionBaseline(
                for: finalRecipes,
                context: context
            )
        )

        let report = await executeWithinTransaction(
            plan: filteredPlan,
            using: broker,
            trigger: .singleAction
        )
        AppLogger.shared.log(
            "✅ [InstallerEngine] runSingleAction(\(action), using:) complete - success: \(report.success)"
        )
        return report
    }

    // MARK: - Unavailable compatibility APIs

    public func uninstallVirtualHIDDrivers(using _: PrivilegeBroker) async throws {
        throw InstallerError.unknownRecipe("VirtualHID uninstall is unavailable in the driverless build")
    }

    public func disableKarabinerGrabber(using _: PrivilegeBroker) async throws {
        throw InstallerError.unknownRecipe("Karabiner mutation is unavailable in the driverless build")
    }

    public func restartKarabinerDaemon(using _: PrivilegeBroker) async throws -> Bool {
        throw InstallerError.unknownRecipe("Karabiner restart is unavailable in the driverless build")
    }

    public func sudoExecuteCommand(
        _: String, description _: String, using _: PrivilegeBroker
    ) async throws {
        throw InstallerError.unknownRecipe("Privileged commands are unavailable in the driverless build")
    }
}

extension InstallerEngine: InstallerEnginePrivilegedRouting {}

// MARK: - Installer Errors

public enum InstallerError: LocalizedError {
    case healthCheckFailed(String)
    case unknownRecipe(String)

    public var errorDescription: String? {
        switch self {
        case let .healthCheckFailed(message):
            message
        case let .unknownRecipe(message):
            message
        }
    }
}

import Foundation
import KeyPathCore
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

/// Façade for installer operations.
///
/// - Provides a stable, unified API for install/repair/uninstall flows.
/// - Wraps extracted services (ServiceHealthChecker, SessionUninstallCoordinator, etc.).
/// - Projects canonical system evidence into the planner's SystemContext input.
@MainActor
public final class InstallerEngine {
    // MARK: - Dependencies

    /// Services resolved at call time: injected ones (tests), else the ones the
    /// app or CLI set at launch, so an engine made early still sees them.
    private let injectedServices: InstallerServices?
    private var services: InstallerServices {
        injectedServices ?? InstallerServices.current
    }

    private var systemValidator: (any WizardSystemValidating)? {
        services.systemValidator
    }

    /// Creates an engine. Tests pass their services; app and CLI callers use the
    /// ones set at launch. Passed services replace all of them: whatever a passed
    /// value leaves nil (a runtime, an uninstaller) is nil for this engine.
    public init(services: InstallerServices? = nil) {
        injectedServices = services

        AppLogger.shared.log("🔧 [InstallerEngine] Initialized")
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
        let stateMatrixRow = context.installerStateMatrixRow.rawValue
        let stateMatrixPlan = context.installerStateMatrixPlan.map(\.rawValue)
        let baseMetadata = PlanMetadata(
            stateMatrixRow: stateMatrixRow,
            stateMatrixPlan: stateMatrixPlan
        )

        // Uninstall never runs through a plan; SessionUninstallCoordinator owns it.
        if intent == .uninstall {
            let blockingRequirement = Requirement(
                name: "System uninstall is unavailable in the driverless build", status: .blocked
            )
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

        let orderedRecipes = Self.actions(for: intent, context: context).map(recipeForAction)
        AppLogger.shared.log("📋 [InstallerEngine] \(orderedRecipes.count) recipe(s) for intent: \(intent)")

        let plan = InstallPlan(
            sourceSnapshotID: context.snapshotID,
            recipes: orderedRecipes,
            status: .ready,
            intent: intent,
            blockedBy: nil,
            metadata: PlanMetadata(
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

    /// Execute the planned operations
    /// Returns: Structured report with success/failure details and final state.
    /// If the plan was blocked by unmet requirements, execution stops immediately and the report indicates which requirement failed.
    public func execute(
        plan: InstallPlan,
        trigger: InstallerRepairTelemetryTrigger = .executePlan
    ) async -> InstallerReport {
        await withInstallerTransaction {
            await executeWithinTransaction(plan: plan, trigger: trigger)
        }
    }

    private func executeWithinTransaction(
        plan: InstallPlan,
        trigger: InstallerRepairTelemetryTrigger
    ) async -> InstallerReport {
        AppLogger.shared.log("⚙️ [InstallerEngine] Starting execute(plan:)")
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

        // Validate the entire caller-built plan before the first operation. A
        // permitted session start must not run ahead of a forbidden later step.
        guard plan.recipes.allSatisfy(isSupportedSessionRecipe) else {
            let failure = "Recipes unavailable in the driverless build: "
                + plan.recipes.filter { !isSupportedSessionRecipe($0) }.map(\.id).joined(separator: ", ")
            let finalContext = await captureFreshContext()
            let telemetry = InstallerRepairTelemetryEvent(
                runID: runID, planID: plan.id, beforeSnapshotID: plan.sourceSnapshotID,
                afterSnapshotID: finalContext.snapshotID, trigger: trigger,
                intent: plan.intent.telemetryValue, stateMatrixRow: plan.metadata.stateMatrixRow,
                stateMatrixPlan: plan.metadata.stateMatrixPlan, action: nil,
                recipeID: nil, recipeType: nil, postconditionResult: .failed, error: failure
            )
            return InstallerReport(
                runID: runID, planID: plan.id, beforeSnapshotID: plan.sourceSnapshotID,
                afterSnapshotID: finalContext.snapshotID, success: false,
                completionState: .executionFailed, failureReason: failure,
                executedRecipes: [], finalContext: finalContext, logs: [failure], repairTelemetry: [telemetry]
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
                let executionResult = try await executeRecipeWithDetails(recipe)
                recipeLogs.append(contentsOf: executionResult.logs)
                commandsRun.append(contentsOf: executionResult.commands)

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
            if firstFailure != nil {
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
        guard recipe.dependencies.isEmpty else { return false }
        switch recipe.id {
        case InstallerRecipeID.startSessionRuntime:
            return recipe.type == .installComponent
                && recipe.expectedPostconditions == [.runtimeReadyOrApprovalPending]
        default:
            return false
        }
    }

    /// The session runtime never waits on service approval, so its postcondition
    /// requires a ready runtime.
    private func sessionPostconditionSatisfied(
        _ postcondition: InstallerPostcondition, by context: SystemContext
    ) -> Bool {
        postcondition.isSatisfied(by: context)
    }

    /// Execute a session recipe; there is no system-service fallback.
    private func executeRecipeWithDetails(_ recipe: ServiceRecipe) async throws -> RecipeExecutionResult {
        guard isSupportedSessionRecipe(recipe) else {
            throw InstallerError.unknownRecipe("Recipe unavailable in the driverless build: \(recipe.id)")
        }
        switch recipe.id {
        case InstallerRecipeID.startSessionRuntime:
            guard await services.runtime?.startKanata(reason: "Driverless setup") == true else {
                throw InstallerError.healthCheckFailed("Session runtime did not become ready")
            }
        default:
            throw InstallerError.unknownRecipe("Recipe unavailable in the driverless build: \(recipe.id)")
        }
        return RecipeExecutionResult(logs: ["[\(recipe.id)] Session operation completed"], commands: [])
    }

    // MARK: - Public Health Check API

    /// Check Kanata session runtime health (running + engine socket responding + input capture)
    public func checkKanataServiceHealth() async -> KanataRuntimeReadiness {
        await ServiceHealthChecker.shared.checkKanataServiceHealth()
    }

    /// Convenience wrapper that chains inspectSystem() → makePlan() → execute() internally.
    /// Useful for CLI "one-button repair" automation or simple GUI flows.
    public func run(intent: InstallIntent) async -> InstallerReport {
        await withInstallerTransaction {
            await runWithinTransaction(intent: intent)
        }
    }

    private func runWithinTransaction(intent: InstallIntent) async -> InstallerReport {
        AppLogger.shared.log("🚀 [InstallerEngine] Starting run(intent: \(intent))")

        if intent == .uninstall {
            AppLogger.shared.log(
                "🗑️ [InstallerEngine] Delegating uninstall intent to uninstall(deleteConfig:)"
            )
            return await uninstallWithinTransaction(deleteConfig: false)
        }

        // Chain the steps
        let context = await inspectSystem()
        let plan = await makePlan(for: intent, context: context)
        let report = await executeWithinTransaction(plan: plan, trigger: .run)

        AppLogger.shared.log("✅ [InstallerEngine] run() complete - success: \(report.success)")
        return report
    }

    /// Execute uninstall via the session uninstall coordinator.
    /// The session uninstaller always backs up and removes the user's configuration.
    public func uninstall(deleteConfig: Bool) async -> InstallerReport {
        await withInstallerTransaction {
            await uninstallWithinTransaction(deleteConfig: deleteConfig)
        }
    }

    private func uninstallWithinTransaction(deleteConfig: Bool) async -> InstallerReport {
        guard deleteConfig,
              let coordinator = services.makeUninstaller?()
        else {
            return InstallerReport(success: false, failureReason: "Use Uninstall KeyPath in Settings to back up and remove this user's installation.")
        }
        let result = await coordinator.performUninstall(deleteConfig: true)
        return InstallerReport(success: result.success, failureReason: result.failureReason, logs: result.logs)
    }

    /// Execute a single AutoFixAction by generating a plan that includes that specific action
    /// This is useful for GUI single-action fixes where the user clicks a specific "Fix" button
    public func runSingleAction(_ action: AutoFixAction) async -> InstallerReport {
        await withInstallerTransaction {
            await runSingleActionWithinTransaction(action)
        }
    }

    private func runSingleActionWithinTransaction(_ action: AutoFixAction) async -> InstallerReport {
        AppLogger.shared.log("🔧 [InstallerEngine] runSingleAction(\(action)) starting")
        let context = await inspectSystem()
        let basePlan = await makePlan(for: .repair, context: context)

        // Filter recipes to only include ones matching the action
        let actionRecipeID = Self.recipeID(for: action)
        let filteredRecipes = basePlan.recipes.filter { $0.id == actionRecipeID }

        // If the repair plan does not include the action, generate its recipe directly.
        let finalRecipes: [ServiceRecipe]
        if filteredRecipes.isEmpty {
            AppLogger.shared.log("🔧 [InstallerEngine] Generating direct recipe for action: \(action)")
            finalRecipes = [recipeForAction(action)]
        } else {
            finalRecipes = filteredRecipes
        }

        // Create a filtered plan with just the matching recipes. If the recipe came from a
        // direct single-action fallback, do not inherit a broad repair blocker that
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
            trigger: .singleAction
        )
        AppLogger.shared.log(
            "✅ [InstallerEngine] runSingleAction(\(action)) complete - success: \(report.success)"
        )
        return report
    }
}

// MARK: - Actions and recipes

public extension InstallerEngine {
    /// What install and repair do for the session runtime: start it when it is
    /// not ready. Uninstall and inspection never plan an action here.
    nonisolated static func actions(for intent: InstallIntent, context: SystemContext) -> [AutoFixAction] {
        switch intent {
        case .install, .repair:
            context.services.kanataRuntimeReadiness.isReady ? [] : [.startSessionRuntime]
        case .uninstall, .inspectOnly:
            []
        }
    }

    nonisolated static func recipeID(for action: AutoFixAction) -> String {
        switch action {
        case .startSessionRuntime: InstallerRecipeID.startSessionRuntime
        }
    }

    func recipeForAction(_ action: AutoFixAction) -> ServiceRecipe {
        switch action {
        case .startSessionRuntime:
            ServiceRecipe(
                id: InstallerRecipeID.startSessionRuntime, type: .installComponent,
                expectedPostconditions: [.runtimeReadyOrApprovalPending]
            )
        }
    }
}

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

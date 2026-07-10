@testable import KeyPathAppKit
import KeyPathCore
import KeyPathDaemonLifecycle
@testable import KeyPathInstallationWizard
import KeyPathPermissions
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEngineFailurePathTests: KeyPathAsyncTestCase {
    var engine: InstallerEngine!

    override func setUp() async throws {
        try await super.setUp()
        HelperManager.testHelperFunctionalityOverride = { false }
        engine = InstallerEngine()
    }

    override func tearDown() async throws {
        engine = nil
        HelperManager.testHelperFunctionalityOverride = nil
        try await super.tearDown()
    }

    // MARK: - Blocked Plan Tests

    func testExecute_BlockedPlanReturnsFailure() async {
        let requirement = Requirement(
            name: "Driver Compatibility",
            status: .blocked
        )
        let plan = InstallPlan(
            recipes: [],
            status: .blocked(requirement: requirement),
            intent: .install,
            blockedBy: requirement
        )
        let broker = PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.unmetRequirements.count, 1)
        XCTAssertEqual(report.unmetRequirements.first?.name, "Driver Compatibility")
        XCTAssertTrue(report.failureReason?.contains("blocked") ?? false)
        XCTAssertTrue(report.executedRecipes.isEmpty)
    }

    func testMakePlan_BlockedWhenDriverIncompatible() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false,
            driverCompatible: false
        ).build()

        let plan = await engine.makePlan(for: .install, context: context)
        if case .blocked = plan.status {
            XCTAssertNotNil(plan.blockedBy)
        } else {
            XCTFail("Plan should be blocked when driver is incompatible")
        }
    }

    func testMakePlan_BlockedWhenVHIDDriverExtensionDisabled() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
            componentsInstalled: true,
            driverCompatible: true
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)

        guard case let .blocked(requirement) = plan.status else {
            return XCTFail("Plan should be blocked until the DriverKit extension is enabled")
        }
        XCTAssertEqual(plan.blockedBy, requirement)
        XCTAssertTrue(requirement.name.contains("Driver Extensions"))
        XCTAssertTrue(plan.recipes.isEmpty)
    }

    func testMakePlan_ReadyWhenVHIDHealthyButKanataHasStaleDriverDisabledIssue() async {
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            kanataRunning: false,
            karabinerDaemonRunning: true,
            vhidHealthy: true,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
            componentsInstalled: true,
            driverCompatible: true
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)

        guard case .ready = plan.status else {
            return XCTFail("Plan should repair stale Kanata state after DriverKit approval is enabled")
        }
        XCTAssertNil(plan.blockedBy)
        XCTAssertTrue(plan.recipes.contains(where: { recipe in
            recipe.id == InstallerRecipeID.installRequiredRuntimeServices
        }))
    }

    // MARK: - Recipe Execution Failure Tests

    func testExecute_StopsOnFirstRecipeFailure() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.cleanInstall()
        let deterministicEngine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: StubSystemValidator(context: context)
        )
        let plan = await deterministicEngine.makePlan(for: .install, context: context)

        guard plan.status == .ready else {
            throw XCTSkip("Plan is blocked — cannot test recipe execution")
        }

        let report = await deterministicEngine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.success)
        XCTAssertNotNil(report.failureReason)

        let failedRecipes = report.executedRecipes.filter { !$0.success }
        XCTAssertEqual(failedRecipes.count, 1, "Exactly one recipe should have failed")
        XCTAssertNotNil(failedRecipes.first?.error)
    }

    func testExecute_SuccessfulRecipesBeforeFailureAreRecorded() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "repairVHIDDaemonServices"
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.degradedRepair()
        let plan = await engine.makePlan(for: .repair, context: context)

        guard plan.status == .ready, plan.recipes.count > 1 else {
            throw XCTSkip("Need multi-recipe plan for this test")
        }

        let report = await engine.execute(plan: plan, using: broker)

        let succeeded = report.executedRecipes.filter(\.success)
        let failed = report.executedRecipes.filter { !$0.success }

        if !failed.isEmpty {
            XCTAssertFalse(report.success)
            XCTAssertTrue(succeeded.count + failed.count <= plan.recipes.count)
        }
    }

    func testExecute_FailedRecipeIncludesErrorDescription() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .install, context: context)

        guard plan.status == .ready else {
            throw XCTSkip("Plan is blocked")
        }

        let report = await engine.execute(plan: plan, using: broker)

        let failedRecipe = report.executedRecipes.first(where: { !$0.success })
        XCTAssertNotNil(failedRecipe?.error, "Failed recipe should include error description")
        XCTAssertGreaterThan(failedRecipe?.error?.count ?? 0, 0)
    }

    // MARK: - Privilege Broker Failure Tests

    func testBroker_ThrowsWhenCoordinatorNotConfigured() async {
        let saved = WizardDependencies.privilegedOperations
        WizardDependencies.privilegedOperations = nil
        defer { WizardDependencies.privilegedOperations = saved }

        let broker = PrivilegeBroker()
        do {
            try await broker.installRequiredRuntimeServices()
            XCTFail("Should throw when coordinator not configured")
        } catch {
            XCTAssertTrue(
                "\(error)".contains("coordinatorNotConfigured"),
                "Should throw coordinatorNotConfigured, got: \(error)"
            )
        }
    }

    func testBroker_AllMethodsThrowWhenNoCoordinator() async {
        let saved = WizardDependencies.privilegedOperations
        WizardDependencies.privilegedOperations = nil
        defer { WizardDependencies.privilegedOperations = saved }

        let broker = PrivilegeBroker()

        do { try await broker.recoverRequiredRuntimeServices(); XCTFail("Should throw") } catch {}
        do { try await broker.installNewsyslogConfig(); XCTFail("Should throw") } catch {}
        do { try await broker.regenerateServiceConfiguration(); XCTFail("Should throw") } catch {}
        do { try await broker.repairVHIDDaemonServices(); XCTFail("Should throw") } catch {}
        do { try await broker.downloadAndInstallCorrectVHIDDriver(); XCTFail("Should throw") } catch {}
        do { try await broker.activateVirtualHIDManager(); XCTFail("Should throw") } catch {}
        do { try await broker.killAllKanataProcesses(); XCTFail("Should throw") } catch {}
        do { try await broker.terminateProcess(pid: 1); XCTFail("Should throw") } catch {}
        do { try await broker.uninstallVirtualHIDDrivers(); XCTFail("Should throw") } catch {}
        do { try await broker.disableKarabinerGrabber(); XCTFail("Should throw") } catch {}
        do { try await broker.sudoExecuteCommand("ls", description: "test"); XCTFail("Should throw") } catch {}
    }

    func testBroker_CoordinatorErrorPropagates() async {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: stub)

        do {
            try await broker.installRequiredRuntimeServices()
            XCTFail("Should propagate coordinator error")
        } catch is StubPrivilegedOperationsCoordinator.StubError {
            // Expected
        } catch {
            XCTFail("Expected StubError, got \(error)")
        }
    }

    // MARK: - Empty Plan Tests

    func testExecute_EmptyPlanSucceeds() async {
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .inspectOnly
        )
        let broker = PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success)
        XCTAssertNil(report.failureReason)
        XCTAssertTrue(report.executedRecipes.isEmpty)
    }

    func testMakePlan_InspectOnlyProducesEmptyPlan() async {
        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .inspectOnly, context: context)

        XCTAssertEqual(plan.intent, .inspectOnly)
        XCTAssertTrue(plan.recipes.isEmpty, "Inspect-only should have no recipes")
        XCTAssertEqual(plan.status, .ready)
    }

    // MARK: - Uninstall Failure Tests

    func testUninstall_FailsWhenCoordinatorNotConfigured() async {
        let savedFactory = WizardDependencies.createUninstallCoordinator
        WizardDependencies.createUninstallCoordinator = nil
        defer { WizardDependencies.createUninstallCoordinator = savedFactory }
        let validator = StubSystemValidator(context: SystemContextBuilder.cleanInstall())
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )

        let broker = PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        let report = await engine.uninstall(deleteConfig: false, using: broker)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("not configured") ?? false)
        XCTAssertTrue(validator.freshnessRequests.isEmpty)
        XCTAssertEqual(validator.cacheInvalidationCount, 0)
    }

    func testRun_UninstallDelegatesToUninstallMethod() async {
        let savedFactory = WizardDependencies.createUninstallCoordinator
        WizardDependencies.createUninstallCoordinator = nil
        defer { WizardDependencies.createUninstallCoordinator = savedFactory }

        let broker = PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        let report = await engine.run(intent: .uninstall, using: broker)

        XCTAssertFalse(report.success)
        XCTAssertTrue(report.failureReason?.contains("not configured") ?? false)
    }

    func testUninstall_PreservesStructuredRecoveryAndComponentResults() async {
        let savedFactory = WizardDependencies.createUninstallCoordinator
        let coordinator = StubWizardUninstaller(result: WizardUninstallResult(
            success: false,
            failureReason: "The system helper could not be repaired.",
            recommendedRecovery: .emergencyCleanup,
            steps: [
                WizardUninstallStepResult(
                    id: "repair-uninstall-helper",
                    success: false,
                    error: "The system helper could not be repaired."
                ),
            ],
            logs: ["helper repair failed"]
        ))
        WizardDependencies.createUninstallCoordinator = { coordinator }
        defer { WizardDependencies.createUninstallCoordinator = savedFactory }

        let broker = PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        let report = await engine.uninstall(deleteConfig: false, using: broker)

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.recommendedRecovery, .emergencyCleanup)
        XCTAssertEqual(report.logs, ["helper repair failed"])
        XCTAssertEqual(report.executedRecipes.map(\.recipeID), ["repair-uninstall-helper"])
        XCTAssertFalse(report.executedRecipes[0].success)
    }

    // MARK: - Report Structure Tests

    func testReport_FailureReasonIncludesRecipeID() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .install, context: context)

        guard plan.status == .ready else {
            throw XCTSkip("Plan is blocked")
        }

        let report = await engine.execute(plan: plan, using: broker)

        if let reason = report.failureReason {
            XCTAssertTrue(
                reason.contains("Recipe") || reason.contains("recipe") || reason.contains("'"),
                "Failure reason should reference the recipe: \(reason)"
            )
        }
    }

    func testReport_RecipeDurationsAreNonNegative() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .install, context: context)

        guard plan.status == .ready else {
            throw XCTSkip("Plan is blocked")
        }

        let report = await engine.execute(plan: plan, using: broker)

        for result in report.executedRecipes {
            XCTAssertGreaterThanOrEqual(
                result.duration, 0,
                "Recipe \(result.recipeID) duration should be non-negative"
            )
        }
    }

    func testReport_SuccessfulExecutionHasNoFailureReason() async {
        let stub = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: stub)

        let plan = InstallPlan(recipes: [], status: .ready, intent: .inspectOnly)
        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success)
        XCTAssertNil(report.failureReason)
        XCTAssertTrue(report.unmetRequirements.isEmpty)
    }

    // MARK: - Recipe Logs Tests

    func testReport_FailedRecipeHasLogs() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .install, context: context)

        guard plan.status == .ready else {
            throw XCTSkip("Plan is blocked")
        }

        let report = await engine.execute(plan: plan, using: broker)

        let failedRecipe = report.executedRecipes.first(where: { !$0.success })
        XCTAssertNotNil(failedRecipe)
        XCTAssertFalse(failedRecipe?.logs.isEmpty ?? true, "Failed recipe should have logs")
        XCTAssertTrue(
            failedRecipe?.logs.contains(where: { $0.contains("FAILED") }) ?? false,
            "Failed recipe logs should contain 'FAILED'"
        )
    }

    func testReport_AggregatedLogsIncludeAllRecipes() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: stub)

        let context = SystemContextBuilder.cleanInstall()
        let plan = await engine.makePlan(for: .install, context: context)

        guard plan.status == .ready, !plan.recipes.isEmpty else {
            throw XCTSkip("Need non-empty plan")
        }

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.logs.isEmpty, "Report should have aggregated logs")
    }

    // MARK: - SystemContext Builder Tests

    func testSystemContextBuilder_CleanInstall() {
        let context = SystemContextBuilder.cleanInstall()
        XCTAssertFalse(context.helper.isInstalled)
        XCTAssertFalse(context.services.kanataRunning)
        XCTAssertFalse(context.components.kanataBinaryInstalled)
    }

    func testSystemContextBuilder_DegradedRepair() {
        let context = SystemContextBuilder.degradedRepair()
        XCTAssertTrue(context.helper.isInstalled)
        XCTAssertFalse(context.services.kanataRunning)
        XCTAssertTrue(context.components.kanataBinaryInstalled)
    }

    func testSystemContextBuilder_CustomConflicts() {
        let conflict = SystemConflict.karabinerGrabberRunning(pid: 1234)
        let context = SystemContextBuilder(
            conflicts: [conflict]
        ).build()

        XCTAssertEqual(context.conflicts.conflicts.count, 1)
        XCTAssertTrue(context.conflicts.canAutoResolve)
    }

    // MARK: - Installer Error Tests

    func testInstallerError_HealthCheckFailedHasMessage() {
        let error = InstallerError.healthCheckFailed("Service not responding")
        XCTAssertTrue(error.localizedDescription.contains("not responding"))
    }

    func testInstallerError_UnknownRecipeHasID() {
        let error = InstallerError.unknownRecipe("custom-recipe-123")
        XCTAssertTrue(error.localizedDescription.contains("custom-recipe-123"))
    }

    // MARK: - RecipeResult Tests

    func testRecipeResult_SuccessfulResult() {
        let result = RecipeResult(
            recipeID: "test-recipe",
            success: true,
            duration: 1.5,
            logs: ["Started", "Completed"],
            commandsRun: ["launchctl bootstrap"]
        )
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.recipeID, "test-recipe")
        XCTAssertEqual(result.duration, 1.5)
        XCTAssertEqual(result.logs.count, 2)
        XCTAssertEqual(result.commandsRun.count, 1)
    }

    func testRecipeResult_FailedResult() {
        let result = RecipeResult(
            recipeID: "failed-recipe",
            success: false,
            error: "Permission denied"
        )
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Permission denied")
    }

    // MARK: - InstallPlan Tests

    func testInstallPlan_ReadyStatus() {
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .install
        )
        XCTAssertEqual(plan.status, .ready)
        XCTAssertNil(plan.blockedBy)
        XCTAssertFalse(plan.metadata.needsReboot)
    }

    func testInstallPlan_BlockedStatus() {
        let req = Requirement(
            name: "Test",
            status: .blocked
        )
        let plan = InstallPlan(
            recipes: [],
            status: .blocked(requirement: req),
            intent: .install,
            blockedBy: req,
            metadata: PlanMetadata(needsReboot: true, promptsNeeded: true)
        )
        if case .blocked = plan.status {} else { XCTFail("Should be blocked") }
        XCTAssertNotNil(plan.blockedBy)
        XCTAssertTrue(plan.metadata.needsReboot)
        XCTAssertTrue(plan.metadata.promptsNeeded)
    }

    // MARK: - Health Check Types

    func testKanataHealthSnapshot_AllHealthy() {
        let snapshot = KanataHealthSnapshot(
            isRunning: true,
            isResponding: true,
            inputCaptureReady: true
        )
        XCTAssertTrue(snapshot.isRunning)
        XCTAssertTrue(snapshot.isResponding)
        XCTAssertTrue(snapshot.inputCaptureReady)
    }

    func testKanataHealthSnapshot_PartialFailure() {
        let snapshot = KanataHealthSnapshot(
            isRunning: true,
            isResponding: false,
            inputCaptureReady: false
        )
        XCTAssertTrue(snapshot.isRunning)
        XCTAssertFalse(snapshot.isResponding)
        XCTAssertFalse(snapshot.inputCaptureReady)
    }

    // MARK: - Stub Coordinator Tests

    func testStubCoordinator_RecordsCalls() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        try await stub.installRequiredRuntimeServices()
        try await stub.installNewsyslogConfig()

        XCTAssertEqual(stub.calls, [
            "installRequiredRuntimeServices",
            "installNewsyslogConfig",
        ])
    }

    func testStubCoordinator_FailOnCallThrows() async {
        let stub = StubPrivilegedOperationsCoordinator()
        stub.failOnCall = "installNewsyslogConfig"

        try? await stub.installRequiredRuntimeServices()
        XCTAssertEqual(stub.calls, ["installRequiredRuntimeServices"])

        do {
            try await stub.installNewsyslogConfig()
            XCTFail("Should throw on configured failOnCall")
        } catch is StubPrivilegedOperationsCoordinator.StubError {
            // Expected
        } catch {
            XCTFail("Expected StubError, got \(error)")
        }
        XCTAssertEqual(stub.calls.count, 1, "Failed call should not be recorded")
    }

    func testStubCoordinator_SudoRecordsCommandName() async throws {
        let stub = StubPrivilegedOperationsCoordinator()
        try await stub.sudoExecuteCommand("/bin/launchctl bootout system/com.keypath.kanata", description: "Stop service")
        XCTAssertTrue(stub.calls.first?.contains("sudoExecuteCommand") ?? false)
        XCTAssertTrue(stub.calls.first?.contains("launchctl") ?? false)
    }
}

@MainActor
private final class StubWizardUninstaller: WizardUninstalling {
    let result: WizardUninstallResult

    init(result: WizardUninstallResult) {
        self.result = result
    }

    func performUninstall(
        deleteConfig _: Bool,
        removeVirtualHID _: Bool,
        allowAdminFallback _: Bool
    ) async -> WizardUninstallResult {
        result
    }
}

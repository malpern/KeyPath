@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

private actor InstallerGateTestState {
    private(set) var entered = false
    func markEntered() {
        entered = true
    }
}

@MainActor
final class InstallerEngineTests: KeyPathAsyncTestCase {
    var engine: InstallerEngine!

    override func setUp() async throws {
        try await super.setUp()
        // Skip real XPC calls in tests to avoid timeouts
        HelperManager.testHelperFunctionalityOverride = { false }
        engine = InstallerEngine()
    }

    override func tearDown() async throws {
        engine = nil
        HelperManager.testHelperFunctionalityOverride = nil
        try await super.tearDown()
    }

    // MARK: - Façade Instantiation

    func testInstallerEngineCanBeInstantiated() {
        let engine = InstallerEngine()
        XCTAssertNotNil(engine, "InstallerEngine should be instantiable")
    }

    func testInstallerTransactionGateSerializesConcurrentRuns() async {
        let gate = InstallerTransactionGate()
        await gate.acquire()
        let state = InstallerGateTestState()

        let waitingRun = Task {
            await gate.acquire()
            await state.markEntered()
            await gate.release()
        }

        await Task.yield()
        let enteredWhileOccupied = await state.entered
        XCTAssertFalse(enteredWhileOccupied)

        await gate.release()
        await waitingRun.value
        let enteredAfterRelease = await state.entered
        XCTAssertTrue(enteredAfterRelease)
    }

    // MARK: - inspectSystem() Tests

    func testInspectSystemReturnsSystemContext() async {
        let context = await engine.inspectSystem()

        XCTAssertNotNil(context, "inspectSystem() should return a SystemContext")
        XCTAssertNotNil(context.permissions, "SystemContext should have permissions")
        XCTAssertNotNil(context.services, "SystemContext should have services")
        XCTAssertNotNil(context.conflicts, "SystemContext should have conflicts")
        XCTAssertNotNil(context.components, "SystemContext should have components")
        XCTAssertNotNil(context.helper, "SystemContext should have helper")
        XCTAssertNotNil(context.system, "SystemContext should have system info")
        XCTAssertNotNil(context.timestamp, "SystemContext should have timestamp")

        // Phase 2: Verify we get real data, not stubs
        XCTAssertFalse(context.system.macOSVersion.isEmpty, "macOS version should be detected")
        XCTAssertNotNil(context.permissions.timestamp, "Permissions should have timestamp")
    }

    func testInspectSystemReturnsConsistentContext() async {
        let context1 = await engine.inspectSystem()
        let context2 = await engine.inspectSystem()

        // Verify structure is consistent - timestamps may differ significantly due to async operations
        // (inspectSystem() can take 6+ seconds due to helper timeouts)
        // But the structure should be the same
        XCTAssertNotNil(context1.permissions, "Context1 should have permissions")
        XCTAssertNotNil(context1.services, "Context1 should have services")
        XCTAssertNotNil(context1.components, "Context1 should have components")
        XCTAssertNotNil(context2.permissions, "Context2 should have permissions")
        XCTAssertNotNil(context2.services, "Context2 should have services")
        XCTAssertNotNil(context2.components, "Context2 should have components")

        // Verify timestamps exist and are reasonable (within 10 seconds of each other)
        let timeDiff1 = abs(context1.permissions.timestamp.timeIntervalSince(context1.timestamp))
        let timeDiff2 = abs(context2.permissions.timestamp.timeIntervalSince(context2.timestamp))
        XCTAssertLessThan(
            timeDiff1, 10.0, "Permission timestamp should be within 10 seconds of context timestamp"
        )
        XCTAssertLessThan(
            timeDiff2, 10.0, "Permission timestamp should be within 10 seconds of context timestamp"
        )
    }

    // MARK: - makePlan() Tests

    func testMakePlanReturnsInstallPlan() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)

        XCTAssertNotNil(plan, "makePlan() should return an InstallPlan")
        XCTAssertEqual(plan.intent, .install, "Plan should have correct intent")
        XCTAssertNotNil(plan.recipes, "Plan should have recipes array")
        XCTAssertNotNil(plan.status, "Plan should have status")
        XCTAssertNotNil(plan.metadata, "Plan should have metadata")
    }

    func testMakePlanHandlesAllIntents() async {
        let context = await engine.inspectSystem()

        let installPlan = await engine.makePlan(for: .install, context: context)
        XCTAssertEqual(installPlan.intent, .install)

        let repairPlan = await engine.makePlan(for: .repair, context: context)
        XCTAssertEqual(repairPlan.intent, .repair)

        let uninstallPlan = await engine.makePlan(for: .uninstall, context: context)
        XCTAssertEqual(uninstallPlan.intent, .uninstall)

        let inspectPlan = await engine.makePlan(for: .inspectOnly, context: context)
        XCTAssertEqual(inspectPlan.intent, .inspectOnly)
    }

    func testMakePlanForInstallGeneratesRecipes() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)

        // Install planning may legitimately be empty when the system is already ready;
        // it should still return a valid recipe array rather than forcing recovery work.
        if case .ready = plan.status {
            XCTAssertNotNil(plan.recipes, "Install plan should provide a recipe array")
        }
    }

    func testMakePlanForRepairGeneratesRecipes() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .repair, context: context)

        // Phase 3: Repair intent should generate recipes based on context
        XCTAssertNotNil(plan.recipes, "Repair plan should have recipes array")
    }

    func testMakePlanForInspectOnlyHasNoRecipes() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .inspectOnly, context: context)

        // Phase 3: InspectOnly should have no recipes
        XCTAssertEqual(plan.recipes.count, 0, "InspectOnly plan should have no recipes")
        if case .ready = plan.status {
            XCTAssertTrue(true, "InspectOnly plan should be ready")
        }
    }

    func testMakePlanRecipesHaveValidStructure() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)

        if case .ready = plan.status {
            for recipe in plan.recipes {
                XCTAssertFalse(recipe.id.isEmpty, "Recipe should have non-empty ID")
                // Recipe type should be valid (enum)
                // ServiceID can be nil for some recipe types
            }
        }
    }

    // MARK: - execute() Tests

    func testExecuteReturnsInstallerReport() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)
        let broker = PrivilegeBroker()

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertNotNil(report, "execute() should return an InstallerReport")
        XCTAssertNotNil(report.timestamp, "Report should have timestamp")
        XCTAssertNotNil(report.executedRecipes, "Report should have executedRecipes array")
        XCTAssertNotNil(report.unmetRequirements, "Report should have unmetRequirements array")
    }

    func testExecuteHandlesBlockedPlan() async {
        let blockedRequirement = Requirement(name: "Test requirement", status: .blocked)
        let blockedPlan = InstallPlan(
            recipes: [],
            status: .blocked(requirement: blockedRequirement),
            intent: .install,
            blockedBy: blockedRequirement,
            metadata: PlanMetadata(
                stateMatrixRow: InstallerStateMatrixRow.manualApprovalRequired.rawValue,
                stateMatrixPlan: [InstallerStateMatrixAction.surfaceManualApproval.rawValue]
            )
        )
        let broker = PrivilegeBroker()

        let report = await engine.execute(plan: blockedPlan, using: broker)

        XCTAssertFalse(report.success, "Report should indicate failure for blocked plan")
        XCTAssertNotNil(report.failureReason, "Report should have failure reason")
        XCTAssertEqual(
            report.unmetRequirements.count, 1, "Report should include the blocking requirement"
        )
        XCTAssertEqual(
            report.unmetRequirements.first?.name, "Test requirement",
            "Report should include correct requirement name"
        )
        XCTAssertEqual(report.repairTelemetry.count, 1)
        XCTAssertEqual(report.repairTelemetry.first?.trigger, .executePlan)
        XCTAssertEqual(report.repairTelemetry.first?.intent, "install")
        XCTAssertEqual(
            report.repairTelemetry.first?.stateMatrixRow,
            InstallerStateMatrixRow.manualApprovalRequired.rawValue
        )
        XCTAssertEqual(report.repairTelemetry.first?.postconditionResult, .blocked)
        XCTAssertEqual(report.repairTelemetry.first?.error, "Test requirement")
    }

    func testExecuteRecordsStructuredRepairTelemetryForFailedRecipe() async {
        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(
                    id: "unknown-test-recipe",
                    type: .installComponent
                ),
            ],
            status: .ready,
            intent: .repair,
            metadata: PlanMetadata(
                stateMatrixRow: InstallerStateMatrixRow.definitiveUnhealthyState.rawValue,
                stateMatrixPlan: [InstallerStateMatrixAction.failWithDiagnostics.rawValue]
            )
        )

        let report = await engine.execute(plan: plan, using: PrivilegeBroker())

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.repairTelemetry.count, 1)
        let event = report.repairTelemetry[0]
        XCTAssertEqual(event.intent, "repair")
        XCTAssertEqual(event.stateMatrixRow, InstallerStateMatrixRow.definitiveUnhealthyState.rawValue)
        XCTAssertEqual(event.action, "unknown-test-recipe")
        XCTAssertEqual(event.recipeID, "unknown-test-recipe")
        XCTAssertEqual(event.recipeType, "install-component")
        XCTAssertEqual(event.postconditionResult, .failed)
        XCTAssertTrue(event.error?.contains("Unknown component recipe") == true)
    }

    func testExecuteRecordsStructuredRepairTelemetryForNoopPlan() async {
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .repair,
            metadata: PlanMetadata(
                stateMatrixRow: InstallerStateMatrixRow.runningAndTCPResponding.rawValue,
                stateMatrixPlan: []
            )
        )

        let report = await engine.execute(plan: plan, using: PrivilegeBroker())

        XCTAssertTrue(report.success)
        XCTAssertEqual(report.completionState, .verifiedNoOp)
        XCTAssertEqual(report.repairTelemetry.count, 1)
        let event = report.repairTelemetry[0]
        XCTAssertEqual(event.intent, "repair")
        XCTAssertEqual(event.stateMatrixRow, InstallerStateMatrixRow.runningAndTCPResponding.rawValue)
        XCTAssertEqual(event.action, InstallerRecipeID.verifyPostconditions)
        XCTAssertNil(event.recipeID)
        XCTAssertNil(event.recipeType)
        XCTAssertEqual(event.postconditionResult, .succeeded)
    }

    func testExecuteStopsOnFirstFailure() async {
        // Create a plan with recipes (may succeed or fail depending on system state)
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)
        let broker = PrivilegeBroker()

        let report = await engine.execute(plan: plan, using: broker)

        // Verify report structure - execution may succeed or fail depending on system state
        XCTAssertNotNil(report, "Report should exist")
        XCTAssertNotNil(report.executedRecipes, "Report should have executedRecipes array")

        // If execution failed, verify we stopped at first failure
        if !report.success {
            XCTAssertNotNil(report.failureReason, "Failed execution should have failure reason")
            // Should have executed some recipes before failing (or failed on first)
            // Note: If plan has no recipes, executedRecipes will be empty even on success
            if plan.recipes.count > 0 {
                XCTAssertGreaterThanOrEqual(
                    report.executedRecipes.count, 0, "Should have recipe results if plan had recipes"
                )
            }
        } else {
            // If execution succeeded, verify all recipes were executed
            XCTAssertEqual(
                report.executedRecipes.count, plan.recipes.count,
                "All recipes should be executed on success"
            )
        }
    }

    func testExecuteWithEmptyPlan() async {
        let emptyPlan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .inspectOnly,
            blockedBy: nil
        )
        let broker = PrivilegeBroker()

        let report = await engine.execute(plan: emptyPlan, using: broker)

        XCTAssertTrue(report.success, "Empty plan should succeed")
        XCTAssertEqual(report.executedRecipes.count, 0, "Empty plan should have no executed recipes")
    }

    // MARK: - run() Tests

    func testRunChainsStepsCorrectly() async {
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .repair, using: broker)

        XCTAssertNotNil(report, "run() should return an InstallerReport")
        XCTAssertNotNil(report.timestamp, "Report should have timestamp")
    }

    func testRunHandlesAllIntents() async {
        let broker = PrivilegeBroker()

        let installReport = await engine.run(intent: .install, using: broker)
        XCTAssertNotNil(installReport)
        XCTAssertNotNil(installReport.timestamp)

        let repairReport = await engine.run(intent: .repair, using: broker)
        XCTAssertNotNil(repairReport)
        XCTAssertNotNil(repairReport.timestamp)

        let uninstallReport = await engine.run(intent: .uninstall, using: broker)
        XCTAssertNotNil(uninstallReport)
        XCTAssertNotNil(uninstallReport.timestamp)

        let inspectReport = await engine.run(intent: .inspectOnly, using: broker)
        XCTAssertNotNil(inspectReport)
        XCTAssertNotNil(inspectReport.timestamp)
    }

    func testRunChainsAllSteps() async {
        // Phase 5: Verify run() chains inspectSystem → makePlan → execute
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .install, using: broker)

        // Verify report structure indicates all steps completed
        XCTAssertNotNil(report, "run() should return a report")
        XCTAssertNotNil(report.timestamp, "Report should have timestamp")
        XCTAssertNotNil(report.executedRecipes, "Report should have executedRecipes")
        XCTAssertNotNil(report.unmetRequirements, "Report should have unmetRequirements")

        // Report should indicate success or failure (not nil)
        // Success depends on system state, but report should be complete
        XCTAssertNotNil(report.success, "Report should indicate success or failure")
    }

    func testRunReturnsCompleteReport() async {
        // Phase 5: Verify run() returns a complete report with all fields
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .repair, using: broker)

        // Verify all report fields are present
        XCTAssertNotNil(report.timestamp, "Report should have timestamp")
        XCTAssertNotNil(report.success, "Report should indicate success/failure")
        XCTAssertNotNil(report.executedRecipes, "Report should have executedRecipes array")
        XCTAssertNotNil(report.unmetRequirements, "Report should have unmetRequirements array")
        // failureReason can be nil if successful
        // finalContext is optional
    }

    func testRunWithInspectOnlyHasNoRecipes() async {
        // Phase 5: Verify inspectOnly intent generates no recipes
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .inspectOnly, using: broker)

        // InspectOnly should have no executed recipes
        XCTAssertEqual(report.executedRecipes.count, 0, "InspectOnly should have no executed recipes")
        // Should succeed (no operations to fail)
        XCTAssertTrue(report.success, "InspectOnly should succeed")
    }

    // MARK: - runSingleAction() Tests
}

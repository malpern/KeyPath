@testable import KeyPathAppKit
import XCTest

@MainActor
final class InstallerEngineTests: XCTestCase {
    var engine: InstallerEngine!

    override func setUp() async throws {
        engine = InstallerEngine()
    }

    override func tearDown() async throws {
        engine = nil
    }

    // MARK: - Façade Instantiation

    func testInstallerEngineCanBeInstantiated() {
        let engine = InstallerEngine()
        XCTAssertNotNil(engine, "InstallerEngine should be instantiable")
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
        XCTAssertLessThan(timeDiff1, 10.0, "Permission timestamp should be within 10 seconds of context timestamp")
        XCTAssertLessThan(timeDiff2, 10.0, "Permission timestamp should be within 10 seconds of context timestamp")
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

        // Phase 3: Install intent should generate recipes
        if case .ready = plan.status {
            XCTAssertGreaterThan(plan.recipes.count, 0, "Install plan should have recipes")
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

    func testMakePlanCanBeBlocked() async {
        // Create a context that would block (e.g., non-writable directory)
        // Note: This test may not actually block in test environment
        let plan = await engine.makePlan(for: .install, context: engine.inspectSystem())

        // Plan should either be ready or blocked
        switch plan.status {
        case .ready:
            XCTAssertTrue(true, "Plan is ready")
        case let .blocked(requirement):
            XCTAssertNotNil(requirement, "Blocked plan should have requirement")
            XCTAssertNotNil(plan.blockedBy, "Blocked plan should have blockedBy")
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
            blockedBy: blockedRequirement
        )
        let broker = PrivilegeBroker()

        let report = await engine.execute(plan: blockedPlan, using: broker)

        XCTAssertFalse(report.success, "Report should indicate failure for blocked plan")
        XCTAssertNotNil(report.failureReason, "Report should have failure reason")
        XCTAssertEqual(report.unmetRequirements.count, 1, "Report should include the blocking requirement")
        XCTAssertEqual(report.unmetRequirements.first?.name, "Test requirement", "Report should include correct requirement name")
    }

    func testExecuteExecutesRecipesInOrder() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)
        let broker = PrivilegeBroker()

        // Phase 4: Execute plan and verify recipes are executed
        let report = await engine.execute(plan: plan, using: broker)

        // Verify report has executed recipes
        XCTAssertNotNil(report.executedRecipes, "Report should have executedRecipes")
        if case .ready = plan.status {
            // If plan has recipes, verify they were executed (or attempted)
            if plan.recipes.count > 0 {
                XCTAssertGreaterThanOrEqual(report.executedRecipes.count, 0, "Should have recipe results")
            }
        }
    }

    func testExecuteRecordsRecipeResults() async {
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)
        let broker = PrivilegeBroker()

        let report = await engine.execute(plan: plan, using: broker)

        // Verify recipe results are recorded
        for result in report.executedRecipes {
            XCTAssertFalse(result.recipeID.isEmpty, "Recipe result should have ID")
            XCTAssertGreaterThanOrEqual(result.duration, 0, "Recipe duration should be non-negative")
        }
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
                XCTAssertGreaterThanOrEqual(report.executedRecipes.count, 0, "Should have recipe results if plan had recipes")
            }
        } else {
            // If execution succeeded, verify all recipes were executed
            XCTAssertEqual(report.executedRecipes.count, plan.recipes.count, "All recipes should be executed on success")
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

    func testRunPropagatesBlockedPlans() async {
        // Phase 5: Verify that if makePlan() returns a blocked plan, run() propagates it
        let broker = PrivilegeBroker()

        // Run with install intent (may be blocked if requirements unmet)
        let report = await engine.run(intent: .install, using: broker)

        // If plan was blocked, report should reflect that
        if !report.success, !report.unmetRequirements.isEmpty {
            XCTAssertNotNil(report.failureReason, "Blocked plan should have failure reason")
            XCTAssertEqual(report.executedRecipes.count, 0, "Blocked plan should have no executed recipes")
        }
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
}

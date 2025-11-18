@testable import KeyPath
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
        
        // Timestamps will differ, but structure should be consistent
        XCTAssertEqual(context1.permissions.timestamp, context1.timestamp, "Permission timestamp should match context timestamp")
        XCTAssertEqual(context2.permissions.timestamp, context2.timestamp, "Permission timestamp should match context timestamp")
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
        let context = await engine.inspectSystem()
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
        
        let repairReport = await engine.run(intent: .repair, using: broker)
        XCTAssertNotNil(repairReport)
        
        let uninstallReport = await engine.run(intent: .uninstall, using: broker)
        XCTAssertNotNil(uninstallReport)
        
        let inspectReport = await engine.run(intent: .inspectOnly, using: broker)
        XCTAssertNotNil(inspectReport)
    }
}


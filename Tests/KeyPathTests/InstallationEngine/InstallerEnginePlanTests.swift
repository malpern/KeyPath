@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEnginePlanTests: KeyPathAsyncTestCase {
    func testInstallPlanIncludesRuntimeServicesAndBundledKanata() async {
        let engine = InstallerEngine()
        let context = SystemContextBuilder.cleanInstall()

        let plan = await engine.makePlan(for: .install, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertFalse(ids.isEmpty, "Install plan should produce recipes for clean installs")
        XCTAssertTrue(ids.contains(InstallerRecipeID.installRequiredRuntimeServices), "Should install required runtime services")
        XCTAssertTrue(ids.contains(InstallerRecipeID.installMissingComponents), "Should install missing components")
    }

    func testRepairPlanTargetsUnhealthyServices() async {
        let engine = InstallerEngine()
        let context = SystemContextBuilder.degradedRepair()

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(InstallerRecipeID.installRequiredRuntimeServices)
                || ids.contains(InstallerRecipeID.repairVHIDDaemonServices)
                || ids.contains(InstallerRecipeID.startKarabinerDaemon),
            "Repair plan should use concrete split-runtime service repair actions"
        )
    }

    func testExecuteSkipsRecipesAfterFailure() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        coordinator.failOnCall = "installRequiredRuntimeServices"
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: InstallerRecipeID.installRequiredRuntimeServices, type: .installComponent),
                ServiceRecipe(id: InstallerRecipeID.installMissingComponents, type: .installComponent),
                ServiceRecipe(id: InstallerRecipeID.startKarabinerDaemon, type: .restartService, serviceID: KeyPathConstants.Bundle.vhidDaemonID)
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.success, "Failure should propagate")
        XCTAssertFalse(coordinator.calls.contains("downloadAndInstallCorrectVHIDDriver"), "Later recipes should not execute after failure")
        XCTAssertFalse(coordinator.calls.contains("restartKarabinerDaemonVerified"), "Later recipes should not execute after failure")
        XCTAssertEqual(report.executedRecipes.count, 1, "Execution should stop immediately after first failure")
    }
}

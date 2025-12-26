@preconcurrency import XCTest

@testable import KeyPathAppKit
@testable import KeyPathWizardCore

@MainActor
final class InstallerEnginePlanTests: KeyPathAsyncTestCase {
    func testInstallPlanIncludesLaunchDaemonAndBundledKanata() async {
        let engine = InstallerEngine()
        let context = SystemContextBuilder.cleanInstall()

        let plan = await engine.makePlan(for: .install, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertFalse(ids.isEmpty, "Install plan should produce recipes for clean installs")
        XCTAssertTrue(ids.contains(InstallerRecipeID.installLaunchDaemonServices), "Should install LaunchDaemon services")
        XCTAssertTrue(ids.contains(InstallerRecipeID.installBundledKanata), "Should install bundled Kanata binary")
    }

    func testRepairPlanTargetsUnhealthyServices() async {
        let engine = InstallerEngine()
        let context = SystemContextBuilder.degradedRepair()

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(ids.contains("restart-unhealthy-services") || ids.contains("repair-vhid-daemon-services"),
                      "Repair plan should attempt to restart/repair unhealthy services")
    }

    func testExecuteSkipsRecipesAfterFailure() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        coordinator.failOnCall = "installAllLaunchDaemonServices"
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-daemons", type: .installService),
                ServiceRecipe(id: "install-bundled-kanata", type: .installComponent),
                ServiceRecipe(id: "restart-unhealthy-services", type: .restartService)
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.success, "Failure should propagate")
        XCTAssertFalse(coordinator.calls.contains("installBundledKanata"), "Later recipes should not execute after failure")
        XCTAssertFalse(coordinator.calls.contains("restartUnhealthyServices"), "Later recipes should not execute after failure")
        XCTAssertEqual(report.executedRecipes.count, 1, "Execution should stop immediately after first failure")
    }
}

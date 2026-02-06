@testable import KeyPathAppKit
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEngineEndToEndTests: KeyPathAsyncTestCase {
    func testExecutePlanInvokesBrokerAndSucceeds() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-daemons", type: .installService),
                ServiceRecipe(id: "install-bundled-kanata", type: .installComponent)
            ],
            status: .ready,
            intent: .install
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertTrue(report.success, "Execution should succeed when broker operations succeed")
        XCTAssertTrue(
            coordinator.calls.contains("installAllLaunchDaemonServices"),
            "Install service recipe should attempt to install LaunchDaemon services"
        )
        XCTAssertTrue(
            coordinator.calls.contains("installBundledKanata"),
            "Component recipe should install bundled Kanata"
        )
    }

    func testExecutePlanStopsOnBrokerFailure() async {
        let coordinator = StubPrivilegedOperationsCoordinator()
        coordinator.failOnCall = "installAllLaunchDaemonServices"
        let broker = PrivilegeBroker(coordinator: coordinator)
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-daemons", type: .installService),
                ServiceRecipe(id: "install-bundled-kanata", type: .installComponent)
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan, using: broker)

        XCTAssertFalse(report.success, "Failure from broker should mark report unsuccessful")
        XCTAssertEqual(report.executedRecipes.count, 1, "Execution should stop on first failure")
        XCTAssertTrue(
            report.failureReason?.contains("install-daemons") ?? false,
            "Failure should reference the failing recipe"
        )
    }
}

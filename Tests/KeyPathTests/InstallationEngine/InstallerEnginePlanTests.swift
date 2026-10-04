@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEnginePlanTests: KeyPathAsyncTestCase {
    func testHelperFreshPostconditionRejectsWorkingHelperWithUnknownVersion() {
        let context = SystemContextBuilder(
            helperReady: true,
            helperVersion: nil
        ).build()

        XCTAssertTrue(InstallerPostcondition.helperReadyOrApprovalPending.isSatisfied(by: context))
        XCTAssertFalse(InstallerPostcondition.helperFreshOrApprovalPending.isSatisfied(by: context))
    }

    func testHelperFreshPostconditionAcceptsExactVersionOrPendingApproval() {
        let freshContext = SystemContextBuilder(
            helperReady: true,
            helperVersion: WizardHelperConstants.expectedHelperVersion
        ).build()
        let approvalContext = SystemContextBuilder(
            helperReady: false,
            helperRequiresApproval: true,
            helperVersion: nil
        ).build()

        XCTAssertTrue(InstallerPostcondition.helperFreshOrApprovalPending.isSatisfied(by: freshContext))
        XCTAssertTrue(InstallerPostcondition.helperFreshOrApprovalPending.isSatisfied(by: approvalContext))
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

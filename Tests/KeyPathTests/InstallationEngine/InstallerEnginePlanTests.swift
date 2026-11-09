@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEnginePlanTests: KeyPathAsyncTestCase {
    func testRuntimePostconditionAcceptsReadyRuntimeOrPendingApproval() {
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let stopped = SystemContextBuilder.cleanInstall()
        let pendingApproval = SystemContextBuilder(loginItemsApprovalRequired: true).build()

        XCTAssertTrue(InstallerPostcondition.runtimeReadyOrApprovalPending.isSatisfied(by: ready))
        XCTAssertFalse(InstallerPostcondition.runtimeReadyOrApprovalPending.isSatisfied(by: stopped))
        XCTAssertTrue(InstallerPostcondition.runtimeReadyOrApprovalPending.isSatisfied(by: pendingApproval))
    }

    func testExecuteSkipsRecipesAfterFailure() async {
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-required-runtime-services", type: .installComponent),
                ServiceRecipe(id: "install-missing-components", type: .installComponent),
                ServiceRecipe(id: "start-karabiner-daemon", type: .restartService, serviceID: KeyPathConstants.Bundle.vhidDaemonID)
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan)

        XCTAssertFalse(report.success, "Failure should propagate")
        XCTAssertTrue(report.executedRecipes.isEmpty, "Preflight must refuse the whole unsupported plan")
    }
}

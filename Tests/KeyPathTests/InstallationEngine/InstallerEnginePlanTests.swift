@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class InstallerEnginePlanTests: KeyPathAsyncTestCase {
    func testRuntimePostconditionRequiresAReadyRuntime() {
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let stopped = SystemContextBuilder.cleanInstall()
        let pendingApproval = SystemContextBuilder(loginItemsApprovalRequired: true).build()

        XCTAssertTrue(InstallerPostcondition.runtimeReadyOrApprovalPending.isSatisfied(by: ready))
        XCTAssertFalse(InstallerPostcondition.runtimeReadyOrApprovalPending.isSatisfied(by: stopped))
        // Login Items approval belonged to the retired daemon; it no longer counts.
        XCTAssertFalse(InstallerPostcondition.runtimeReadyOrApprovalPending.isSatisfied(by: pendingApproval))
    }

    func testExecuteSkipsRecipesAfterFailure() async {
        let engine = InstallerEngine()

        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "install-required-runtime-services", type: .installComponent),
                ServiceRecipe(id: "install-missing-components", type: .installComponent),
                ServiceRecipe(id: "start-karabiner-daemon", type: .checkRequirement)
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(plan: plan)

        XCTAssertFalse(report.success, "Failure should propagate")
        XCTAssertTrue(report.executedRecipes.isEmpty, "Preflight must refuse the whole unsupported plan")
    }
}

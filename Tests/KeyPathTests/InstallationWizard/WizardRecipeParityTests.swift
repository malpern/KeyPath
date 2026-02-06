@testable import KeyPathAppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// Characterization tests to ensure auto-fix actions map to the same recipes the planner uses.
@MainActor
final class WizardRecipeParityTests: XCTestCase {
    func testRecipeIDsMatchForCommonActions() {
        let engine = InstallerEngine()
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let actions: [AutoFixAction] = [
            .installBundledKanata,
            .installLaunchDaemonServices,
            .restartUnhealthyServices,
            .terminateConflictingProcesses
        ]

        for action in actions {
            guard let recipe = engine.recipeForAction(action, context: context) else {
                XCTFail("Missing recipe for action \(action)")
                continue
            }
            XCTAssertEqual(
                recipe.id,
                engine.recipeIDForAction(action),
                "recipeForAction and recipeIDForAction should agree for \(action)"
            )
        }
    }

    func testInstallPlanIncludesBundledKanataWhenComponentsMissing() async {
        let engine = InstallerEngine()
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: false
        ).build()

        let plan = await engine.makePlan(for: .install, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.installBundledKanata)),
            "Install plan should include bundled kanata when components are missing"
        )
    }

    func testRepairPlanRestartsServicesWhenUnhealthy() async {
        let engine = InstallerEngine()
        let context = SystemContextBuilder(
            permissionsStatus: .granted,
            helperReady: true,
            servicesHealthy: false,
            componentsInstalled: true
        ).build()

        let plan = await engine.makePlan(for: .repair, context: context)
        let ids = plan.recipes.map(\.id)

        XCTAssertTrue(
            ids.contains(engine.recipeIDForAction(.restartUnhealthyServices)),
            "Repair plan should restart unhealthy services when health is false"
        )
    }
}

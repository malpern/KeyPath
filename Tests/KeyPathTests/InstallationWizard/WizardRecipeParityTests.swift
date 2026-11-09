import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
@preconcurrency import XCTest

/// Executable session plans and individual actions must share the same restricted recipes.
@MainActor
final class WizardRecipeParityTests: KeyPathTestCase {
    private func context(running: Bool) -> SystemContext {
        let now = Date()
        return SystemContext(
            permissions: .fixture(source: "session-test", timestamp: now),
            services: HealthStatus(
                kanataProcessRunning: running, kanataTCPResponding: running,
                kanataRunning: running, kanataInputCaptureReady: running
            ),
            conflicts: .empty,
            components: ComponentStatus(
                kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true
            ),
            system: EngineSystemInfo(macOSVersion: "27.0"),
            timestamp: now
        )
    }

    func testSupportedActionIDsMatchRestrictedRecipes() {
        let engine = InstallerEngine()
        for action in [AutoFixAction.restartCommServer, .synchronizeConfigPaths] {
            let recipe = engine.recipeForAction(action, context: context(running: false))
            XCTAssertEqual(recipe.id, engine.recipeIDForAction(action))
            XCTAssertTrue(recipe.dependencies.isEmpty)
        }
    }

    func testInstallAndRepairPlansOnlyStartMissingSession() async {
        let engine = InstallerEngine()
        for intent in [InstallIntent.install, .repair] {
            let captured = context(running: false)
            let plan = await engine.makePlan(for: intent, context: captured)
            XCTAssertEqual(plan.recipes.map(\.id), [engine.recipeIDForAction(.restartCommServer)])
            XCTAssertEqual(plan.recipes.first?.expectedPostconditions, [.runtimeReadyOrApprovalPending])
            XCTAssertEqual(plan.sourceSnapshotID, captured.snapshotID)
        }
    }

    func testReadySessionHasNoHelperOrDriverRepairPlan() async {
        let engine = InstallerEngine()
        for intent in [InstallIntent.install, .repair] {
            let captured = context(running: true)
            let plan = await engine.makePlan(for: intent, context: captured)
            XCTAssertTrue(plan.recipes.isEmpty)
            XCTAssertEqual(plan.sourceSnapshotID, captured.snapshotID)
        }
    }
}

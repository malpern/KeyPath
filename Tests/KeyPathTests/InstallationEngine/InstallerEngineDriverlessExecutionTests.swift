@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

@MainActor
final class InstallerEngineDriverlessExecutionTests: KeyPathTestCase {
    func testOnlySessionStartIsPlannedRegardlessOfLegacyDriverMetadata() async {
        let engine = InstallerEngine()
        for intent in [InstallIntent.install, .repair] {
            let stopped = SystemContextBuilder.cleanInstall()
            let plan = await engine.makePlan(for: intent, context: stopped)
            XCTAssertEqual(plan.recipes.map(\.id), ["start-session-runtime"])
            XCTAssertEqual(plan.sourceSnapshotID, stopped.snapshotID)
            XCTAssertFalse(plan.metadata.promptsNeeded)
            let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
            let noOp = await engine.makePlan(for: intent, context: ready)
            XCTAssertTrue(noOp.recipes.isEmpty)
        }
    }

    func testMalformedAndPrivilegedRecipesCannotExecuteOrBecomeVerifiedSuccess() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let final = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let engine = InstallerEngine(systemValidator: StubSystemValidator(context: final))
        let recipes = [
            ServiceRecipe(id: "forged-component", type: .installComponent),
            ServiceRecipe(id: "start-session-runtime", type: .checkRequirement,
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent, dependencies: ["injected"],
                          expectedPostconditions: [.runtimeReadyOrApprovalPending])
        ]
        for recipe in recipes {
            let plan = InstallPlan(recipes: [recipe], status: .ready, intent: .repair,
                                   initialPostconditionStates: [.runtimeReadyOrApprovalPending: false])
            let report = await engine.execute(plan: plan)
            XCTAssertFalse(report.success, "Malformed recipe must never execute")
            XCTAssertTrue(report.failureReason?.contains("unavailable in the driverless build") ?? false)
            XCTAssertTrue(report.executedRecipes.isEmpty)
            XCTAssertNotNil(report.finalContext)
        }
        XCTAssertEqual(runtime.starts, 0)
    }

    func testMixedPlanRefusesBeforePermittedSessionStart() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let context = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let engine = InstallerEngine(systemValidator: StubSystemValidator(context: context))
        let permitted = engine.recipeForAction(.startSessionRuntime)
        let plan = InstallPlan(recipes: [permitted, ServiceRecipe(id: "forbidden-recipe", type: .installComponent)],
                               status: .ready, intent: .repair)
        let report = await engine.execute(plan: plan)
        XCTAssertFalse(report.success)
        XCTAssertTrue(report.executedRecipes.isEmpty)
        XCTAssertEqual(runtime.starts, 0)
        XCTAssertEqual(report.planID, plan.id)
        XCTAssertEqual(report.finalContext?.snapshotID, context.snapshotID)
    }

    func testExternallyConstructedInspectionAndUninstallPlansCannotStartRuntime() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let engine = InstallerEngine()
        let recipe = engine.recipeForAction(.startSessionRuntime)
        for intent in [InstallIntent.inspectOnly, .uninstall] {
            let plan = InstallPlan(recipes: [recipe], status: .ready, intent: intent)
            let report = await engine.execute(plan: plan)
            XCTAssertFalse(report.success)
            XCTAssertEqual(report.planID, plan.id)
            XCTAssertTrue(report.executedRecipes.isEmpty)
        }
        XCTAssertEqual(runtime.starts, 0)
    }

    func testSessionStartRequiresFreshCompleteRuntimeReadiness() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let stopped = SystemContextBuilder.cleanInstall()
        for final in [ready, stopped] {
            let engine = InstallerEngine(systemValidator: StubSystemValidator(context: final))
            let recipe = engine.recipeForAction(.startSessionRuntime)
            let plan = InstallPlan(recipes: [recipe], status: .ready, intent: .repair)
            let report = await engine.execute(plan: plan)
            XCTAssertEqual(report.success, final.services.kanataRuntimeReadiness.isReady)
            XCTAssertEqual(report.finalContext?.snapshotID, final.snapshotID)
            if !report.success {
                XCTAssertEqual(report.completionState, .verificationFailed)
                XCTAssertEqual(report.failedPostconditions, [.runtimeReadyOrApprovalPending])
            }
        }
        XCTAssertEqual(runtime.starts, 2)
    }
}

@MainActor
private final class RuntimeStub: RuntimeCoordinating {
    var starts = 0
    var lastError: String?
    func startKanata(reason _: String) async -> Bool {
        starts += 1; return true
    }

    func stopKanata(reason _: String) async -> Bool {
        true
    }

    func restartKanata(reason _: String) async -> Bool {
        true
    }

    func updateStatus() async {}
    func currentRuntimeStatus() async -> WizardRuntimeStatus {
        .stopped
    }

    func isInTransientRuntimeStartupWindow() async -> Bool {
        false
    }

    func openAccessibilitySettings() {}
}

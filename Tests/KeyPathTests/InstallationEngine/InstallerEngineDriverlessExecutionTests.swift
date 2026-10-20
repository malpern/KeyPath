@testable import KeyPathAppKit
import KeyPathCore
import KeyPathDaemonLifecycle
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
        let coordinator = StubPrivilegedOperationsCoordinator()
        let final = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let engine = InstallerEngine(processLifecycleManager: ProcessLifecycleManager(),
                                     systemValidator: StubSystemValidator(context: final))
        let recipes = [
            ServiceRecipe(id: "forged-service", type: .installService),
            ServiceRecipe(id: "forged-restart", type: .restartService),
            ServiceRecipe(id: "forged-helper", type: .repairPrivilegedHelper),
            ServiceRecipe(id: "start-session-runtime", type: .restartService,
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent, serviceID: "system-service",
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent,
                          launchctlActions: [.kickstart(serviceID: "system-service")],
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent, plistContent: "injected",
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent,
                          healthCheck: .init(serviceID: "system-service", shouldBeRunning: true),
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent,
                          expectedPostconditions: [.helperReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent, dependencies: ["injected"],
                          expectedPostconditions: [.runtimeReadyOrApprovalPending]),
            ServiceRecipe(id: "start-session-runtime", type: .installComponent,
                          expectedPostconditions: [.runtimeReadyOrApprovalPending],
                          conflictsToResolve: [.kanataProcessRunning(pid: 123, command: "kanata")])
        ]
        for recipe in recipes {
            let plan = InstallPlan(recipes: [recipe], status: .ready, intent: .repair,
                                   initialPostconditionStates: [.runtimeReadyOrApprovalPending: false,
                                                                .helperReadyOrApprovalPending: false])
            let report = await engine.execute(plan: plan, using: PrivilegeBroker(coordinator: coordinator))
            XCTAssertFalse(report.success, "Malformed recipe must never execute")
            XCTAssertTrue(report.failureReason?.contains("unavailable in the driverless build") ?? false)
            XCTAssertTrue(report.executedRecipes.isEmpty)
            XCTAssertNotNil(report.finalContext)
        }
        XCTAssertEqual(runtime.starts, 0)
        XCTAssertTrue(coordinator.calls.isEmpty)
    }

    func testMixedPlanRefusesBeforePermittedSessionStart() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let coordinator = StubPrivilegedOperationsCoordinator()
        let context = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let engine = InstallerEngine(processLifecycleManager: ProcessLifecycleManager(),
                                     systemValidator: StubSystemValidator(context: context))
        let permitted = engine.recipeForAction(.restartCommServer, context: context)!
        let plan = InstallPlan(recipes: [permitted, ServiceRecipe(id: "forbidden-helper", type: .repairPrivilegedHelper)],
                               status: .ready, intent: .repair)
        let report = await engine.execute(plan: plan, using: PrivilegeBroker(coordinator: coordinator))
        XCTAssertFalse(report.success)
        XCTAssertTrue(report.executedRecipes.isEmpty)
        XCTAssertEqual(runtime.starts, 0)
        XCTAssertTrue(coordinator.calls.isEmpty)
        XCTAssertEqual(report.planID, plan.id)
        XCTAssertEqual(report.finalContext?.snapshotID, context.snapshotID)
    }

    func testExternallyConstructedInspectionAndUninstallPlansCannotStartRuntime() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let coordinator = StubPrivilegedOperationsCoordinator()
        let engine = InstallerEngine()
        let recipe = engine.recipeForAction(.restartCommServer, context: .empty)!
        for intent in [InstallIntent.inspectOnly, .uninstall] {
            let plan = InstallPlan(recipes: [recipe], status: .ready, intent: intent)
            let report = await engine.execute(plan: plan, using: PrivilegeBroker(coordinator: coordinator))
            XCTAssertFalse(report.success)
            XCTAssertEqual(report.planID, plan.id)
            XCTAssertTrue(report.executedRecipes.isEmpty)
        }
        XCTAssertEqual(runtime.starts, 0)
        XCTAssertTrue(coordinator.calls.isEmpty)
    }

    func testSessionStartRequiresFreshCompleteRuntimeReadiness() async {
        let runtime = RuntimeStub()
        let previous = WizardDependencies.runtimeCoordinator
        WizardDependencies.runtimeCoordinator = runtime
        defer { WizardDependencies.runtimeCoordinator = previous }
        let coordinator = StubPrivilegedOperationsCoordinator()
        let ready = SystemContextBuilder(servicesHealthy: true, componentsInstalled: true).build()
        let stoppedWithLegacyApproval = SystemContextBuilder(loginItemsApprovalRequired: true).build()
        for final in [ready, stoppedWithLegacyApproval] {
            let engine = InstallerEngine(processLifecycleManager: ProcessLifecycleManager(),
                                         systemValidator: StubSystemValidator(context: final))
            let recipe = engine.recipeForAction(.restartCommServer, context: final)!
            let plan = InstallPlan(recipes: [recipe], status: .ready, intent: .repair)
            let report = await engine.execute(plan: plan, using: PrivilegeBroker(coordinator: coordinator))
            XCTAssertEqual(report.success, final.services.kanataRuntimeReadiness.isReady)
            XCTAssertEqual(report.finalContext?.snapshotID, final.snapshotID)
            if !report.success {
                XCTAssertEqual(report.completionState, .verificationFailed)
                XCTAssertEqual(report.failedPostconditions, [.runtimeReadyOrApprovalPending])
            }
        }
        XCTAssertEqual(runtime.starts, 2)
        XCTAssertTrue(coordinator.calls.isEmpty)
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

    func openInputMonitoringSettings() {}
    func openAccessibilitySettings() {}
    func isKarabinerElementsRunning() async -> Bool {
        false
    }

    func isKarabinerDriverInstalled() -> Bool {
        false
    }

    func getVirtualHIDBreakageSummary() async -> String {
        "Unavailable"
    }
}

@testable import KeyPathAppKit
import KeyPathCore
@testable import KeyPathInstallationWizard
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
        XCTAssertEqual(plan.sourceSnapshotID, context.snapshotID)
        XCTAssertTrue(ids.contains(InstallerRecipeID.installRequiredRuntimeServices), "Should install required runtime services")
        XCTAssertTrue(ids.contains(InstallerRecipeID.installMissingComponents), "Should install missing components")
        XCTAssertTrue(plan.expectedPostconditions.contains(.runtimeReadyOrApprovalPending))
        XCTAssertTrue(plan.expectedPostconditions.contains(.vhidServicesHealthy))
        XCTAssertTrue(plan.expectedPostconditions.contains(.virtualHIDDriverInstalled))
        XCTAssertEqual(plan.initialPostconditionStates?[.runtimeReadyOrApprovalPending], false)
        XCTAssertEqual(plan.initialPostconditionStates?[.vhidServicesHealthy], false)
        XCTAssertEqual(plan.initialPostconditionStates?[.virtualHIDDriverInstalled], false)
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

    func testMissingVHIDDeviceProducesExplicitActivationBeforeServiceWork() async throws {
        let base = SystemContextBuilder(
            servicesHealthy: false,
            componentsInstalled: true
        ).build()
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: false,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: false,
            vhidVersionMismatch: false
        )
        let context = SystemContext(
            snapshotID: base.snapshotID,
            permissions: base.permissions,
            services: base.services,
            conflicts: base.conflicts,
            components: components,
            helper: base.helper,
            system: base.system,
            timestamp: base.timestamp
        )

        for intent in [InstallIntent.install, .repair] {
            let plan = await InstallerEngine().makePlan(for: intent, context: context)
            let ids = plan.recipes.map(\.id)
            let installIndex = try XCTUnwrap(ids.firstIndex(of: InstallerRecipeID.installMissingComponents))
            let activationIndex = try XCTUnwrap(ids.firstIndex(of: InstallerRecipeID.activateVHIDManager))
            let daemonIndex = try XCTUnwrap(ids.firstIndex(of: InstallerRecipeID.startKarabinerDaemon))

            XCTAssertLessThan(installIndex, activationIndex)
            XCTAssertLessThan(activationIndex, daemonIndex)
        }
    }

    func testManualVHIDApprovalDoesNotPlanActivationOrDaemonStart() {
        let base = SystemContextBuilder(
            servicesHealthy: false,
            kanataInputCaptureReady: false,
            kanataInputCaptureIssue: ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason,
            componentsInstalled: true
        ).build()
        let components = ComponentStatus(
            kanataBinaryInstalled: true,
            karabinerDriverInstalled: true,
            karabinerDaemonRunning: false,
            vhidDeviceInstalled: false,
            vhidDeviceHealthy: false,
            vhidServicesHealthy: false,
            vhidVersionMismatch: false
        )
        let context = SystemContext(
            snapshotID: base.snapshotID,
            permissions: base.permissions,
            services: base.services,
            conflicts: base.conflicts,
            components: components,
            helper: base.helper,
            system: base.system,
            timestamp: base.timestamp
        )

        for intent in [InstallIntent.install, .repair] {
            let actions = InstallerDecisionPipeline.determineActions(for: intent, context: context)
            XCTAssertFalse(actions.contains(.activateVHIDDeviceManager))
            XCTAssertFalse(actions.contains(.startKarabinerDaemon))
        }
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

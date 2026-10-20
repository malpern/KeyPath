@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
import ServiceManagement
@preconcurrency import XCTest

@MainActor
final class InstallerEngineEndToEndTests: KeyPathAsyncTestCase {
    func testInspectSystemForwardsCanonicalSnapshotFreshnessPolicy() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )

        let cachedContext = await engine.inspectSystem(freshness: .cached)
        let freshContext = await engine.inspectSystem()

        XCTAssertEqual(validator.freshnessRequests, [.cached, .fresh])
        XCTAssertEqual(validator.cacheInvalidationCount, 0)
        XCTAssertEqual(cachedContext.system, context.system)
        XCTAssertEqual(freshContext.system, context.system)
    }

    func testExecuteOwnsOneFreshFinalSnapshot() async {
        let context = SystemContextBuilder(
            servicesHealthy: true,
            componentsInstalled: true
        ).build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertEqual(validator.freshnessRequests, [.fresh])
        XCTAssertEqual(validator.cacheInvalidationCount, 1)
        XCTAssertEqual(report.finalContext?.timestamp, context.timestamp)
        XCTAssertEqual(report.finalContext?.captureStatus, context.captureStatus)
    }

    func testExecuteCarriesPlanAndSnapshotEvidenceThroughReportAndTelemetry() async {
        let finalSnapshotID = UUID()
        let context = SystemContextBuilder(
            snapshotID: finalSnapshotID,
            servicesHealthy: true,
            componentsInstalled: true
        ).build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let beforeSnapshotID = UUID()
        let plan = InstallPlan(
            sourceSnapshotID: beforeSnapshotID,
            recipes: [],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertEqual(report.planID, plan.id)
        XCTAssertEqual(report.beforeSnapshotID, beforeSnapshotID)
        XCTAssertEqual(report.afterSnapshotID, finalSnapshotID)
        XCTAssertEqual(report.finalContext?.snapshotID, finalSnapshotID)
        XCTAssertEqual(report.completionState, .verifiedNoOp)
        XCTAssertFalse(report.repairTelemetry.isEmpty)
        for event in report.repairTelemetry {
            XCTAssertEqual(event.runID, report.runID)
            XCTAssertEqual(event.planID, plan.id)
            XCTAssertEqual(event.beforeSnapshotID, beforeSnapshotID)
            XCTAssertEqual(event.afterSnapshotID, finalSnapshotID)
        }
    }

    func testExecuteRejectsNoOpWhenFreshFinalStateRequiresRepair() async {
        let context = SystemContextBuilder.degradedRepair()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            sourceSnapshotID: UUID(),
            recipes: [],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.completionState, .verificationFailed)
        XCTAssertTrue(report.failureReason?.contains("No-op verification failed") == true)
        XCTAssertFalse(report.recoveryPlan?.recipes.isEmpty ?? true)
        XCTAssertEqual(report.repairTelemetry.last?.postconditionResult, .failed)
    }

    func testExecuteRejectsNoOpWhenFreshFinalEvidenceIsIncomplete() async {
        let context = SystemContextBuilder(
            servicesHealthy: true,
            componentsInstalled: true,
            captureStatus: .failed
        ).build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(recipes: [], status: .ready, intent: .repair)

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertFalse(report.success)
        XCTAssertEqual(report.completionState, .verificationFailed)
        XCTAssertEqual(report.failureReason, "No-op verification failed: final system evidence is incomplete")
    }

    func testInspectOnlyExecuteDoesNotCaptureRedundantFinalSnapshot() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            recipes: [],
            status: .ready,
            intent: .inspectOnly
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertTrue(validator.freshnessRequests.isEmpty)
        XCTAssertEqual(validator.cacheInvalidationCount, 0)
        XCTAssertNil(report.finalContext)
    }

    func testFailedExecuteStillOwnsOneFreshFinalSnapshot() async {
        let context = SystemContextBuilder().build()
        let validator = StubSystemValidator(snapshot: Self.snapshot(from: context))
        let engine = InstallerEngine(
            processLifecycleManager: ProcessLifecycleManager(),
            systemValidator: validator
        )
        let plan = InstallPlan(
            recipes: [
                ServiceRecipe(id: "unknown-test-recipe", type: .installComponent),
            ],
            status: .ready,
            intent: .repair
        )

        let report = await engine.execute(
            plan: plan,
            using: PrivilegeBroker(coordinator: StubPrivilegedOperationsCoordinator())
        )

        XCTAssertFalse(report.success)
        XCTAssertEqual(validator.freshnessRequests, [.fresh])
        XCTAssertEqual(validator.cacheInvalidationCount, 1)
        XCTAssertEqual(report.finalContext?.timestamp, context.timestamp)
        XCTAssertEqual(report.finalContext?.captureStatus, context.captureStatus)
    }

    private static func snapshot(from context: SystemContext) -> SystemSnapshot {
        SystemSnapshot(
            id: context.snapshotID,
            permissions: context.permissions,
            components: context.components,
            conflicts: context.conflicts,
            health: context.services,
            helper: context.helper,
            compatibility: SystemCompatibilityStatus(
                macOSVersion: context.system.macOSVersion,
                driverCompatible: context.system.driverCompatible
            ),
            timestamp: context.timestamp,
            captureStatus: context.captureStatus
        )
    }
}

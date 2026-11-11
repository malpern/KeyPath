import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

@MainActor
final class SessionInstallerPolicyTests: KeyPathTestCase {
    private final class Validator: WizardSystemValidating, @unchecked Sendable {
        let value: SystemSnapshot
        init(_ value: SystemSnapshot) {
            self.value = value
        }

        func checkSystem() async -> SystemSnapshot {
            value
        }
    }

    func testWizardRefreshPreservesSessionModeThroughUIOperation() async throws {
        let previous = WizardDependencies.systemValidator
        defer { WizardDependencies.systemValidator = previous }
        WizardDependencies.systemValidator = Validator(snapshot(running: false, ax: .denied, input: .denied))
        let machine = WizardStateMachine()
        let result = try await WizardOperations.stateDetection(stateMachine: machine).execute { _ in }
        XCTAssertEqual(result.permissions?.accessibility, .denied)
        machine.updateWizardState(from: result)
        let next = await machine.getNextPage(for: result.state, issues: result.issues)
        XCTAssertEqual(next, .accessibility)
    }

    private func snapshot(running: Bool, ax: PermissionOracle.Status = .granted,
                          input: PermissionOracle.Status = .granted) -> SystemSnapshot
    {
        SystemSnapshot(
            permissions: .fixture(accessibility: ax, runtimeKeyAccess: input, source: "independent-process"),
            components: ComponentStatus(
                kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true
            ), conflicts: .empty,
            health: .init(kanataProcessRunning: running, kanataTCPResponding: running,
                          kanataRunning: running, kanataInputCaptureReady: running),
            compatibility: .unknown, timestamp: Date()
        )
    }

    func testSessionReadinessFollowsRuntimeEvidence() {
        let snapshot = snapshot(running: true)
        XCTAssertTrue(snapshot.isReady)
        XCTAssertTrue(snapshot.blockingIssues.isEmpty)
        XCTAssertTrue(snapshot.health.isHealthy)
        let context = SystemContext(snapshot: snapshot)
        XCTAssertTrue(context.isReady)
        XCTAssertFalse(SystemContext(snapshot: self.snapshot(running: false)).isReady)
        XCTAssertFalse(SystemContext.empty.isReady)
        XCTAssertEqual(SystemInspector.inspect(context: context).0, .active)
        XCTAssertEqual(InstallerEngine.actions(for: .install, context: context), [])
        XCTAssertEqual(context.installerStateMatrixRow, .sessionRuntimeReady)
    }

    func testSessionSetupAndRepairNeverPlanPrivilegedInstallation() {
        let context = SystemContext(snapshot: snapshot(running: false))
        XCTAssertEqual(InstallerEngine.actions(for: .install, context: context), [.startSessionRuntime])
        XCTAssertEqual(InstallerEngine.actions(for: .repair, context: context), [.startSessionRuntime])
        XCTAssertEqual(context.installerStateMatrixRow, .sessionRuntimeStopped)
        let recipe = InstallerEngine().recipeForAction(.startSessionRuntime)
        XCTAssertEqual(recipe.id, "start-session-runtime")
        XCTAssertEqual(recipe.expectedPostconditions, [.runtimeReadyOrApprovalPending])
    }

    func testSessionPermissionRoutingIsAXFirstWithoutHelperOrFDA() {
        let context = SystemContext(snapshot: snapshot(running: false, ax: .denied, input: .denied))
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(WizardRouter.route(state: result.state, issues: result.issues), .accessibility)
        XCTAssertFalse(result.issues.contains { $0.description.contains("Full Disk Access") })
    }

    func testRuntimeKeyAccessDenialRoutesToAccessibilityRelaunchGuidance() {
        let context = SystemContext(snapshot: snapshot(running: false, input: .denied))
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(WizardRouter.route(state: result.state, issues: result.issues), .accessibility)
        XCTAssertFalse(snapshot(running: true, input: .denied).isReady)
    }
}

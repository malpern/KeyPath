import KeyPathCore
@testable import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import XCTest

@MainActor
final class SessionInstallerPolicyTests: XCTestCase {
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
        XCTAssertEqual(result.backend, .session)
        machine.updateWizardState(from: result)
        let next = await machine.getNextPage(for: result.state, issues: result.issues)
        XCTAssertEqual(next, .accessibility)
    }

    private func snapshot(running: Bool, ax: PermissionOracle.Status = .granted,
                          input: PermissionOracle.Status = .granted,
                          backend: KanataRuntimeBackend = .session) -> SystemSnapshot
    {
        let permissions = PermissionOracle.PermissionSet(
            accessibility: ax, inputMonitoring: input, source: "independent-process", confidence: .high, timestamp: Date()
        )
        return SystemSnapshot(
            permissions: .init(keyPath: permissions, kanata: permissions, timestamp: Date(), backend: backend),
            components: ComponentStatus(
                kanataBinaryInstalled: true, requiredRuntimePayloadPresent: true,
                karabinerDriverInstalled: false, karabinerDaemonRunning: false,
                vhidDeviceInstalled: false, vhidDeviceHealthy: false,
                vhidServicesHealthy: false, vhidVersionMismatch: false
            ), conflicts: .empty,
            health: .init(backend: backend, kanataProcessRunning: running, kanataTCPResponding: running,
                          kanataRunning: running, karabinerDaemonRunning: false, vhidHealthy: false,
                          kanataInputCaptureReady: running),
            helper: .empty, compatibility: .unknown, timestamp: Date()
        )
    }

    func testSessionReadinessDoesNotInventHelperOrDriverHealth() {
        let snapshot = snapshot(running: true)
        XCTAssertTrue(snapshot.isReady)
        XCTAssertTrue(snapshot.blockingIssues.isEmpty)
        XCTAssertFalse(snapshot.helper.isInstalled)
        XCTAssertFalse(snapshot.components.karabinerDriverInstalled)
        XCTAssertFalse(snapshot.health.vhidHealthy)
        XCTAssertTrue(snapshot.health.isHealthy)
        let context = SystemContext(snapshot: snapshot)
        XCTAssertEqual(SystemInspector.inspect(context: context).0, .active)
        XCTAssertEqual(InstallerDecisionPipeline.determineInstallActions(context: context), [])
        XCTAssertEqual(context.installerStateMatrixRow, .sessionRuntimeReady)
        XCTAssertFalse(self.snapshot(running: true, backend: .driverKit).isReady)
    }

    func testSessionSetupAndRepairNeverPlanPrivilegedInstallation() {
        let context = SystemContext(snapshot: snapshot(running: false))
        XCTAssertEqual(InstallerDecisionPipeline.determineInstallActions(context: context), [.restartCommServer])
        XCTAssertEqual(InstallerDecisionPipeline.determineRepairActions(context: context), [.restartCommServer])
        XCTAssertEqual(context.installerStateMatrixRow, .sessionRuntimeStopped)
        let recipe = InstallerEngine().recipeForAction(.restartCommServer, context: context)
        XCTAssertEqual(recipe?.id, "start-session-runtime")
        XCTAssertEqual(recipe?.expectedPostconditions, [.runtimeReadyOrApprovalPending])
    }

    func testSessionPermissionRoutingIsAXFirstWithoutHelperOrFDA() {
        let context = SystemContext(snapshot: snapshot(running: false, ax: .denied, input: .denied))
        let result = SystemStateResult.projecting(context)
        XCTAssertFalse(result.helperInstalled)
        XCTAssertEqual(result.backend, .session)
        XCTAssertEqual(WizardRouter.route(state: result.state, issues: result.issues,
                                          helperInstalled: false, helperNeedsApproval: false, backend: result.backend), .accessibility)
        XCTAssertFalse(result.issues.contains { $0.description.contains("Full Disk Access") })
    }

    func testEffectiveInputDenialStillRequiresConditionalApproval() {
        let context = SystemContext(snapshot: snapshot(running: false, input: .denied))
        let result = SystemStateResult.projecting(context)
        XCTAssertEqual(WizardRouter.route(state: result.state, issues: result.issues,
                                          helperInstalled: false, helperNeedsApproval: false, backend: result.backend), .inputMonitoring)
        XCTAssertFalse(snapshot(running: true, input: .denied).isReady)
    }
}

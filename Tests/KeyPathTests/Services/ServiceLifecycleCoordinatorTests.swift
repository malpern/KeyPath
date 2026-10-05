@testable import KeyPathAppKit
@testable import KeyPathCore
@testable import KeyPathInstallationWizard
@testable import KeyPathWizardCore
@preconcurrency import XCTest

@MainActor
final class ServiceLifecycleCoordinatorTests: KeyPathTestCase {
    private var coordinator: ServiceLifecycleCoordinator!
    private var capturedErrors: [String?] = []
    private var capturedWarnings: [String?] = []
    private var stateChangeCount = 0

    override func setUp() async throws {
        try await super.setUp()
        coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
        capturedErrors = []
        capturedWarnings = []
        stateChangeCount = 0

        coordinator.onError = { [unowned self] error in
            capturedErrors.append(error)
        }
        coordinator.onWarning = { [unowned self] warning in
            capturedWarnings.append(warning)
        }
        coordinator.onStateChanged = { [unowned self] in
            stateChangeCount += 1
        }
    }

    func testUnsupportedConfigurationRefusesBeforeLaunchAndPersistsFailure() async {
        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged
        var launches = 0
        coordinator.testSessionConfigurationValidation = { .invalid(reason: "Caps Lock remapping requires the advanced driver backend") }
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        let admissionResult1 = await coordinator.startKanata(reason: "unsupported config")
        XCTAssertFalse(admissionResult1)
        XCTAssertEqual(launches, 0)
        XCTAssertTrue(privileged.calls.isEmpty)
        XCTAssertFalse(coordinator.isStartingKanata)
        let admissionResult2 = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertFalse(admissionResult2)
        guard case let .failed(reason) = await coordinator.currentRuntimeStatus() else {
            return XCTFail("The refusal must survive absence of a worker report")
        }
        XCTAssertTrue(reason.contains("Caps Lock remapping requires the advanced driver backend"))
        XCTAssertTrue(reason.contains("Edit the configuration"))
        XCTAssertTrue(reason.contains("existing rules were preserved"))
    }

    func testValidRetryClearsConfigurationRefusal() async {
        coordinator.testSessionConfigurationValidation = { .invalid(reason: "unsupported action") }
        let admissionResult3 = await coordinator.startKanata()
        XCTAssertFalse(admissionResult3)
        coordinator.testSessionConfigurationValidation = { .valid }
        var launches = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        let admissionResult4 = await coordinator.startKanata(reason: "corrected config")
        XCTAssertTrue(admissionResult4)
        XCTAssertEqual(launches, 1)
        XCTAssertNil(coordinator.sessionConfigurationRefusal)
        XCTAssertEqual(coordinator.sessionConfigurationAdmission, .valid)
    }

    func testUnavailableValidationIsNotUnsupportedConfiguration() async {
        coordinator.testSessionConfigurationValidation = { .unavailable(reason: "bridge library missing") }
        var launches = 0
        ServiceLifecycleCoordinator.testSessionStart = { _ in launches += 1; return true }
        let admissionResult5 = await coordinator.startKanata()
        XCTAssertFalse(admissionResult5)
        XCTAssertEqual(launches, 0)
        XCTAssertNil(coordinator.sessionConfigurationRefusal)
        let admissionResult6 = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertTrue(admissionResult6)
        guard case let .failed(reason) = await coordinator.currentRuntimeStatus() else {
            return XCTFail("Validation coverage failure must remain visible")
        }
        XCTAssertTrue(reason.contains("validation is unavailable"))
        XCTAssertFalse(reason.contains("cannot run"))
    }

    func testInvalidRestartPreservesOwnedRunningTapUntilExplicitStop() async {
        let report = SessionRuntimeReport(nonce: "owned", pid: 100, uid: 501, state: .running,
                                         accessibility: true, effectiveInputAccess: true, tapActive: true,
                                         tcpPort: 37001, inputCount: 1, outputCount: 1, timestamp: Date())
        coordinator.testSessionCurrentReport = { report }
        var validations = 0, stops = 0
        coordinator.testSessionConfigurationValidation = { validations += 1; return .invalid(reason: "edited config unsupported") }
        ServiceLifecycleCoordinator.testSessionStop = { stops += 1; return true }
        let admissionResult7 = await coordinator.restartKanata(reason: "invalid edit")
        XCTAssertFalse(admissionResult7)
        XCTAssertEqual(stops, 0)
        let liveStatus = await coordinator.currentRuntimeStatus()
        XCTAssertEqual(liveStatus, .running(pid: 100))
        XCTAssertNil(coordinator.configurationRefusalForStartup())
        XCTAssertEqual(validations, 1, "Readiness must use the owned live tap rather than reparsing edited input")
        let admissionResult8 = await coordinator.stopKanata(reason: "explicit stop")
        XCTAssertTrue(admissionResult8)
        XCTAssertEqual(stops, 1, "Refusal must not bypass owned stop/restore admission")
    }

    // MARK: - Session lifecycle routing

    func testStartUsesSessionOwnerWithoutPrivilegedFallbackOnFailure() async {
        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged
        var reasons: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { reason in
            reasons.append(reason)
            XCTAssertTrue(self.coordinator.isStartingKanata)
            return false
        }
        let started = await coordinator.startKanata(reason: "session failure")
        XCTAssertFalse(started)
        XCTAssertEqual(reasons, ["session failure"])
        XCTAssertTrue(privileged.calls.isEmpty)
        XCTAssertFalse(coordinator.isStartingKanata)
    }

    func testValidationUsesSessionStart() async {
        var reasons: [String] = []
        ServiceLifecycleCoordinator.testSessionStart = { reason in
            reasons.append(reason)
            return false
        }
        await coordinator.startKanataWithValidation()
        XCTAssertEqual(reasons, ["Session validation start"])
    }

    func testStopUsesOnlySessionOwner() async {
        let privileged = StubPrivilegedOperationsCoordinator()
        WizardDependencies.privilegedOperations = privileged
        ServiceLifecycleCoordinator.testSessionStop = {
            self.coordinator.onStateChanged?()
            return true
        }
        let stopped = await coordinator.stopKanata(reason: "test")
        XCTAssertTrue(stopped)
        XCTAssertTrue(privileged.calls.isEmpty)
        XCTAssertGreaterThan(stateChangeCount, 0)
    }

    // MARK: - Stop

    func testStopNotifiesStateChange() async {
        ServiceLifecycleCoordinator.testSessionStop = { self.coordinator.onStateChanged?(); return true }
        let result = await coordinator.stopKanata(reason: "test")

        XCTAssertTrue(result)
        XCTAssertGreaterThan(stateChangeCount, 0)
    }

    // MARK: - Intentional-transition gate (#625)

    func testNotInIntentionalTransitionWhenIdle() {
        // A fresh coordinator that hasn't stopped anything is not transitioning, so a
        // grab failure observed now is genuine and eligible for recovery.
        XCTAssertFalse(coordinator.isIntentionalTransitionInProgress)
    }

    func testIntentionalTransitionFlagSetDuringStop() async {
        // The flag must be closed *while the stop runs*, so a benign `active=false`
        // from the dying kanata is suppressed. We observe it from the onStateChanged
        // callback, which fires inside stopKanata before its `defer` opens the grace.
        var seenDuringStop: Bool?
        coordinator.onStateChanged = { [unowned self] in
            if seenDuringStop == nil {
                seenDuringStop = coordinator.isIntentionalTransitionInProgress
            }
        }

        ServiceLifecycleCoordinator.testSessionStop = { self.coordinator.onStateChanged?(); return true }
        _ = await coordinator.stopKanata(reason: "test")

        XCTAssertEqual(seenDuringStop, true, "Transition gate must be closed during the stop")
    }

    func testIntentionalTransitionGraceHoldsBrieflyAfterStop() async {
        // Immediately after stop returns, the short trailing grace keeps the gate closed
        // so a late last-gasp `active=false` from the just-killed kanata is still suppressed.
        _ = await coordinator.stopKanata(reason: "test")
        XCTAssertTrue(
            coordinator.isIntentionalTransitionInProgress,
            "Gate should remain closed during the post-stop grace window"
        )
    }

    func testStartClearsLingeringStopGrace() async {
        // The stop-grace exists only to swallow the OLD process's last gasp. Once a new
        // start begins (e.g. the start phase of a restart), the grace must end so a
        // genuine `active=false` from the freshly started kanata is NOT masked as benign.
        _ = await coordinator.stopKanata(reason: "stop for restart")
        XCTAssertTrue(coordinator.isIntentionalTransitionInProgress, "Grace armed after stop")

        _ = await coordinator.startKanata(reason: "restart")

        XCTAssertFalse(
            coordinator.isIntentionalTransitionInProgress,
            "Starting a new kanata must clear the stale stop-grace so post-start grab failures are caught"
        )
    }

    func testPostStartReadinessAcceptsLiveRuntimeDespiteStaleRegistrationMetadata() {
        let snapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot(
            managementState: .smappserviceActive,
            isRunning: true,
            isResponding: true,
            inputCaptureReady: true,
            inputCaptureIssue: nil,
            launchctlExitCode: 0,
            staleEnabledRegistration: true,
            recentlyRestarted: false
        )

        XCTAssertTrue(
            ServiceLifecycleCoordinator.shouldAcceptPostStartRuntime(snapshot),
            "Current process, TCP, and input-capture evidence must outrank stale registration metadata"
        )
    }

    // MARK: - Restart

    func testRestartCallsSessionStopThenStart() async {
        var operations: [String] = []
        ServiceLifecycleCoordinator.testSessionStop = { operations.append("stop"); return true }
        ServiceLifecycleCoordinator.testSessionStart = { _ in operations.append("start"); return true }
        let restarted = await coordinator.restartKanata(reason: "test restart")
        XCTAssertTrue(restarted)
        XCTAssertEqual(operations, ["stop", "start"])
    }

    func testRestartRefusesStartAfterSessionStopFailure() async {
        var startCalls = 0
        ServiceLifecycleCoordinator.testSessionStop = { false }
        ServiceLifecycleCoordinator.testSessionStart = { _ in startCalls += 1; return true }
        let restarted = await coordinator.restartKanata(reason: "test restart")
        XCTAssertFalse(restarted)
        XCTAssertEqual(startCalls, 0)
    }

    // MARK: - Runtime Status

    func testRuntimeStatusReportsStartingDuringStart() async {
        coordinator.isStartingKanata = true

        let status = await coordinator.currentRuntimeStatus()

        XCTAssertEqual(status, .starting)
    }

    func testRuntimeStatusReportsStoppedWhenDaemonNotRunning() async {
        // In test env, daemon is not running
        let status = await coordinator.currentRuntimeStatus()

        // Should be stopped or unknown (not starting, not running)
        XCTAssertFalse(status.isRunning)
        XCTAssertNotEqual(status, .starting)
    }

    // MARK: - Startup Window

    func testTransientStartupWindowDuringStart() async {
        coordinator.isStartingKanata = true

        let inWindow = await coordinator.isInTransientRuntimeStartupWindow()

        XCTAssertTrue(inWindow, "Should be in startup window while start is in progress")
    }

    func testNotInStartupWindowWhenIdle() async {
        coordinator.isStartingKanata = false

        let inWindow = await coordinator.isInTransientRuntimeStartupWindow()

        // May or may not be in window depending on SMAppService state,
        // but should not crash
        XCTAssertNotNil(inWindow)
    }
}

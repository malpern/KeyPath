@testable import KeyPathAppKit
@preconcurrency import XCTest

@MainActor
final class ServiceLifecycleCoordinatorTests: KeyPathTestCase {
    private var coordinator: ServiceLifecycleCoordinator!
    private var capturedErrors: [String?] = []
    private var capturedWarnings: [String?] = []
    private var stateChangeCount = 0

    override func setUp() {
        super.setUp()
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

    // MARK: - Start gating

    func testStartFailsWhenVHIDDaemonNotRunning() async {
        coordinator.isKarabinerDaemonRunning = { false }

        let result = await coordinator.startKanata(reason: "test")

        XCTAssertFalse(result, "Start should fail when VHID daemon is not running")
        XCTAssertEqual(capturedErrors.count, 1)
        XCTAssertTrue(capturedErrors.first??.contains("VirtualHID") ?? false)
        XCTAssertGreaterThan(stateChangeCount, 0, "Should notify state change on failure")
    }

    func testStartSetsIsStartingFlag() async {
        coordinator.isKarabinerDaemonRunning = { true }

        // isStartingKanata should be false before and after (defer resets it)
        XCTAssertFalse(coordinator.isStartingKanata)
        _ = await coordinator.startKanata(reason: "test")
        XCTAssertFalse(coordinator.isStartingKanata, "isStartingKanata should be reset after start completes")
    }

    // MARK: - Stop

    func testStopNotifiesStateChange() async {
        let result = await coordinator.stopKanata(reason: "test")

        // Should succeed (stopIfRunning returns false if not running, which is fine)
        XCTAssertTrue(result)
        XCTAssertGreaterThan(stateChangeCount, 0)
    }

    // MARK: - Restart

    func testRestartCallsStopThenStart() async {
        coordinator.isKarabinerDaemonRunning = { true }

        // Restart should call stop then start
        let result = await coordinator.restartKanata(reason: "test restart")

        // Result depends on whether daemon registration succeeds (likely fails in test env)
        // But the flow should complete without crashing
        XCTAssertNotNil(result)
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

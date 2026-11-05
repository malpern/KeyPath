@testable import KeyPathAppKit
@preconcurrency import XCTest

/// A daemon left by public 1.0.1 and a session tap would both modify the
/// keyboard. This refusal is the only protection until the upgrade path in
/// ADR-045 exists. The real start path runs here; launches are disabled in
/// unit tests, so that failure is the proof that a start got past the check.
@MainActor
final class SessionLegacyDaemonRefusalTests: KeyPathTestCase {
    private let refusal = ServiceLifecycleCoordinator.legacyDaemonRefusalMessage
    private var errors: [String] = []
    private var daemonChecks = 0
    private var publishedError: String?

    private func start(daemonRunning: Bool) async -> Bool {
        await start(daemonRunning: daemonRunning, using: makeCoordinator())
    }

    private func start(daemonRunning: Bool, using coordinator: ServiceLifecycleCoordinator) async -> Bool {
        coordinator.testSessionLegacyDaemonRunning = { [weak self] in
            self?.daemonChecks += 1
            return daemonRunning
        }
        return await coordinator.startKanata(reason: "Legacy daemon test")
    }

    private func makeCoordinator() -> ServiceLifecycleCoordinator {
        ServiceLifecycleCoordinator.testSessionStart = nil
        addTeardownBlock { @MainActor in
            ServiceLifecycleCoordinator.testSessionStart = { _ in false }
        }
        let coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
        coordinator.testSessionCurrentReport = { nil }
        coordinator.testSessionConfigurationValidation = { .valid }
        coordinator.testSessionCapsPreparation = {}
        coordinator.testSessionCapsRecovery = {}
        coordinator.onError = { [weak self] message in
            if let message {
                self?.errors.append(message)
            }
        }
        return coordinator
    }

    func testRefusalStaysVisibleWhileTheDaemonRuns() async {
        let coordinator = makeCoordinator()

        _ = await start(daemonRunning: true, using: coordinator)
        let refusedStatus = await coordinator.currentRuntimeStatus()
        XCTAssertEqual(refusedStatus, .failed(reason: refusal))
        let inTransientWindow = await coordinator.isInTransientRuntimeStartupWindow()
        XCTAssertFalse(inTransientWindow, "A completed refusal must not read as startup in progress")
    }

    func testRefusalClearsOnceTheDaemonStopsWithoutAnotherStart() async {
        let coordinator = makeCoordinator()
        _ = await start(daemonRunning: true, using: coordinator)
        var stateChanges = 0
        coordinator.onStateChanged = { stateChanges += 1 }
        coordinator.onError = { [weak self] message in self?.publishedError = message }
        publishedError = refusal

        coordinator.testSessionLegacyDaemonRunning = { false }
        let status = await coordinator.currentRuntimeStatus()

        XCTAssertEqual(status, .stopped)
        XCTAssertNil(coordinator.sessionLegacyDaemonRefusal)
        XCTAssertNil(publishedError, "Settings shows the last error, so it must clear with the refusal")
        XCTAssertEqual(stateChanges, 1)
    }

    func testTurningRemappingOffDropsTheRefusal() async {
        let coordinator = makeCoordinator()
        _ = await start(daemonRunning: true, using: coordinator)

        _ = await coordinator.stopKanata(reason: "Legacy daemon test")

        XCTAssertNil(coordinator.sessionLegacyDaemonRefusal)
        let status = await coordinator.currentRuntimeStatus()
        XCTAssertEqual(status, .stopped)
    }

    func testProbeOverlappingANewerRefusedStartLeavesThatRefusal() async {
        let coordinator = makeCoordinator()
        _ = await start(daemonRunning: true, using: coordinator)
        coordinator.testSessionLegacyDaemonRunning = { [weak coordinator] in
            coordinator?.testSessionLegacyDaemonRunning = { true }
            _ = await coordinator?.startKanata(reason: "Newer start")
            return false
        }

        let remaining = await coordinator.legacyDaemonRefusalForStartup()

        XCTAssertEqual(remaining, refusal)
    }

    func testConfigurationRefusalOutranksAStaleDaemonRefusal() async {
        let coordinator = makeCoordinator()
        _ = await start(daemonRunning: true, using: coordinator)
        coordinator.testSessionConfigurationValidation = {
            .invalid(reason: "Unsupported rule")
        }

        _ = await coordinator.startKanata(reason: "Legacy daemon test")

        let status = await coordinator.currentRuntimeStatus()
        guard case let .failed(reason) = status else { return XCTFail("Expected a failure, got \(status)") }
        XCTAssertNotEqual(reason, refusal)
    }

    func testRefreshAfterCleanupClearsTheRefusalOnlyWhenTheDaemonIsGone() async {
        let coordinator = makeCoordinator()
        _ = await start(daemonRunning: true, using: coordinator)

        let stillRefused = await coordinator.refreshLegacyDaemonRefusalAfterCleanup()
        XCTAssertTrue(stillRefused, "A daemon that is still running must keep blocking the start")
        XCTAssertEqual(coordinator.sessionLegacyDaemonRefusal, refusal)

        coordinator.testSessionLegacyDaemonRunning = { false }
        let refusedAfterRemoval = await coordinator.refreshLegacyDaemonRefusalAfterCleanup()
        XCTAssertFalse(refusedAfterRemoval)
        XCTAssertNil(coordinator.sessionLegacyDaemonRefusal)
    }

    func testRunningLegacyDaemonRefusesStartWithoutLaunching() async {
        let started = await start(daemonRunning: true)
        XCTAssertFalse(started)
        XCTAssertEqual(daemonChecks, 1)
        XCTAssertEqual(errors, [refusal], "A launch failure here would mean the check did not stop the start")
    }

    func testNoLegacyDaemonLetsStartReachLaunch() async {
        let started = await start(daemonRunning: false)
        XCTAssertFalse(started, "Launches are disabled in unit tests")
        XCTAssertEqual(daemonChecks, 1)
        XCTAssertFalse(errors.contains(refusal))
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.hasPrefix("Driverless runtime launch failed") == true,
                      "Expected the start to reach launch, got \(errors)")
    }
}

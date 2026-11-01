@testable import KeyPathAppKit
@preconcurrency import XCTest

/// A daemon left by public 1.0.1 and a session tap would both modify the
/// keyboard. This refusal is the only protection until the upgrade path in
/// ADR-045 exists. The real start path runs here; launches are disabled in
/// unit tests, so that failure is the proof that a start got past the check.
@MainActor
final class SessionLegacyDaemonRefusalTests: KeyPathTestCase {
    private let refusal = "Stop the existing keyboard service before trying driverless mode."
    private var coordinator: ServiceLifecycleCoordinator!
    private var errors: [String] = []
    private var daemonChecks = 0

    override func setUp() {
        super.setUp()
        ServiceLifecycleCoordinator.testSessionStart = nil
        errors = []
        daemonChecks = 0
        coordinator = ServiceLifecycleCoordinator(
            kanataDaemonService: KanataDaemonService(),
            recoveryCoordinator: RecoveryCoordinator()
        )
        coordinator.testSessionCurrentReport = { nil }
        coordinator.testSessionConfigurationValidation = { .valid }
        coordinator.testSessionCapsPreparation = {}
        coordinator.testSessionCapsRecovery = {}
        coordinator.onError = { [weak self] message in
            if let message { self?.errors.append(message) }
        }
    }

    override func tearDown() {
        coordinator = nil
        ServiceLifecycleCoordinator.testSessionStart = { _ in false }
        super.tearDown()
    }

    private func start(daemonRunning: Bool) async -> Bool {
        coordinator.testSessionLegacyDaemonRunning = { [weak self] in
            self?.daemonChecks += 1
            return daemonRunning
        }
        return await coordinator.startKanata(reason: "Legacy daemon test")
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

@testable import KeyPathAppKit
@preconcurrency import XCTest

/// The real start path runs here. Launches are disabled in unit tests, so the
/// launch failure is the proof that a start reached the launch instead of being
/// skipped by an earlier check.
@MainActor
final class SessionStartReachesLaunchTests: KeyPathTestCase {
    func testStartReachesLaunch() async {
        ServiceLifecycleCoordinator.testSessionStart = nil
        addTeardownBlock { @MainActor in
            ServiceLifecycleCoordinator.testSessionStart = { _ in false }
        }
        let coordinator = ServiceLifecycleCoordinator(recoveryCoordinator: RecoveryCoordinator())
        coordinator.testSessionCurrentReport = { nil }
        coordinator.testSessionConfigurationValidation = { .valid }
        coordinator.testSessionCapsPreparation = {}
        coordinator.testSessionCapsRecovery = {}
        var errors: [String] = []
        coordinator.onError = { message in
            if let message { errors.append(message) }
        }

        let started = await coordinator.startKanata(reason: "Start reaches launch test")

        XCTAssertFalse(started, "Launches are disabled in unit tests")
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.hasPrefix("Driverless runtime launch failed") == true,
                      "Expected the start to reach launch, got \(errors)")
    }
}

import Foundation
import XCTest

@testable import KeyPathAppKit

/// Unit tests for ServiceBootstrapper service.
///
/// Tests service lifecycle management and restart tracking.
/// These tests verify:
/// - Restart time tracking
/// - Warm-up window detection
/// - Service identifier constants
@MainActor
final class ServiceBootstrapperTests: XCTestCase {
    // MARK: - Service Identifier Tests

    func testServiceIdentifiers() {
        XCTAssertEqual(ServiceBootstrapper.kanataServiceID, "com.keypath.kanata")
        XCTAssertEqual(ServiceBootstrapper.vhidDaemonServiceID, "com.keypath.karabiner-vhiddaemon")
        XCTAssertEqual(ServiceBootstrapper.vhidManagerServiceID, "com.keypath.karabiner-vhidmanager")
        XCTAssertEqual(ServiceBootstrapper.logRotationServiceID, "com.keypath.logrotate")
    }

    // MARK: - Restart Time Tracking Tests

    func testMarkRestartTimeRecordsTimestamp() {
        let bootstrapper = ServiceBootstrapper.shared
        // Use a unique service ID to avoid state leakage from other tests
        let serviceID = "com.keypath.test-service-\(UUID().uuidString)"

        // This service ID has never been marked
        let before = ServiceBootstrapper.wasRecentlyRestarted(serviceID)

        // Mark restart
        bootstrapper.markRestartTime(for: [serviceID])

        // Should be recently restarted
        let after = ServiceBootstrapper.wasRecentlyRestarted(serviceID)

        XCTAssertFalse(before, "Service should not be recently restarted before marking")
        XCTAssertTrue(after, "Service should be recently restarted after marking")
    }

    func testWasRecentlyRestartedReturnsFalseForUnknownService() {
        let result = ServiceBootstrapper.wasRecentlyRestarted("com.keypath.unknown-service")
        XCTAssertFalse(result, "Unknown service should not be recently restarted")
    }

    func testWasRecentlyRestartedExpiresAfterWarmupWindow() async {
        let bootstrapper = ServiceBootstrapper.shared
        let serviceID = "com.keypath.test-service"

        // Mark restart with very short window
        bootstrapper.markRestartTime(for: [serviceID])

        // Should be recently restarted immediately
        let immediately = ServiceBootstrapper.wasRecentlyRestarted(serviceID, within: 0.1)
        XCTAssertTrue(immediately, "Service should be recently restarted immediately")

        // Wait longer than warm-up window
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // Should no longer be recently restarted (with 0.1s window)
        let afterDelay = ServiceBootstrapper.wasRecentlyRestarted(serviceID, within: 0.1)
        XCTAssertFalse(afterDelay, "Service should not be recently restarted after warm-up window")
    }

    func testWasRecentlyRestartedWithCustomWindow() {
        let bootstrapper = ServiceBootstrapper.shared
        let serviceID = "com.keypath.test-service"

        bootstrapper.markRestartTime(for: [serviceID])

        // With default window (2.0s), should be true
        let defaultWindow = ServiceBootstrapper.wasRecentlyRestarted(serviceID)
        XCTAssertTrue(defaultWindow, "Should be true with default 2.0s window")

        // With very short window (0.001s), should be true immediately
        let shortWindow = ServiceBootstrapper.wasRecentlyRestarted(serviceID, within: 0.001)
        XCTAssertTrue(shortWindow, "Should be true with short window immediately after restart")

        // With very long window (100s), should be true
        let longWindow = ServiceBootstrapper.wasRecentlyRestarted(serviceID, within: 100.0)
        XCTAssertTrue(longWindow, "Should be true with long window")
    }

    func testMarkRestartTimeForMultipleServices() {
        let bootstrapper = ServiceBootstrapper.shared
        let serviceIDs = [
            "com.keypath.service1",
            "com.keypath.service2",
            "com.keypath.service3"
        ]

        bootstrapper.markRestartTime(for: serviceIDs)

        for serviceID in serviceIDs {
            let isRecent = ServiceBootstrapper.wasRecentlyRestarted(serviceID)
            XCTAssertTrue(isRecent, "Service \(serviceID) should be recently restarted")
        }
    }

    func testHadRecentRestartReturnsTrueWhenAnyServiceRestarted() {
        let bootstrapper = ServiceBootstrapper.shared
        let serviceID = "com.keypath.test-service"

        bootstrapper.markRestartTime(for: [serviceID])

        let hadRecent = ServiceBootstrapper.hadRecentRestart()
        XCTAssertTrue(hadRecent, "Should return true when any service was recently restarted")
    }

    func testHadRecentRestartReturnsFalseWhenNoServicesRestarted() {
        // Don't mark any restarts
        let hadRecent = ServiceBootstrapper.hadRecentRestart()
        XCTAssertFalse(hadRecent, "Should return false when no services were recently restarted")
    }

    func testHadRecentRestartWithCustomWindow() async {
        let bootstrapper = ServiceBootstrapper.shared
        let serviceID = "com.keypath.test-service"

        bootstrapper.markRestartTime(for: [serviceID])

        // Immediately after restart, should be true with any window
        let immediately = ServiceBootstrapper.hadRecentRestart(within: 0.1)
        XCTAssertTrue(immediately, "Should be true immediately after restart")

        // Wait longer than window
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // Should be false with short window
        let afterDelay = ServiceBootstrapper.hadRecentRestart(within: 0.1)
        XCTAssertFalse(afterDelay, "Should be false after warm-up window expires")
    }

    // MARK: - Thread Safety Tests

    func testRestartTrackingIsThreadSafe() async {
        let bootstrapper = ServiceBootstrapper.shared
        let serviceIDs = (0 ..< 10).map { "com.keypath.service-\($0)" }

        // Mark restarts concurrently (on MainActor)
        await withTaskGroup(of: Void.self) { group in
            for serviceID in serviceIDs {
                group.addTask { @MainActor in
                    bootstrapper.markRestartTime(for: [serviceID])
                }
            }
        }

        // Verify all were recorded
        for serviceID in serviceIDs {
            let isRecent = ServiceBootstrapper.wasRecentlyRestarted(serviceID)
            XCTAssertTrue(isRecent, "Service \(serviceID) should be recently restarted after concurrent marking")
        }
    }

    // MARK: - Integration Tests

    func testRestartTrackingWorksWithRealServiceIDs() {
        let bootstrapper = ServiceBootstrapper.shared

        let serviceIDs = [
            ServiceBootstrapper.kanataServiceID,
            ServiceBootstrapper.vhidDaemonServiceID,
            ServiceBootstrapper.vhidManagerServiceID
        ]

        bootstrapper.markRestartTime(for: serviceIDs)

        for serviceID in serviceIDs {
            let isRecent = ServiceBootstrapper.wasRecentlyRestarted(serviceID)
            XCTAssertTrue(isRecent, "Real service ID \(serviceID) should be tracked")
        }
    }
}

@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
import ServiceManagement
@preconcurrency import XCTest

/// Mock implementation of SMAppServiceProtocol for testing
private class MockSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    var status: SMAppService.Status
    var registerCalled = false
    var unregisterCalled = false

    init(status: SMAppService.Status = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCalled = true
        // Simulate successful registration transition
        if status == .notRegistered || status == .notFound {
            status = .enabled
        }
    }

    func unregister() async throws {
        unregisterCalled = true
        status = .notRegistered
    }
}

@MainActor
final class RecoveryDaemonServiceIntegrationTests: KeyPathAsyncTestCase {
    var service: RecoveryDaemonService!

    /// Keep reference to original factory to restore it
    var originalFactory: ((String) -> SMAppServiceProtocol)!

    override func setUp() async throws {
        try await super.setUp()

        // 1. Mock SMAppService
        originalFactory = RecoveryDaemonService.smServiceFactory
        RecoveryDaemonService.smServiceFactory = { _ in
            MockSMAppService(status: .notRegistered)
        }

        // 2. Create Service under test
        service = RecoveryDaemonService()
    }

    override func tearDown() async throws {
        RecoveryDaemonService.smServiceFactory = originalFactory
        service = nil
        try await super.tearDown()
    }

    func testStopService_ShouldUnregister() async throws {
        // Given: Service is "running" (simulated by setting mock status)
        RecoveryDaemonService.smServiceFactory = { _ in
            MockSMAppService(status: .enabled)
        }
        // Re-init to pick up new mock state
        service = RecoveryDaemonService()

        // When: Stop is called
        try await service.stop()

        // Then: Status should no longer report running
        let status = await service.refreshStatus()
        XCTAssertNotEqual(status, .running(pid: 0))
        if case .running = status {
            XCTFail("Expected service to be stopped or unknown after stop, got \(status)")
        }
    }

    func testStatusRefresh_ShouldDetectChanges() async {
        // Given: Initial unknown state

        // When: Refresh is called
        let status = await service.refreshStatus()

        // Then: Should return a valid state (likely .stopped in test env)
        XCTAssertNotEqual(status, .unknown)
    }

    func testEvaluateStatus_WhenPIDAndTCPBothFail_ShouldReportFailed() async {
        // Given: SMAppService reports .enabled but no process is running
        // and no kanata TCP server is listening (default in test env)
        RecoveryDaemonService.smServiceFactory = { _ in
            MockSMAppService(status: .enabled)
        }
        service = RecoveryDaemonService()

        // When: Refresh enough times to exhaust the debounce threshold (3 samples)
        var lastStatus: RecoveryDaemonService.ServiceState = .unknown
        for _ in 0 ..< 4 {
            lastStatus = await service.refreshStatus()
        }

        // Then: Should report .failed because both PID detection AND TCP probe failed
        if case let .failed(reason) = lastStatus {
            XCTAssertTrue(
                reason.contains("process not running"),
                "Expected 'process not running' failure, got: \(reason)"
            )
        } else {
            XCTFail("Expected .failed state after PID + TCP both fail, got: \(lastStatus)")
        }
    }
}

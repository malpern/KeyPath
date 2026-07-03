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
final class KanataDaemonServiceIntegrationTests: KeyPathAsyncTestCase {
    var service: KanataDaemonService!

    /// Keep reference to original factory to restore it
    var originalFactory: ((String) -> SMAppServiceProtocol)!
    var originalStatusProvider: SMAppServiceStatusProvider!

    /// Point the centralized status provider (#853) at the same status the service's
    /// factory would report, with a zero TTL so each refresh re-reads. `evaluateStatus`
    /// now sources status from the provider rather than the service's own factory.
    private func useStatus(_ status: SMAppService.Status) {
        KanataDaemonService.smServiceFactory = { _ in MockSMAppService(status: status) }
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 0,
            serviceFactory: { _ in MockSMAppService(status: status) }
        )
    }

    override func setUp() async throws {
        try await super.setUp()

        // 1. Mock SMAppService
        originalFactory = KanataDaemonService.smServiceFactory
        originalStatusProvider = SMAppServiceStatusProvider.shared
        useStatus(.notRegistered)

        // 1b. Force the last-resort TCP liveness probe to report "no server". The CI
        // runner is a dev Mac with a real kanata listening on the default port, which
        // would otherwise make the probe succeed and contaminate these status tests.
        KanataDaemonService.tcpProbeOverride = { _, _ in false }

        // 2. Create Service under test
        service = KanataDaemonService()
    }

    override func tearDown() async throws {
        KanataDaemonService.smServiceFactory = originalFactory
        SMAppServiceStatusProvider.shared = originalStatusProvider
        KanataDaemonService.tcpProbeOverride = nil
        service = nil
        try await super.tearDown()
    }

    func testStopService_ShouldUnregister() async throws {
        // Given: Service is "running" (simulated by setting mock status)
        useStatus(.enabled)
        // Re-init to pick up new mock state
        service = KanataDaemonService()

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
        // and the TCP probe is forced to report "no server" (see setUp) so a live
        // kanata on the machine cannot mask the failure.
        useStatus(.enabled)
        service = KanataDaemonService()

        // When: Refresh enough times to exhaust the debounce threshold (3 samples)
        var lastStatus: KanataDaemonService.ServiceState = .unknown
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

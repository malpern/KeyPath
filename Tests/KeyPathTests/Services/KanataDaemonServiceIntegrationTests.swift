@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
import ServiceManagement
@preconcurrency import XCTest

/// Mock implementation of SMAppServiceProtocol for testing
private class MockSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    var status: SMAppService.Status
    var registerCalled = false
    var unregisterCalled = false
    var calls: [String] = []

    init(status: SMAppService.Status = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCalled = true
        calls.append("register")
        // Simulate successful registration transition
        if status == .notRegistered || status == .notFound {
            status = .enabled
        }
    }

    func unregister() async throws {
        unregisterCalled = true
        calls.append("unregister")
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
    private func useService(_ service: MockSMAppService) {
        KanataDaemonService.smServiceFactory = { _ in service }
        SMAppServiceStatusProvider.shared = SMAppServiceStatusProvider(
            cacheTTL: 0,
            serviceFactory: { _ in service }
        )
    }

    private func useStatus(_ status: SMAppService.Status) {
        useService(MockSMAppService(status: status))
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
        KanataDaemonService.runningPostconditionOverride = { true }
        KanataDaemonService.stoppedPostconditionOverride = { true }

        // 2. Create Service under test
        service = KanataDaemonService()
    }

    override func tearDown() async throws {
        KanataDaemonService.smServiceFactory = originalFactory
        SMAppServiceStatusProvider.shared = originalStatusProvider
        KanataDaemonService.tcpProbeOverride = nil
        KanataDaemonService.runningPostconditionOverride = nil
        KanataDaemonService.stoppedPostconditionOverride = nil
        KanataDaemonService.privilegedStopOverride = nil
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

    func testStartServiceRegisters() async throws {
        let mock = MockSMAppService(status: .notRegistered)
        useService(mock)
        service = KanataDaemonService()

        try await service.start()

        XCTAssertTrue(mock.registerCalled)
        XCTAssertEqual(mock.calls, ["register"])
    }

    func testRestartServiceUnregistersBeforeRegistering() async throws {
        let mock = MockSMAppService(status: .enabled)
        useService(mock)
        service = KanataDaemonService()

        try await service.restart()

        XCTAssertTrue(mock.unregisterCalled)
        XCTAssertTrue(mock.registerCalled)
        XCTAssertEqual(mock.calls, ["unregister", "register"])
    }

    func testStartServiceFailsExplicitlyWhenApprovalIsRequired() async {
        let mock = MockSMAppService(status: .requiresApproval)
        useService(mock)
        service = KanataDaemonService()

        do {
            try await service.start()
            XCTFail("Expected approval-required failure")
        } catch let error as KanataDaemonServiceError {
            XCTAssertEqual(error, .approvalRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(mock.registerCalled)
    }

    func testStartServiceFailsWhenRegisteredRuntimeDoesNotBecomeReady() async {
        let mock = MockSMAppService(status: .notRegistered)
        useService(mock)
        KanataDaemonService.runningPostconditionOverride = { false }
        service = KanataDaemonService()

        do {
            try await service.start()
            XCTFail("Expected runtime-readiness failure")
        } catch let error as KanataDaemonServiceError {
            guard case let .startFailed(reason) = error else {
                return XCTFail("Expected startFailed, got \(error)")
            }
            XCTAssertTrue(reason.contains("process and TCP readiness"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStopRetriesUnregisterThenUsesPrivilegedFallbackForStaleJob() async throws {
        let mock = MockSMAppService(status: .enabled)
        useService(mock)

        var postconditionChecks = 0
        KanataDaemonService.stoppedPostconditionOverride = {
            postconditionChecks += 1
            return postconditionChecks > 20
        }
        var privilegedStopCalls = 0
        KanataDaemonService.privilegedStopOverride = {
            privilegedStopCalls += 1
        }
        service = KanataDaemonService()

        try await service.stop()

        XCTAssertEqual(mock.calls, ["unregister", "unregister"])
        XCTAssertEqual(privilegedStopCalls, 1)
        XCTAssertGreaterThanOrEqual(postconditionChecks, 21)
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

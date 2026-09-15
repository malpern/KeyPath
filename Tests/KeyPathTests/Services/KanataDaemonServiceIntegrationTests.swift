@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
import ServiceManagement
@preconcurrency import XCTest

/// Mock implementation of SMAppServiceProtocol for testing
private class MockSMAppService: SMAppServiceProtocol, @unchecked Sendable {
    enum MockError: Error {
        case registerFailed
        case unregisterFailed
    }

    private var storedStatus: SMAppService.Status
    var registerCalled = false
    var unregisterCalled = false
    var calls: [String] = []
    var statusesAfterUnregister: [SMAppService.Status] = []
    var failingUnregisterCalls: Set<Int> = []
    var failingRegisterCalls: Set<Int> = []
    var statusBeforeRegisterError: SMAppService.Status?
    /// Statuses handed out by the next reads, ahead of the stored value. Models
    /// SMAppService settling a registration asynchronously.
    var pendingStatusReads: [SMAppService.Status] = []

    var status: SMAppService.Status {
        get {
            guard !pendingStatusReads.isEmpty else { return storedStatus }
            return pendingStatusReads.removeFirst()
        }
        set { storedStatus = newValue }
    }

    /// The stored value, read without consuming a pending read.
    var settledStatus: SMAppService.Status {
        storedStatus
    }

    init(status: SMAppService.Status = .notRegistered) {
        storedStatus = status
    }

    func register() throws {
        registerCalled = true
        calls.append("register")
        if failingRegisterCalls.contains(calls.count(where: { $0 == "register" })) {
            throw MockError.registerFailed
        }
        if let statusBeforeRegisterError {
            status = statusBeforeRegisterError
            throw MockError.registerFailed
        }
        // Simulate successful registration transition
        if status == .notRegistered || status == .notFound {
            status = .enabled
        }
    }

    func unregister() async throws {
        unregisterCalled = true
        calls.append("unregister")
        if failingUnregisterCalls.contains(calls.count(where: { $0 == "unregister" })) {
            throw MockError.unregisterFailed
        }
        status = statusesAfterUnregister.isEmpty
            ? .notRegistered
            : statusesAfterUnregister.removeFirst()
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
        KanataDaemonService.processRunningOverride = { false }
        KanataDaemonService.runningPostconditionOverride = { true }

        // 2. Create Service under test
        service = KanataDaemonService()
    }

    override func tearDown() async throws {
        KanataDaemonService.smServiceFactory = originalFactory
        SMAppServiceStatusProvider.shared = originalStatusProvider
        KanataDaemonService.tcpProbeOverride = nil
        KanataDaemonService.processRunningOverride = nil
        KanataDaemonService.runningPostconditionOverride = nil
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

    func testStartVerifiesFinalStateWhenRegisterThrowsAfterEnabling() async throws {
        let mock = MockSMAppService(status: .notRegistered)
        mock.statusBeforeRegisterError = .enabled
        useService(mock)
        service = KanataDaemonService()

        try await service.start()

        XCTAssertEqual(mock.calls, ["register"])
        XCTAssertEqual(mock.status, .enabled)
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
        mock.statusesAfterUnregister = [.enabled, .enabled, .notRegistered]
        useService(mock)

        var privilegedStopCalls = 0
        KanataDaemonService.privilegedStopOverride = {
            privilegedStopCalls += 1
        }
        service = KanataDaemonService()

        try await service.stop()

        XCTAssertEqual(mock.calls, ["unregister", "unregister", "unregister"])
        XCTAssertEqual(privilegedStopCalls, 1)
        XCTAssertEqual(mock.status, .notRegistered)
    }

    func testStopUsesPrivilegedFallbackWithoutRedundantUnregisterWhenOnlyProcessLingers() async throws {
        let mock = MockSMAppService(status: .enabled)
        useService(mock)

        var processRunning = true
        KanataDaemonService.processRunningOverride = { processRunning }
        var privilegedStopCalls = 0
        KanataDaemonService.privilegedStopOverride = {
            privilegedStopCalls += 1
            processRunning = false
        }
        service = KanataDaemonService()

        try await service.stop()

        XCTAssertEqual(mock.calls, ["unregister"])
        XCTAssertEqual(privilegedStopCalls, 1)
        XCTAssertEqual(mock.status, .notRegistered)
    }

    func testStopVerifiesFinalStateWhenPostFallbackUnregisterThrows() async throws {
        let mock = MockSMAppService(status: .enabled)
        mock.statusesAfterUnregister = [.enabled, .enabled]
        mock.failingUnregisterCalls = [3]
        useService(mock)

        KanataDaemonService.privilegedStopOverride = {
            mock.status = .notRegistered
        }
        service = KanataDaemonService()

        try await service.stop()

        XCTAssertEqual(mock.calls, ["unregister", "unregister", "unregister"])
        XCTAssertEqual(mock.status, .notRegistered)
    }

    func testStopRetriesWhenInitialUnregisterThrows() async throws {
        let mock = MockSMAppService(status: .enabled)
        mock.failingUnregisterCalls = [1]
        useService(mock)

        var privilegedStopCalls = 0
        KanataDaemonService.privilegedStopOverride = {
            privilegedStopCalls += 1
        }
        service = KanataDaemonService()

        try await service.stop()

        XCTAssertEqual(mock.calls, ["unregister", "unregister"])
        XCTAssertEqual(privilegedStopCalls, 0)
        XCTAssertEqual(mock.status, .notRegistered)
    }

    func testStopVerifiesFinalStateWhenPrivilegedCleanupThrows() async throws {
        let mock = MockSMAppService(status: .enabled)
        mock.statusesAfterUnregister = [.enabled, .enabled]
        useService(mock)

        KanataDaemonService.privilegedStopOverride = {
            throw MockSMAppService.MockError.unregisterFailed
        }
        service = KanataDaemonService()

        try await service.stop()

        XCTAssertEqual(mock.calls, ["unregister", "unregister", "unregister"])
        XCTAssertEqual(mock.status, .notRegistered)
    }

    /// A restart that fails must never leave the daemon unregistered. `stop()`
    /// removes the SMAppService registration before verifying its postcondition,
    /// so without a rollback a failed restart leaves launchd with no such
    /// service and no command-line path back.
    func testRestartRestoresRegistrationWhenStartCannotRegister() async {
        let mock = MockSMAppService(status: .enabled)
        // Fail only the start path's register, so the rollback's register works.
        mock.failingRegisterCalls = [1]
        useService(mock)
        service = KanataDaemonService()

        do {
            try await service.restart()
            XCTFail("Expected restart to fail when the service cannot re-register")
        } catch {
            // Expected: the restart still reports failure.
        }

        XCTAssertEqual(
            mock.settledStatus, .enabled,
            "A failed restart must leave the daemon registered, not unregistered"
        )
        XCTAssertEqual(
            mock.calls.count(where: { $0 == "register" }), 2,
            "Expected the failed start's register plus the rollback's register"
        )
    }

    /// The same guarantee when the failure happens in `stop()` rather than
    /// `start()`: the registration is already gone by the time stop throws.
    func testRestartRestoresRegistrationWhenStopFails() async {
        let mock = MockSMAppService(status: .enabled)
        useService(mock)
        // The process never goes away, so the stopped postcondition is never met.
        KanataDaemonService.processRunningOverride = { true }
        KanataDaemonService.privilegedStopOverride = {}
        service = KanataDaemonService()

        do {
            try await service.restart()
            XCTFail("Expected restart to fail when the daemon never stops")
        } catch {
            // Expected: the restart still reports failure.
        }

        XCTAssertEqual(
            mock.settledStatus, .enabled,
            "A restart that fails during stop must still leave the daemon registered"
        )
    }

    /// SMAppService settles a registration asynchronously, so the status read
    /// taken right after `register()` can still say `.notRegistered`. Starting
    /// must poll rather than fail a start that would have succeeded, which is
    /// what made recovery take two attempts.
    func testStartPollsWhileRegistrationSettles() async throws {
        let mock = MockSMAppService(status: .notRegistered)
        // Entry read, the read inside register(), and one stale post-register read.
        mock.pendingStatusReads = [.notRegistered, .notRegistered, .notRegistered]
        useService(mock)
        service = KanataDaemonService()

        try await service.start()

        XCTAssertEqual(mock.settledStatus, .enabled)
        XCTAssertEqual(
            mock.calls.count(where: { $0 == "register" }), 1,
            "A settling registration must not trigger a second register"
        )
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

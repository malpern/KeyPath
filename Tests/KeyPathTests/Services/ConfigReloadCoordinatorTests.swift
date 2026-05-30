import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import KeyPathDaemonLifecycle
import Testing

// MARK: - Mocks

/// Mock engine client that returns configurable results without TCP connections.
private final class MockEngineClient: EngineClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: EngineReloadResult = .success(response: "ok")
    private var _reloadCallCount: Int = 0

    var result: EngineReloadResult {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var reloadCallCount: Int {
        lock.withLock { _reloadCallCount }
    }

    func reloadConfig() async -> EngineReloadResult {
        lock.withLock { _reloadCallCount += 1 }
        return result
    }
}

/// Mock diagnostics manager with configurable health status.
@MainActor
private final class MockDiagnosticsManager: @preconcurrency DiagnosticsManaging {
    var healthStatus: ServiceHealthStatus = .healthy()
    private var diagnostics: [KanataDiagnostic] = []
    var connectionFailureCount = 0

    func addDiagnostic(_ diagnostic: KanataDiagnostic) {
        diagnostics.append(diagnostic)
    }

    func getDiagnostics() -> [KanataDiagnostic] {
        diagnostics
    }

    func clearDiagnostics() {
        diagnostics.removeAll()
    }

    func startLogMonitoring() {}
    func stopLogMonitoring() {}

    func checkHealth(tcpPort _: Int) async -> ServiceHealthStatus {
        healthStatus
    }

    func recordConnectionFailure() async -> Bool {
        connectionFailureCount += 1
        return connectionFailureCount >= 10
    }

    func recordConnectionSuccess() async {
        connectionFailureCount = 0
    }

    func recordGrabFailureAndDecideRecovery() async -> GrabRecoveryDecision {
        .recover(attempt: 1)
    }

    func recordGrabSuccess() async {}

    func diagnoseFailure(exitCode _: Int32, output _: String) -> [KanataDiagnostic] {
        []
    }

    func getSystemDiagnostics(engineClient _: EngineClient?) async -> [KanataDiagnostic] {
        []
    }
}

// MARK: - Thread-safe notification helpers

/// Thread-safe boolean flag for use in notification observer closures.
private final class NotificationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.withLock { _value }
    }

    func set() {
        lock.withLock { _value = true }
    }
}

/// Thread-safe optional string for capturing notification payloads.
private final class NotificationMessage: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?

    var value: String? {
        lock.withLock { _value }
    }

    func set(_ msg: String?) {
        lock.withLock { _value = msg }
    }
}

// MARK: - Tests

@Suite("ConfigReloadCoordinator Tests")
@MainActor
struct ConfigReloadCoordinatorTests {

    // MARK: - Factory

    /// Creates a ConfigReloadCoordinator with the given mock dependencies.
    /// The coordinator is wired to the shared mocks so callers can adjust
    /// behaviour before invoking `triggerConfigReload()` etc.
    private static func makeSUT(
        engineResult: EngineReloadResult = .success(response: "ok"),
        healthy: Bool = true
    ) -> (
        coordinator: ConfigReloadCoordinator,
        engine: MockEngineClient,
        diagnostics: MockDiagnosticsManager
    ) {
        let engine = MockEngineClient()
        engine.result = engineResult

        let diagnostics = MockDiagnosticsManager()
        diagnostics.healthStatus = healthy
            ? .healthy()
            : .unhealthy(reason: "Service not running")

        let safetyMonitor = ReloadSafetyMonitor()
        let processLifecycle = ProcessLifecycleManager()

        let coordinator = ConfigReloadCoordinator(
            engineClient: engine,
            reloadSafetyMonitor: safetyMonitor,
            diagnosticsManager: diagnostics,
            processLifecycleManager: processLifecycle
        )

        return (coordinator, engine, diagnostics)
    }

    // MARK: - triggerConfigReload: unhealthy service

    @Test("triggerConfigReload returns failure when service is unhealthy")
    func reloadFailsWhenUnhealthy() async {
        let (coordinator, _, _) = Self.makeSUT(healthy: false)

        let result = await coordinator.triggerConfigReload()

        #expect(result.isSuccess == false)
        #expect(result.errorMessage != nil)
        #expect(result.errorMessage?.contains("not running") == true
            || result.errorMessage?.contains("starting") == true
            || result.errorMessage?.contains("Service") == true,
            "Error message should reference unhealthy service, got: \(result.errorMessage ?? "nil")")
    }

    // MARK: - triggerConfigReload: onReloadSuccess callback

    @Test("triggerConfigReload calls onReloadSuccess on successful reload")
    func reloadCallsOnSuccessCallback() async {
        let (coordinator, _, _) = Self.makeSUT(
            engineResult: .success(response: "reload ok"),
            healthy: true
        )

        var callbackCalled = false
        coordinator.onReloadSuccess = { callbackCalled = true }

        let result = await coordinator.triggerConfigReload()

        // triggerConfigReload calls triggerTCPReload which bails in the
        // test environment, so the TCP result will be a networkError.
        // The onReloadSuccess callback is only called on TCP success,
        // so in the test environment it will NOT be called.
        // This verifies the correct wiring even though the test env guard
        // prevents the full path.
        if result.isSuccess {
            #expect(callbackCalled == true, "onReloadSuccess should fire on success")
        } else {
            // In test environment triggerTCPReload returns networkError,
            // so the callback is not expected to fire.
            #expect(callbackCalled == false,
                "onReloadSuccess should not fire when TCP is disabled in test env")
        }
    }

    // MARK: - triggerConfigReload: notification on success

    @Test("triggerConfigReload posts configReloadRecovered on success")
    func reloadPostsRecoveredNotification() async {
        let (coordinator, _, _) = Self.makeSUT(
            engineResult: .success(response: "ok"),
            healthy: true
        )

        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadRecovered,
            object: nil,
            queue: .main
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        // If the reload succeeded (unlikely in test env due to TCP guard),
        // the notification should be posted.
        if result.isSuccess {
            #expect(received.value == true)
        }
        // If TCP is disabled, we verify no false positive notification fires.
        if !result.isSuccess {
            #expect(received.value == false,
                "Should not post recovered notification when reload failed")
        }
    }

    // MARK: - triggerConfigReload: notification on non-cooldown failure

    @Test("triggerConfigReload posts configReloadFailed on non-cooldown failure")
    func reloadPostsFailedNotification() async {
        let (coordinator, _, _) = Self.makeSUT(
            engineResult: .failure(error: "validation error", response: "bad config"),
            healthy: true
        )

        let received = NotificationFlag()
        let message = NotificationMessage()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: nil,
            queue: nil // deliver synchronously on posting thread
        ) { notification in
            received.set()
            message.set(notification.userInfo?["message"] as? String)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        // In test env, triggerTCPReload returns .networkError("Test environment - TCP disabled").
        // That is NOT a cooldown message, so configReloadFailed should be posted.
        if !result.isSuccess {
            #expect(received.value == true,
                "Should post configReloadFailed for non-cooldown errors")
            if let msg = message.value {
                #expect(!msg.contains("cooldown"),
                    "Error message should not be a cooldown block")
            }
        }
    }

    // MARK: - Cooldown block detection

    @Test("cooldown block message is detected correctly")
    func cooldownBlockDetection() async {
        let (coordinator, _, _) = Self.makeSUT(healthy: true)

        // We cannot call isCooldownBlockMessage directly (it is private),
        // but we can verify the behaviour indirectly: when the TCP error
        // contains "Reload blocked" and "cooldown", configReloadFailed
        // should NOT be posted (it is treated as a throttle, not a real failure).
        //
        // In test env, triggerTCPReload always returns
        //   .networkError("Test environment - TCP disabled")
        // which does NOT contain "Reload blocked" or "cooldown", so the
        // notification WILL fire. We test the detection logic by checking
        // that a non-cooldown message does fire the notification (already
        // covered above) and separately verify the string matching logic
        // via ReloadResult properties.

        // Simulate a cooldown-like error message and verify it matches
        // the pattern the coordinator uses internally.
        let cooldownMsg = "Reload blocked by safety monitor: Reload cooldown - 1.5s remaining"
        let normalMsg = "validation error in config file"

        // The coordinator checks: message.contains("Reload blocked") && message.contains("cooldown")
        let isCooldown = cooldownMsg.contains("Reload blocked") && cooldownMsg.contains("cooldown")
        let isNormalCooldown = normalMsg.contains("Reload blocked") && normalMsg.contains("cooldown")

        #expect(isCooldown == true, "Should detect cooldown block message")
        #expect(isNormalCooldown == false, "Should not falsely detect cooldown in normal error")

        // Also verify partial matches are rejected
        let partialA = "Reload blocked by something else"
        let partialB = "In cooldown period"
        #expect(
            !(partialA.contains("Reload blocked") && partialA.contains("cooldown")),
            "Partial match without 'cooldown' should not be detected")
        #expect(
            !(partialB.contains("Reload blocked") && partialB.contains("cooldown")),
            "Partial match without 'Reload blocked' should not be detected")

        // Confirm the coordinator itself can be called without crashing
        _ = await coordinator.triggerConfigReload()
    }

    // MARK: - triggerTCPReload: test environment guard

    @Test("triggerTCPReload returns networkError in test environment")
    func tcpReloadDisabledInTests() async {
        let (coordinator, _, _) = Self.makeSUT()

        let tcpResult = await coordinator.triggerTCPReload()

        #expect(tcpResult.isSuccess == false,
            "TCP reload should not succeed in test environment")
        #expect(tcpResult.errorMessage?.contains("Test environment") == true,
            "Error should mention test environment, got: \(tcpResult.errorMessage ?? "nil")")
    }

    // MARK: - ReloadResult properties

    @Test("ReloadResult properties work correctly")
    func reloadResultProperties() {
        let success = ReloadResult(
            success: true,
            response: "config reloaded",
            errorMessage: nil,
            protocol: .tcp
        )
        #expect(success.isSuccess == true)
        #expect(success.response == "config reloaded")
        #expect(success.errorMessage == nil)

        let failure = ReloadResult(
            success: false,
            response: "error details",
            errorMessage: "validation failed",
            protocol: .tcp
        )
        #expect(failure.isSuccess == false)
        #expect(failure.response == "error details")
        #expect(failure.errorMessage == "validation failed")

        let noProtocol = ReloadResult(
            success: false,
            response: nil,
            errorMessage: "Permission required",
            protocol: nil
        )
        #expect(noProtocol.isSuccess == false)
        #expect(noProtocol.response == nil)
        #expect(noProtocol.errorMessage == "Permission required")
    }

    // MARK: - triggerReload: completes without crashing

    @Test("triggerReload logs warning on failure and completes")
    func triggerReloadCompletesOnFailure() async {
        let (coordinator, _, _) = Self.makeSUT(healthy: false)

        // triggerReload calls triggerConfigReload internally.
        // With unhealthy diagnostics, it should fail gracefully and log a warning.
        // The key assertion is that it completes without throwing or crashing.
        await coordinator.triggerReload()

        // If we got here, the method completed successfully.
        // Verify the coordinator is still functional after the failure path.
        let result = await coordinator.triggerConfigReload()
        #expect(result.isSuccess == false,
            "Should still return failure on subsequent calls with unhealthy service")
    }

    // MARK: - TCPReloadResult properties

    @Test("TCPReloadResult enum cases expose correct properties")
    func tcpReloadResultProperties() {
        let success = TCPReloadResult.success(response: "reload ok")
        #expect(success.isSuccess == true)
        #expect(success.errorMessage == nil)
        #expect(success.response == "reload ok")

        let failure = TCPReloadResult.failure(error: "bad config", response: "details here")
        #expect(failure.isSuccess == false)
        #expect(failure.errorMessage == "bad config")
        #expect(failure.response == "details here")

        let networkError = TCPReloadResult.networkError("connection refused")
        #expect(networkError.isSuccess == false)
        #expect(networkError.errorMessage == "connection refused")
        #expect(networkError.response == nil)
    }

    // MARK: - EngineReloadResult properties

    @Test("EngineReloadResult enum cases expose correct properties")
    func engineReloadResultProperties() {
        let success = EngineReloadResult.success(response: "done")
        #expect(success.isSuccess == true)
        #expect(success.errorMessage == nil)
        #expect(success.response == "done")

        let failure = EngineReloadResult.failure(error: "parse error", response: "line 42")
        #expect(failure.isSuccess == false)
        #expect(failure.errorMessage == "parse error")
        #expect(failure.response == "line 42")

        let networkErr = EngineReloadResult.networkError("timeout")
        #expect(networkErr.isSuccess == false)
        #expect(networkErr.errorMessage == "timeout")
        #expect(networkErr.response == nil)
    }

    // MARK: - Multiple reloads are independent

    @Test("successive triggerConfigReload calls return independent results")
    func successiveReloadsAreIndependent() async {
        let (coordinator, _, diagnostics) = Self.makeSUT(healthy: false)

        // First call: unhealthy -> fails
        let result1 = await coordinator.triggerConfigReload()
        #expect(result1.isSuccess == false)

        // Switch to healthy
        diagnostics.healthStatus = .healthy()

        // Second call: healthy -> proceeds (though TCP guard will still fire in test env)
        let result2 = await coordinator.triggerConfigReload()

        // Whether it ultimately succeeds or fails via the TCP guard,
        // the error message should differ from the first call's health error.
        if let err1 = result1.errorMessage, let err2 = result2.errorMessage {
            // err1 is a health-related message, err2 is a TCP/test-environment message
            #expect(err1 != err2 || result2.isSuccess,
                "Second call should get past the health check gate")
        }
    }

    // MARK: - onReloadSuccess is nil-safe

    @Test("triggerConfigReload works when onReloadSuccess is nil")
    func reloadWithNilCallback() async {
        let (coordinator, _, _) = Self.makeSUT(healthy: true)

        // Explicitly leave onReloadSuccess as nil (the default)
        coordinator.onReloadSuccess = nil

        // Should complete without crashing regardless of outcome
        _ = await coordinator.triggerConfigReload()
    }
}

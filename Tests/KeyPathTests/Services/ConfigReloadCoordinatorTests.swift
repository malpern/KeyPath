import Foundation
@testable import KeyPathAppKit
import KeyPathCore
import Testing
@preconcurrency import XCTest

// MARK: - Thread-safe notification helpers

@MainActor
private final class MutableHealthStatus {
    var value: ServiceHealthStatus

    init(_ value: ServiceHealthStatus) {
        self.value = value
    }
}

@MainActor
private final class MutableRuntimeTransition {
    var isTransitioning: Bool
    var waitCount = 0
    var reloadCount = 0
    var tcpReloadCount = 0
    var managedCaps = false
    var paused = false
    var restartCount = 0
    var wantsRunning = true
    var intentGeneration: UInt64 = 0

    init(isTransitioning: Bool) {
        self.isTransitioning = isTransitioning
    }
}

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
        healthStatusOverride: (@MainActor @Sendable () async -> ServiceHealthStatus)? = nil,
        healthy: Bool = true,
        runtimeTransitioning: Bool = false,
        runtimeTransitionState: MutableRuntimeTransition? = nil,
        tcpReloadResult: TCPReloadResult = .success(response: "ok"),
        reloadEngine: (@MainActor @Sendable () async -> TCPReloadResult)? = nil,
        reloadCooldownSeconds: TimeInterval = 0,
        transitionRetryMaximumPolls: Int = Int((RuntimeStartupTiming.uiGracePeriod / 0.5).rounded(.up)),
        transitionRetryWait: @escaping @MainActor @Sendable () async -> Void = {
            await Task.yield()
        },
        automaticDeferredRetriesEnabled: Bool = true,
        startRuntimeForExplicitApply: (@MainActor @Sendable () async -> Bool)? = nil,
        currentManagedCaps: @escaping @MainActor @Sendable () -> Bool = { false },
        restartForManagedCapsChange: (@MainActor @Sendable () async -> Bool)? = nil,
        sessionValidationOverride: (@MainActor @Sendable () -> (result: KanataHostBridgeValidationResult, managedCaps: Bool))? = nil,
        currentCapsIntermediate: @escaping @MainActor @Sendable () -> UInt32? = { nil },
        admittedIntermediateOverride: (@MainActor @Sendable () -> UInt32)? = nil,
        currentCapsPaused: @escaping @MainActor @Sendable () -> Bool = { false },
        capsNoLongerNeeded: (@MainActor @Sendable () -> Void)? = nil
    ) -> (coordinator: ConfigReloadCoordinator, healthStatus: MutableHealthStatus) {
        let healthStatus = MutableHealthStatus(healthy
            ? .healthy()
            : .unhealthy(reason: "Service not running"))

        let transitionState = runtimeTransitionState
            ?? MutableRuntimeTransition(isTransitioning: runtimeTransitioning)
        let coordinator = ConfigReloadCoordinator(
            reloadSafetyMonitor: ReloadSafetyMonitor(reloadCooldownSeconds: reloadCooldownSeconds),
            healthStatusProvider: {
                if let healthStatusOverride { return await healthStatusOverride() }
                return healthStatus.value
            },
            isRuntimeTransitioning: { transitionState.isTransitioning },
            reloadEngine: reloadEngine ?? { tcpReloadResult },
            transitionRetryMaximumPolls: transitionRetryMaximumPolls,
            transitionRetryWait: transitionRetryWait,
            automaticDeferredRetriesEnabled: automaticDeferredRetriesEnabled,
            startRuntimeForExplicitApply: startRuntimeForExplicitApply,
            runtimeWantsRunning: { transitionState.wantsRunning },
            runtimeIntentGeneration: { transitionState.intentGeneration },
            currentManagedCaps: currentManagedCaps,
            currentCapsIntermediate: currentCapsIntermediate,
            currentCapsPaused: currentCapsPaused,
            capsNoLongerNeeded: capsNoLongerNeeded,
            restartForManagedCapsChange: restartForManagedCapsChange,
            sessionValidationOverride: sessionValidationOverride ?? { (.valid, false) },
            admittedIntermediateOverride: admittedIntermediateOverride
        )

        return (coordinator, healthStatus)
    }

    @Test("Explicit retry starts a stopped session and reloads only after fresh readiness")
    func explicitRetryRecoversStoppedRuntime() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let health = MutableHealthStatus(.unhealthy(reason: "Keyboard disconnected"))
        let sut = ConfigReloadCoordinator(
            reloadSafetyMonitor: ReloadSafetyMonitor(),
            healthStatusProvider: { health.value },
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "applied") },
            startRuntimeForExplicitApply: { state.restartCount += 1; health.value = .healthy(); return true },
            sessionValidationOverride: { (.valid, false) }
        )
        let result = await sut.triggerConfigReload(recoverStoppedRuntime: true)
        #expect(result.disposition == .applied)
        #expect(state.restartCount == 1)
        #expect(state.tcpReloadCount == 1)
    }

    @Test("Ordinary reload never starts a stopped runtime")
    func backgroundReloadPreservesManualStop() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (sut, _) = Self.makeSUT(healthy: false,
                                    startRuntimeForExplicitApply: { state.restartCount += 1; return true })
        let result = await sut.triggerConfigReload()
        #expect(result.disposition == .pending)
        #expect(state.restartCount == 0)
    }

    @Test("Failed or unverified startup cannot report applied", arguments: [false, true])
    func explicitRetryRequiresReadiness(startResult: Bool) async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (sut, _) = Self.makeSUT(healthy: false,
                                    reloadEngine: { state.tcpReloadCount += 1; return .success(response: "wrong") },
                                    startRuntimeForExplicitApply: { state.restartCount += 1; return startResult })
        let result = await sut.triggerConfigReload(recoverStoppedRuntime: true)
        #expect(result.disposition == .pending)
        #expect(state.restartCount == 1)
        #expect(state.tcpReloadCount == 0)
    }

    @Test("Explicit retry does not race an in-progress transition")
    func explicitRetryWaitsForTransition() async {
        let state = MutableRuntimeTransition(isTransitioning: true)
        let (sut, _) = Self.makeSUT(healthy: false, runtimeTransitionState: state,
                                    startRuntimeForExplicitApply: { state.restartCount += 1; return true })
        #expect(await sut.triggerConfigReload(recoverStoppedRuntime: true).disposition == .pending)
        #expect(state.restartCount == 0)
    }

    @Test("Crossing Caps runtime modes restarts and never sends a TCP reload", arguments: [false, true])
    func capsModeChangeRestarts(current: Bool) async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        state.managedCaps = current
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            currentManagedCaps: { state.managedCaps },
            restartForManagedCapsChange: {
                state.restartCount += 1
                state.managedCaps = !current
                return true
            },
            sessionValidationOverride: { (.valid, !current) }
        )
        let result = await coordinator.triggerTCPReload()
        #expect(result.isSuccess)
        #expect(state.restartCount == 1)
        #expect(state.tcpReloadCount == 0)
        #expect(state.managedCaps == !current)
    }

    @Test("A session running with Caps paused reloads in place instead of restarting on every save")
    func pausedCapsSessionReloadsInPlace() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            currentManagedCaps: { false },
            restartForManagedCapsChange: { state.restartCount += 1; return true },
            sessionValidationOverride: { (.valid, true) },
            currentCapsPaused: { true }
        )
        #expect(await coordinator.triggerTCPReload().isSuccess)
        #expect(state.restartCount == 0)
        #expect(state.tcpReloadCount == 1)
    }

    @Test("Reloading a profile without Caps rules clears a standing pause; one with Caps rules keeps it",
          arguments: [false, true])
    func reloadClearsPauseOnlyWithoutCapsRules(needsCaps: Bool) async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        state.paused = true
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { .success(response: "tcp") },
            currentManagedCaps: { false },
            restartForManagedCapsChange: { state.restartCount += 1; return true },
            sessionValidationOverride: { (.valid, needsCaps) },
            currentCapsPaused: { state.paused },
            capsNoLongerNeeded: { state.paused = false }
        )
        #expect(await coordinator.triggerTCPReload().isSuccess)
        #expect(state.paused == needsCaps)
        #expect(state.restartCount == 0)
    }

    @Test("A Caps restart that lands paused (no keyboard found) still applies the reload")
    func capsRestartLandingPausedSucceeds() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            currentManagedCaps: { false },
            restartForManagedCapsChange: { state.restartCount += 1; state.paused = true; return true },
            sessionValidationOverride: { (.valid, true) },
            currentCapsPaused: { state.paused }
        )
        #expect(await coordinator.triggerTCPReload().isSuccess)
        #expect(state.restartCount == 1)
        #expect(state.tcpReloadCount == 0)
    }

    @Test("A rule that takes the running Caps intermediate restarts instead of reloading", arguments: [UInt32(109), 110])
    func movedCapsIntermediateRestarts(admitted: UInt32) async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        state.managedCaps = true
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            currentManagedCaps: { state.managedCaps },
            restartForManagedCapsChange: {
                state.restartCount += 1
                return true
            },
            sessionValidationOverride: { (.valid, true) },
            currentCapsIntermediate: { 109 },
            admittedIntermediateOverride: { admitted }
        )
        let result = await coordinator.triggerTCPReload()
        #expect(result.isSuccess)
        let moved = admitted != 109
        #expect(state.restartCount == (moved ? 1 : 0))
        #expect(state.tcpReloadCount == (moved ? 0 : 1))
    }

    @Test("A successful Caps mode restart may advance lifecycle intent")
    func successfulCapsRestartAdvancesIntent() async {
        let transition = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            runtimeTransitionState: transition,
            currentManagedCaps: { transition.managedCaps },
            restartForManagedCapsChange: {
                transition.intentGeneration += 1
                transition.managedCaps = true
                return true
            },
            sessionValidationOverride: { (.valid, true) }
        )
        #expect(await coordinator.triggerConfigReload().disposition == .applied)
        #expect(transition.intentGeneration == 1)
    }

    @Test("A Caps mode change without a restart owner is refused")
    func capsModeChangeRequiresRestartOwner() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            sessionValidationOverride: { (.valid, true) }
        )
        let result = await coordinator.triggerTCPReload()
        #expect(!result.isSuccess)
        #expect(result.errorMessage?.contains("requires a session restart") == true)
        #expect(state.tcpReloadCount == 0)
    }

    @Test("A failed restart or an unconfirmed Caps report blocks the reload", arguments: [false, true])
    func capsRestartMustConfirmMode(restartResult: Bool) async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            restartForManagedCapsChange: { state.restartCount += 1; return restartResult },
            sessionValidationOverride: { (.valid, true) }
        )
        let result = await coordinator.triggerTCPReload()
        #expect(!result.isSuccess)
        #expect(state.restartCount == 1)
        #expect(state.tcpReloadCount == 0)
    }

    @Test("Same Caps mode uses TCP without restarting", arguments: [false, true])
    func unchangedCapsModeReloads(current: Bool) async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            currentManagedCaps: { current },
            restartForManagedCapsChange: { state.restartCount += 1; return false },
            sessionValidationOverride: { (.valid, current) }
        )
        let result = await coordinator.triggerTCPReload()
        #expect(result.isSuccess)
        #expect(state.tcpReloadCount == 1)
        #expect(state.restartCount == 0)
    }

    @Test("Invalid admission cannot restart or TCP reload")
    func invalidCapsProfileCannotApply() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "tcp") },
            restartForManagedCapsChange: { state.restartCount += 1; return true },
            sessionValidationOverride: { (.invalid(reason: "Caps is not eligible"), true) }
        )
        let result = await coordinator.triggerTCPReload()
        #expect(!result.isSuccess)
        #expect(state.tcpReloadCount == 0)
        #expect(state.restartCount == 0)
    }

    // MARK: - triggerConfigReload: unhealthy service

    @Test("triggerConfigReload returns failure when service is unhealthy")
    func reloadFailsWhenUnhealthy() async {
        let (coordinator, _) = Self.makeSUT(healthy: false)

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
        let (coordinator, _) = Self.makeSUT(
            tcpReloadResult: .success(response: "reload ok")
        )

        var callbackCalled = false
        coordinator.onReloadSuccess = { callbackCalled = true }

        let result = await coordinator.triggerConfigReload()

        #expect(result.disposition == .applied)
        #expect(result.response == "reload ok")
        #expect(callbackCalled)
    }

    // MARK: - triggerConfigReload: notification on success

    @Test("triggerConfigReload posts configReloadRecovered on success")
    func reloadPostsRecoveredNotification() async {
        let (coordinator, _) = Self.makeSUT()

        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadRecovered,
            object: coordinator,
            queue: .main
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        #expect(result.disposition == .applied)
        #expect(received.value)
    }

    // MARK: - triggerConfigReload: notification on non-cooldown failure

    @Test("network failure during runtime transition stays pending without failure notification")
    func transitionNetworkFailureStaysPending() async {
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitioning: true,
            tcpReloadResult: .networkError("Connection failed: Connection closed"),
            automaticDeferredRetriesEnabled: false
        )

        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        #expect(result.isSuccess == false)
        #expect(result.disposition == .pending)
        #expect(result.errorMessage?.contains("restarting") == true)
        #expect(received.value == false)
    }

    @Test("network failure stays pending when transition finishes during TCP request")
    func transitionEndingDuringTCPFailureStaysPending() async {
        let transition = MutableRuntimeTransition(isTransitioning: true)
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitionState: transition,
            reloadEngine: {
                transition.isTransitioning = false
                return .networkError("Connection failed: Connection closed")
            },
            automaticDeferredRetriesEnabled: false
        )
        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        #expect(result.disposition == .pending)
        #expect(received.value == false)
    }

    @Test("deferred success refreshes context inside configuration admission")
    func deferredSuccessRefreshesContextUnderAdmission() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(healthy: true, tcpReloadResult: .success(response: "ok"))
        let gate = ConfigurationOperationGate()
        coordinator.configurationOperationGate = gate
        coordinator.onDeferredReloadSuccess = {
            state.reloadCount += 1
            do {
                try await gate.withOperation { _ in }
                Issue.record("Context refresh must retain configuration admission")
            } catch {
                if case ConfigurationOperationGate.Failure.recursiveOperation = error {}
                else { Issue.record("Unexpected admission error: \(error)") }
            }
        }
        _ = await coordinator.triggerConfigReload()
        #expect(state.reloadCount == 0, "Immediate reload settlement belongs to the save owner")
        let result = await coordinator.performDeferredReload()
        #expect(result.disposition == .applied)
        #expect(state.reloadCount == 1)
    }

    @Test("An edit during unhealthy startup is delivered after readiness")
    func unhealthyStartupSchedulesDeferredReload() async {
        let transition = MutableRuntimeTransition(isTransitioning: true)
        let applied = XCTestExpectation(description: "Deferred edit reached runtime")
        let (coordinator, health) = Self.makeSUT(
            healthy: false,
            runtimeTransitionState: transition,
            reloadEngine: {
                transition.tcpReloadCount += 1
                return .success(response: "ok")
            },
            transitionRetryMaximumPolls: 1,
            transitionRetryWait: {
                while transition.isTransitioning {
                    await Task.yield()
                }
            }
        )
        coordinator.onDeferredReloadSuccess = { applied.fulfill() }
        let result = await coordinator.triggerConfigReload()
        #expect(result.disposition == .pending)
        #expect(transition.tcpReloadCount == 0)
        health.value = .healthy()
        transition.isTransitioning = false
        let settled = await XCTWaiter.fulfillment(of: [applied], timeout: 2)
        #expect(settled == .completed)
        #expect(transition.tcpReloadCount == 1)
    }

    @Test("A manual stop during deferred startup cancels retry quietly")
    func stopDuringTransitionRetryCancelsQuietly() async {
        let transition = MutableRuntimeTransition(isTransitioning: true)
        let (coordinator, _) = Self.makeSUT(
            runtimeTransitionState: transition,
            reloadEngine: { transition.tcpReloadCount += 1; return .success(response: "ok") },
            transitionRetryMaximumPolls: 1,
            transitionRetryWait: {
                transition.wantsRunning = false
                transition.intentGeneration += 1
                transition.isTransitioning = false
            }
        )
        let failure = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(forName: .configReloadFailed, object: coordinator, queue: nil) { _ in failure.set() }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(await coordinator.retryAfterRuntimeTransition() == false)
        #expect(transition.tcpReloadCount == 0)
        #expect(!failure.value)
    }

    @Test("A reload waiting for health cannot undo a newer manual stop")
    func newerStopPreventsManagedCapsRestart() async {
        let transition = MutableRuntimeTransition(isTransitioning: false)
        transition.managedCaps = true
        let (coordinator, _) = Self.makeSUT(
            healthStatusOverride: {
                // Simulate Stop completing while the fresh TCP health request
                // is suspended. Its older reply must not override that intent.
                transition.managedCaps = false
                transition.wantsRunning = false
                transition.intentGeneration += 1
                return .healthy()
            },
            runtimeTransitionState: transition,
            reloadEngine: { transition.tcpReloadCount += 1; return .success(response: "ok") },
            currentManagedCaps: { transition.managedCaps },
            restartForManagedCapsChange: {
                transition.restartCount += 1
                transition.managedCaps = true
                return true
            },
            sessionValidationOverride: { (.valid, true) }
        )
        let result = await coordinator.triggerConfigReload()
        #expect(result.disposition == .pending)
        #expect(transition.restartCount == 0)
        #expect(transition.tcpReloadCount == 0)
    }

    @Test("transition retry waits for readiness and reloads once")
    func transitionRetryWaitsForReadiness() async {
        let transition = MutableRuntimeTransition(isTransitioning: true)
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitionState: transition,
            tcpReloadResult: .success(response: "ok"),
            transitionRetryMaximumPolls: 1,
            transitionRetryWait: {
                transition.waitCount += 1
                transition.isTransitioning = false
            }
        )
        coordinator.onReloadSuccess = { transition.reloadCount += 1 }
        coordinator.onDeferredReloadSuccess = { transition.tcpReloadCount += 1 }

        let didRetry = await coordinator.retryAfterRuntimeTransition()

        #expect(didRetry == true)
        #expect(transition.waitCount == 1)
        #expect(transition.reloadCount == 1)
        #expect(transition.tcpReloadCount == 1)
    }

    @Test("transition retry checks reload outcome and retries a transient failure")
    func transitionRetryChecksReloadOutcome() async {
        let transition = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitionState: transition,
            reloadEngine: {
                transition.tcpReloadCount += 1
                if transition.tcpReloadCount == 1 {
                    transition.isTransitioning = true
                    return .networkError("Connection closed")
                }
                return .success(response: "ok")
            },
            transitionRetryMaximumPolls: 2,
            transitionRetryWait: {
                transition.waitCount += 1
                transition.isTransitioning = false
            }
        )
        coordinator.onReloadSuccess = { transition.reloadCount += 1 }

        let didRetry = await coordinator.retryAfterRuntimeTransition()

        #expect(didRetry == true)
        #expect(transition.tcpReloadCount == 2)
        #expect(transition.waitCount == 1)
        #expect(transition.reloadCount == 1)
    }

    @Test("transition retry surfaces a permanent reload rejection immediately")
    func transitionRetrySurfacesPermanentRejection() async {
        let transition = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitionState: transition,
            tcpReloadResult: .failure(error: "validation error", response: "bad config"),
            transitionRetryMaximumPolls: 2,
            transitionRetryWait: { transition.waitCount += 1 }
        )
        let message = NotificationMessage()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil
        ) { notification in
            message.set(notification.userInfo?["message"] as? String)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let didRetry = await coordinator.retryAfterRuntimeTransition()

        #expect(didRetry == false)
        #expect(transition.waitCount == 0)
        #expect(message.value == "validation error")
    }

    @Test("transition retry expires without reloading when runtime never settles")
    func transitionRetryExpires() async {
        let transition = MutableRuntimeTransition(isTransitioning: true)
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitionState: transition,
            tcpReloadResult: .success(response: "ok"),
            transitionRetryMaximumPolls: 2,
            transitionRetryWait: { transition.waitCount += 1 }
        )
        coordinator.onReloadSuccess = { transition.reloadCount += 1 }
        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let didRetry = await coordinator.retryAfterRuntimeTransition()

        #expect(didRetry == false)
        #expect(transition.waitCount == 2)
        #expect(transition.reloadCount == 0)
        #expect(received.value == true)
    }

    @Test("network failure outside runtime transition remains a visible failure")
    func settledNetworkFailureStillNotifies() async {
        let (coordinator, _) = Self.makeSUT(
            healthy: true,
            runtimeTransitioning: false,
            tcpReloadResult: .networkError("Connection failed: Connection closed")
        )

        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        #expect(result.disposition == .failed)
        #expect(received.value == true)
    }

    @Test("triggerConfigReload posts configReloadFailed on non-cooldown failure")
    func reloadPostsFailedNotification() async {
        let (coordinator, _) = Self.makeSUT(
            tcpReloadResult: .failure(error: "validation error", response: "bad config")
        )

        let received = NotificationFlag()
        let message = NotificationMessage()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil // deliver synchronously on posting thread
        ) { notification in
            received.set()
            message.set(notification.userInfo?["message"] as? String)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = await coordinator.triggerConfigReload()

        #expect(result.disposition == .rejected)
        #expect(result.response == "bad config")
        #expect(received.value)
        #expect(message.value == "validation error")
    }

    // MARK: - Cooldown block detection

    @Test("A reload during cooldown stays pending without sending another engine request")
    func cooldownBlockDetection() async {
        let state = MutableRuntimeTransition(isTransitioning: false)
        let (coordinator, _) = Self.makeSUT(
            reloadEngine: { state.tcpReloadCount += 1; return .success(response: "applied") },
            reloadCooldownSeconds: 60
        )
        let received = NotificationFlag()
        let observer = NotificationCenter.default.addObserver(
            forName: .configReloadFailed,
            object: coordinator,
            queue: nil
        ) { _ in received.set() }
        defer { NotificationCenter.default.removeObserver(observer) }

        #expect(await coordinator.triggerConfigReload().disposition == .applied)
        let result = await coordinator.triggerConfigReload(scheduleRetryOnPending: false)
        #expect(result.disposition == .pending)
        #expect(result.errorMessage?.contains("cooldown") == true)
        #expect(state.tcpReloadCount == 1)
        #expect(!received.value)
    }

    // MARK: - triggerTCPReload: test environment guard

    @Test("triggerTCPReload returns networkError in test environment")
    func tcpReloadDisabledInTests() async {
        let coordinator = ConfigReloadCoordinator(
            reloadSafetyMonitor: ReloadSafetyMonitor(),
            healthStatusProvider: { .healthy() }
        )

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
        let (coordinator, _) = Self.makeSUT(healthy: false)

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

    // MARK: - Multiple reloads are independent

    @Test("successive triggerConfigReload calls return independent results")
    func successiveReloadsAreIndependent() async {
        let (coordinator, diagnostics) = Self.makeSUT(healthy: false)

        // First call: unhealthy -> fails
        let result1 = await coordinator.triggerConfigReload()
        #expect(result1.isSuccess == false)

        // Switch to healthy
        diagnostics.value = .healthy()

        let result2 = await coordinator.triggerConfigReload()
        #expect(result2.disposition == .applied)
    }

    // MARK: - onReloadSuccess is nil-safe

    @Test("triggerConfigReload works when onReloadSuccess is nil")
    func reloadWithNilCallback() async {
        let (coordinator, _) = Self.makeSUT(healthy: true)

        // Explicitly leave onReloadSuccess as nil (the default)
        coordinator.onReloadSuccess = nil

        // Should complete without crashing regardless of outcome
        _ = await coordinator.triggerConfigReload()
    }
}

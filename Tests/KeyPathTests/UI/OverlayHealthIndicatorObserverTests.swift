@testable import KeyPathAppKit
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore
import XCTest

final class OverlayHealthIndicatorObserverTests: KeyPathTestCase {
    @MainActor
    func testHealthyStateTriggersDismiss() async {
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in states.append(state) },
            onDismiss: { states.append(.dismissed) },
            sleep: { _ in }
        )

        let controller = MainAppStateController()
        controller.validationState = .success
        controller.issues = []

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(states.contains(.healthy))
        XCTAssertEqual(states.last, .dismissed)
    }

    @MainActor
    func testSuccessWithNonBlockingIssuesShowsHealthy() async {
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in states.append(state) },
            onDismiss: { states.append(.dismissed) },
            sleep: { _ in }
        )

        let controller = MainAppStateController()
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .warning,
                category: .daemon,
                title: "Warning",
                description: "Non-blocking warning",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .conflict(.kanataProcessRunning(pid: 1, command: "test")),
                severity: .error,
                category: .conflicts,
                title: "Conflict",
                description: "Resolvable conflict",
                autoFixAction: nil,
                userAction: nil
            ),
        ]
        controller.validationState = .success

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(
            states.contains(.healthy),
            "Should show healthy when validation succeeds with non-blocking issues"
        )
        XCTAssertEqual(states.last, .dismissed, "Should auto-dismiss after healthy")
    }

    @MainActor
    func testFailedWithBlockingIssuesShowsCorrectCount() async {
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in states.append(state) },
            onDismiss: {},
            sleep: { _ in }
        )

        let controller = MainAppStateController()
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .error,
                category: .daemon,
                title: "Daemon Error",
                description: "Blocking issue",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .warning,
                category: .permissions,
                title: "Permission Warning",
                description: "Non-blocking",
                autoFixAction: nil,
                userAction: nil
            ),
            WizardIssue(
                identifier: .conflict(.kanataProcessRunning(pid: 1, command: "test")),
                severity: .error,
                category: .conflicts,
                title: "Conflict",
                description: "Resolvable",
                autoFixAction: nil,
                userAction: nil
            ),
        ]
        controller.validationState = .failed(blockingCount: 1, totalCount: 3)

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(
            states.last,
            .unhealthy(issueCount: 1),
            "Should only count blocking issues (1 daemon error)"
        )
    }

    @MainActor
    func testDismissCancelledWhenStateChanges() async {
        var states: [HealthIndicatorState] = []
        let gate = AsyncGate()

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in states.append(state) },
            onDismiss: { states.append(.dismissed) },
            sleep: { _ in await gate.wait() }
        )

        let controller = MainAppStateController()
        controller.validationState = .success
        controller.issues = []

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        // Now transition to failed with an issue while dismiss is gated
        controller.issues = [
            WizardIssue(
                identifier: .daemon,
                severity: .error,
                category: .daemon,
                title: "Test",
                description: "Test",
                autoFixAction: nil,
                userAction: nil
            ),
        ]
        controller.validationState = .failed(blockingCount: 1, totalCount: 1)
        try? await Task.sleep(for: .milliseconds(400))

        gate.open()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(states.last, .unhealthy(issueCount: 1))
    }

    @MainActor
    func testRevalidationDoesNotFlashCheckingWhenHealthy() async {
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in states.append(state) },
            onDismiss: { states.append(.dismissed) },
            sleep: { _ in }
        )

        let controller = MainAppStateController()
        controller.validationState = .success
        controller.issues = []

        observer.startObserving(controller: controller)
        try? await Task.sleep(for: .milliseconds(400))

        // At this point observer should be healthy then dismissed
        XCTAssertTrue(states.contains(.healthy))
        states.removeAll()

        // Simulate periodic revalidation: success → checking → success
        controller.validationState = .checking
        try? await Task.sleep(for: .milliseconds(400))

        controller.validationState = .success
        try? await Task.sleep(for: .milliseconds(400))

        // Should NOT have flashed .checking — the observer should suppress it
        // when transitioning from healthy/dismissed
        XCTAssertFalse(
            states.contains(.checking),
            "Should not flash 'checking' during periodic revalidation when already healthy"
        )
    }
}

@MainActor
private final class AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Initialization Order Invariant Tests

final class HealthObserverInitializationOrderTests: XCTestCase {
    @MainActor
    func testRefreshRequiresConfiguredStateController() {
        let controller = MainAppStateController()

        XCTAssertFalse(controller.isConfigured, "Controller starts unconfigured")

        // Just set the validator — don't create a full RuntimeCoordinator
        // which starts TCP connections, event monitoring, etc. that hang on CI.
        let validator = SystemValidator(
            vhidDeviceManager: VHIDDeviceManager(),
            processLifecycleManager: ProcessLifecycleManager()
        )
        controller.setValidator(validator)

        XCTAssertTrue(controller.isConfigured, "Controller is configured after setValidator()")
    }

    @MainActor
    func testSharedControllerConfigurationCheckExists() {
        _ = MainAppStateController.shared.isConfigured
    }
}

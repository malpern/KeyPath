import Combine
@testable import KeyPathAppKit
import KeyPathWizardCore
import XCTest

final class OverlayHealthIndicatorObserverTests: XCTestCase {
    @MainActor
    func testHealthyAutoDismiss() async {
        let validation = CurrentValueSubject<MainAppStateController.ValidationState?, Never>(.checking)
        let issues = CurrentValueSubject<[WizardIssue], Never>([])
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in
                states.append(state)
            },
            onDismiss: {
                states.append(.dismissed)
            },
            sleep: { _ in }
        )

        observer.start(
            validationStatePublisher: validation.eraseToAnyPublisher(),
            issuesPublisher: issues.eraseToAnyPublisher()
        )

        await Task.yield()
        validation.send(.success)
        await Task.yield()

        XCTAssertTrue(states.contains(.healthy))
        XCTAssertEqual(states.last, .dismissed)
    }

    @MainActor
    func testSuccessWithNonBlockingIssuesShowsHealthy() async {
        // Regression test: .success state should show healthy even when non-blocking issues exist
        // (warnings, info, conflicts are not blocking)
        let validation = CurrentValueSubject<MainAppStateController.ValidationState?, Never>(.checking)
        let issues = CurrentValueSubject<[WizardIssue], Never>([])
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in
                states.append(state)
            },
            onDismiss: {
                states.append(.dismissed)
            },
            sleep: { _ in }
        )

        observer.start(
            validationStatePublisher: validation.eraseToAnyPublisher(),
            issuesPublisher: issues.eraseToAnyPublisher()
        )

        await Task.yield()

        // Send non-blocking issues (warning severity, conflicts category)
        let warningIssue = WizardIssue(
            identifier: .daemon,
            severity: .warning, // Non-blocking
            category: .daemon,
            title: "Warning",
            description: "Non-blocking warning",
            autoFixAction: nil,
            userAction: nil
        )
        let conflictIssue = WizardIssue(
            identifier: .conflictingProcess("karabiner"),
            severity: .error,
            category: .conflicts, // Conflicts are resolvable, not blocking
            title: "Conflict",
            description: "Resolvable conflict",
            autoFixAction: nil,
            userAction: nil
        )
        issues.send([warningIssue, conflictIssue])
        await Task.yield()

        // Despite issues existing, .success should show healthy
        validation.send(.success)
        await Task.yield()

        XCTAssertTrue(states.contains(.healthy), "Should show healthy when validation succeeds with non-blocking issues")
        XCTAssertEqual(states.last, .dismissed, "Should auto-dismiss after healthy")
    }

    @MainActor
    func testFailedWithBlockingIssuesShowsCorrectCount() async {
        // Only blocking issues (critical/error severity, non-conflict categories) should be counted
        let validation = CurrentValueSubject<MainAppStateController.ValidationState?, Never>(.checking)
        let issues = CurrentValueSubject<[WizardIssue], Never>([])
        var states: [HealthIndicatorState] = []

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in
                states.append(state)
            },
            onDismiss: {},
            sleep: { _ in }
        )

        observer.start(
            validationStatePublisher: validation.eraseToAnyPublisher(),
            issuesPublisher: issues.eraseToAnyPublisher()
        )

        await Task.yield()

        // Mix of blocking and non-blocking issues
        let blockingIssue = WizardIssue(
            identifier: .daemon,
            severity: .error, // Blocking
            category: .daemon, // Non-conflict category
            title: "Daemon Error",
            description: "Blocking issue",
            autoFixAction: nil,
            userAction: nil
        )
        let nonBlockingWarning = WizardIssue(
            identifier: .permissions,
            severity: .warning, // Non-blocking (warning)
            category: .permissions,
            title: "Permission Warning",
            description: "Non-blocking",
            autoFixAction: nil,
            userAction: nil
        )
        let conflictIssue = WizardIssue(
            identifier: .conflictingProcess("test"),
            severity: .error,
            category: .conflicts, // Conflicts are resolvable, not counted
            title: "Conflict",
            description: "Resolvable",
            autoFixAction: nil,
            userAction: nil
        )

        issues.send([blockingIssue, nonBlockingWarning, conflictIssue])
        await Task.yield()

        validation.send(.failed)
        await Task.yield()

        // Should only count the one blocking issue (daemon error), not the warning or conflict
        XCTAssertEqual(states.last, .unhealthy(issueCount: 1), "Should only count blocking issues (1 daemon error)")
    }

    @MainActor
    func testDismissCancelledWhenStateChanges() async {
        let validation = CurrentValueSubject<MainAppStateController.ValidationState?, Never>(.checking)
        let issues = CurrentValueSubject<[WizardIssue], Never>([])
        var states: [HealthIndicatorState] = []
        let gate = AsyncGate()

        let observer = OverlayHealthIndicatorObserver(
            onStateChange: { state in
                states.append(state)
            },
            onDismiss: {
                states.append(.dismissed)
            },
            sleep: { _ in
                await gate.wait()
            }
        )

        observer.start(
            validationStatePublisher: validation.eraseToAnyPublisher(),
            issuesPublisher: issues.eraseToAnyPublisher()
        )

        await Task.yield()
        validation.send(.success)
        await Task.yield()

        let issue = WizardIssue(
            identifier: .daemon,
            severity: .error,
            category: .daemon,
            title: "Test",
            description: "Test",
            autoFixAction: nil,
            userAction: nil
        )
        issues.send([issue])
        await Task.yield()

        gate.open()
        await Task.yield()

        XCTAssertEqual(states.last, .unhealthy(issueCount: 1))
        XCTAssertFalse(states.contains(.dismissed))
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

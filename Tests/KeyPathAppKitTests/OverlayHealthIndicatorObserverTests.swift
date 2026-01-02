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

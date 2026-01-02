import Combine
import Foundation
import KeyPathWizardCore

@MainActor
final class OverlayHealthIndicatorObserver {
    typealias StateHandler = (HealthIndicatorState) -> Void
    typealias Sleep = (UInt64) async -> Void

    private let onStateChange: StateHandler
    private let onDismiss: () -> Void
    private let sleep: Sleep
    private var cancellable: AnyCancellable?
    private var dismissTask: Task<Void, Never>?
    private var currentState: HealthIndicatorState = .dismissed
    private var isObserving = false

    init(
        onStateChange: @escaping StateHandler,
        onDismiss: @escaping () -> Void,
        sleep: @escaping Sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.onStateChange = onStateChange
        self.onDismiss = onDismiss
        self.sleep = sleep
    }

    func start(
        validationStatePublisher: AnyPublisher<MainAppStateController.ValidationState?, Never>,
        issuesPublisher: AnyPublisher<[WizardIssue], Never>
    ) {
        guard !isObserving else { return }
        isObserving = true

        cancellable = Publishers.CombineLatest(
            validationStatePublisher,
            issuesPublisher
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] state, issues in
            self?.handle(state: state, issues: issues)
        }
    }

    private func handle(state: MainAppStateController.ValidationState?, issues: [WizardIssue]) {
        dismissTask?.cancel()
        dismissTask = nil

        switch state {
        case nil, .checking:
            setState(.checking)
        case .success where issues.isEmpty:
            setState(.healthy)
            scheduleDismiss()
        default:
            setState(.unhealthy(issueCount: issues.count))
        }
    }

    private func scheduleDismiss() {
        dismissTask = Task { [sleep] in
            await sleep(1_500_000_000)
            guard !Task.isCancelled else { return }
            if case .healthy = currentState {
                currentState = .dismissed
                onDismiss()
            }
        }
    }

    private func setState(_ state: HealthIndicatorState) {
        currentState = state
        onStateChange(state)
    }
}

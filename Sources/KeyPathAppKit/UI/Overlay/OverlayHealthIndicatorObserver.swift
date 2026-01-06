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
    private var checkingDebounceTask: Task<Void, Never>?
    private var currentState: HealthIndicatorState = .dismissed
    private var isObserving = false

    /// Debounce duration for showing "checking" state (prevents brief flashes)
    private let checkingDebounceNanoseconds: UInt64 = 300_000_000 // 300ms

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
            // Debounce the "checking" state to prevent brief flashes when validation is quick
            // Only show "checking" if we're not already in a good state or if it persists
            if currentState == .dismissed || currentState == .healthy {
                // Already in good state - debounce before showing "checking"
                scheduleCheckingState()
            } else {
                // Already showing checking or unhealthy - update immediately
                setState(.checking)
            }
        case .success where issues.isEmpty:
            // Cancel any pending "checking" state since we're now healthy
            checkingDebounceTask?.cancel()
            checkingDebounceTask = nil
            setState(.healthy)
            scheduleDismiss()
        default:
            // Cancel any pending "checking" state
            checkingDebounceTask?.cancel()
            checkingDebounceTask = nil
            setState(.unhealthy(issueCount: issues.count))
        }
    }

    /// Schedule showing the "checking" state after a debounce period
    /// This prevents the drawer from flashing "System Not Ready" during quick revalidations
    private func scheduleCheckingState() {
        // Cancel any existing debounce task
        checkingDebounceTask?.cancel()

        checkingDebounceTask = Task { [weak self, sleep, checkingDebounceNanoseconds] in
            await sleep(checkingDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.setState(.checking)
            }
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

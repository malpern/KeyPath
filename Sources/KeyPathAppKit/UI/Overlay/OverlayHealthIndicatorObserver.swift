import Foundation
import KeyPathCore
import KeyPathWizardCore

@MainActor
final class OverlayHealthIndicatorObserver {
    typealias StateHandler = (HealthIndicatorState) -> Void
    typealias Sleep = (Duration) async -> Void

    private let onStateChange: StateHandler
    private let onDismiss: () -> Void
    private let sleep: Sleep
    private var dismissTask: Task<Void, Never>?
    private var checkingDebounceTask: Task<Void, Never>?
    private var currentState: HealthIndicatorState = .dismissed
    private var isObserving = false

    /// Debounce duration for showing "checking" state (prevents brief flashes)
    private let checkingDebounceDuration: Duration = .milliseconds(300)

    init(
        onStateChange: @escaping StateHandler,
        onDismiss: @escaping () -> Void,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.onStateChange = onStateChange
        self.onDismiss = onDismiss
        self.sleep = sleep
    }

    /// Start observing an @Observable MainAppStateController via polling
    func startObserving(controller: MainAppStateController) {
        AppLogger.shared.log("🔔 [HealthObserver] startObserving(controller:) called - isObserving=\(isObserving)")
        guard !isObserving else {
            AppLogger.shared.log("🔔 [HealthObserver] startObserving() - already observing, skipping")
            return
        }
        isObserving = true

        Task { @MainActor [weak self] in
            var lastState: MainAppStateController.ValidationState?
            var lastIssueCount: Int?
            while let self, !Task.isCancelled {
                let state = controller.validationState
                let issues = controller.issues
                if state != lastState || issues.count != lastIssueCount {
                    lastState = state
                    lastIssueCount = issues.count
                    handle(state: state, issues: issues)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        // Handle initial values
        handle(state: controller.validationState, issues: controller.issues)
    }

    /// Force a refresh of the health state from current MainAppStateController values.
    /// Call this when showing the overlay to ensure UI reflects current state,
    /// especially when Combine subscription is already active (won't re-emit current value).
    ///
    /// This fixes the "System Not Ready" stale state bug where `showForStartup()` is called
    /// multiple times but the observer guard prevents re-subscription, leaving the UI stuck.
    ///
    /// - Precondition: MainAppStateController must be configured before calling this method.
    func refresh() {
        // INVARIANT: MainAppStateController must be configured before overlay observes it.
        // If this check fails, configure() is being called too late in the startup sequence.
        // See: App.swift init() where configure() must happen before showForStartup().
        guard MainAppStateController.shared.isConfigured else {
            // Log error in all builds (including Release) so we can detect this in production
            AppLogger.shared.error(
                "🚨 [HealthObserver] INITIALIZATION ORDER BUG: MainAppStateController.configure() was not called before overlay health observation. This will cause stale 'System Not Ready' state."
            )
            // In debug builds, crash to catch this during development
            assertionFailure(
                "MainAppStateController.configure() must be called before overlay health observation starts"
            )
            // In release builds, show checking state and return (graceful degradation)
            setState(.checking)
            return
        }

        let state = MainAppStateController.shared.validationState
        let issues = MainAppStateController.shared.issues
        AppLogger.shared.log("🔔 [HealthObserver] refresh() called - forcing state re-evaluation")
        handle(state: state, issues: issues)
    }

    private func handle(state: MainAppStateController.ValidationState?, issues: [WizardIssue]) {
        AppLogger.shared.log("🔔 [HealthObserver] handle() called - state=\(String(describing: state)), issues=\(issues.count), currentState=\(currentState)")

        dismissTask?.cancel()
        dismissTask = nil

        // Only count blocking issues (critical/error severity, excluding conflicts which are resolvable)
        let blockingIssues = issues.filter { issue in
            switch issue.category {
            case .conflicts:
                false // Conflicts are resolvable, not blocking
            case .permissions, .installation, .systemRequirements, .backgroundServices, .daemon:
                issue.severity == .critical || issue.severity == .error
            }
        }

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
        case .success:
            // Cancel any pending "checking" state since we're now healthy
            // Note: We trust .success state regardless of non-blocking issues
            checkingDebounceTask?.cancel()
            checkingDebounceTask = nil
            setState(.healthy)
            scheduleDismiss()
        case .failed:
            // Cancel any pending "checking" state
            checkingDebounceTask?.cancel()
            checkingDebounceTask = nil
            // If there are no blocking issues (only conflicts which are filtered out),
            // treat as healthy - conflicts don't block the drawer from working
            if blockingIssues.isEmpty {
                setState(.healthy)
                scheduleDismiss()
            } else {
                setState(.unhealthy(issueCount: blockingIssues.count))
            }
        }
    }

    /// Schedule showing the "checking" state after a debounce period
    /// This prevents the drawer from flashing "System Not Ready" during quick revalidations
    private func scheduleCheckingState() {
        // Cancel any existing debounce task
        checkingDebounceTask?.cancel()

        checkingDebounceTask = Task { [weak self, sleep, checkingDebounceDuration] in
            await sleep(checkingDebounceDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.setState(.checking)
            }
        }
    }

    private func scheduleDismiss() {
        dismissTask = Task { [sleep] in
            await sleep(.milliseconds(1500))
            guard !Task.isCancelled else { return }
            if case .healthy = currentState {
                currentState = .dismissed
                onDismiss()
            }
        }
    }

    private func setState(_ state: HealthIndicatorState) {
        AppLogger.shared.log("🔔 [HealthObserver] setState: \(currentState) -> \(state)")
        currentState = state
        onStateChange(state)
    }
}

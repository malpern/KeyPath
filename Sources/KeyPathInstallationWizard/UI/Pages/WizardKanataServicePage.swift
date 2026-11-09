import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public struct WizardKanataServicePage: View {
    @Environment(\.runtimeCoordinator) var kanataManager
    public let onRefresh: () -> Void

    @State private var isPerformingAction = false
    @State private var serviceStatus: ServiceStatus = .unknown
    @State private var actionStatus: WizardDesign.ActionStatus = .idle
    @State private var attemptedAutomaticStart = false
    @State private var refreshTask: Task<Void, Never>?

    /// Integration with RuntimeCoordinator for better error context
    @Environment(WizardStateMachine.self) private var stateMachine

    private var systemState: WizardSystemState {
        stateMachine.wizardState
    }

    private var issues: [WizardIssue] {
        stateMachine.wizardIssues
    }

    public init(onRefresh: @escaping () -> Void) {
        self.onRefresh = onRefresh
    }

    enum ServiceStatus: Equatable {
        case unknown
        case running
        case stopped
        case failed(error: String)
        case starting
        case stopping

        var color: Color {
            switch self {
            case .running: .green
            case .stopped: .orange
            case .failed: .red
            case .starting, .stopping: .blue
            case .unknown: .gray
            }
        }

        var icon: String {
            switch self {
            case .running: "checkmark.circle.fill"
            case .stopped: "stop.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            case .starting, .stopping: "arrow.clockwise.circle.fill"
            case .unknown: "questionmark.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .running: "Runtime is running"
            case .stopped: "Runtime is not running"
            case .failed: "Service error"
            case .starting: "Runtime is starting..."
            case .stopping: "Runtime is stopping..."
            case .unknown: "Checking runtime status..."
            }
        }
    }

    private var startFailed: Bool {
        if case .error = actionStatus { return true }
        return false
    }

    public var body: some View {
        VStack(spacing: 0) {
            WizardHeroSection(
                icon: "gearshape.2",
                iconColor: serviceStatus.color,
                overlayIcon: serviceStatus.icon,
                overlayColor: serviceStatus.color,
                overlaySize: .large,
                title: "KeyPath Runtime",
                subtitle: statusMessage,
                iconTapAction: { refreshStatus() }
            )
            .padding(.top, WizardDesign.Spacing.sectionGap)

            // Inline action status
            if actionStatus.isActive, let message = actionStatus.message {
                InlineStatusView(status: actionStatus, message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Hidden only while the one automatic start is pending. Once it has been
            // tried, a stopped runtime always offers the button: the status clears
            // after a success, so "failed" alone could leave the page stuck.
            if let cta = primaryCTAConfiguration,
               serviceStatus != .stopped || startFailed || (attemptedAutomaticStart && !isPerformingAction)
            {
                Button(cta.label, action: cta.action)
                    .buttonStyle(WizardDesign.Component.PrimaryButton(isLoading: isPerformingAction))
                    .keyboardShortcut(.defaultAction)
                    .disabled(cta.disabled)
                    .frame(minHeight: 44)
                    .padding(.top, WizardDesign.Spacing.itemGap)
                    .accessibilityIdentifier("wizard-service-action-button")
            }

            if shouldShowNextStepButton {
                Button(nextStepButtonTitle) {
                    navigateToNextStep()
                }
                .buttonStyle(WizardDesign.Component.PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .padding(.top, WizardDesign.Spacing.sectionGap)
                .accessibilityIdentifier("wizard-service-next-button")
            }
        }
        .animation(WizardDesign.Animation.statusTransition, value: actionStatus)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(WizardDesign.Colors.wizardBackground)
        .wizardDetailPage()
        .task(id: serviceStatus) {
            switch serviceStatus {
            case .stopped where !attemptedAutomaticStart && !isPerformingAction:
                attemptedAutomaticStart = true
                startService()
            case .running:
                _ = await WizardSleep.ms(1000)
                guard !Task.isCancelled, serviceStatus == .running else { return }
                navigateToNextStep()
            default:
                break
            }
        }
        .onAppear {
            refreshStatus()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .onChange(of: systemState) { _, _ in refreshStatus() }
        .onChange(of: issues) { _, _ in refreshStatus() }
    }

    // MARK: - Helper Methods

    private enum DesiredServiceState {
        case running
        case stopped
    }

    private func evaluateServiceCompletion(target: DesiredServiceState, actionName: String) {
        switch target {
        case .running:
            switch serviceStatus {
            case .running:
                actionStatus = .success(message: "\(actionName) succeeded")
                scheduleStatusClear()
            case let .failed(error):
                actionStatus = .error(message: error)
            default:
                actionStatus = .error(message: "\(actionName) did not complete. Try again.")
            }
        case .stopped:
            switch serviceStatus {
            case .stopped:
                actionStatus = .success(message: "\(actionName) succeeded")
                scheduleStatusClear()
            case .failed:
                actionStatus = .error(message: "\(actionName) failed. Try again.")
            default:
                actionStatus = .error(message: "\(actionName) did not complete. Try again.")
            }
        }
    }

    @MainActor
    private func completeServiceAction(
        succeeded: Bool,
        target: DesiredServiceState,
        actionName: String
    ) async {
        isPerformingAction = false
        if !succeeded, case .running = target,
           let error = kanataManager?.lastError,
           !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            // A completed refusal is not transient startup. Cancel the initial
            // status poll so it cannot replace this known failure with a spinner.
            refreshTask?.cancel()
            refreshTask = nil
            serviceStatus = .failed(error: error)
            actionStatus = .error(message: error)
            onRefresh()
            return
        }
        await refreshStatusAsync(actionSucceeded: succeeded)
        evaluateServiceCompletion(target: target, actionName: actionName)
        if !succeeded, case .running = target, let error = kanataManager?.lastError {
            actionStatus = .error(message: error)
        }
        onRefresh()
    }

    /// Auto-clear success status after 3 seconds
    private func scheduleStatusClear() {
        Task { @MainActor in
            _ = await WizardSleep.seconds(3)
            if case .success = actionStatus {
                actionStatus = .idle
            }
        }
    }

    // MARK: - Computed Properties

    private var statusForHeader: WizardPageHeader.HeaderStatus {
        switch serviceStatus {
        case .running: .success
        case .stopped, .unknown: .info
        case .failed: .error
        case .starting, .stopping: .warning
        }
    }

    private var statusTitle: String {
        switch serviceStatus {
        case .running: "Service Running"
        case .stopped: "Service Not Running"
        case .failed: "Service Error"
        case .starting: "Starting Service"
        case .stopping: "Stopping Service"
        case .unknown: "Checking Status"
        }
    }

    private var statusMessage: String {
        switch serviceStatus {
        case .running:
            "KeyPath Runtime, powered by Kanata Engine, is running and ready to process keyboard events."
        case .stopped:
            "Preparing your keyboard shortcuts…"
        case let .failed(error):
            error
        case .starting:
            "Starting KeyPath runtime…"
        case .stopping:
            "KeyPath runtime is shutting down."
        case .unknown:
            "Checking KeyPath runtime status… If this takes too long, click Start."
        }
    }

    private var shouldShowNextStepButton: Bool {
        serviceStatus == .running
    }

    private var nextStepButtonTitle: String {
        issues.isEmpty ? "Return to Summary" : "Next Issue"
    }

    // MARK: - Actions

    private func startService() {
        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [WizardKanataServicePage] kanataManager not configured")
            return
        }
        isPerformingAction = true
        serviceStatus = .starting
        actionStatus = .inProgress(message: "Starting KeyPath runtime…")

        Task { @MainActor in
            let succeeded = await kanataManager.startKanata(reason: "Wizard automatic startup")
            await completeServiceAction(
                succeeded: succeeded,
                target: .running,
                actionName: "Kanata start"
            )
        }
    }

    private func restartService() {
        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [WizardKanataServicePage] kanataManager not configured")
            return
        }
        isPerformingAction = true
        serviceStatus = .stopping
        actionStatus = .inProgress(message: "Restarting KeyPath runtime…")

        Task { @MainActor in
            let succeeded = await kanataManager.restartKanata(reason: "Wizard service restart button")
            await completeServiceAction(
                succeeded: succeeded,
                target: .running,
                actionName: "Kanata restart"
            )
        }
    }

    private func stopService() {
        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [WizardKanataServicePage] kanataManager not configured")
            return
        }
        isPerformingAction = true
        serviceStatus = .stopping
        actionStatus = .inProgress(message: "Stopping KeyPath runtime…")

        Task { @MainActor in
            let succeeded = await kanataManager.stopKanata(reason: "Wizard service stop button")
            await completeServiceAction(
                succeeded: succeeded,
                target: .stopped,
                actionName: "Kanata stop"
            )
        }
    }

    private func refreshStatus() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshStatusAsync()
        }
    }

    private func refreshStatusAsync(actionSucceeded: Bool? = nil) async {
        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [WizardKanataServicePage] kanataManager not configured — skipping status refresh")
            return
        }
        var completedAttempts = 0

        while !Task.isCancelled {
            let runtimeStatus = await kanataManager.currentRuntimeStatus()
            let isInTransientStartupWindow = await kanataManager.isInTransientRuntimeStartupWindow()

            let processStatus = if let actionSucceeded {
                ServiceStatusEvaluator.evaluateAfterAction(
                    operationSucceeded: actionSucceeded,
                    kanataIsRunning: runtimeStatus.isRunning,
                    systemState: systemState,
                    issues: issues
                )
            } else {
                ServiceStatusEvaluator.evaluateObservedRuntime(
                    runtimeStatus: runtimeStatus,
                    systemState: systemState,
                    issues: issues
                )
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    applyStatusUpdate(
                        runtimeStatus: runtimeStatus,
                        processStatus: processStatus,
                        isInTransientStartupWindow: isInTransientStartupWindow
                    )
                }
            }

            completedAttempts += 1
            let shouldRetry = ServiceStatusEvaluator.shouldRetryTransientStatus(
                runtimeStatus: runtimeStatus,
                isInTransientStartupWindow: isInTransientStartupWindow,
                completedAttempts: completedAttempts
            )
            guard shouldRetry else {
                if ServiceStatusEvaluator.didExhaustTransientStatus(
                    runtimeStatus: runtimeStatus,
                    isInTransientStartupWindow: isInTransientStartupWindow,
                    completedAttempts: completedAttempts
                ) {
                    await MainActor.run {
                        serviceStatus = .failed(
                            error: "Runtime startup did not finish. Click Restart to retry."
                        )
                    }
                }
                return
            }

            AppLogger.shared.log(
                "⏳ [WizardKanataServicePage] Runtime is still starting; scheduling bounded status retry \(completedAttempts)/\(ServiceStatusEvaluator.transientRefreshAttemptLimit)"
            )
            guard await WizardSleep.seconds(1) else { return }
        }
    }

    @MainActor
    private func applyStatusUpdate(
        runtimeStatus: WizardRuntimeStatus,
        processStatus: ServiceProcessStatus,
        isInTransientStartupWindow: Bool
    ) {
        var derivedStatus: ServiceStatus = switch runtimeStatus {
        case .running:
            .running
        case .stopped:
            isInTransientStartupWindow ? .starting : .stopped
        case let .failed(reason):
            .failed(error: reason)
        case .starting:
            .starting
        case .unknown:
            .unknown
        }

        switch processStatus {
        case .running:
            break
        case let .failed(message):
            let errorMessage = message ?? "Permission or service issue detected"
            derivedStatus = .failed(error: errorMessage)
        case .stopped:
            // If we previously thought it was running, align with evaluator
            if derivedStatus == .running {
                derivedStatus = .stopped
            }
        }

        if case .stopped = derivedStatus {
            serviceStatus = .stopped
            AppLogger.shared.log("🔍 [ServiceStatus] Service stopped")
            return
        }

        if case .running = derivedStatus {
            AppLogger.shared.log("✅ [ServiceStatus] Service confirmed functional via shared evaluator")
        } else if case let .failed(error) = derivedStatus {
            AppLogger.shared.log("⚠️ [ServiceStatus] Service failed: \(error)")
        }

        serviceStatus = derivedStatus
    }

    private func navigateToNextStep() {
        if issues.isEmpty {
            stateMachine.navigateToPage(.summary)
            return
        }

        Task {
            if let nextPage = await stateMachine.getNextPage(for: systemState, issues: issues),
               nextPage != stateMachine.currentPage
            {
                stateMachine.navigateToPage(nextPage)
            } else {
                stateMachine.navigateToPage(.summary)
            }
        }
    }

    private var primaryCTAConfiguration:
        (label: String, action: () -> Void, disabled: Bool)?
    {
        switch serviceStatus {
        case .running:
            nil
        case .starting, .stopping:
            nil
        case .unknown:
            (
                label: "Start",
                action: startService,
                disabled: isPerformingAction
            )
        case .stopped:
            (
                label: "Start",
                action: startService,
                disabled: isPerformingAction
            )
        case .failed:
            (
                label: "Restart",
                action: restartService,
                disabled: isPerformingAction
            )
        }
    }
}

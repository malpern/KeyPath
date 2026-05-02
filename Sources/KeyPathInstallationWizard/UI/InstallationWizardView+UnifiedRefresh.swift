import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Unified State Refresh

    /// Consolidated refresh method that handles all refresh scenarios
    /// - Parameters:
    ///   - showSpinner: Whether to show summary validating activity state
    ///   - previousPage: The page we're coming from (enables special handling for communication page)
    public func refreshSystemState(showSpinner: Bool = false, previousPage: WizardPage? = nil) {
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Refresh blocked - force closing in progress")
            return
        }

        // Debounce rapid refreshes
        let now = Date()
        if let last = lastRefreshAt, now.timeIntervalSince(last) < 0.3 {
            AppLogger.shared.log("🔍 [Wizard] Refresh skipped (debounced)")
            return
        }
        lastRefreshAt = now

        AppLogger.shared.log("🔍 [Wizard] Refreshing system state (showSpinner=\(showSpinner), from=\(previousPage?.rawValue ?? "nil"))")

        // Cancel any previous refresh task
        refreshTask?.cancel()

        // Show validating state if requested (used when returning to summary page)
        if showSpinner {
            withAnimation(.easeInOut(duration: 0.2)) {
                isValidating = true
            }
            stateMachine.wizardIssues = []
        }

        refreshTask = Task { [previousPage, showSpinner] in
            // Wait for in-flight operations to complete (only when showing validating state)
            if showSpinner, await MainActor.run(body: { asyncOperationManager.hasRunningOperations }) {
                AppLogger.shared.log("🔍 [Wizard] Refresh waiting for in-flight operations")
                while !Task.isCancelled,
                      await MainActor.run(body: { asyncOperationManager.hasRunningOperations })
                {
                    _ = await WizardSleep.ms(200)
                }
            }

            guard !Task.isCancelled else { return }

            // Give TCP server time to recover after leaving communication page
            if previousPage == .communication {
                _ = await WizardSleep.seconds(1)
            }

            // Run state detection with optional retry for communication page
            await MainActor.run {
                performStateDetection(
                    previousPage: previousPage,
                    attempt: 0,
                    showSpinner: showSpinner
                )
            }
        }
    }

    /// Internal: Performs state detection with retry logic for communication page
    @MainActor
    public func performStateDetection(previousPage: WizardPage?, attempt: Int, showSpinner: Bool) {
        guard !isForceClosing else { return }

        let operation = WizardOperations.stateDetection(
            stateMachine: stateMachine,
            progressCallback: { _ in }
        )

        asyncOperationManager.execute(operation: operation) { [previousPage, attempt, showSpinner] (result: SystemStateResult) in
            // Retry once if coming from communication page and seeing transient issues
            if previousPage == .communication, attempt == 0, shouldRetryForCommunication(result: result) {
                AppLogger.shared.log("🔍 [Wizard] Deferring result for TCP warm-up, will retry")
                Task {
                    _ = await WizardSleep.seconds(1.5)
                    await MainActor.run {
                        performStateDetection(previousPage: previousPage, attempt: 1, showSpinner: showSpinner)
                    }
                }
                return
            }

            _ = applySystemStateResult(result)

            if showSpinner {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isValidating = false
                }
            }
        }
    }

    /// Check if we should retry due to transient communication issues
    public func shouldRetryForCommunication(result: SystemStateResult) -> Bool {
        // Retry if service appears not running
        switch result.state {
        case .serviceNotRunning, .daemonNotRunning:
            return true
        default:
            break
        }

        // Also retry if there are transient communication issues (TCP warm-up)
        return result.issues.contains { issue in
            guard case let .component(component) = issue.identifier else { return false }
            switch component {
            case .kanataTCPServer,
                 .communicationServerConfiguration,
                 .communicationServerNotResponding,
                 .tcpServerConfiguration,
                 .tcpServerNotResponding:
                return true
            default:
                return false
            }
        }
    }

    public func cachedPreferredPage() async -> WizardPage? {
        // Use last known system state from WizardStateMachine if available
        guard let cachedState = stateMachine.lastWizardSnapshot else { return nil }
        let page = await stateMachine.navigationEngine.firstPageNeedingAttention(
            for: cachedState.state, issues: cachedState.issues
        )
        return page != .summary ? page : nil
    }

    public func sanitizedIssues(from issues: [WizardIssue], for state: WizardSystemState)
        -> [WizardIssue]
    {
        guard shouldSuppressCommunicationIssues(for: state) else {
            return issues
        }

        let filtered = issues.filter { !isCommunicationIssue($0) }
        if filtered.count != issues.count {
            AppLogger.shared.log(
                "🔇 [Wizard] Suppressing \(issues.count - filtered.count) communication issue(s) because Kanata service is not running"
            )
        }
        return filtered
    }

    @MainActor
    public func applySystemStateResult(_ result: SystemStateResult) -> [WizardIssue] {
        let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
        stateMachine.updateWizardState(result.state, issues: filteredIssues)

        // Only auto-navigate if user hasn't been interacting with the wizard
        // This prevents jarring navigation away from a page after a fix completes
        let shouldAutoNavigate = !stateMachine.userInteractionMode

        if shouldNavigateToSummary(
            currentPage: stateMachine.currentPage,
            state: result.state,
            issues: filteredIssues
        ) {
            AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
            stateMachine.navigateToPage(.summary)
        } else if shouldAutoNavigate {
            // Skip green pages: if current page has no relevant issues, navigate to one that does
            let currentPageHasIssues = stateMachine.navigationEngine.pageHasRelevantIssues(
                stateMachine.currentPage,
                issues: filteredIssues,
                state: result.state
            )
            if !currentPageHasIssues {
                Task {
                    let recommended = await stateMachine.navigationEngine
                        .firstPageNeedingAttention(for: result.state, issues: filteredIssues)
                    if recommended != stateMachine.currentPage {
                        AppLogger.shared.log("🔄 [Wizard] Skipping green page \(stateMachine.currentPage) → \(recommended)")
                        stateMachine.navigateToPage(recommended)
                    }
                }
            }
        }

        AppLogger.shared.log(
            "🔍 [Wizard] State applied - Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
        )

        return filteredIssues
    }

    public func shouldSuppressCommunicationIssues(for state: WizardSystemState) -> Bool {
        if case .active = state {
            return false
        }
        return true
    }

    public func isCommunicationIssue(_ issue: WizardIssue) -> Bool {
        guard case let .component(component) = issue.identifier else {
            return false
        }

        switch component {
        case .kanataTCPServer,
             .communicationServerConfiguration,
             .communicationServerNotResponding,
             .tcpServerConfiguration,
             .tcpServerNotResponding:
            return true
        default:
            return false
        }
    }

    public func startKeyPathRuntime() {
        Task {
            if stateMachine.wizardState != .active {
                guard let kanataManager else {
                    AppLogger.shared.log("⚠️ [Wizard] kanataManager not configured — cannot start runtime")
                    return
                }
                let operation = WizardOperations.startService(kanataManager: kanataManager)

                asyncOperationManager.execute(operation: operation) { (success: Bool) in
                    if success {
                        AppLogger.shared.log("✅ [Wizard] KeyPath Runtime started successfully")
                        toastManager.showSuccess("KeyPath Runtime started")
                        dismissAndRefreshMainScreen()
                    } else {
                        AppLogger.shared.log("❌ [Wizard] Failed to start KeyPath Runtime")
                        let failureMessage =
                            kanataManager.lastError
                                ?? "KeyPath Runtime failed to stay running. Review /var/log/com.keypath.kanata.stderr.log for details."
                        toastManager.showError(failureMessage)
                    }
                } onFailure: { error in
                    AppLogger.shared.log(
                        "❌ [Wizard] Error starting KeyPath Runtime: \(error.localizedDescription)"
                    )
                    toastManager.showError("Start failed: \(error.localizedDescription)")
                }
            } else {
                // Service already running, dismiss wizard
                dismissAndRefreshMainScreen()
            }
        }
    }

}

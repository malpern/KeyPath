import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - Unified State Refresh

    /// Consolidated refresh method that handles all refresh scenarios
    /// - Parameters:
    ///   - showSpinner: Whether to show the validating spinner (used when returning to summary)
    ///   - previousPage: The page we're coming from (enables special handling for communication page)
    func refreshSystemState(showSpinner: Bool = false, previousPage: WizardPage? = nil) {
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

        // Show spinner if requested (used when returning to summary page)
        if showSpinner {
            withAnimation(.easeInOut(duration: 0.2)) {
                isValidating = true
            }
            stateMachine.wizardIssues = []
        }

        refreshTask = Task { [previousPage, showSpinner] in
            // Wait for in-flight operations to complete (only when showing spinner)
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
    func performStateDetection(previousPage: WizardPage?, attempt: Int, showSpinner: Bool) {
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
    func shouldRetryForCommunication(result: SystemStateResult) -> Bool {
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

    @MainActor
    func autoNavigateIfSingleIssue(in issues: [WizardIssue], state _: WizardSystemState) {
        AppLogger.shared.log("🔍 [AutoNav] ===== autoNavigateIfSingleIssue CALLED =====")
        AppLogger.shared.log("🔍 [AutoNav] Current page: \(stateMachine.currentPage)")
        AppLogger.shared.log("🔍 [AutoNav] Issues count: \(issues.count)")
        AppLogger.shared.log("🔍 [AutoNav] navSequence count: \(navSequence.count)")
        AppLogger.shared.log("🔍 [AutoNav] navSequence pages: \(navSequence.map(\.displayName))")

        guard stateMachine.currentPage == .summary else {
            AppLogger.shared.log("🔍 [AutoNav] SKIP: Not on summary page")
            return
        }

        // If there's exactly 1 item in the summary list, navigate to it directly
        // navSequence represents what's actually displayed, so trust it
        guard navSequence.count == 1, let targetPage = navSequence.first else {
            AppLogger.shared.log(
                "🔍 [AutoNav] ❌ NOT AUTO-NAVIGATING: navSequence has \(navSequence.count) items"
            )
            return
        }

        AppLogger.shared.log("🔍 [AutoNav] ✅ AUTO-NAVIGATING to \(targetPage) (single item in summary)")
        stateMachine.navigateToPage(targetPage)
        AppLogger.shared.log("🔍 [AutoNav] Navigation command sent")
    }

    func preferredDetailPage(for state: WizardSystemState, issues: [WizardIssue])
        async -> WizardPage?
    {
        let page = await stateMachine.navigationEngine.determineCurrentPage(
            for: state, issues: issues
        )
        guard page != .summary else { return nil }

        let hasExactlyOneIssue = issues.count == 1
        let serviceOnly = issues.isEmpty && page == .service
        return (hasExactlyOneIssue || serviceOnly) ? page : nil
    }

    func cachedPreferredPage() async -> WizardPage? {
        // Use last known system state from WizardStateMachine if available
        guard let cachedState = stateMachine.lastWizardSnapshot else { return nil }
        let adaptedIssues = cachedState.issues
        let adaptedState = cachedState.state
        return await preferredDetailPage(for: adaptedState, issues: adaptedIssues)
    }

    func sanitizedIssues(from issues: [WizardIssue], for state: WizardSystemState)
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
    func applySystemStateResult(_ result: SystemStateResult) -> [WizardIssue] {
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
            Task {
                if let preferred = await preferredDetailPage(for: result.state, issues: filteredIssues),
                   stateMachine.currentPage != preferred
                {
                    AppLogger.shared.log("🔄 [Wizard] Deterministic routing to \(preferred) after refresh")
                    stateMachine.navigateToPage(preferred)
                }
            }
        }
        if stateMachine.currentPage == .summary, shouldAutoNavigate {
            Task { @MainActor in
                _ = await WizardSleep.ms(50) // 50ms
                autoNavigateIfSingleIssue(in: filteredIssues, state: result.state)
            }
        }

        AppLogger.shared.log(
            "🔍 [Wizard] State applied - Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
        )

        return filteredIssues
    }

    func shouldSuppressCommunicationIssues(for state: WizardSystemState) -> Bool {
        if case .active = state {
            return false
        }
        return true
    }

    func isCommunicationIssue(_ issue: WizardIssue) -> Bool {
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

    func startKanataService() {
        Task {
            // Show safety confirmation before starting
            let shouldStart = await showStartConfirmation()

            if shouldStart {
                if stateMachine.wizardState != .active {
                    let operation = WizardOperations.startService(kanataManager: kanataManager)

                    asyncOperationManager.execute(operation: operation) { (success: Bool) in
                        if success {
                            AppLogger.shared.log("✅ [Wizard] Kanata service started successfully")
                            toastManager.showSuccess("Kanata service started")
                            dismissAndRefreshMainScreen()
                        } else {
                            AppLogger.shared.log("❌ [Wizard] Failed to start Kanata service")
                            let failureMessage =
                                kanataManager.lastError
                                    ?? "Kanata service failed to stay running. Review /var/log/com.keypath.kanata.stderr.log for details."
                            toastManager.showError(failureMessage)
                        }
                    } onFailure: { error in
                        AppLogger.shared.log(
                            "❌ [Wizard] Error starting Kanata service: \(error.localizedDescription)"
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

    func handleCloseButtonTapped() {
        // INSTANT CLOSE: Cancel operations immediately and force close
        asyncOperationManager.cancelAllOperationsAsync()

        // Check for critical issues - but don't block the close
        let criticalIssues = stateMachine.wizardIssues.filter { $0.severity == .critical }

        if criticalIssues.isEmpty {
            // Force immediate close - bypass any SwiftUI environment blocking
            forceInstantClose()
        } else {
            // Show confirmation but allow instant close anyway
            showingCloseConfirmation = true
        }
    }

    /// Force immediate wizard dismissal bypassing any potential SwiftUI blocking
    func forceInstantClose() {
        dismissAndRefreshMainScreen()
    }

    /// Dismiss wizard and trigger main screen validation refresh
    func dismissAndRefreshMainScreen() {
        // Cancel any Login Items polling before dismissing
        stopLoginItemsApprovalPolling()

        // Use DispatchQueue to ensure immediate execution
        DispatchQueue.main.async {
            // Trigger StartupValidator refresh before dismissing
            // This ensures main screen status updates after wizard changes
            NotificationCenter.default.post(name: .kp_startupRevalidate, object: nil)
            AppLogger.shared.log("🔄 [Wizard] Triggered StartupValidator refresh before dismiss")

            dismiss()
        }
    }

    /// Performs cancellation and cleanup in the background after UI dismissal
    func performBackgroundCleanup() {
        // Use structured concurrency; hop to MainActor for UI-safe cleanup without blocking
        Task { @MainActor [weak asyncOperationManager] in
            asyncOperationManager?.cancelAllOperationsAsync()
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else {
            let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
            NSWorkspace.shared.openApplication(
                at: fallbackURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil
            )
        }
    }

    /// Start polling for Login Items approval status change
    func startLoginItemsApprovalPolling() {
        stopLoginItemsApprovalPolling() // Cancel any existing polling

        AppLogger.shared.log("🔍 [LoginItems] Starting approval polling (3 min timeout)...")

        loginItemsPollingTask = Task { @MainActor in
            // Poll every 2 seconds for up to 3 minutes (90 attempts)
            let maxAttempts = 90
            for attempt in 1 ... maxAttempts {
                guard !Task.isCancelled else {
                    AppLogger.shared.log("🔍 [LoginItems] Polling cancelled")
                    return
                }

                // Check SMAppService status
                let state = await KanataDaemonManager.shared.refreshManagementState()
                // Only log every 10th attempt to reduce noise
                if attempt % 10 == 1 {
                    AppLogger.shared.log("🔍 [LoginItems] Poll #\(attempt)/\(maxAttempts): state=\(state)")
                }

                if state == .smappserviceActive {
                    // User approved! Dismiss dialog, refresh and show success
                    AppLogger.shared.log("✅ [LoginItems] Approval detected at poll #\(attempt)! Refreshing wizard state...")

                    await MainActor.run {
                        // Dismiss the dialog if it's still showing
                        showingBackgroundApprovalPrompt = false
                        toastManager.showSuccess("KeyPath approved in Login Items")
                    }

                    // Refresh the wizard state
                    refreshSystemState()

                    return
                }

                // Wait before next poll
                _ = await WizardSleep.seconds(2) // 2 seconds
            }

            AppLogger.shared.log("⏰ [LoginItems] Polling timed out after 3 minutes")
            toastManager.showInfo("Login Items check timed out. Click refresh to check again.")
        }
    }

    /// Stop polling for Login Items approval
    func stopLoginItemsApprovalPolling() {
        loginItemsPollingTask?.cancel()
        loginItemsPollingTask = nil
    }

    /// Nuclear option: Force wizard closed immediately, bypass all operations and confirmations
    func forciblyCloseWizard() {
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Starting nuclear shutdown at \(Date())")

        // Set force closing flag to prevent any new operations
        isForceClosing = true
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Force closing flag set - no new operations allowed")

        // Immediately clear operation state to stop UI spinners
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Clearing operation state...")
        Task { @MainActor in
            AppLogger.shared.log("🔴 [FORCE-CLOSE] MainActor task - clearing operations")
            asyncOperationManager.runningOperations.removeAll()
            asyncOperationManager.operationProgress.removeAll()
            isValidating = false // Stop validation state
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Operation state cleared")
            AppLogger.shared.flushBuffer()
        }

        // Cancel monitoring tasks
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Cancelling refresh task...")
        refreshTask?.cancel()
        stopLoginItemsApprovalPolling()
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Refresh and polling tasks cancelled")

        // Force immediate dismissal - no confirmation, no state checks, no waiting
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Calling dismiss()...")
        AppLogger.shared.flushBuffer() // Ensure logs are written before dismissal
        dismiss()
        AppLogger.shared.log("🔴 [FORCE-CLOSE] dismiss() called")

        // Clean up in background after UI is gone
        AppLogger.shared.log("🔴 [FORCE-CLOSE] Starting background cleanup...")
        Task { @MainActor [weak asyncOperationManager] in
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Background cleanup task started")
            asyncOperationManager?.cancelAllOperationsAsync()
            AppLogger.shared.log("🔴 [FORCE-CLOSE] Background cleanup completed")
            AppLogger.shared.flushBuffer()
        }

        AppLogger.shared.log("🔴 [FORCE-CLOSE] Nuclear shutdown completed")
        AppLogger.shared.flushBuffer()
    }

    func showStartConfirmation() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                startConfirmationResult = continuation
                showingStartConfirmation = true
            }
        }
    }
}

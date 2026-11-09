import AppKit
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    // MARK: - Unified State Refresh

    /// Consolidated refresh method that handles all refresh scenarios
    /// - Parameters:
    ///   - showSpinner: Whether to show summary validating activity state
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
        let requestID = UUID()
        stateMachine.inspectionRequestID = requestID

        AppLogger.shared.log("🔍 [Wizard] Refreshing system state (showSpinner=\(showSpinner), from=\(previousPage?.rawValue ?? "nil"))")

        // Cancel any previous refresh task
        refreshTask?.cancel()

        // Show validating state if requested (used when returning to summary page)
        if showSpinner {
            withAnimation(.easeInOut(duration: 0.2)) {
                isValidating = true
            }
        }

        refreshTask = Task { [showSpinner] in
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

            // Run state detection
            await MainActor.run {
                performStateDetection(requestID: requestID)
            }
        }
    }

    /// Internal: Performs state detection
    @MainActor
    func performStateDetection(requestID: UUID) {
        guard !isForceClosing, !Task.isCancelled,
              stateMachine.inspectionRequestID == requestID else { return }

        let operation = WizardOperations.stateDetection(
            stateMachine: stateMachine,
            progressCallback: { _ in }
        )

        asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            guard stateMachine.inspectionRequestID == requestID else { return }
            _ = applySystemStateResult(result)

            // A quiet refresh may have replaced one that showed the spinner.
            withAnimation(.easeInOut(duration: 0.2)) {
                isValidating = false
            }
        } onFailure: { error in
            handleStateCheckFailure(error)
        }
    }

    /// Every failed check exits validation and keeps the last useful snapshot.
    @MainActor
    func handleStateCheckFailure(_ error: WizardError) {
        isValidating = false
        asyncOperationManager.lastError = error
    }

    func cachedPreferredPage() async -> WizardPage? {
        guard let cachedState = stateMachine.lastWizardSnapshot else { return nil }
        let page = WizardRouter.route(
            state: cachedState.state,
            issues: cachedState.issues
        )
        return page != .summary ? page : nil
    }

    @MainActor
    func applySystemStateResult(_ result: SystemStateResult) -> [WizardIssue] {
        let issues = result.issues
        stateMachine.updateWizardState(from: result)

        // Only auto-navigate if user hasn't been interacting with the wizard
        // This prevents jarring navigation away from a page after a fix completes
        let shouldAutoNavigate = !stateMachine.userInteractionMode

        if WizardRouter.shouldNavigateToSummary(
            currentPage: stateMachine.currentPage,
            state: result.state,
            issues: issues
        ) {
            AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
            stateMachine.navigateToPage(.summary, userInitiated: false)
        } else if shouldAutoNavigate {
            let currentPageHasIssues = WizardRouter.pageHasRelevantIssues(
                stateMachine.currentPage,
                issues: issues,
                state: result.state
            )
            if !currentPageHasIssues {
                Task {
                    let recommended = WizardRouter.route(
                        state: result.state,
                        issues: issues
                    )
                    if recommended != stateMachine.currentPage {
                        AppLogger.shared.log("🔄 [Wizard] Skipping green page \(stateMachine.currentPage) → \(recommended)")
                        stateMachine.navigateToPage(recommended, userInitiated: false)
                    }
                }
            }
        }

        AppLogger.shared.log(
            "🔍 [Wizard] State applied - Issues: \(issues.map { "\($0.category)-\($0.title)" })"
        )

        return issues
    }

    func startKeyPathRuntime() {
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
                        verifyPostStartStateAndDismiss()
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

    /// Refresh the wizard's authoritative system state after a successful
    /// runtime start before deciding whether first-success education is safe.
    /// `startKanata` verifies the runtime itself, but it does not update the
    /// wizard state machine that owns onboarding eligibility.
    func verifyPostStartStateAndDismiss() {
        Task { @MainActor in
            await refreshPostStartStateAndDismiss()
        }
    }

    @MainActor
    func refreshPostStartStateAndDismiss() async {
        let result = if let postStartStateDetector {
            await postStartStateDetector()
        } else {
            await stateMachine.detectCurrentState()
        }
        stateMachine.updateWizardState(from: result)
        guard result.state == .active, result.issues.isEmpty else {
            stateMachine.navigateToPage(WizardRouter.route(
                state: result.state, issues: result.issues
            ), userInitiated: false)
            return
        }
        dismissAndRefreshMainScreen()
    }
}

import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

extension InstallationWizardView {
    // MARK: - State Management

    public func setupWizard() async {
        AppLogger.shared.log("🔍 [Wizard] Setting up wizard with new architecture")

        // Always reset navigation state for fresh run
        stateMachine.navigationEngine.resetNavigationState()

        // Configure state providers
        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [Wizard] kanataManager not configured — skipping wizard setup")
            return
        }
        stateMachine.configure(kanataManager: kanataManager)
        autoFixer.configure(
            kanataManager: kanataManager,
            toastManager: toastManager,
            statusReporter: { message in
                showStatusBanner(message)
                Task { await WizardTelemetry.shared.record(
                    WizardEvent(
                        timestamp: Date(),
                        category: .statusBanner,
                        name: "banner",
                        result: nil,
                        details: ["message": message]
                    )
                ) }
            }
        )

        // Determine initial page based on cached system snapshot (if available)
        // Skip summary on initial run - go directly to helper page to start the wizard flow
        let preferredPage = await cachedPreferredPage()
        if let preferredPage, initialPage == nil {
            AppLogger.shared.log("🔍 [Wizard] Preferring cached page: \(preferredPage)")
            stateMachine.navigateToPage(preferredPage)
        } else if let initialPage {
            AppLogger.shared.log("🔍 [Wizard] Navigating to initial page override: \(initialPage)")
            stateMachine.navigateToPage(initialPage)
        } else {
            // Start at helper page, not summary - avoids showing unverified permission status
            // before user has had a chance to decide on enhanced diagnostics (FDA)
            AppLogger.shared.log("🔍 [Wizard] Starting at helper page (skipping initial summary)")
            stateMachine.navigateToPage(.helper)
        }

        Task {
            await MainActor.run {
                // Start validation state
                preflightStart = Date()
                evaluationProgress = 0.0
                isValidating = true
                stateMachine.wizardState = .initializing
                stateMachine.wizardIssues = []
                AppLogger.shared.log("🚀 [Wizard] Summary page shown immediately, starting validation")
                AppLogger.shared.log("⏱️ [TIMING] Wizard validation START")
            }

            // Small delay to ensure UI is ready before starting heavy checks
            _ = await WizardSleep.ms(100) // 100ms delay

            guard !Task.isCancelled else { return }
            await performInitialStateCheck()
        }
    }

    public func performInitialStateCheck(retryAllowed: Bool = true) async {
        // Check if user has already closed wizard
        guard !Task.isCancelled else {
            AppLogger.shared.log("🔍 [Wizard] Initial state check cancelled - wizard closing")
            return
        }

        // Check if force closing flag is set
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Initial state check blocked - force closing in progress")
            return
        }

        AppLogger.shared.log("🔍 [Wizard] Performing initial state check")
        AppLogger.shared.log("⏱️ [TIMING] Wizard validation START")

        let operation = WizardOperations.stateDetection(
            stateMachine: stateMachine,
            progressCallback: { progress in
                // Update progress on MainActor (callback may be called from background)
                Task { @MainActor in
                    evaluationProgress = progress
                }
            }
        )

        asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
            let wizardDuration = Date().timeIntervalSince(preflightStart)
            AppLogger.shared.log(
                "⏱️ [TIMING] Wizard validation COMPLETE: \(String(format: "%.3f", wizardDuration))s"
            )

            // Freshness guard: drop stale results and retry once
            if !isFresh(result) {
                AppLogger.shared.log(
                    "⚠️ [Wizard] Discarding stale initial state result (age: \(snapshotAge(result))s)."
                )
                if retryAllowed {
                    Task { await performInitialStateCheck(retryAllowed: false) }
                } else {
                    AppLogger.shared.log(
                        "⚠️ [Wizard] Stale result retry already attempted; keeping existing state."
                    )
                }
                return
            }

            let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
            stateMachine.wizardState = result.state
            stateMachine.wizardIssues = filteredIssues
            stateMachine.lastWizardSnapshot = WizardSnapshotRecord(
                state: result.state, issues: filteredIssues
            )
            // Start at summary page - no auto navigation
            // stateMachine.autoNavigateIfNeeded(for: result.state, issues: result.issues)

            // Transition to results immediately when validation completes
            Task { @MainActor in
                // Mark validation as complete - this transitions validating state to final icon
                withAnimation(.easeInOut(duration: 0.25)) {
                    isValidating = false
                }
            }

            AppLogger.shared.log(
                "🔍 [Wizard] Initial setup - State: \(result.state), Issues: \(filteredIssues.count), Target Page: \(stateMachine.currentPage)"
            )
            AppLogger.shared.log(
                "🔍 [Wizard] Issue details: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
            )

            // Ensure permissions are verified before auto-advancing.
            // Without this, .unknown permission states (Oracle hasn't finished TCC check)
            // are treated as non-blocking, causing the wizard to skip permission pages.
            let permSnapshot = await PermissionOracle.shared.forceRefresh()
            let permissionsStillUnknown =
                permSnapshot.kanata.accessibility == .unknown
                || permSnapshot.kanata.inputMonitoring == .unknown
            if permissionsStillUnknown {
                AppLogger.shared.log("🔍 [Wizard] Permissions still unverified — staying on summary to avoid skipping permission pages")
                Task { @MainActor in
                    stateMachine.navigateToPage(.summary)
                }
                return
            }

            // Auto-navigate to the first page that needs attention, skipping all green pages
            let recommended = await stateMachine.navigationEngine
                .firstPageNeedingAttention(for: result.state, issues: filteredIssues)
            Task { @MainActor in
                if shouldNavigateToSummary(
                    currentPage: stateMachine.currentPage,
                    state: result.state,
                    issues: filteredIssues
                ) {
                    AppLogger.shared.log("🟢 [Wizard] Healthy system detected; routing to summary")
                    stateMachine.navigateToPage(.summary)
                } else if recommended != stateMachine.currentPage {
                    AppLogger.shared.log("🔍 [Wizard] Auto-navigating to \(recommended) (skipping green pages)")
                    stateMachine.navigateToPage(recommended)
                }
            }
        }
    }

    public func monitorSystemState() async {
        AppLogger.shared.log("🟡 [MONITOR] System state monitoring started with 60s interval")

        // Smart monitoring: Only poll when needed, much less frequently
        while !Task.isCancelled {
            _ = await WizardSleep.seconds(60) // 60 seconds instead of 10

            // Skip state detection if async operations are running to avoid conflicts
            guard !asyncOperationManager.hasRunningOperations else {
                continue
            }

            // Only poll if we're on summary page or user recently interacted
            let shouldPoll = shouldPerformBackgroundPolling()
            guard shouldPoll else {
                continue
            }

            // Use page-specific detection instead of full system scan
            await performSmartStateCheck()
        }

        AppLogger.shared.log("🟡 [MONITOR] System state monitoring stopped")
    }

    /// Determine if background polling is needed
    public func shouldPerformBackgroundPolling() -> Bool {
        // Only poll on summary page where overview is shown
        stateMachine.currentPage == .summary
    }

    /// Perform targeted state check based on current page
    public func performSmartStateCheck(retryAllowed: Bool = true) async {
        // Check if force closing is in progress
        guard !isForceClosing else {
            AppLogger.shared.log("🔍 [Wizard] Smart state check blocked - force closing in progress")
            return
        }

        switch stateMachine.currentPage {
        case .summary:
            // Full check only for summary page
            let operation = WizardOperations.stateDetection(
                stateMachine: stateMachine,
                progressCallback: { _ in }
            )
            asyncOperationManager.execute(operation: operation) { (result: SystemStateResult) in
                let oldState = stateMachine.wizardState
                let oldPage = stateMachine.currentPage

                // Freshness guard: drop stale results and retry once
                if !isFresh(result) {
                    AppLogger.shared.log(
                        "⚠️ [Wizard] Ignoring stale smart state result (age: \(snapshotAge(result))s)."
                    )
                    if retryAllowed {
                        Task { await performSmartStateCheck(retryAllowed: false) }
                    } else {
                        AppLogger.shared.log(
                            "⚠️ [Wizard] Stale smart-state retry already attempted; leaving state unchanged."
                        )
                    }
                    return
                }

                let filteredIssues = sanitizedIssues(from: result.issues, for: result.state)
                stateMachine.wizardState = result.state
                stateMachine.wizardIssues = filteredIssues

                AppLogger.shared.log(
                    "🔍 [Navigation] Current: \(stateMachine.currentPage), Issues: \(filteredIssues.map { "\($0.category)-\($0.title)" })"
                )

                // No auto-navigation - stay on current page
                // stateMachine.autoNavigateIfNeeded(for: result.state, issues: result.issues)

                Task { @MainActor in
                    if shouldNavigateToSummary(
                        currentPage: stateMachine.currentPage,
                        state: result.state,
                        issues: filteredIssues
                    ) {
                        AppLogger.shared.log(
                            "🟢 [Wizard] Healthy system detected during monitor; routing to summary"
                        )
                        stateMachine.navigateToPage(.summary)
                    }
                }

                if oldState != stateMachine.wizardState || oldPage != stateMachine.currentPage {
                    AppLogger.shared.log(
                        "🔍 [Wizard] State changed: \(oldState) -> \(stateMachine.wizardState), page: \(oldPage) -> \(stateMachine.currentPage)"
                    )
                }
            }
        case .inputMonitoring, .accessibility, .conflicts:
            // 🎯 Phase 2: Quick checks removed - SystemValidator does full check
            // The full check is fast enough (<1s) and prevents partial state issues
            // If needed later, can add specific quick methods to SystemValidator
            break
        default:
            // No background polling for other pages
            break
        }
    }
}

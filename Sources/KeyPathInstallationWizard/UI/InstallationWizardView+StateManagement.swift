import AppKit
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore
import SwiftUI

public extension InstallationWizardView {
    // MARK: - State Management

    func setupWizard() async {
        AppLogger.shared.log("🔍 [Wizard] Setting up wizard with new architecture")

        // Always reset navigation state for fresh run
        stateMachine.resetNavigation()

        guard kanataManager != nil else {
            AppLogger.shared.log("⚠️ [Wizard] kanataManager not configured — skipping wizard setup")
            return
        }

        // Determine initial page based on cached system snapshot (if available)
        // Skip summary on initial run - go directly to helper page to start the wizard flow
        let cachedSnapshot = stateMachine.lastWizardSnapshot
        let preferredPage = await cachedPreferredPage()
        if initialPage == nil,
           let cachedSnapshot,
           shouldShowWelcomePage(helperInstalled: cachedSnapshot.helperInstalled)
        {
            // Fresh install, Get Started never clicked: open on the one-time
            // welcome page (issue #932) using the already captured helper fact.
            // Validation still runs underneath; performInitialStateCheck()
            // leaves the welcome page alone.
            AppLogger.shared.log("👋 [Wizard] Fresh install — starting at welcome page")
            stateMachine.navigateToPage(.welcome)
        } else if let preferredPage, initialPage == nil {
            AppLogger.shared.log("🔍 [Wizard] Preferring cached page: \(preferredPage)")
            stateMachine.navigateToPage(preferredPage)
        } else if let initialPage {
            AppLogger.shared.log("🔍 [Wizard] Navigating to initial page override: \(initialPage)")
            stateMachine.navigateToPage(initialPage)
        } else {
            // No cached snapshot and no explicit override: stay on summary until
            // performInitialStateCheck() captures the canonical result. That one
            // result decides both the one-time welcome gate and the first setup
            // page, avoiding a separate helper/SMAppService probe.
            AppLogger.shared.log("🔍 [Wizard] No cached page — staying on summary until initial state check completes")
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

    /// Whether the wizard should open on the one-time Welcome page (issue #932):
    /// fresh install (helper not installed) and Get Started never clicked.
    internal func shouldShowWelcomePage(helperInstalled: Bool) -> Bool {
        WizardWelcomeGate.shouldShowWelcome(helperInstalled: helperInstalled)
    }

    func performInitialStateCheck(
        retryAllowed: Bool = true,
        permissionRetriesRemaining: Int = 2,
        permissionRetryDelay: Double = 2.0
    ) async {
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
            freshness: .cached,
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
            stateMachine.updateWizardState(from: result, issues: filteredIssues)
            if initialPage == nil,
               stateMachine.currentPage != .welcome,
               shouldShowWelcomePage(helperInstalled: result.helperInstalled)
            {
                AppLogger.shared.log("👋 [Wizard] Fresh install snapshot — presenting welcome page")
                stateMachine.navigateToPage(.welcome)
            }
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
            let permSnapshot = await SystemStateProvider.shared.refreshPermissionSnapshot()
            let kanataAccessibilityUnknown = permSnapshot.kanata.accessibility == .unknown
            let kanataInputMonitoringUnknown = permSnapshot.kanata.inputMonitoring == .unknown
            if kanataAccessibilityUnknown || kanataInputMonitoringUnknown {
                if permissionRetriesRemaining > 0 {
                    // Possibly transient (Oracle racing app startup / slow TCC read):
                    // park on summary and retry with backoff.
                    AppLogger.shared.log(
                        "🔍 [Wizard] Permissions still unverified — retrying in \(permissionRetryDelay)s (\(permissionRetriesRemaining) left)"
                    )
                    Task { @MainActor in
                        // Never yank the user off the welcome page; Get Started routes onward.
                        if stateMachine.currentPage != .welcome {
                            stateMachine.navigateToPage(.summary)
                        }
                    }
                    Task {
                        _ = await WizardSleep.seconds(permissionRetryDelay)
                        guard !Task.isCancelled, !isForceClosing else { return }
                        await performInitialStateCheck(
                            retryAllowed: retryAllowed,
                            permissionRetriesRemaining: permissionRetriesRemaining - 1,
                            permissionRetryDelay: permissionRetryDelay * 2
                        )
                    }
                    return
                }
                // Steady-state .unknown (no Full Disk Access to read TCC.db, or a
                // fresh install with no TCC row) — retrying won't resolve it. Fall
                // through and let routing land on the first unverified permission
                // page instead of dead-ending on summary (the pre-#934 gap).
                AppLogger.shared.log(
                    "🔍 [Wizard] Permissions unverifiable after retries — routing to first unverified permission page"
                )
            }

            // Auto-navigate to the first page that needs attention
            let recommended = WizardRouter.routeForUnverifiedKanataPermissions(
                base: WizardRouter.route(
                    state: result.state,
                    issues: filteredIssues,
                    helperInstalled: result.helperInstalled,
                    helperNeedsApproval: result.helperNeedsApproval
                ),
                inputMonitoringUnknown: kanataInputMonitoringUnknown,
                accessibilityUnknown: kanataAccessibilityUnknown
            )
            Task { @MainActor in
                // Never yank the user off the welcome page mid-read; validation has
                // already resolved by the time they click Get Started, which routes onward.
                guard stateMachine.currentPage != .welcome else { return }
                if WizardRouter.shouldNavigateToSummary(
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

    func monitorSystemState() async {
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
    func shouldPerformBackgroundPolling() -> Bool {
        // Only poll on summary page where overview is shown
        stateMachine.currentPage == .summary
    }

    /// Perform targeted state check based on current page
    func performSmartStateCheck(retryAllowed: Bool = true) async {
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
                    if WizardRouter.shouldNavigateToSummary(
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

import Foundation
import KeyPathCore
import KeyPathWizardCore
import OSLog

/// Handles wizard navigation logic based on system state
@MainActor
final class WizardNavigationEngine: WizardNavigating {
    // Track single-show pages
    private var hasShownFullDiskAccessPage = false
    private var hasShownKanataMigrationPage = false
    private var hasShownKarabinerImportPage = false

    /// Reset navigation state for a fresh wizard run
    func resetNavigationState() {
        hasShownFullDiskAccessPage = false
        hasShownKanataMigrationPage = false
        hasShownKarabinerImportPage = false
    }

    /// Mark FDA page as shown (called when user completes or skips FDA)
    func markFDAPageShown() {
        hasShownFullDiskAccessPage = true
    }

    /// Mark migration page as shown
    func markMigrationPageShown() {
        hasShownKanataMigrationPage = true
    }

    /// Mark Karabiner import page as shown
    func markKarabinerImportPageShown() {
        hasShownKarabinerImportPage = true
    }

    /// Check if FDA page has been shown
    var hasFDABeenShown: Bool {
        hasShownFullDiskAccessPage
    }

    /// Check if Karabiner import page has been shown
    var hasKarabinerImportBeenShown: Bool {
        hasShownKarabinerImportPage
    }

    /// Skip all green pages (including one-time offerings) to find the first page
    /// that actually needs user attention. Used for auto-navigation after validation.
    ///
    /// NOTE: FDA (.fullDiskAccess) is never auto-skipped here. It's a one-time offering
    /// that the user must see and explicitly dismiss. Only the FDA page itself marks it
    /// as shown when the user makes a choice.
    func firstPageNeedingAttention(for state: WizardSystemState, issues: [WizardIssue]) async -> WizardPage {
        var page = await determineCurrentPage(for: state, issues: issues)
        // Loop past one-time offering pages that have no issues — but NOT FDA
        var iterations = 0
        while !pageHasRelevantIssues(page, issues: issues, state: state), page != .summary, iterations < 5 {
            // FDA is an offering page that the user must explicitly dismiss
            if page == .fullDiskAccess {
                return page
            }
            // Mark other one-time pages as "shown" so determineCurrentPage advances past them
            switch page {
            case .kanataMigration:
                hasShownKanataMigrationPage = true
            case .karabinerImport:
                hasShownKarabinerImportPage = true
            default:
                break
            }
            page = await determineCurrentPage(for: state, issues: issues)
            iterations += 1
        }
        return page
    }

    // MARK: - Main Navigation Logic

    // Primary navigation method - determines the current page based on system state and issues
    // This is the preferred method as it uses structured issue identifiers for type-safe navigation

    func determineCurrentPage(for state: WizardSystemState, issues: [WizardIssue]) async -> WizardPage {
        AppLogger.shared.log("🔍 [NavigationEngine] Determining page for \(issues.count) issues, state: \(state)")

        // Helper status (async) gathered once, then passed into pure router.
        let helperNeedsApproval = HelperManager.shared.helperNeedsLoginItemsApproval()
        let helperInstalled = await HelperManager.shared.isHelperInstalled()

        AppLogger.shared.log("🔍 [NavigationEngine] helperInstalled: \(helperInstalled), needsApproval: \(helperNeedsApproval)")

        // Check for helper issues first - helper is always the first priority
        let hasHelperIssues = issues.contains { issue in
            if case let .component(req) = issue.identifier {
                return req == .privilegedHelper || req == .privilegedHelperUnhealthy
            }
            return false
        }

        // 1. HELPER: If helper not installed or has issues, go to helper page
        if !helperInstalled || hasHelperIssues || helperNeedsApproval {
            AppLogger.shared.log("🔍 [NavigationEngine] → .helper (helper needs attention)")
            return .helper
        }

        // 2. MIGRATION: Check for Kanata migration opportunity (one-time)
        if !hasShownKanataMigrationPage,
           !WizardSystemPaths.userConfigExists,
           !WizardSystemPaths.detectExistingKanataConfigs().isEmpty
        {
            AppLogger.shared.log("🔍 [NavigationEngine] → .kanataMigration (existing configs detected)")
            hasShownKanataMigrationPage = true
            return .kanataMigration
        }

        // 2b. KARABINER IMPORT: Offer import when Karabiner config exists (one-time)
        if !hasShownKarabinerImportPage, WizardSystemPaths.karabinerConfigExists {
            AppLogger.shared.log("🔍 [NavigationEngine] → .karabinerImport (Karabiner config detected)")
            hasShownKarabinerImportPage = true
            return .karabinerImport
        }

        // 3. FDA: Show Enhanced Diagnostics decision (one-time, after helper is ready)
        // This MUST come before permissions so user can decide on FDA first
        // Skip automatically if user already has Full Disk Access
        if !hasShownFullDiskAccessPage {
            if FullDiskAccessChecker.shared.hasFullDiskAccess() {
                AppLogger.shared.log("🔍 [NavigationEngine] Skipping FDA page - already granted")
                hasShownFullDiskAccessPage = true
            } else {
                AppLogger.shared.log("🔍 [NavigationEngine] → .fullDiskAccess (offering enhanced diagnostics)")
                // Don't mark as shown here - let the FDA page mark it when user makes a choice
                return .fullDiskAccess
            }
        }

        // 4. Use the router for remaining navigation (permissions, components, service)
        let corePage = WizardRouter.route(
            state: state,
            issues: issues,
            helperInstalled: helperInstalled,
            helperNeedsApproval: helperNeedsApproval
        )

        AppLogger.shared.log("🔍 [NavigationEngine] → \(corePage) (from router)")
        return corePage
    }

    func canNavigate(from _: WizardPage, to _: WizardPage, given _: WizardSystemState) -> Bool {
        // Users can always navigate manually via page dots
        // This method is mainly for programmatic navigation validation
        true
    }

    func nextPage(
        from current: WizardPage, given state: WizardSystemState, issues: [WizardIssue] = []
    ) async -> WizardPage? {
        // Get the logical page order
        let pageOrder = getPageOrder()
        guard let currentIndex = pageOrder.firstIndex(of: current) else {
            return nil
        }

        // Check if there are blocking issues that require going to a specific page
        let targetPage = await determineCurrentPage(for: state, issues: issues)

        // If the target is a blocking page and we're not on it, jump there immediately
        if await isBlockingPage(targetPage), targetPage != current {
            return targetPage
        }

        // If the target page is ahead of us in the flow and different from current, jump to it
        if let targetIndex = pageOrder.firstIndex(of: targetPage),
           targetIndex > currentIndex,
           targetPage != current
        {
            return targetPage
        }

        // Otherwise, continue forward in the sequential flow, skipping green pages
        var candidateIndex = currentIndex + 1
        while candidateIndex < pageOrder.count {
            let candidate = pageOrder[candidateIndex]
            if candidate == .summary || pageHasRelevantIssues(candidate, issues: issues, state: state) {
                return candidate
            }
            candidateIndex += 1
        }

        // All remaining pages are green — go to summary
        return .summary
    }

    // MARK: - Navigation State Creation

    func createNavigationState(
        currentPage: WizardPage, systemState: WizardSystemState, issues: [WizardIssue] = []
    ) async -> WizardNavigationState {
        let targetPage = await determineCurrentPage(for: systemState, issues: issues)
        let shouldAutoNavigate = currentPage != targetPage

        return WizardNavigationState(
            currentPage: currentPage,
            availablePages: WizardPage.allCases,
            canNavigateNext: shouldAutoNavigate,
            canNavigatePrevious: true, // Users can always go back manually
            shouldAutoNavigate: shouldAutoNavigate
        )
    }

    // MARK: - Page Ordering Logic

    /// Returns the typical ordering of pages for a complete setup flow.
    /// Uses the static orderedPages array to ensure consistent navigation.
    func getPageOrder() -> [WizardPage] {
        // Use the static orderedPages array for consistent navigation
        // This ensures "Continue" buttons move through pages in a predictable order
        WizardPage.orderedPages
    }

    /// Returns the index of a page in the typical flow
    func pageIndex(_ page: WizardPage) -> Int {
        let order = getPageOrder()
        return order.firstIndex(of: page) ?? 0
    }

    /// Determines if a page has relevant issues that need user attention.
    /// Pages with no relevant issues are considered "green" and can be skipped during navigation.
    func pageHasRelevantIssues(_ page: WizardPage, issues: [WizardIssue], state: WizardSystemState) -> Bool {
        switch page {
        case .summary:
            true // Summary is always a valid destination
        case .conflicts:
            issues.contains { $0.category == .conflicts }
        case .helper:
            issues.contains { issue in
                if case let .component(req) = issue.identifier {
                    return req == .privilegedHelper || req == .privilegedHelperUnhealthy
                }
                return false
            }
        case .inputMonitoring:
            issues.contains { issue in
                if case let .permission(perm) = issue.identifier {
                    return perm == .keyPathInputMonitoring || perm == .kanataInputMonitoring
                }
                return false
            }
        case .accessibility:
            issues.contains { issue in
                if case let .permission(perm) = issue.identifier {
                    return perm == .keyPathAccessibility || perm == .kanataAccessibility
                }
                return false
            }
        case .communication:
            issues.contains { issue in
                if case let .component(comp) = issue.identifier {
                    switch comp {
                    case .communicationServerConfiguration,
                         .communicationServerNotResponding,
                         .tcpServerConfiguration,
                         .tcpServerNotResponding:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
        case .karabinerComponents:
            issues.contains { issue in
                if case let .component(comp) = issue.identifier {
                    switch comp {
                    case .karabinerDriver, .karabinerDaemon,
                         .vhidDeviceManager, .vhidDeviceActivation,
                         .vhidDeviceRunning,
                         .vhidDaemonMisconfigured, .vhidDriverVersionMismatch:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
        case .service:
            switch state {
            case .serviceNotRunning, .ready, .daemonNotRunning:
                true
            default:
                false
            }
        case .fullDiskAccess, .kanataMigration, .stopExternalKanata, .karabinerImport:
            false // Optional/offering pages — not issue-based
        }
    }

    /// Determines if a page represents a "blocking" issue that must be resolved
    func isBlockingPage(_ page: WizardPage) async -> Bool {
        switch page {
        case .conflicts:
            return true // Cannot proceed with conflicts
        case .karabinerComponents:
            return true // Cannot use without components
        case .helper:
            // Helper is blocking if Login Items approval is required OR helper is not installed
            // Without the helper, privileged operations require repeated password prompts
            let needsApproval = HelperManager.shared.helperNeedsLoginItemsApproval()
            let notInstalled = await !(HelperManager.shared.isHelperInstalled())
            return needsApproval || notInstalled
        case .inputMonitoring, .accessibility:
            return false // Can proceed but functionality limited
        case .service:
            return false // Can manage service state
        case .fullDiskAccess:
            return false // Optional, not blocking
        case .kanataMigration:
            return false // Optional, not blocking
        case .karabinerImport:
            return false // Optional, not blocking
        case .stopExternalKanata:
            return false // Optional, only shown when migrating with running process
        case .communication:
            return false // Optional, not blocking
        case .summary:
            return false // Final state
        }
    }

    // MARK: - Navigation Helpers

    /// Determines if the wizard should show a "Next" button on the given page
    func shouldShowNextButton(
        for page: WizardPage, state: WizardSystemState, issues: [WizardIssue] = []
    ) async -> Bool {
        let targetPage = await determineCurrentPage(for: state, issues: issues)
        let currentIndex = pageIndex(page)
        let targetIndex = pageIndex(targetPage)

        // Show next button if we're not on the final target page
        return currentIndex < targetIndex || targetPage != WizardPage.summary
    }

    /// Determines if the wizard should show a "Previous" button on the given page
    func shouldShowPreviousButton(for page: WizardPage, state: WizardSystemState) -> Bool {
        // Always allow going back, except on summary when everything is complete
        !(page == .summary && state == .active)
    }

    /// Determines the appropriate button text for the current page and state
    func primaryButtonText(for page: WizardPage, state: WizardSystemState) async -> String {
        switch page {
        case .conflicts:
            "Resolve Conflicts"
        case .inputMonitoring:
            "Open System Settings"
        case .accessibility:
            "Open System Settings"
        case .karabinerComponents:
            "Install Karabiner Components"
        case .helper:
            await HelperManager.shared.isHelperInstalled() ? "Manage Helper" : "Install Helper"
        case .communication:
            "Check TCP Server"
        case .service:
            "Start Keyboard Service"
        case .fullDiskAccess:
            "Grant Full Disk Access"
        case .kanataMigration:
            "Use This Config"
        case .karabinerImport:
            "Import Rules"
        case .stopExternalKanata:
            "Stop Kanata"
        case .summary:
            switch state {
            case .active:
                "Close Setup"
            case .serviceNotRunning, .ready:
                "Start KeyPath Runtime"
            default:
                "Continue Setup"
            }
        }
    }

    /// Determines if the primary button should be enabled
    func isPrimaryButtonEnabled(
        for page: WizardPage, state: WizardSystemState, isProcessing: Bool = false
    ) -> Bool {
        if isProcessing {
            return false
        }

        switch page {
        case .conflicts:
            if case let .conflictsDetected(conflicts) = state {
                return !conflicts.isEmpty
            }
            return false
        case .inputMonitoring, .accessibility:
            return true // Can always open settings
        case .karabinerComponents:
            if case let .missingComponents(missing) = state {
                return !missing.isEmpty
            }
            return true // Can always try to install components
        case .helper:
            return true
        case .communication:
            return true // Can always check TCP server
        case .service:
            return true // Can always manage service
        case .fullDiskAccess:
            return true // Can always try to grant FDA
        case .kanataMigration:
            return true // Can always skip or migrate
        case .karabinerImport:
            return true // Can always skip or import
        case .stopExternalKanata:
            return true // Can always stop external kanata
        case .summary:
            return true
        }
    }

    // MARK: - Progress Calculation

    /// Calculates completion progress as a percentage (0.0 to 1.0)
    func calculateProgress(for state: WizardSystemState) -> Double {
        switch state {
        case .initializing:
            0.0
        case .conflictsDetected:
            0.1 // Just started
        case .missingComponents:
            0.2 // Conflicts resolved
        case .missingPermissions:
            0.5 // Components installed
        case .daemonNotRunning:
            0.8 // Permissions granted
        case .serviceNotRunning, .ready:
            0.9 // Daemon running
        case .active:
            1.0 // Complete
        }
    }

    /// Returns a user-friendly progress description
    func progressDescription(for state: WizardSystemState) -> String {
        switch state {
        case .initializing:
            "Checking system..."
        case .conflictsDetected:
            "Resolving conflicts..."
        case .missingComponents:
            "Installing components..."
        case .missingPermissions:
            "Configuring permissions..."
        case .daemonNotRunning:
            "Starting services..."
        case .serviceNotRunning, .ready:
            "Ready to start..."
        case .active:
            "Setup complete!"
        }
    }
}

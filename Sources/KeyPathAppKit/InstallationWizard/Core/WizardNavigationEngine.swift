import Foundation
import KeyPathCore
import KeyPathWizardCore
import OSLog

/// Handles wizard navigation logic based on system state
@MainActor
final class WizardNavigationEngine: WizardNavigating, @unchecked Sendable {
    // Track if we've shown the FDA page
    private var hasShownFullDiskAccessPage = false

    /// Reset navigation state for a fresh wizard run
    func resetNavigationState() {
        hasShownFullDiskAccessPage = false
    }

    // MARK: - Main Navigation Logic

    /// Primary navigation method - determines the current page based on system state and issues
    /// This is the preferred method as it uses structured issue identifiers for type-safe navigation

    func determineCurrentPage(for state: WizardSystemState, issues: [WizardIssue]) async -> WizardPage {
        AppLogger.shared.log("🔍 [NavigationEngine] Determining page for \(issues.count) issues:")
        for issue in issues {
            AppLogger.shared.log("🔍 [NavigationEngine]   - \(issue.category): \(issue.title)")
        }

        // Helper status (async) gathered once, then passed into pure router.
        let helperNeedsApproval = HelperManager.shared.helperNeedsLoginItemsApproval()
        let helperInstalled = await HelperManager.shared.isHelperInstalled()

        let corePage: WizardPage = if FeatureFlags.useUnifiedWizardRouter {
            WizardRouter.route(
                state: state,
                issues: issues,
                helperInstalled: helperInstalled,
                helperNeedsApproval: helperNeedsApproval
            )
        } else {
            // Fallback: legacy inline logic (kept for quick rollback)
            legacyDetermineCurrentPage(
                state: state,
                issues: issues,
                helperInstalled: helperInstalled,
                helperNeedsApproval: helperNeedsApproval
            )
        }

        // Preserve single-show Full Disk Access behavior here.
        if corePage == .summary, !hasShownFullDiskAccessPage, state != .active {
            AppLogger.shared.log(
                "🔍 [NavigationEngine] → .fullDiskAccess (no blocking issues - checking optional FDA)")
            hasShownFullDiskAccessPage = true
            return .fullDiskAccess
        }

        AppLogger.shared.log("🔍 [NavigationEngine] → \(corePage) (routed by WizardRouter)")
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

        // Otherwise, continue forward in the sequential flow
        // This handles: no issues, non-blocking issues resolved, or optional pages
        let nextIndex = currentIndex + 1
        if nextIndex < pageOrder.count {
            return pageOrder[nextIndex]
        }

        // We're at the end of the flow
        return nil
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

    /// Determines if a page represents a "blocking" issue that must be resolved
    func isBlockingPage(_ page: WizardPage) async -> Bool {
        switch page {
        case .conflicts:
            return true // Cannot proceed with conflicts
        case .karabinerComponents, .kanataComponents:
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
        case .communication:
            return false // Optional, not blocking
        case .summary:
            return false // Final state
        }
    }

    // MARK: - Legacy routing fallback (kept for feature-flag rollback)

    private func legacyDetermineCurrentPage(
        state: WizardSystemState,
        issues: [WizardIssue],
        helperInstalled: Bool,
        helperNeedsApproval: Bool
    ) -> WizardPage {
        // Conflicts
        if issues.contains(where: { $0.category == .conflicts }) { return .conflicts }

        // Helper gating
        if helperNeedsApproval { return .helper }
        if !helperInstalled { return .helper }

        // Permissions
        let hasInputMonitoring = issues.contains {
            if case let .permission(permissionType) = $0.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        if hasInputMonitoring { return .inputMonitoring }

        let hasAccessibility = issues.contains {
            if case let .permission(permissionType) = $0.identifier {
                return permissionType == .keyPathAccessibility || permissionType == .kanataAccessibility
            }
            return false
        }
        if hasAccessibility { return .accessibility }

        // Communication
        let hasCommunication = issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.communicationServerConfiguration),
                     .component(.communicationServerNotResponding),
                     .component(.tcpServerConfiguration),
                     .component(.tcpServerNotResponding):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasCommunication { return .communication }

        // Karabiner components
        let hasKarabinerIssues = issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.karabinerDriver),
                     .component(.karabinerDaemon),
                     .component(.vhidDeviceManager),
                     .component(.vhidDeviceActivation),
                     .component(.vhidDeviceRunning),
                     .component(.launchDaemonServices),
                     .component(.vhidDaemonMisconfigured),
                     .component(.vhidDriverVersionMismatch):
                    return true
                default:
                    return false
                }
            }
            return $0.category == .daemon || $0.category == .backgroundServices
        }
        if hasKarabinerIssues { return .karabinerComponents }

        // Kanata components
        let hasKanataIssues = issues.contains {
            if $0.category == .installation {
                switch $0.identifier {
                case .component(.kanataBinaryMissing), .component(.kanataService):
                    return true
                default:
                    return false
                }
            }
            return false
        }
        if hasKanataIssues { return .kanataComponents }

        // Service readiness
        switch state {
        case .serviceNotRunning, .ready, .daemonNotRunning:
            return .service
        default:
            break
        }

        return .summary
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
        case .kanataComponents:
            "Install Kanata Components"
        case .helper:
            await HelperManager.shared.isHelperInstalled() ? "Manage Helper" : "Install Helper"
        case .communication:
            "Check TCP Server"
        case .service:
            "Start Keyboard Service"
        case .fullDiskAccess:
            "Grant Full Disk Access"
        case .summary:
            switch state {
            case .active:
                "Close Setup"
            case .serviceNotRunning, .ready:
                "Start Kanata Service"
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
        case .karabinerComponents, .kanataComponents:
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

import Foundation
import KeyPathCore
import KeyPathWizardCore
import OSLog

/// Handles wizard navigation logic based on system state
class WizardNavigationEngine: WizardNavigating {
    // Track if we've shown the FDA page
    private var hasShownFullDiskAccessPage = false

    /// Reset navigation state for a fresh wizard run
    func resetNavigationState() {
        hasShownFullDiskAccessPage = false
    }

    // MARK: - Main Navigation Logic

    /// Primary navigation method - determines the current page based on system state and issues
    /// This is the preferred method as it uses structured issue identifiers for type-safe navigation

    func determineCurrentPage(for state: WizardSystemState, issues: [WizardIssue]) -> WizardPage {
        // First check for blocking issues in priority order
        AppLogger.shared.log("🔍 [NavigationEngine] Determining page for \(issues.count) issues:")
        for issue in issues {
            AppLogger.shared.log("🔍 [NavigationEngine]   - \(issue.category): \(issue.title)")
        }

        // 1. Conflicts (highest priority)
        if issues.contains(where: { $0.category == .conflicts }) {
            AppLogger.shared.log("🔍 [NavigationEngine] → .conflicts (found conflicts)")
            return .conflicts
        }

        // 2. Permission Issues - navigate to first missing permission
        let inputMonitoringIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathInputMonitoring || permissionType == .kanataInputMonitoring
            }
            return false
        }
        let accessibilityIssues = issues.contains { issue in
            if case let .permission(permissionType) = issue.identifier {
                return permissionType == .keyPathAccessibility || permissionType == .kanataAccessibility
            }
            return false
        }

        if inputMonitoringIssues {
            AppLogger.shared.log(
                "🔍 [NavigationEngine] → .inputMonitoring (found Input Monitoring issues)")
            return .inputMonitoring
        } else if accessibilityIssues {
            AppLogger.shared.log("🔍 [NavigationEngine] → .accessibility (found Accessibility issues)")
            return .accessibility
        }

        // 3. Communication Server Configuration Issues (critical for permission detection)
        let hasCommunicationIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
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

        if hasCommunicationIssues {
            AppLogger.shared.log("🔍 [NavigationEngine] → .communication (found communication configuration issues)")
            return .communication
        }

        // 4. Karabiner Components - driver, VirtualHID, background services
        let hasKarabinerIssues = issues.contains { issue in
            // Installation issues related to Karabiner
            if issue.category == .installation {
                switch issue.identifier {
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
            // Daemon and background services issues
            return issue.category == .daemon || issue.category == .backgroundServices
        }

        if hasKarabinerIssues {
            AppLogger.shared.log(
                "🔍 [NavigationEngine] → .karabinerComponents (found Karabiner-related issues)")
            return .karabinerComponents
        }

        // 5. Kanata Components - binary and service
        let hasKanataIssues = issues.contains { issue in
            if issue.category == .installation {
                switch issue.identifier {
                case .component(.kanataBinaryMissing),
                     .component(.kanataService):
                    return true
                default:
                    return false
                }
            }
            return false
        }

        if hasKanataIssues {
            AppLogger.shared.log("🔍 [NavigationEngine] → .kanataComponents (found Kanata-related issues)")
            return .kanataComponents
        }

        // 6. Privileged Helper — recommend installing before service management to avoid repeated prompts
        // Only surface this step if the helper isn’t installed yet. This is non-blocking but improves UX.
        let helperInstalled = HelperManager.shared.isHelperInstalled()
        if !helperInstalled {
            AppLogger.shared.log("🔍 [NavigationEngine] → .helper (helper not installed)")
            return .helper
        }

        // 6. Service state check (directly from WizardSystemState)
        switch state {
        case .serviceNotRunning:
            AppLogger.shared.log("🔍 [NavigationEngine] → .service (service not running)")
            return .service
        case .ready:
            // Ready means everything installed but service not started yet
            AppLogger.shared.log("🔍 [NavigationEngine] → .service (ready to start service)")
            return .service
        default:
            break
        }

        // 7. Full Disk Access (optional but helpful - show once when no blocking issues)
        // If we reach here, all blocking issues (conflicts, permissions, components, service) have been checked
        // Show FDA page if we haven't shown it yet AND system is not already active
        if !hasShownFullDiskAccessPage, state != .active {
            AppLogger.shared.log(
                "🔍 [NavigationEngine] → .fullDiskAccess (no blocking issues - checking optional FDA)")
            hasShownFullDiskAccessPage = true
            return .fullDiskAccess
        }

        // 8. If no issues and service is running, go to summary
        AppLogger.shared.log("🔍 [NavigationEngine] → .summary (no issues found)")
        return .summary
    }

    func canNavigate(from _: WizardPage, to _: WizardPage, given _: WizardSystemState) -> Bool {
        // Users can always navigate manually via page dots
        // This method is mainly for programmatic navigation validation
        true
    }

    func nextPage(
        from current: WizardPage, given state: WizardSystemState, issues: [WizardIssue] = []
    ) -> WizardPage? {
        // Get the logical page order
        let pageOrder = getPageOrder()
        guard let currentIndex = pageOrder.firstIndex(of: current) else {
            return nil
        }

        // Check if there are blocking issues that require going to a specific page
        let targetPage = determineCurrentPage(for: state, issues: issues)

        // If the target is a blocking page and we're not on it, jump there immediately
        if isBlockingPage(targetPage), targetPage != current {
            return targetPage
        }

        // If the target page is ahead of us in the flow and different from current, jump to it
        if let targetIndex = pageOrder.firstIndex(of: targetPage),
           targetIndex > currentIndex,
           targetPage != current {
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
    ) -> WizardNavigationState {
        let targetPage = determineCurrentPage(for: systemState, issues: issues)
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
    func isBlockingPage(_ page: WizardPage) -> Bool {
        switch page {
        case .conflicts:
            true // Cannot proceed with conflicts
        case .karabinerComponents, .kanataComponents:
            true // Cannot use without components
        case .helper:
            false // Optional but recommended to avoid prompts
        case .inputMonitoring, .accessibility:
            false // Can proceed but functionality limited
        case .service:
            false // Can manage service state
        case .fullDiskAccess:
            false // Optional, not blocking
        case .communication:
            false // Optional, not blocking
        case .summary:
            false // Final state
        }
    }

    // MARK: - Navigation Helpers

    /// Determines if the wizard should show a "Next" button on the given page
    func shouldShowNextButton(
        for page: WizardPage, state: WizardSystemState, issues: [WizardIssue] = []
    ) -> Bool {
        let targetPage = determineCurrentPage(for: state, issues: issues)
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
    func primaryButtonText(for page: WizardPage, state: WizardSystemState) -> String {
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
            HelperManager.shared.isHelperInstalled() ? "Manage Helper" : "Install Helper"
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

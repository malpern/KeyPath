import Foundation
import OSLog

/// Handles wizard navigation logic based on system state
class WizardNavigationEngine: WizardNavigating {
    
    // MARK: - Main Navigation Logic
    
    func determineCurrentPage(for state: WizardSystemState) -> WizardPage {
        switch state {
        case .initializing:
            return .summary
            
        case .conflictsDetected:
            return .conflicts
            
        case .missingPermissions(let missing):
            // Prioritize Input Monitoring first, then Accessibility
            if missing.contains(.kanataInputMonitoring) {
                return .inputMonitoring
            } else if missing.contains(.kanataAccessibility) {
                return .accessibility
            } else if missing.contains(.backgroundServicesEnabled) {
                return .backgroundServices
            } else {
                // Driver extension - show on input monitoring page
                return .inputMonitoring
            }
            
        case .missingComponents:
            return .installation
            
        case .daemonNotRunning:
            return .daemon
            
        case .serviceNotRunning, .ready, .active:
            return .summary
        }
    }
    
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
        
        // 2. Missing components 
        if issues.contains(where: { $0.category == .installation }) {
            AppLogger.shared.log("🔍 [NavigationEngine] → .installation (found installation issues)")
            return .installation
        }
        
        // 3. Permissions (check specific types and only go to pages with actual issues)
        let inputMonitoringIssue = issues.first(where: { $0.category == .permissions && $0.title == "Kanata Input Monitoring" })
        if let issue = inputMonitoringIssue {
            AppLogger.shared.log("🔍 [NavigationEngine] → .inputMonitoring (found input monitoring issue: '\(issue.title)')")
            return .inputMonitoring
        } else {
            AppLogger.shared.log("🔍 [NavigationEngine] No input monitoring issues found - skipping input monitoring page")
        }
        
        let accessibilityIssue = issues.first(where: { $0.category == .permissions && $0.title == "Kanata Accessibility" })
        if let issue = accessibilityIssue {
            AppLogger.shared.log("🔍 [NavigationEngine] → .accessibility (found accessibility issue: '\(issue.title)')")
            return .accessibility
        } else {
            AppLogger.shared.log("🔍 [NavigationEngine] No accessibility issues found - skipping accessibility page")
        }
        
        // 4. Background services
        if issues.contains(where: { $0.category == .backgroundServices }) {
            AppLogger.shared.log("🔍 [NavigationEngine] → .backgroundServices (found background services issues)")
            return .backgroundServices
        }
        
        // 5. Daemon issues
        if issues.contains(where: { $0.category == .daemon }) {
            AppLogger.shared.log("🔍 [NavigationEngine] → .daemon (found daemon issues)")
            return .daemon
        }
        
        // 6. If no issues, go to summary
        AppLogger.shared.log("🔍 [NavigationEngine] → .summary (no issues found)")
        return .summary
    }
    
    func canNavigate(from: WizardPage, to: WizardPage, given state: WizardSystemState) -> Bool {
        // Users can always navigate manually via page dots
        // This method is mainly for programmatic navigation validation
        return true
    }
    
    func nextPage(from current: WizardPage, given state: WizardSystemState) -> WizardPage? {
        // Determine what the next logical page should be based on current state
        let targetPage = determineCurrentPage(for: state)
        
        // If we're already on the target page, no next page
        if current == targetPage {
            return nil
        }
        
        return targetPage
    }
    
    // MARK: - Navigation State Creation
    
    func createNavigationState(currentPage: WizardPage, systemState: WizardSystemState) -> WizardNavigationState {
        let targetPage = determineCurrentPage(for: systemState)
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
    
    /// Returns the typical ordering of pages for a complete setup flow
    func getPageOrder() -> [WizardPage] {
        return [
            .conflicts,           // Must resolve conflicts first
            .inputMonitoring,     // Permissions before installation
            .accessibility,       // Second permission type
            .backgroundServices,  // Background services setup
            .installation,        // Install components after permissions
            .daemon,              // Start daemon after installation
            .summary              // Final state
        ]
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
            return true  // Cannot proceed with conflicts
        case .installation:
            return true  // Cannot use without components
        case .inputMonitoring, .accessibility:
            return false // Can proceed but functionality limited
        case .backgroundServices:
            return false // Can proceed but services won't auto-start
        case .daemon:
            return false // Can auto-start
        case .summary:
            return false // Final state
        }
    }
    
    // MARK: - Navigation Helpers
    
    /// Determines if the wizard should show a "Next" button on the given page
    func shouldShowNextButton(for page: WizardPage, state: WizardSystemState) -> Bool {
        let targetPage = determineCurrentPage(for: state)
        let currentIndex = pageIndex(page)
        let targetIndex = pageIndex(targetPage)
        
        // Show next button if we're not on the final target page
        return currentIndex < targetIndex || targetPage != .summary
    }
    
    /// Determines if the wizard should show a "Previous" button on the given page
    func shouldShowPreviousButton(for page: WizardPage, state: WizardSystemState) -> Bool {
        // Always allow going back, except on summary when everything is complete
        return !(page == .summary && state == .active)
    }
    
    /// Determines the appropriate button text for the current page and state
    func primaryButtonText(for page: WizardPage, state: WizardSystemState) -> String {
        switch page {
        case .conflicts:
            return "Resolve Conflicts"
        case .inputMonitoring:
            return "Open Settings"
        case .accessibility:
            return "Open Settings"
        case .backgroundServices:
            return "Open System Settings"
        case .installation:
            return "Install Components"
        case .daemon:
            return "Start Daemon"
        case .summary:
            switch state {
            case .active:
                return "Close Setup"
            case .serviceNotRunning, .ready:
                return "Start Kanata Service"
            default:
                return "Continue Setup"
            }
        }
    }
    
    /// Determines if the primary button should be enabled
    func isPrimaryButtonEnabled(for page: WizardPage, state: WizardSystemState, isProcessing: Bool = false) -> Bool {
        if isProcessing {
            return false
        }
        
        switch page {
        case .conflicts:
            if case .conflictsDetected(let conflicts) = state {
                return !conflicts.isEmpty
            }
            return false
        case .inputMonitoring, .accessibility:
            return true // Can always open settings
        case .backgroundServices:
            return true // Can always open system settings
        case .installation:
            if case .missingComponents(let missing) = state {
                return !missing.isEmpty
            }
            return false
        case .daemon:
            return state == .daemonNotRunning
        case .summary:
            return true
        }
    }
    
    // MARK: - Progress Calculation
    
    /// Calculates completion progress as a percentage (0.0 to 1.0)
    func calculateProgress(for state: WizardSystemState) -> Double {
        switch state {
        case .initializing:
            return 0.0
        case .conflictsDetected:
            return 0.1  // Just started
        case .missingComponents:
            return 0.2  // Conflicts resolved
        case .missingPermissions:
            return 0.5  // Components installed
        case .daemonNotRunning:
            return 0.8  // Permissions granted
        case .serviceNotRunning, .ready:
            return 0.9  // Daemon running
        case .active:
            return 1.0  // Complete
        }
    }
    
    /// Returns a user-friendly progress description
    func progressDescription(for state: WizardSystemState) -> String {
        switch state {
        case .initializing:
            return "Checking system..."
        case .conflictsDetected:
            return "Resolving conflicts..."
        case .missingComponents:
            return "Installing components..."
        case .missingPermissions:
            return "Configuring permissions..."
        case .daemonNotRunning:
            return "Starting services..."
        case .serviceNotRunning, .ready:
            return "Ready to start..."
        case .active:
            return "Setup complete!"
        }
    }
}
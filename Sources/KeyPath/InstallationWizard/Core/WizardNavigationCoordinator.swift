import SwiftUI
import Foundation

/// Coordinates navigation between wizard pages and manages page transitions
@MainActor
class WizardNavigationCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var currentPage: WizardPage = .summary
    @Published var userInteractionMode = false
    
    // MARK: - Private Properties
    private let navigationEngine = WizardNavigationEngine()
    private var lastPageChangeTime = Date()
    private let autoNavigationGracePeriod: TimeInterval = 10.0
    
    // Navigation animation configuration
    private let navigationAnimation: Animation = .easeInOut(duration: 0.3)
    
    // MARK: - Navigation Methods
    
    /// Navigate to a specific page with animation
    func navigateToPage(_ page: WizardPage) {
        withAnimation(navigationAnimation) {
            currentPage = page
            lastPageChangeTime = Date()
            userInteractionMode = true
        }
    }
    
    /// Auto-navigate based on system state (if user hasn't interacted recently)
    func autoNavigateIfNeeded(for state: WizardSystemState, issues: [WizardIssue]) {
        // Don't auto-navigate if user has recently interacted
        guard !isInUserInteractionMode() else { return }
        
        let recommendedPage = navigationEngine.determineCurrentPage(for: state, issues: issues)
        
        // Only navigate if it's different from current page
        guard recommendedPage != currentPage else { return }
        
        withAnimation(navigationAnimation) {
            currentPage = recommendedPage
            lastPageChangeTime = Date()
        }
    }
    
    /// Check if we can navigate to a specific page
    func canNavigate(to page: WizardPage, given state: WizardSystemState) -> Bool {
        return navigationEngine.canNavigate(from: currentPage, to: page, given: state)
    }
    
    /// Get the next logical page in the wizard flow
    func getNextPage(for state: WizardSystemState, issues: [WizardIssue]) -> WizardPage? {
        return navigationEngine.nextPage(from: currentPage, given: state, issues: issues)
    }
    
    /// Reset navigation state (typically called when wizard starts)
    func resetNavigation() {
        currentPage = .summary
        userInteractionMode = false
        lastPageChangeTime = Date()
    }
    
    // MARK: - Private Helpers
    
    private func isInUserInteractionMode() -> Bool {
        return userInteractionMode && 
               Date().timeIntervalSince(lastPageChangeTime) < autoNavigationGracePeriod
    }
}

// MARK: - Navigation State Helpers

extension WizardNavigationCoordinator {
    
    /// Get navigation state for UI components (like page dots)
    var navigationState: WizardNavigationState {
        return WizardNavigationState(
            currentPage: currentPage,
            availablePages: WizardPage.allCases,
            canNavigateNext: false, // This would need system state to determine
            canNavigatePrevious: false, // This would need system state to determine
            shouldAutoNavigate: !isInUserInteractionMode()
        )
    }
    
    /// Check if a page is the currently active page
    func isCurrentPage(_ page: WizardPage) -> Bool {
        return currentPage == page
    }
    
    /// Get pages that have been visited or are available
    func getAvailablePages(for state: WizardSystemState) -> [WizardPage] {
        // This could be enhanced to show which pages are accessible
        // based on current system state
        return WizardPage.allCases
    }
}

// MARK: - Animation Helpers

extension WizardNavigationCoordinator {
    
    /// Standard page transition animation
    static let pageTransition: Animation = .easeInOut(duration: 0.3)
    
    /// Quick feedback animation for user interactions
    static let userFeedback: Animation = .easeInOut(duration: 0.2)
    
    /// Perform navigation with custom animation
    func navigateToPage(_ page: WizardPage, animation: Animation) {
        withAnimation(animation) {
            currentPage = page
            lastPageChangeTime = Date()
            userInteractionMode = true
        }
    }
}
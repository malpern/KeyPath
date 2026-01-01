import Foundation
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

/// Coordinates navigation between wizard pages and manages page transitions
@MainActor
class WizardNavigationCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published var currentPage: WizardPage = .summary
    @Published var lastVisitedPage: WizardPage?
    @Published var userInteractionMode = false
    /// Optional external sequence to drive back/next order (e.g., filtered issues-only list).
    /// When nil or empty, the default ordered pages are used.
    @Published var customSequence: [WizardPage]?

    // MARK: - Properties

    let navigationEngine = WizardNavigationEngine()
    private var lastPageChangeTime = Date()
    private let autoNavigationGracePeriod: TimeInterval = 10.0

    // Navigation animation configuration
    private let navigationAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.9)

    /// Returns true if navigating forward (to a later page in the flow)
    var isNavigatingForward: Bool {
        guard let lastPage = lastVisitedPage else { return true }
        let order = WizardPage.orderedPages
        guard let currentIndex = order.firstIndex(of: currentPage),
              let lastIndex = order.firstIndex(of: lastPage) else { return true }
        return currentIndex > lastIndex
    }

    // MARK: - Navigation Methods

    /// Navigate to a specific page with animation
    func navigateToPage(_ page: WizardPage) {
        AppLogger.shared.log("🧭 [NavCoord] navigateToPage(\(page)) called, current=\(currentPage)")
        withAnimation(navigationAnimation) {
            lastVisitedPage = currentPage
            currentPage = page
            lastPageChangeTime = Date()
            userInteractionMode = true
        }
        AppLogger.shared.log("🧭 [NavCoord] navigateToPage(\(page)) complete, now=\(currentPage)")
    }

    /// Auto-navigate based on system state (if user hasn't interacted recently)
    func autoNavigateIfNeeded(for state: WizardSystemState, issues: [WizardIssue]) async {
        // Don't auto-navigate if user has recently interacted
        guard !isInUserInteractionMode() else { return }

        let recommendedPage = await navigationEngine.determineCurrentPage(for: state, issues: issues)

        // Only navigate if it's different from current page
        guard recommendedPage != currentPage else { return }

        withAnimation(navigationAnimation) {
            lastVisitedPage = currentPage
            currentPage = recommendedPage
            lastPageChangeTime = Date()
        }
    }

    /// Check if we can navigate to a specific page
    func canNavigate(to page: WizardPage, given state: WizardSystemState) -> Bool {
        navigationEngine.canNavigate(from: currentPage, to: page, given: state)
    }

    /// Get the next logical page in the wizard flow
    func getNextPage(for state: WizardSystemState, issues: [WizardIssue]) async -> WizardPage? {
        await navigationEngine.nextPage(from: currentPage, given: state, issues: issues)
    }

    /// Reset navigation state (typically called when wizard starts)
    func resetNavigation() {
        currentPage = .summary
        userInteractionMode = false
        lastPageChangeTime = Date()
    }

    // MARK: - Private Helpers

    private func isInUserInteractionMode() -> Bool {
        userInteractionMode
            && Date().timeIntervalSince(lastPageChangeTime) < autoNavigationGracePeriod
    }
}

// MARK: - Navigation State Helpers

extension WizardNavigationCoordinator {
    /// Active sequence used for previous/next navigation
    private var activeSequence: [WizardPage] {
        if let custom = customSequence, !custom.isEmpty {
            return custom
        }
        return WizardPage.orderedPages
    }

    /// Get navigation state for UI components (like page dots)
    var navigationState: WizardNavigationState {
        WizardNavigationState(
            currentPage: currentPage,
            availablePages: WizardPage.allCases,
            canNavigateNext: false, // This would need system state to determine
            canNavigatePrevious: false, // This would need system state to determine
            shouldAutoNavigate: !isInUserInteractionMode()
        )
    }

    /// Check if a page is the currently active page
    func isCurrentPage(_ page: WizardPage) -> Bool {
        currentPage == page
    }

    /// Get pages that have been visited or are available
    func getAvailablePages(for _: WizardSystemState) -> [WizardPage] {
        // This could be enhanced to show which pages are accessible
        // based on current system state
        WizardPage.allCases
    }

    /// Check if we can navigate to the previous page
    var canNavigateBack: Bool {
        guard let currentIndex = activeSequence.firstIndex(of: currentPage) else {
            return false
        }
        return currentIndex > 0
    }

    /// Check if we can navigate to the next page
    var canNavigateForward: Bool {
        guard let currentIndex = activeSequence.firstIndex(of: currentPage) else {
            return false
        }
        return currentIndex < activeSequence.count - 1
    }

    /// Get the previous page in the ordered sequence
    var previousPage: WizardPage? {
        guard let currentIndex = activeSequence.firstIndex(of: currentPage),
              currentIndex > 0
        else {
            return nil
        }
        return activeSequence[currentIndex - 1]
    }

    /// Get the next page in the ordered sequence
    var nextPage: WizardPage? {
        guard let currentIndex = activeSequence.firstIndex(of: currentPage),
              currentIndex < activeSequence.count - 1
        else {
            return nil
        }
        return activeSequence[currentIndex + 1]
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

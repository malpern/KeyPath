import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import SwiftUI

/// Record of wizard snapshot for caching
struct WizardSnapshotRecord {
    let state: WizardSystemState
    let issues: [WizardIssue]
}

/// Simple wizard state machine using SystemValidator
///
/// Replaces: WizardStateManager + WizardNavigationEngine + WizardNavigationCoordinator + WizardStateInterpreter
///
/// Key design:
/// - Single @Published state property
/// - Explicit refresh (no automatic)
/// - Simple navigation logic (no separate engine/coordinator)
/// - Uses SystemValidator (stateless)
@MainActor
class WizardStateMachine: ObservableObject {
    // MARK: - Published State

    /// Single source of truth for all wizard state
    @Published var systemSnapshot: SystemSnapshot?

    /// Current wizard page
    @Published var currentPage: WizardPage = .summary

    /// Last visited page for direction detection
    @Published var lastVisitedPage: WizardPage?

    /// Whether user has manually interacted (blocks auto-navigation)
    @Published var userInteractionMode = false

    /// Optional external sequence to drive back/next order (e.g., filtered issues-only list).
    /// When nil or empty, the default ordered pages are used.
    @Published var customSequence: [WizardPage]?

    /// Whether we're currently refreshing state
    @Published var isRefreshing = false

    /// Last refresh timestamp
    @Published var lastRefreshTime: Date?

    /// Monotonically increasing version counter, bumped each time state detection completes.
    /// Used by callers to detect when a refresh has finished.
    @Published private(set) var stateVersion: Int = 0

    /// Cache for the last known wizard state (for backward compatibility with legacy flows)
    var lastWizardSnapshot: WizardSnapshotRecord?

    // MARK: - Dependencies

    private var validator: SystemValidator?
    private weak var kanataManager: RuntimeCoordinator?

    /// Navigation engine for determining appropriate pages
    let navigationEngine = WizardNavigationEngine()

    // MARK: - Navigation State

    private var lastPageChangeTime = Date()
    private let autoNavigationGracePeriod: TimeInterval = 10.0
    private let navigationAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.9)

    // MARK: - Defensive State

    private var refreshCount = 0
    private var lastRefreshStart: Date?

    // MARK: - Initialization

    init() {
        AppLogger.shared.log("🎯 [WizardStateMachine] Initialized")
    }

    /// Configure with RuntimeCoordinator (called after init)
    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager

        // Create validator with process manager
        let processManager = ProcessLifecycleManager()
        validator = SystemValidator(
            processLifecycleManager: processManager,
            kanataManager: kanataManager
        )

        AppLogger.shared.log("🎯 [WizardStateMachine] Configured with validator")
    }

    // MARK: - State Refresh

    /// Refresh system state (explicit user action only)
    func refresh() async {
        guard let validator else {
            AppLogger.shared.warn("⚠️ [WizardStateMachine] Cannot refresh - not configured")
            return
        }

        // Defensive: Detect rapid-fire refreshes
        if let last = lastRefreshStart {
            let interval = Date().timeIntervalSince(last)
            if interval < 0.5 {
                AppLogger.shared.log(
                    """
                    ⚠️ [WizardStateMachine] RAPID REFRESH: \(String(format: "%.3f", interval))s since last
                    This might indicate automatic triggers - expected: manual user actions only
                    """)
            }
        }
        lastRefreshStart = Date()

        refreshCount += 1
        let myID = refreshCount

        AppLogger.shared.info("🔄 [WizardStateMachine] Refresh #\(myID) starting")

        isRefreshing = true

        // Get fresh state from validator
        let snapshot = await validator.checkSystem()

        isRefreshing = false
        systemSnapshot = snapshot
        lastRefreshTime = Date()

        AppLogger.shared.info(
            "🔄 [WizardStateMachine] Refresh #\(myID) complete - ready=\(snapshot.isReady), issues=\(snapshot.blockingIssues.count)"
        )
    }

    /// Detect current state and return as SystemStateResult (legacy compatibility)
    /// Prefer using refresh() + systemSnapshot for new code
    func detectCurrentState(progressCallback _: @escaping @Sendable (Double) -> Void = { _ in }) async
        -> SystemStateResult {
        if let manager = kanataManager {
            AppLogger.shared.log("🎯 [WizardStateMachine] Using RuntimeCoordinator.inspectSystemContext()")
            let context = await manager.inspectSystemContext()
            return SystemContextAdapter.adapt(context)
        } else {
            AppLogger.shared.warn("⚠️ [WizardStateMachine] RuntimeCoordinator not configured; falling back to InstallerEngine.inspectSystem()")
            let context = await InstallerEngine().inspectSystem()
            return SystemContextAdapter.adapt(context)
        }
    }

    /// Bump the state version to signal that a refresh cycle has completed.
    func markRefreshComplete() {
        stateVersion += 1
    }

    // MARK: - Navigation

    /// Navigate to a specific page with animation (main navigation method)
    func navigateToPage(_ page: WizardPage) {
        AppLogger.shared.log("🧭 [StateMachine] navigateToPage(\(page)) called, current=\(currentPage)")
        withAnimation(navigationAnimation) {
            lastVisitedPage = currentPage
            currentPage = page
            lastPageChangeTime = Date()
            userInteractionMode = true
        }
        AppLogger.shared.log("🧭 [StateMachine] navigateToPage(\(page)) complete, now=\(currentPage)")
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

    /// Navigate to specific page (simplified, without animation tracking)
    func navigateTo(_ page: WizardPage) {
        AppLogger.shared.log("🎯 [WizardStateMachine] Navigate to: \(page.rawValue)")
        currentPage = page
    }

    /// Navigate to next appropriate page based on system state (used by determinism tests)
    func nextPage() {
        guard let snapshot = systemSnapshot else {
            AppLogger.shared.warn("⚠️ [WizardStateMachine] Cannot navigate - no system state")
            return
        }

        let next = determineNextPage(from: currentPage, state: snapshot)
        AppLogger.shared.log(
            "🎯 [WizardStateMachine] Navigate: \(currentPage.rawValue) → \(next.rawValue)")
        currentPage = next
    }

    /// Navigate to previous page based on hardcoded flow
    func previousPage() {
        let previous = determinePreviousPage(from: currentPage)
        AppLogger.shared.log(
            "🎯 [WizardStateMachine] Navigate: \(currentPage.rawValue) ← \(previous.rawValue)")
        currentPage = previous
    }

    // MARK: - Private Navigation Helpers

    private func determineNextPage(from current: WizardPage, state: SystemSnapshot) -> WizardPage {
        // Use the shared pure router to choose target page based on latest snapshot.
        // Adapt SystemSnapshot to SystemContext so we can reuse existing adapter logic.
        let placeholderSystem = EngineSystemInfo(macOSVersion: "unknown", driverCompatible: true)
        let context = SystemContext(
            permissions: state.permissions,
            services: state.health,
            conflicts: state.conflicts,
            components: state.components,
            helper: state.helper,
            system: placeholderSystem,
            timestamp: state.timestamp
        )
        let adapted = SystemContextAdapter.adapt(context)
        let target = WizardRouter.route(
            state: adapted.state,
            issues: adapted.issues,
            helperInstalled: state.helper.isInstalled,
            helperNeedsApproval: HelperManager.shared.helperNeedsLoginItemsApproval()
        )

        // If the router says stay, remain on the current page; otherwise move to target.
        return target == current ? current : target
    }

    private func determinePreviousPage(from current: WizardPage) -> WizardPage {
        // Simple reverse navigation
        switch current {
        case .summary:
            .summary // First page
        case .kanataMigration:
            .summary // Migration is early optional page
        case .stopExternalKanata:
            .kanataMigration // Stop external kanata comes after migration
        case .helper:
            .stopExternalKanata // Helper is after stop external kanata
        case .fullDiskAccess:
            .helper
        case .conflicts:
            .helper
        case .inputMonitoring:
            .conflicts
        case .accessibility:
            .inputMonitoring
        case .karabinerComponents:
            .accessibility
        case .kanataComponents:
            .karabinerComponents
        case .communication:
            .kanataComponents
        case .service:
            .kanataComponents // Service comes after all components
        }
    }

    private func isInUserInteractionMode() -> Bool {
        userInteractionMode
            && Date().timeIntervalSince(lastPageChangeTime) < autoNavigationGracePeriod
    }

    // MARK: - Computed Properties

    /// Whether system is ready
    var isSystemReady: Bool {
        systemSnapshot?.isReady ?? false
    }

    /// Blocking issues count
    var blockingIssueCount: Int {
        systemSnapshot?.blockingIssues.count ?? 0
    }

    /// All issues count
    var totalIssueCount: Int {
        systemSnapshot?.allIssues.count ?? 0
    }

    /// Whether we should show the service as running
    var isServiceRunning: Bool {
        systemSnapshot?.health.kanataRunning ?? false
    }

    // MARK: - Debug Support

    /// Get refresh stats for debugging
    func getRefreshStats() -> (count: Int, lastStart: Date?) {
        (refreshCount, lastRefreshStart)
    }
}

// MARK: - Navigation State Helpers

extension WizardStateMachine {
    /// Returns true if navigating forward (to a later page in the flow)
    var isNavigatingForward: Bool {
        guard let lastPage = lastVisitedPage else { return true }
        let order = WizardPage.orderedPages
        guard let currentIndex = order.firstIndex(of: currentPage),
              let lastIndex = order.firstIndex(of: lastPage) else { return true }
        return currentIndex > lastIndex
    }

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
    var previousPageInSequence: WizardPage? {
        guard let currentIndex = activeSequence.firstIndex(of: currentPage),
              currentIndex > 0
        else {
            return nil
        }
        return activeSequence[currentIndex - 1]
    }

    /// Get the next page in the ordered sequence
    var nextPageInSequence: WizardPage? {
        guard let currentIndex = activeSequence.firstIndex(of: currentPage),
              currentIndex < activeSequence.count - 1
        else {
            return nil
        }
        return activeSequence[currentIndex + 1]
    }
}

// MARK: - Animation Helpers

extension WizardStateMachine {
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

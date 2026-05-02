import KeyPathCore
import KeyPathWizardCore
import Observation
import SwiftUI

/// Record of wizard snapshot for caching
public struct WizardSnapshotRecord {
    public let state: WizardSystemState
    public let issues: [WizardIssue]
}

/// Observable state container for the installation wizard.
///
/// Holds the current page, system state, and issues. Pages read these via @Environment.
/// Navigation decisions are made by WizardRouter (pure function); this class just stores
/// the results and provides animated page transitions.
@MainActor
@Observable
public class WizardStateMachine {
    // MARK: - State

    public var wizardState: WizardSystemState = .initializing
    public var wizardIssues: [WizardIssue] = []
    public var currentPage: WizardPage = .summary
    public var lastVisitedPage: WizardPage?
    public var userInteractionMode = false
    public var isRefreshing = false
    public var lastRefreshTime: Date?
    public private(set) var stateVersion: Int = 0
    public var lastWizardSnapshot: WizardSnapshotRecord?
    public var systemSnapshot: SystemSnapshot?
    public var customSequence: [WizardPage]?

    // MARK: - One-Time Page Tracking

    public var hasShownFDAPage = false
    public var hasShownMigrationPage = false
    public var hasShownKarabinerImportPage = false

    @ObservationIgnored private let navigationAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.9)

    // MARK: - Init

    public init() {}

    // MARK: - State Updates

    /// Update wizard state and issues. Called by the view after SystemInspector.inspect().
    public func updateWizardState(_ state: WizardSystemState, issues: [WizardIssue]) {
        wizardState = state
        wizardIssues = issues
        lastWizardSnapshot = WizardSnapshotRecord(state: state, issues: issues)
        stateVersion += 1
    }

    // MARK: - Navigation

    /// Navigate to a specific page with animation.
    public func navigateToPage(_ page: WizardPage) {
        withAnimation(navigationAnimation) {
            lastVisitedPage = currentPage
            currentPage = page
            userInteractionMode = true
        }
    }

    /// Get the next logical page (delegates to WizardRouter).
    public func getNextPage(for state: WizardSystemState, issues: [WizardIssue]) async -> WizardPage? {
        let next = WizardRouter.nextPage(after: currentPage, state: state, issues: issues)
        return next != currentPage ? next : nil
    }

    /// Navigate to the next page (fire-and-forget).
    public func nextPage() {
        Task { @MainActor in
            let next = WizardRouter.nextPage(after: currentPage, state: wizardState, issues: wizardIssues)
            if next != currentPage {
                navigateToPage(next)
            }
        }
    }

    /// Reset navigation state for a fresh wizard run.
    public func resetNavigation() {
        currentPage = .summary
        userInteractionMode = false
        hasShownFDAPage = false
        hasShownMigrationPage = false
        hasShownKarabinerImportPage = false
        // One-time page tracking is reset via the properties above
    }

    // MARK: - Legacy Compatibility

    /// Configure with RuntimeCoordinating — no-op in simplified architecture.
    /// Kept for call-site compatibility during migration.
    public func configure(kanataManager _: any RuntimeCoordinating) {}

    /// Detect current state via InstallerEngine (used by existing refresh paths).
    public func detectCurrentState(progressCallback _: @escaping @Sendable (Double) -> Void = { _ in }) async
        -> SystemStateResult
    {
        let context = await InstallerEngine().inspectSystem()
        return SystemContextAdapter.adapt(context)
    }

    /// Auto-navigate based on system state using WizardRouter.
    public func autoNavigateIfNeeded(for state: WizardSystemState, issues: [WizardIssue]) async {
        guard !userInteractionMode else { return }

        let recommended = WizardRouter.route(
            state: state,
            issues: issues,
            helperInstalled: await WizardDependencies.helperManager?.isHelperInstalled() ?? false,
            helperNeedsApproval: WizardDependencies.helperManager?.helperNeedsLoginItemsApproval() ?? false
        )

        guard recommended != currentPage else { return }

        withAnimation(navigationAnimation) {
            lastVisitedPage = currentPage
            currentPage = recommended
        }
    }

    // MARK: - Refresh (delegates to InstallerEngine + SystemInspector)

    public func refresh() async {
        isRefreshing = true
        let context = await InstallerEngine().inspectSystem()
        let (state, issues) = SystemInspector.inspect(context: context)
        updateWizardState(state, issues: issues)
        isRefreshing = false
        lastRefreshTime = Date()
    }

    // MARK: - Backward Compat Properties

    public var isNavigatingForward: Bool {
        guard let last = lastVisitedPage else { return true }
        let order = WizardPage.orderedPages
        let lastIdx = order.firstIndex(of: last) ?? 0
        let curIdx = order.firstIndex(of: currentPage) ?? 0
        return curIdx >= lastIdx
    }

    public func isCurrentPage(_ page: WizardPage) -> Bool { currentPage == page }
    public var canNavigateBack: Bool { currentPage != .summary }
    public var canNavigateForward: Bool { true }

    public var previousPageInSequence: WizardPage? {
        let order = customSequence ?? WizardPage.orderedPages
        guard let idx = order.firstIndex(of: currentPage), idx > 0 else { return nil }
        return order[idx - 1]
    }

    public var nextPageInSequence: WizardPage? {
        let order = customSequence ?? WizardPage.orderedPages
        guard let idx = order.firstIndex(of: currentPage), idx < order.count - 1 else { return nil }
        return order[idx + 1]
    }

    public var isSystemReady: Bool {
        systemSnapshot?.isReady ?? false
    }

    public var blockingIssueCount: Int {
        systemSnapshot?.blockingIssues.count ?? 0
    }

    public var totalIssueCount: Int {
        systemSnapshot?.allIssues.count ?? 0
    }

    public var isServiceRunning: Bool {
        systemSnapshot?.health.kanataRunning ?? false
    }

    /// Previous page for back navigation (legacy — used by WizardStateMachine.previousPage)
    public func previousPage() {
        let previous = determinePreviousPage(from: currentPage)
        navigateToPage(previous)
    }

    private func determinePreviousPage(from current: WizardPage) -> WizardPage {
        switch current {
        case .summary: .summary
        case .kanataMigration: .summary
        case .stopExternalKanata: .kanataMigration
        case .karabinerImport:
            hasShownKarabinerImportPage ? .karabinerImport : .stopExternalKanata
        case .helper: .summary
        case .fullDiskAccess: .helper
        case .conflicts: .helper
        case .inputMonitoring: .conflicts
        case .accessibility: .inputMonitoring
        case .karabinerComponents: .accessibility
        case .communication: .karabinerComponents
        case .service: .karabinerComponents
        }
    }
}

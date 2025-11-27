import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import SwiftUI

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

    /// Whether we're currently refreshing state
    @Published var isRefreshing = false

    /// Last refresh timestamp
    @Published var lastRefreshTime: Date?

    // MARK: - Dependencies

    private var validator: SystemValidator?
    private weak var kanataManager: RuntimeCoordinator?

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

    // MARK: - Navigation

    /// Navigate to next appropriate page based on system state
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

    /// Navigate to previous page
    func previousPage() {
        let previous = determinePreviousPage(from: currentPage)
        AppLogger.shared.log(
            "🎯 [WizardStateMachine] Navigate: \(currentPage.rawValue) ← \(previous.rawValue)")
        currentPage = previous
    }

    /// Navigate to specific page
    func navigateTo(_ page: WizardPage) {
        AppLogger.shared.log("🎯 [WizardStateMachine] Navigate to: \(page.rawValue)")
        currentPage = page
    }

    // MARK: - Navigation Logic

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
        let target: WizardPage
        if FeatureFlags.useUnifiedWizardRouter {
            target = WizardRouter.route(
                state: adapted.state,
                issues: adapted.issues,
                helperInstalled: state.helper.isInstalled,
                helperNeedsApproval: HelperManager.shared.helperNeedsLoginItemsApproval()
            )
        } else {
            target = WizardRouter.route(
                state: adapted.state,
                issues: adapted.issues,
                helperInstalled: state.helper.isInstalled,
                helperNeedsApproval: HelperManager.shared.helperNeedsLoginItemsApproval()
            )
        }

        // If the router says stay, remain on the current page; otherwise move to target.
        return target == current ? current : target
    }

    private func determinePreviousPage(from current: WizardPage) -> WizardPage {
        // Simple reverse navigation
        switch current {
        case .summary:
            .summary // First page
        case .helper:
            .summary // Helper is first after summary
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

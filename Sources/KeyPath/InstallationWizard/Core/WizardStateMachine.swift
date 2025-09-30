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
    private weak var kanataManager: KanataManager?

    // MARK: - Defensive State

    private var refreshCount = 0
    private var lastRefreshStart: Date?

    // MARK: - Initialization

    init() {
        AppLogger.shared.log("🎯 [WizardStateMachine] Initialized")
    }

    /// Configure with KanataManager (called after init)
    func configure(kanataManager: KanataManager) {
        self.kanataManager = kanataManager

        // Create validator with process manager
        let processManager = ProcessLifecycleManager(kanataManager: kanataManager)
        self.validator = SystemValidator(
            processLifecycleManager: processManager,
            kanataManager: kanataManager
        )

        AppLogger.shared.log("🎯 [WizardStateMachine] Configured with validator")
    }

    // MARK: - State Refresh

    /// Refresh system state (explicit user action only)
    func refresh() async {
        guard let validator else {
            AppLogger.shared.log("⚠️ [WizardStateMachine] Cannot refresh - not configured")
            return
        }

        // Defensive: Detect rapid-fire refreshes
        if let last = lastRefreshStart {
            let interval = Date().timeIntervalSince(last)
            if interval < 0.5 {
                AppLogger.shared.log("""
                    ⚠️ [WizardStateMachine] RAPID REFRESH: \(String(format: "%.3f", interval))s since last
                    This might indicate automatic triggers - expected: manual user actions only
                    """)
            }
        }
        lastRefreshStart = Date()

        refreshCount += 1
        let myID = refreshCount

        AppLogger.shared.log("🔄 [WizardStateMachine] Refresh #\(myID) starting")

        isRefreshing = true

        // Get fresh state from validator
        let snapshot = await validator.checkSystem()

        isRefreshing = false
        systemSnapshot = snapshot
        lastRefreshTime = Date()

        AppLogger.shared.log("🔄 [WizardStateMachine] Refresh #\(myID) complete - ready=\(snapshot.isReady), issues=\(snapshot.blockingIssues.count)")
    }

    // MARK: - Navigation

    /// Navigate to next appropriate page based on system state
    func nextPage() {
        guard let snapshot = systemSnapshot else {
            AppLogger.shared.log("⚠️ [WizardStateMachine] Cannot navigate - no system state")
            return
        }

        let next = determineNextPage(from: currentPage, state: snapshot)
        AppLogger.shared.log("🎯 [WizardStateMachine] Navigate: \(currentPage.rawValue) → \(next.rawValue)")
        currentPage = next
    }

    /// Navigate to previous page
    func previousPage() {
        let previous = determinePreviousPage(from: currentPage)
        AppLogger.shared.log("🎯 [WizardStateMachine] Navigate: \(currentPage.rawValue) ← \(previous.rawValue)")
        currentPage = previous
    }

    /// Navigate to specific page
    func navigateTo(_ page: WizardPage) {
        AppLogger.shared.log("🎯 [WizardStateMachine] Navigate to: \(page.rawValue)")
        currentPage = page
    }

    // MARK: - Navigation Logic

    private func determineNextPage(from current: WizardPage, state: SystemSnapshot) -> WizardPage {
        // Simple linear flow with intelligent skipping
        switch current {
        case .summary:
            // Check for conflicts first
            if state.conflicts.hasConflicts {
                return .conflicts
            }
            // Then check KeyPath permissions
            if !state.permissions.keyPath.hasAllPermissions {
                return .inputMonitoring
            }
            // Then Kanata permissions
            if !state.permissions.kanata.hasAllPermissions {
                return .accessibility
            }
            // Then components
            if !state.components.hasAllRequired {
                return .karabinerComponents
            }
            // Finally service
            return .service

        case .fullDiskAccess:
            // FDA is optional, proceed to conflicts
            if state.conflicts.hasConflicts {
                return .conflicts
            }
            return .inputMonitoring

        case .conflicts:
            // After resolving conflicts, check permissions
            if !state.permissions.keyPath.hasAllPermissions {
                return .inputMonitoring
            }
            return .accessibility

        case .inputMonitoring:
            // KeyPath IM → KeyPath AX → Kanata permissions
            if !state.permissions.keyPath.accessibility.isReady {
                return .accessibility
            }
            if !state.permissions.kanata.hasAllPermissions {
                return .accessibility
            }
            return .karabinerComponents

        case .accessibility:
            // After permissions, check components
            if !state.components.hasAllRequired {
                return .karabinerComponents
            }
            return .service

        case .karabinerComponents:
            // After Karabiner, check Kanata
            return .kanataComponents

        case .kanataComponents:
            // After components, start service
            return .service

        case .communication:
            // Communication → Service
            return .service

        case .service:
            // Service is the last page
            return .service
        }
    }

    private func determinePreviousPage(from current: WizardPage) -> WizardPage {
        // Simple reverse navigation
        switch current {
        case .summary:
            return .summary // First page
        case .fullDiskAccess:
            return .summary
        case .conflicts:
            return .summary
        case .inputMonitoring:
            return .conflicts
        case .accessibility:
            return .inputMonitoring
        case .karabinerComponents:
            return .accessibility
        case .kanataComponents:
            return .karabinerComponents
        case .communication:
            return .kanataComponents
        case .service:
            return .communication
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
        return (refreshCount, lastRefreshStart)
    }
}
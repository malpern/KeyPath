import SwiftUI
import KeyPathCore
import KeyPathWizardCore
import KeyPathDaemonLifecycle

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
                AppLogger.shared.log("""
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

        AppLogger.shared.info("🔄 [WizardStateMachine] Refresh #\(myID) complete - ready=\(snapshot.isReady), issues=\(snapshot.blockingIssues.count)")
    }

    // MARK: - Navigation

    /// Navigate to next appropriate page based on system state
    func nextPage() {
        guard let snapshot = systemSnapshot else {
            AppLogger.shared.warn("⚠️ [WizardStateMachine] Cannot navigate - no system state")
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
        // NOTE: Helper ALWAYS checked first after summary (required for privileged operations)
        switch current {
        case .summary:
            // Check helper first - it's required for system operations
            if !state.helper.isReady {
                return .helper
            }
            // Then check for conflicts
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
            // All checks passed, go to service
            return .service

        case .helper:
            // After helper, check conflicts
            if state.conflicts.hasConflicts {
                return .conflicts
            }
            // Then permissions
            if !state.permissions.keyPath.hasAllPermissions {
                return .inputMonitoring
            }
            return .accessibility

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
            // After all components, go to service
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

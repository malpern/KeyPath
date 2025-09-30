import Foundation
@preconcurrency import Combine
import SwiftUI

/// Service that runs system validation checks silently at app startup
///
/// This service provides a lightweight way to validate system state without
/// showing the full wizard UI. It reuses the existing SystemStatusChecker
/// infrastructure to maintain consistency with the wizard's validation logic.
@MainActor
final class StartupValidator: ObservableObject {
    // MARK: - Published Properties

    @Published var validationState: ValidationState = .checking
    @Published var issues: [WizardIssue] = []
    @Published var lastValidationDate: Date?

    // MARK: - Validation State

    enum ValidationState: Equatable {
        case checking
        case success
        case failed(blockingCount: Int, totalCount: Int)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        var hasCriticalIssues: Bool {
            if case let .failed(blockingCount, _) = self, blockingCount > 0 { return true }
            return false
        }
    }

    // MARK: - Dependencies

    private weak var kanataManager: KanataManager?
    private var validationTask: Task<Void, Never>?
    private var currentRunID: UUID?
    private let minRevalidationInterval: TimeInterval = 2.0
    private var lastRunAt: Date?
    private var cancellables: Set<AnyCancellable> = []

    // Warmup window during which transient startup states remain as .checking
    private var warmupStart: Date = .init()
    private let warmupGraceWindow: TimeInterval = 3.0

    // MARK: - Initialization

    init() {
        AppLogger.shared.log("✅ [StartupValidator] Initialized")
    }

    deinit {
        validationTask?.cancel()
    }

    // MARK: - Configuration

    /// Configure the validator with the KanataManager dependency
    func configure(with kanataManager: KanataManager) {
        self.kanataManager = kanataManager
        AppLogger.shared.log("🔧 [StartupValidator] Configured with KanataManager")

        // Start warmup timer now
        warmupStart = Date()

        // REMOVED: Automatic revalidation listeners
        // Previously listened to:
        // - kanataManager.$isRunning → caused validation spam during startup
        // - kanataManager.$lastConfigUpdate → caused validation spam on config changes
        // - Oracle permission updates → caused validation spam on permission checks
        //
        // These were causing race conditions where multiple validations would fire rapidly
        // and cancel each other, leaving stale .checking states in the UI.
        //
        // Validation now only runs on:
        // 1. App launch (after service ready)
        // 2. Wizard close
        // 3. Manual refresh
        //
        // Oracle cache invalidation happens internally during those validations.
    }

    // MARK: - Validation Methods

    /// Perform startup validation asynchronously
    /// This is the main entry point that should be called during app launch
    /// - Parameter force: When true, bypasses the throttle and runs validation immediately
    func performStartupValidation(force: Bool = false) {
        // Cancel any existing validation
        validationTask?.cancel()

        // Throttle: if a recent run finished very recently, skip (unless forced)
        if !force, let last = lastRunAt, Date().timeIntervalSince(last) < minRevalidationInterval {
            AppLogger.shared.log("⏱️ [StartupValidator] Skipping validation (throttled)")
            return
        }

        // Reset state
        validationState = .checking
        issues = []

        let runID = UUID()
        currentRunID = runID
        let startupMode = ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1"
        AppLogger.shared.log("🔍 [StartupValidator] Starting system validation (runID: \(runID), startupMode: \(startupMode))")

        validationTask = Task { [weak self] in
            guard let self else { return }
            // Yield once to ensure UI updates (spinner appears) before heavy work
            await Task.yield()
            await runSystemValidation(runID: runID)
        }
    }

    /// Force refresh validation (can be called manually)
    /// - Parameter force: When true, bypasses throttle and runs now
    func refreshValidation(force: Bool = false) {
        performStartupValidation(force: force)
    }

    // MARK: - Private Implementation

    private func runSystemValidation(runID: UUID) async {
        guard let kanataManager else {
            AppLogger.shared.log("❌ [StartupValidator] No KanataManager configured; keeping state at .checking")
            // Do not mark as failed because dependency is not ready yet
            return
        }

        // CRITICAL: Wait for kanata service to be fully ready before validation
        // This prevents race conditions where UDP checks timeout during service warmup
        AppLogger.shared.log("⏳ [StartupValidator] Waiting for kanata service to be ready before validation...")
        let isReady = await kanataManager.waitForServiceReady(timeout: 10.0)

        if !isReady {
            AppLogger.shared.log("⏱️ [StartupValidator] Service did not become ready within timeout")
            // Continue with validation anyway to detect what's wrong
        } else {
            AppLogger.shared.log("✅ [StartupValidator] Service is ready, proceeding with validation")
        }

        // SystemStatusChecker is @MainActor, so it must run on main actor
        AppLogger.shared.log("🔍 [StartupValidator] Running comprehensive system detection (runID: \(runID))")
        let systemChecker = SystemStatusChecker.shared(kanataManager: kanataManager)

        // Get Oracle snapshot to log timing relationship
        let oracleSnapshot = await PermissionOracle.shared.currentSnapshot()
        AppLogger.shared.log("🔍 [StartupValidator] Oracle snapshot timestamp: \(oracleSnapshot.timestamp) (runID: \(runID))")

        let result = await systemChecker.detectCurrentState()

        // Check if this run is still valid
        guard !Task.isCancelled, runID == currentRunID else {
            AppLogger.shared.log("🚫 [StartupValidator] Outdated or cancelled run (runID: \(runID))")
            return
        }

        AppLogger.shared.log("🔍 [StartupValidator] System detection completed (runID: \(runID))")
        AppLogger.shared.log("🔍 [StartupValidator] Found \(result.issues.count) total issues")


        // Analyze results
        let criticalIssues = result.issues.filter { $0.severity == .critical }
        let errorIssues = result.issues.filter { $0.severity == .error }

        // Filter blocking issues to align with wizard UX design
        // Conflicts are resolvable and shouldn't block basic functionality
        let actuallyBlockingIssues = criticalIssues + errorIssues.filter { issue in
            switch issue.category {
            case .conflicts:
                return false // Conflicts are resolvable, not blocking
            case .permissions, .installation, .systemRequirements, .backgroundServices, .daemon:
                return true // These are truly blocking
            }
        }
        let blockingIssues = actuallyBlockingIssues

        AppLogger.shared.log("🔍 [StartupValidator] Critical issues: \(criticalIssues.count)")
        AppLogger.shared.log("🔍 [StartupValidator] Error issues: \(errorIssues.count)")
        let filteredConflictCount = (criticalIssues.count + errorIssues.count) - blockingIssues.count
        AppLogger.shared.log("🔍 [StartupValidator] Blocking issues: \(blockingIssues.count) (filtered \(filteredConflictCount) conflicts as non-blocking)")

        // Update state based on results
        updateValidationResults(
            issues: result.issues,
            blockingIssues: blockingIssues,
            conflictIssues: errorIssues.filter { $0.category == .conflicts },
            totalCount: result.issues.count
        )
        lastRunAt = Date()

        // Clear startup mode flag now that initial validation is complete
        // This re-enables full permission checks including IOHIDCheckAccess
        if ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1" {
            unsetenv("KEYPATH_STARTUP_MODE")
            AppLogger.shared.log("🔍 [StartupValidator] Startup mode cleared - full permission checks now enabled")

            // Invalidate Oracle cache to ensure fresh permission checks
            AppLogger.shared.log("🔍 [StartupValidator] Invalidating Oracle cache before second validation")
            await PermissionOracle.shared.invalidateCache()

            // Re-run validation with full permission checks now enabled
            AppLogger.shared.log("🔍 [StartupValidator] Re-running validation with full permission checks")
            Task {
                await runSystemValidation(runID: UUID())
            }
        }
    }

    @MainActor
    private func updateValidationResults(issues: [WizardIssue], blockingIssues: [WizardIssue], conflictIssues: [WizardIssue], totalCount: Int) {
        self.issues = issues
        lastValidationDate = Date()

        // Warmup grace: keep spinner during startup/transient states
        let withinWarmup = Date().timeIntervalSince(warmupStart) < warmupGraceWindow
        let isStarting = kanataManager?.currentState == .starting || (kanataManager?.isRunning == false)
        let onlyTransient = issues.allSatisfy { issue in
            switch issue.category {
            case .backgroundServices, .daemon, .systemRequirements: true
            case .permissions, .installation, .conflicts: false
            }
        }

        let blockingCount = blockingIssues.count

        // Apply wizard-consistent logic: system is healthy if Kanata is running AND no blocking issues
        let kanataIsRunning = kanataManager?.isRunning ?? false
        if kanataIsRunning && blockingCount == 0 {
            validationState = .success
            AppLogger.shared.log("✅ [StartupValidator] Validation successful - Kanata is running with no blocking issues")
            // Notify recovery if app not frontmost
            UserNotificationService.shared.notifyRecoverySucceeded("Kanata is running")
        } else if blockingCount == 0 {
            validationState = .success
            AppLogger.shared.log("✅ [StartupValidator] Validation successful - no blocking issues")
        } else if withinWarmup && isStarting && onlyTransient {
            validationState = .checking
            AppLogger.shared.log("⏳ [StartupValidator] Warmup grace → keeping spinner during startup transients")
            // Schedule a follow-up validation to flip to green automatically
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.performStartupValidation()
            }
        } else {
            validationState = .failed(blockingCount: blockingCount, totalCount: totalCount)
            AppLogger.shared.log("❌ [StartupValidator] Validation failed - \(blockingCount) blocking issues out of \(totalCount) total")
            // If there are blocking permission issues, surface as system notifications when backgrounded
            let missingPerms: [PermissionRequirement] = issues.compactMap { issue in
                if case let .permission(req) = issue.identifier { return req }
                return nil
            }
            if !missingPerms.isEmpty {
                UserNotificationService.shared.notifyPermissionRequired(missingPerms)
            }
        }

        // Log blocking issues for debugging (using same filtering logic)
        if blockingCount > 0 {
            for issue in blockingIssues.prefix(3) { // Log first 3 for brevity
                AppLogger.shared.log("❌ [StartupValidator] Blocking issue: \(issue.title) (category: \(issue.category), severity: \(issue.severity))")
            }
        }

        // Log filtered out conflict issues for debugging
        for conflict in conflictIssues.prefix(2) {
            AppLogger.shared.log("🔧 [StartupValidator] Filtered conflict (non-blocking): \(conflict.title)")
        }
    }

    @MainActor
    private func updateValidationState(_ newState: ValidationState) {
        validationState = newState
        lastValidationDate = Date()
    }

    // MARK: - Public Accessors

    /// Get a summary of critical issues for display purposes
    var criticalIssuesSummary: String {
        let criticalIssues = issues.filter { $0.severity == .critical || $0.severity == .error }

        guard !criticalIssues.isEmpty else {
            return "System is healthy"
        }

        if criticalIssues.count == 1 {
            return "1 critical issue detected"
        } else {
            return "\(criticalIssues.count) critical issues detected"
        }
    }

    /// Get tooltip text for the status indicator
    var statusTooltip: String {
        switch validationState {
        case .checking:
            "Checking system status..."
        case .success:
            "System is ready - all checks passed"
        case let .failed(blockingCount, totalCount):
            if blockingCount == 1 {
                "1 blocking issue found (click to fix)"
            } else if blockingCount > 1 {
                "\(blockingCount) blocking issues found (click to fix)"
            } else {
                "\(totalCount) minor issues found (click to review)"
            }
        }
    }

    /// Check if validation is currently running
    var isValidating: Bool {
        if case .checking = validationState { return true }
        return false
    }

    /// Get count of issues by severity for external use
    func getIssueCount(severity: WizardIssue.IssueSeverity) -> Int {
        issues.filter { $0.severity == severity }.count
    }
}

// MARK: - Extensions for Convenience

extension StartupValidator {
    /// Quick check if the system has any issues that would prevent KeyPath from working
    var hasBlockingIssues: Bool {
        validationState.hasCriticalIssues
    }

    /// Get the main status message for display
    var statusMessage: String {
        switch validationState {
        case .checking:
            "Checking..."
        case .success:
            "Ready"
        case let .failed(blockingCount, _):
            blockingCount > 0 ? "Issues Found" : "Warnings"
        }
    }
}

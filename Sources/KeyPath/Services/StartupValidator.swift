import Foundation
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
    }

    // MARK: - Validation Methods

    /// Perform startup validation asynchronously
    /// This is the main entry point that should be called during app launch
    func performStartupValidation() {
        // Cancel any existing validation
        validationTask?.cancel()

        // Throttle: if a recent run finished very recently, skip
        if let last = lastRunAt, Date().timeIntervalSince(last) < minRevalidationInterval {
            AppLogger.shared.log("⏱️ [StartupValidator] Skipping validation (throttled)")
            return
        }

        // Reset state
        validationState = .checking
        issues = []

        let runID = UUID()
        currentRunID = runID
        AppLogger.shared.log("🔍 [StartupValidator] Starting system validation (runID: \(runID))")

        validationTask = Task { [weak self] in
            guard let self else { return }
            // Yield once to ensure UI updates (spinner appears) before heavy work
            await Task.yield()
            await runSystemValidation(runID: runID)
        }
    }

    /// Force refresh validation (can be called manually)
    func refreshValidation() {
        performStartupValidation()
    }

    // MARK: - Private Implementation

    private func runSystemValidation(runID: UUID) async {
        guard let kanataManager else {
            AppLogger.shared.log("❌ [StartupValidator] No KanataManager configured; keeping state at .checking")
            // Do not mark as failed because dependency is not ready yet
            return
        }

        // SystemStatusChecker is @MainActor, so it must run on main actor
        AppLogger.shared.log("🔍 [StartupValidator] Running comprehensive system detection (runID: \(runID))")
        let systemChecker = SystemStatusChecker.shared(kanataManager: kanataManager)
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
        let blockingIssues = criticalIssues + errorIssues

        AppLogger.shared.log("🔍 [StartupValidator] Critical issues: \(criticalIssues.count)")
        AppLogger.shared.log("🔍 [StartupValidator] Error issues: \(errorIssues.count)")
        AppLogger.shared.log("🔍 [StartupValidator] Blocking issues: \(blockingIssues.count)")

        // Update state based on results
        updateValidationResults(
            issues: result.issues,
            blockingCount: blockingIssues.count,
            totalCount: result.issues.count
        )
        lastRunAt = Date()

        // Clear startup mode flag now that initial validation is complete
        // This re-enables full permission checks including IOHIDCheckAccess
        if ProcessInfo.processInfo.environment["KEYPATH_STARTUP_MODE"] == "1" {
            unsetenv("KEYPATH_STARTUP_MODE")
            AppLogger.shared.log("🔍 [StartupValidator] Startup mode cleared - full permission checks now enabled")

            // Re-run validation with full permission checks now enabled
            AppLogger.shared.log("🔍 [StartupValidator] Re-running validation with full permission checks")
            Task {
                await runSystemValidation(runID: UUID())
            }
        }
    }

    @MainActor
    private func updateValidationResults(issues: [WizardIssue], blockingCount: Int, totalCount: Int) {
        self.issues = issues
        lastValidationDate = Date()

        if blockingCount == 0 {
            validationState = .success
            AppLogger.shared.log("✅ [StartupValidator] Validation successful - no blocking issues")
        } else {
            validationState = .failed(blockingCount: blockingCount, totalCount: totalCount)
            AppLogger.shared.log("❌ [StartupValidator] Validation failed - \(blockingCount) blocking issues out of \(totalCount) total")
        }

        // Log blocking issues for debugging
        if blockingCount > 0 {
            let blockingIssuesList = issues.filter { $0.severity == .critical || $0.severity == .error }
            for issue in blockingIssuesList.prefix(3) { // Log first 3 for brevity
                AppLogger.shared.log("❌ [StartupValidator] Blocking issue: \(issue.title)")
            }
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

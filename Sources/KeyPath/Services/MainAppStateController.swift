import Foundation
import SwiftUI

/// Main app state controller using SystemValidator
///
/// Replaces StartupValidator with simpler, pull-based model using SystemValidator.
/// Key design:
/// - EXPLICIT validation only (no automatic reactivity)
/// - Single validation on app launch
/// - Manual refresh via user action
/// - SystemValidator defensive assertions active
@MainActor
class MainAppStateController: ObservableObject {
    // MARK: - Published State (Compatible with existing UI)

    @Published var validationState: ValidationState = .checking
    @Published var issues: [WizardIssue] = []
    @Published var lastValidationDate: Date?

    // MARK: - Validation State (compatible with StartupValidator)

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

    private var validator: SystemValidator?
    private weak var kanataManager: KanataManager?
    private var hasRunInitialValidation = false

    // MARK: - Initialization

    init() {
        AppLogger.shared.log("🎯 [MainAppStateController] Initialized (Phase 3)")
    }

    /// Configure with KanataManager (called after init)
    func configure(with kanataManager: KanataManager) {
        self.kanataManager = kanataManager

        // Create validator
        let processManager = ProcessLifecycleManager(kanataManager: kanataManager)
        self.validator = SystemValidator(
            processLifecycleManager: processManager,
            kanataManager: kanataManager
        )

        AppLogger.shared.log("🎯 [MainAppStateController] Configured with SystemValidator (Phase 3)")
    }

    // MARK: - Validation Methods

    /// Perform initial validation on app launch
    /// This is the ONLY automatic validation - runs once on launch
    func performInitialValidation() async {
        guard !hasRunInitialValidation else {
            AppLogger.shared.log("⚠️ [MainAppStateController] Initial validation already run")
            return
        }
        hasRunInitialValidation = true

        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [MainAppStateController] Cannot validate - not configured")
            return
        }

        AppLogger.shared.log("🎯 [MainAppStateController] Performing INITIAL validation (Phase 3)")

        // Set checking state
        validationState = .checking

        // Wait for services to be ready (same as StartupValidator)
        AppLogger.shared.log("⏳ [MainAppStateController] Waiting for kanata service to be ready...")
        let isReady = await kanataManager.waitForServiceReady(timeout: 10.0)

        if !isReady {
            AppLogger.shared.log("⏱️ [MainAppStateController] Service did not become ready within timeout")
        } else {
            AppLogger.shared.log("✅ [MainAppStateController] Service is ready, proceeding with validation")
        }

        // Run validation
        await performValidation()
    }

    /// Manual refresh (explicit user action only)
    func refreshValidation(force: Bool = false) async {
        AppLogger.shared.log("🔄 [MainAppStateController] Manual refresh requested (force: \(force))")
        await performValidation()
    }

    // MARK: - Private Implementation

    private func performValidation() async {
        guard let validator else {
            AppLogger.shared.log("⚠️ [MainAppStateController] Cannot validate - validator not configured")
            return
        }

        validationState = .checking

        AppLogger.shared.log("🎯 [MainAppStateController] Running SystemValidator (Phase 3)")

        // Get fresh state from validator (defensive assertions active)
        let snapshot = await validator.checkSystem()

        // Convert to old format for UI compatibility
        let result = SystemSnapshotAdapter.adapt(snapshot)

        // Update published state
        issues = result.issues
        lastValidationDate = Date()

        // Determine validation state
        let blockingIssues = result.issues.filter { issue in
            switch issue.category {
            case .conflicts:
                return false // Conflicts are resolvable, not blocking
            case .permissions, .installation, .systemRequirements, .backgroundServices, .daemon:
                return issue.severity == .critical || issue.severity == .error
            }
        }

        let kanataIsRunning = kanataManager?.isRunning ?? false

        if kanataIsRunning && blockingIssues.isEmpty {
            validationState = .success
            AppLogger.shared.log("✅ [MainAppStateController] Validation successful - Kanata running, no blocking issues")
        } else if blockingIssues.isEmpty {
            validationState = .success
            AppLogger.shared.log("✅ [MainAppStateController] Validation successful - no blocking issues")
        } else {
            validationState = .failed(blockingCount: blockingIssues.count, totalCount: result.issues.count)
            AppLogger.shared.log("❌ [MainAppStateController] Validation failed - \(blockingIssues.count) blocking issues")
        }
    }

    // MARK: - Public Accessors (Compatible with StartupValidator)

    /// Get tooltip text for status indicator
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

    /// Get status message for display
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

    /// Check if the system has blocking issues
    var hasBlockingIssues: Bool {
        validationState.hasCriticalIssues
    }

    /// Get critical issues summary
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

    /// Check if validation is currently running
    var isValidating: Bool {
        if case .checking = validationState { return true }
        return false
    }
}
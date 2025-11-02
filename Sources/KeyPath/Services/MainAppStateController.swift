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

    @Published var validationState: ValidationState? // nil = not yet validated, show nothing
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
        validator = SystemValidator(
            processLifecycleManager: processManager,
            kanataManager: kanataManager
        )

        AppLogger.shared.log("🎯 [MainAppStateController] Configured with SystemValidator (Phase 3)")
    }

    // MARK: - TCP Configuration Check

    /// Check if TCP communication is properly configured
    /// Matches wizard logic from WizardSystemStatusOverview.getCommunicationServerStatus()
    ///
    /// **SECURITY NOTE (ADR-013):** No authentication check needed.
    /// Kanata v1.9.0 TCP server does not support authentication.
    /// We only verify: (1) plist exists, (2) plist has --port argument
    private func checkTCPConfiguration() async -> Bool {
        // NOTE: Kanata v1.9.0 TCP does NOT require authentication
        // No token check needed - just verify service has TCP configuration

        // Check if the LaunchDaemon plist exists and has TCP configuration
        let plistPath = "/Library/LaunchDaemons/com.keypath.kanata.plist"
        let plistExists = FileManager.default.fileExists(atPath: plistPath)

        guard plistExists else {
            AppLogger.shared.log("⚠️ [MainAppStateController] TCP check failed: Service plist doesn't exist")
            return false
        }

        // Verify plist has TCP port argument
        if let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
           let args = plist["ProgramArguments"] as? [String] {
            let hasTCPPort = args.contains("--port")
            guard hasTCPPort else {
                AppLogger.shared.log("⚠️ [MainAppStateController] TCP check failed: Service missing --port argument")
                return false
            }
        } else {
            AppLogger.shared.log("⚠️ [MainAppStateController] TCP check failed: Can't read plist or parse arguments")
            return false
        }

        // All checks passed
        AppLogger.shared.log("✅ [MainAppStateController] TCP configuration verified: plist has --port")
        return true
    }

    // MARK: - Validation Methods

    /// Perform initial validation on app launch
    /// Can be called multiple times - first time waits for service, subsequent times validate immediately
    func performInitialValidation() async {
        guard let kanataManager else {
            AppLogger.shared.log("⚠️ [MainAppStateController] Cannot validate - not configured")
            return
        }

        let isFirstRun = !hasRunInitialValidation

        if isFirstRun {
            hasRunInitialValidation = true
            AppLogger.shared.log("🎯 [MainAppStateController] Performing INITIAL validation (Phase 3)")

            // Set checking state
            validationState = .checking

            // Wait for services to be ready (first time only)
            AppLogger.shared.log("⏳ [MainAppStateController] Waiting for kanata service to be ready...")
            let isReady = await kanataManager.waitForServiceReady(timeout: 10.0)

            if !isReady {
                AppLogger.shared.log("⏱️ [MainAppStateController] Service did not become ready within timeout")
            } else {
                AppLogger.shared.log("✅ [MainAppStateController] Service is ready, proceeding with validation")
            }

            // Clear startup mode flag now that services are ready
            // This ensures Oracle runs full permission checks for accurate results
            if FeatureFlags.shared.startupModeActive {
                FeatureFlags.shared.deactivateStartupMode()
                AppLogger.shared.log("🔍 [MainAppStateController] Cleared startup mode flag for accurate validation")

                // Invalidate Oracle cache so it runs fresh permission checks without startup mode
                await PermissionOracle.shared.invalidateCache()
                AppLogger.shared.log("🔍 [MainAppStateController] Invalidated Oracle cache to force fresh permission checks")
            }
        } else {
            AppLogger.shared.log("🔄 [MainAppStateController] Revalidation (skipping service wait)")
        }

        // Run validation (always)
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

        // 📊 LOG RAW SNAPSHOT DATA
        AppLogger.shared.log("📊 [MainAppStateController] === RAW SNAPSHOT DATA ===")
        AppLogger.shared.log("📊 [MainAppStateController] Timestamp: \(snapshot.timestamp)")
        AppLogger.shared.log("📊 [MainAppStateController] isReady: \(snapshot.isReady)")
        AppLogger.shared.log("📊 [MainAppStateController] Conflicts: \(snapshot.conflicts.hasConflicts)")
        AppLogger.shared.log("📊 [MainAppStateController] Health.kanataRunning: \(snapshot.health.kanataRunning)")
        AppLogger.shared.log("📊 [MainAppStateController] Health.daemonRunning: \(snapshot.health.karabinerDaemonRunning)")
        AppLogger.shared.log("📊 [MainAppStateController] Health.vhidHealthy: \(snapshot.health.vhidHealthy)")
        AppLogger.shared.log("📊 [MainAppStateController] Permissions.keyPath.IM.isReady: \(snapshot.permissions.keyPath.inputMonitoring.isReady)")
        AppLogger.shared.log("📊 [MainAppStateController] Permissions.keyPath.IM.isBlocking: \(snapshot.permissions.keyPath.inputMonitoring.isBlocking)")
        AppLogger.shared.log("📊 [MainAppStateController] Permissions.kanata.IM.isReady: \(snapshot.permissions.kanata.inputMonitoring.isReady)")
        AppLogger.shared.log("📊 [MainAppStateController] Permissions.kanata.IM.isBlocking: \(snapshot.permissions.kanata.inputMonitoring.isBlocking)")
        AppLogger.shared.log("📊 [MainAppStateController] Components.kanataBinary: \(snapshot.components.kanataBinaryInstalled)")
        AppLogger.shared.log("📊 [MainAppStateController] Components.vhidHealthy: \(snapshot.components.vhidDeviceHealthy)")
        AppLogger.shared.log("📊 [MainAppStateController] Components.daemonServicesHealthy: \(snapshot.components.launchDaemonServicesHealthy)")
        AppLogger.shared.log("📊 [MainAppStateController] Blocking issues: \(snapshot.blockingIssues.count)")

        // Convert to old format for UI compatibility
        let result = SystemSnapshotAdapter.adapt(snapshot)

        // 📊 LOG ADAPTER OUTPUT
        AppLogger.shared.log("📊 [MainAppStateController] === ADAPTER OUTPUT ===")
        AppLogger.shared.log("📊 [MainAppStateController] Adapter state: \(result.state)")
        AppLogger.shared.log("📊 [MainAppStateController] Adapter issues count: \(result.issues.count)")
        for (index, issue) in result.issues.enumerated() {
            AppLogger.shared.log("📊 [MainAppStateController]   Issue \(index + 1): [\(issue.severity)] \(issue.title) - \(issue.description)")
        }

        // Update published state
        issues = result.issues
        lastValidationDate = Date()

        // Determine validation state
        let blockingIssues = result.issues.filter { issue in
            switch issue.category {
            case .conflicts:
                false // Conflicts are resolvable, not blocking
            case .permissions, .installation, .systemRequirements, .backgroundServices, .daemon:
                issue.severity == .critical || issue.severity == .error
            }
        }

        AppLogger.shared.log("📊 [MainAppStateController] === VALIDATION DECISION ===")
        AppLogger.shared.log("📊 [MainAppStateController] Blocking issues after filter: \(blockingIssues.count)")
        for (index, issue) in blockingIssues.enumerated() {
            AppLogger.shared.log("📊 [MainAppStateController]   Blocking \(index + 1): [\(issue.category)] \(issue.title)")
        }

        let kanataIsRunning = kanataManager?.isRunning ?? false
        AppLogger.shared.log("📊 [MainAppStateController] kanataManager.isRunning: \(kanataIsRunning)")

        // ⭐ Check blocking issues EVEN when adapter says .active
        // This ensures main screen status matches wizard component status
        switch result.state {
        case .active:
            // Kanata is running - but check if there are blocking issues that prevent proper operation
            // Also verify TCP communication is properly configured (matches wizard logic)
            let tcpConfigured = await checkTCPConfiguration()

            if blockingIssues.isEmpty, tcpConfigured {
                validationState = .success
                AppLogger.shared.log("✅ [MainAppStateController] Validation SUCCESS - adapter state is .active (kanata running), no blocking issues, TCP configured")
            } else {
                var reasons: [String] = []
                if !blockingIssues.isEmpty {
                    reasons.append("\(blockingIssues.count) blocking issues")
                }
                if !tcpConfigured {
                    reasons.append("TCP communication not configured")
                }

                validationState = .failed(blockingCount: blockingIssues.count + (tcpConfigured ? 0 : 1), totalCount: result.issues.count)
                AppLogger.shared.log("❌ [MainAppStateController] Validation FAILED - \(reasons.joined(separator: ", "))")
                for (index, issue) in blockingIssues.enumerated() {
                    AppLogger.shared.log("   Blocking \(index + 1): \(issue.title)")
                }
                if !tcpConfigured {
                    AppLogger.shared.log("   TCP: Communication server not properly configured")
                }
            }

        case .ready:
            // Everything ready but not running
            validationState = .success
            AppLogger.shared.log("✅ [MainAppStateController] Validation SUCCESS - adapter state is .ready")

        case .initializing, .serviceNotRunning, .daemonNotRunning:
            // Service not running but could be starting
            if blockingIssues.isEmpty {
                validationState = .success
                AppLogger.shared.log("✅ [MainAppStateController] Validation SUCCESS - no blocking issues")
            } else {
                validationState = .failed(blockingCount: blockingIssues.count, totalCount: result.issues.count)
                AppLogger.shared.log("❌ [MainAppStateController] Validation FAILED - \(blockingIssues.count) blocking issues")
            }

        case .conflictsDetected, .missingPermissions, .missingComponents:
            // Definite problems that need fixing
            validationState = .failed(blockingCount: blockingIssues.count, totalCount: result.issues.count)
            AppLogger.shared.log("❌ [MainAppStateController] Validation FAILED - adapter state: \(result.state)")
            for issue in blockingIssues {
                AppLogger.shared.log("❌ [MainAppStateController]   - \(issue.title): \(issue.description)")
            }
        }
    }

    // MARK: - Public Accessors (Compatible with StartupValidator)

    /// Get tooltip text for status indicator
    var statusTooltip: String {
        guard let state = validationState else {
            return "System status not yet checked"
        }
        switch state {
        case .checking:
            return "Checking system status..."
        case .success:
            return "System is ready - all checks passed"
        case let .failed(blockingCount, totalCount):
            if blockingCount == 1 {
                return "1 blocking issue found (click to fix)"
            } else if blockingCount > 1 {
                return "\(blockingCount) blocking issues found (click to fix)"
            } else {
                return "\(totalCount) minor issues found (click to review)"
            }
        }
    }

    /// Get status message for display
    var statusMessage: String {
        guard let state = validationState else {
            return ""
        }
        switch state {
        case .checking:
            return "Checking..."
        case .success:
            return "Ready"
        case let .failed(blockingCount, _):
            return blockingCount > 0 ? "Issues Found" : "Warnings"
        }
    }

    /// Check if the system has blocking issues
    var hasBlockingIssues: Bool {
        validationState?.hasCriticalIssues ?? false
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

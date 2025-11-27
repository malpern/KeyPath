import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathPermissions
import KeyPathWizardCore
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
    // MARK: - Shared Instance

    static let shared = MainAppStateController()

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
    private weak var kanataManager: RuntimeCoordinator?
    private var hasRunInitialValidation = false

    // MARK: - Validation Cooldown (Optimization: Skip redundant validations on rapid restarts)

    private var lastValidationTime: Date?
    private let validationCooldown: TimeInterval = 30.0 // Skip validation if completed within last 30 seconds

    // MARK: - Initialization

    init() {
        AppLogger.shared.log("🎯 [MainAppStateController] Initialized (Phase 3)")
    }

    /// Configure with RuntimeCoordinator (called after init)
    func configure(with kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager

        // Create validator
        let processManager = ProcessLifecycleManager()
        validator = SystemValidator(
            processLifecycleManager: processManager,
            kanataManager: kanataManager
        )

        AppLogger.shared.log("🎯 [MainAppStateController] Configured with SystemValidator (Phase 3)")

        // Check for orphaned installation (leftover files from manual deletion)
        OrphanDetector.shared.checkForOrphans()
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

        // Check SMAppService plist first if active, otherwise fall back to legacy plist
        let plistPath = KanataDaemonManager.getActivePlistPath()

        let plistExists = FileManager.default.fileExists(atPath: plistPath)

        guard plistExists else {
            AppLogger.shared.warn(
                "⚠️ [MainAppStateController] TCP check failed: Service plist doesn't exist at \(plistPath)")
            return false
        }

        // Verify plist has TCP port argument
        if let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
           let plist = try? PropertyListSerialization.propertyList(
               from: plistData, options: [], format: nil
           ) as? [String: Any],
           let args = plist["ProgramArguments"] as? [String] {
            let hasTCPPort = args.contains("--port")
            guard hasTCPPort else {
                AppLogger.shared.warn(
                    "⚠️ [MainAppStateController] TCP check failed: Service missing --port argument")
                return false
            }
        } else {
            AppLogger.shared.warn(
                "⚠️ [MainAppStateController] TCP check failed: Can't read plist or parse arguments")
            return false
        }

        // All checks passed
        AppLogger.shared.info("✅ [MainAppStateController] TCP configuration verified: plist has --port")
        return true
    }

    // MARK: - Validation Methods

    /// Perform initial validation on app launch
    /// Can be called multiple times - first time waits for service, subsequent times validate immediately
    /// Optimization: Skips validation if completed within cooldown period (30s) to avoid redundant work on rapid restarts
    func performInitialValidation() async {
        guard kanataManager != nil else {
            AppLogger.shared.warn("⚠️ [MainAppStateController] Cannot validate - not configured")
            return
        }

        // Optimization: Skip validation if recently completed (prevents redundant work on rapid restarts)
        if let lastTime = lastValidationTime,
           Date().timeIntervalSince(lastTime) < validationCooldown {
            let timeSince = Int(Date().timeIntervalSince(lastTime))
            AppLogger.shared.log(
                "⏭️ [MainAppStateController] Skipping validation - completed \(timeSince)s ago (cooldown: \(Int(validationCooldown))s)"
            )
            return
        }

        let isFirstRun = !hasRunInitialValidation

        if isFirstRun {
            hasRunInitialValidation = true
            AppLogger.shared.log("🎯 [MainAppStateController] Performing INITIAL validation (Phase 3)")

            let firstRunStart = Date()

            // Wait for services to be ready (first time only)
            // Optimized: Reduced timeout from 10s to 3s, fast process check added
            // NOTE: Don't show spinner during service wait - only show during actual validation
            AppLogger.shared.log("⏳ [MainAppStateController] Waiting for kanata service to be ready...")
            AppLogger.shared.log("⏱️ [TIMING] Service wait START")
            let serviceWaitStart = Date()

            // Legacy waitForServiceReady removed.
            // We accept the current state as-is.
            let isReady = true

            let serviceWaitDuration = Date().timeIntervalSince(serviceWaitStart)
            AppLogger.shared.log(
                "⏱️ [TIMING] Service wait COMPLETE: \(String(format: "%.3f", serviceWaitDuration))s (ready: \(isReady))"
            )
            AppLogger.shared.log(
                "⏱️ [MainAppStateController] Service wait completed in \(String(format: "%.3f", serviceWaitDuration))s (ready: \(isReady))"
            )

            AppLogger.shared.info(
                "✅ [MainAppStateController] Service is ready, proceeding with validation")

            // Clear startup mode flag now that services are ready
            // This ensures Oracle runs full permission checks for accurate results
            let cacheStart = Date()
            AppLogger.shared.log("⏱️ [TIMING] Cache operations START")
            if FeatureFlags.shared.startupModeActive {
                FeatureFlags.shared.deactivateStartupMode()
                AppLogger.shared.log(
                    "🔍 [MainAppStateController] Cleared startup mode flag for accurate validation")

                // Invalidate Oracle cache so it runs fresh permission checks without startup mode
                await PermissionOracle.shared.invalidateCache()
                AppLogger.shared.debug(
                    "🔍 [MainAppStateController] Invalidated Oracle cache to force fresh permission checks")
            }
            let cacheDuration = Date().timeIntervalSince(cacheStart)
            if cacheDuration > 0.01 {
                AppLogger.shared.log(
                    "⏱️ [TIMING] Cache operations COMPLETE: \(String(format: "%.3f", cacheDuration))s")
                AppLogger.shared.log(
                    "⏱️ [MainAppStateController] Cache operations completed in \(String(format: "%.3f", cacheDuration))s"
                )
            } else {
                AppLogger.shared.log(
                    "⏱️ [TIMING] Cache operations COMPLETE: \(String(format: "%.3f", cacheDuration))s (skipped)"
                )
            }

            let firstRunDuration = Date().timeIntervalSince(firstRunStart)
            AppLogger.shared.log(
                "⏱️ [TIMING] First-run overhead COMPLETE: \(String(format: "%.3f", firstRunDuration))s (service wait + cache)"
            )
            AppLogger.shared.log(
                "⏱️ [MainAppStateController] First-run overhead: \(String(format: "%.3f", firstRunDuration))s (service wait + cache)"
            )
        } else {
            AppLogger.shared.info("🔄 [MainAppStateController] Revalidation (skipping service wait)")
        }

        // Set checking state ONLY when we're about to start actual validation
        // This prevents showing spinner during service wait (which is a background operation)
        validationState = .checking

        // Run validation (always)
        await performValidation()
    }

    /// Manual refresh (explicit user action only)
    /// If force=true, bypasses cooldown and always validates
    func refreshValidation(force: Bool = false) async {
        AppLogger.shared.info("🔄 [MainAppStateController] Manual refresh requested (force: \(force))")
        if force {
            // Force refresh: clear cooldown
            lastValidationTime = nil
            AppLogger.shared.log("🔄 [MainAppStateController] Force refresh - cooldown cleared")
        }
        await performValidation()
    }

    /// Invalidate validation cooldown (call when system state may have changed externally)
    /// Called automatically when wizard closes to ensure fresh validation after setup changes
    func invalidateValidationCooldown() {
        lastValidationTime = nil
        AppLogger.shared.log("🔄 [MainAppStateController] Validation cooldown invalidated")
    }

    /// Force a fresh validation immediately (clears cooldown and runs)
    func revalidate() async {
        AppLogger.shared.log("🔄 [MainAppStateController] Revalidate requested - clearing cooldown")
        lastValidationTime = nil
        await performValidation()
    }

    // MARK: - Private Implementation

    private func performValidation() async {
        guard let validator else {
            AppLogger.shared.warn("⚠️ [MainAppStateController] Cannot validate - validator not configured")
            return
        }

        // Check service status with startup grace period
        // Give Kanata up to 3 seconds to finish starting before reporting an error
        let startupGracePeriod: TimeInterval = 3.0
        let checkInterval: TimeInterval = 0.5
        let maxChecks = Int(startupGracePeriod / checkInterval)

        var serviceStatus = await InstallerEngine().getServiceStatus()
        var checksPerformed = 0

        while !serviceStatus.kanataServiceHealthy, checksPerformed < maxChecks {
            checksPerformed += 1
            AppLogger.shared.debug(
                "⏳ [MainAppStateController] Waiting for Kanata service... (\(checksPerformed)/\(maxChecks))")
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            serviceStatus = await InstallerEngine().getServiceStatus()
        }

        if !serviceStatus.kanataServiceHealthy {
            AppLogger.shared.warn(
                "⚠️ [MainAppStateController] Kanata service not healthy after \(startupGracePeriod)s - showing error state")
            // Set failed state so System indicator shows red X instead of spinning forever
            validationState = .failed(blockingCount: 1, totalCount: 1)
            issues = [WizardIssue(
                identifier: .component(.kanataService),
                severity: .error,
                category: .daemon,
                title: "Kanata service not running",
                description: "The Kanata service failed to start or is not healthy.",
                autoFixAction: .restartUnhealthyServices,
                userAction: "Click System to open the setup wizard and diagnose the issue."
            )]
            return
        }

        validationState = .checking

        let validationStart = Date()
        AppLogger.shared.log("🎯 [MainAppStateController] Running SystemValidator (Phase 3)")
        AppLogger.shared.log("⏱️ [TIMING] Main screen validation START")

        // Get fresh state from validator (defensive assertions active)
        // Note: Main screen doesn't use progress callback (wizard does)
        let snapshot = await validator.checkSystem()

        let validationDuration = Date().timeIntervalSince(validationStart)
        AppLogger.shared.log(
            "⏱️ [TIMING] Main screen validation COMPLETE: \(String(format: "%.3f", validationDuration))s")
        AppLogger.shared.log(
            "⏱️ [MainAppStateController] Validation completed in \(String(format: "%.3f", validationDuration))s"
        )

        // 📊 LOG RAW SNAPSHOT DATA
        AppLogger.shared.debug("📊 [MainAppStateController] === RAW SNAPSHOT DATA ===")
        AppLogger.shared.debug("📊 [MainAppStateController] Timestamp: \(snapshot.timestamp)")
        AppLogger.shared.debug("📊 [MainAppStateController] isReady: \(snapshot.isReady)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Conflicts: \(snapshot.conflicts.hasConflicts)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Health.kanataRunning: \(snapshot.health.kanataRunning)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Health.daemonRunning: \(snapshot.health.karabinerDaemonRunning)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Health.vhidHealthy: \(snapshot.health.vhidHealthy)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Permissions.keyPath.IM.isReady: \(snapshot.permissions.keyPath.inputMonitoring.isReady)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Permissions.keyPath.IM.isBlocking: \(snapshot.permissions.keyPath.inputMonitoring.isBlocking)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Permissions.kanata.IM.isReady: \(snapshot.permissions.kanata.inputMonitoring.isReady)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Permissions.kanata.IM.isBlocking: \(snapshot.permissions.kanata.inputMonitoring.isBlocking)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Components.kanataBinary: \(snapshot.components.kanataBinaryInstalled)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Components.vhidHealthy: \(snapshot.components.vhidDeviceHealthy)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Components.daemonServicesHealthy: \(snapshot.components.launchDaemonServicesHealthy)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Blocking issues: \(snapshot.blockingIssues.count)")

        // Adapt to wizard-style issues/state using existing adapter (keeps UI expectations stable)
        let context = SystemContext(
            permissions: snapshot.permissions,
            services: snapshot.health,
            conflicts: snapshot.conflicts,
            components: snapshot.components,
            helper: snapshot.helper,
            system: EngineSystemInfo(
                macOSVersion: SystemRequirements().getSystemInfo().macosVersion.versionString,
                driverCompatible: true // compatibility already validated in snapshot path
            ),
            timestamp: snapshot.timestamp
        )
        let adapted = SystemContextAdapter.adapt(context)

        // Update published state
        issues = adapted.issues
        lastValidationDate = Date()
        lastValidationTime = Date() // Track for cooldown optimization

        // Determine validation state
        let blockingIssues = issues.filter { issue in
            switch issue.category {
            case .conflicts:
                false // Conflicts are resolvable, not blocking
            case .permissions, .installation, .systemRequirements, .backgroundServices, .daemon:
                issue.severity == .critical || issue.severity == .error
            }
        }

        AppLogger.shared.debug("📊 [MainAppStateController] === VALIDATION DECISION ===")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Blocking issues after filter: \(blockingIssues.count)")
        for (index, issue) in blockingIssues.enumerated() {
            AppLogger.shared.debug(
                "📊 [MainAppStateController]   Blocking \(index + 1): [\(issue.category)] \(issue.title)")
        }

        // ⭐ Check blocking issues EVEN when Kanata is running to keep UI honest
        switch adapted.state {
        case .active:
            // Kanata is running - but check if there are blocking issues that prevent proper operation
            // Also verify TCP communication is properly configured (matches wizard logic)
            let tcpConfigured = await checkTCPConfiguration()

            if blockingIssues.isEmpty, tcpConfigured {
                validationState = .success
                AppLogger.shared.info(
                    "✅ [MainAppStateController] Validation SUCCESS - adapter state is .active (kanata running), no blocking issues, TCP configured"
                )
            } else {
                var reasons: [String] = []
                if !blockingIssues.isEmpty {
                    reasons.append("\(blockingIssues.count) blocking issues")
                }
                if !tcpConfigured {
                    reasons.append("TCP communication not configured")
                }

                validationState = .failed(
                    blockingCount: blockingIssues.count + (tcpConfigured ? 0 : 1),
                    totalCount: issues.count
                )
                AppLogger.shared.error(
                    "❌ [MainAppStateController] Validation FAILED - \(reasons.joined(separator: ", "))")
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
            AppLogger.shared.info(
                "✅ [MainAppStateController] Validation SUCCESS - adapter state is .ready")

        case .initializing, .serviceNotRunning, .daemonNotRunning:
            // Service not running but could be starting
            if blockingIssues.isEmpty {
                validationState = .success
                AppLogger.shared.info("✅ [MainAppStateController] Validation SUCCESS - no blocking issues")
            } else {
                validationState = .failed(
                    blockingCount: blockingIssues.count, totalCount: issues.count
                )
                AppLogger.shared.error(
                    "❌ [MainAppStateController] Validation FAILED - \(blockingIssues.count) blocking issues")
            }

        case .conflictsDetected, .missingPermissions, .missingComponents:
            // Definite problems that need fixing
            validationState = .failed(
                blockingCount: blockingIssues.count, totalCount: issues.count
            )
            AppLogger.shared.error(
                "❌ [MainAppStateController] Validation FAILED - adapter state: \(adapted.state)")
            for issue in blockingIssues {
                AppLogger.shared.error(
                    "❌ [MainAppStateController]   - \(issue.title): \(issue.description)")
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

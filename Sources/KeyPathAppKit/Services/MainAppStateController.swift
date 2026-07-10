import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import Observation

/// Main app state controller using SystemValidator
///
/// Replaces StartupValidator with simpler, pull-based model using SystemValidator.
/// Key design:
/// - EXPLICIT validation only (no automatic reactivity)
/// - Single validation on app launch
/// - Manual refresh via user action
/// - SystemValidator defensive assertions active
@MainActor
@Observable
class MainAppStateController {
    // MARK: - Shared Instance

    static let shared = MainAppStateController()

    // MARK: - Published State (Compatible with existing UI)

    var validationState: ValidationState? // nil = not yet validated, show nothing
    var issues: [WizardIssue] = []
    var lastValidationDate: Date?
    /// Latest validated system context — consumed by Settings Status tab and other UI surfaces.
    private(set) var lastValidatedSystemContext: SystemContext?
    /// Adapted wizard state from the last validation — consumed by Settings Status tab.
    private(set) var lastAdaptedState: WizardSystemState = .initializing
    /// TCP configuration status from the last validation — consumed by Settings Status tab.
    private(set) var lastTCPConfigured: Bool?
    /// Latest shared installer state-matrix row — consumed by CLI/status/menu surfaces.
    var lastInstallerStateMatrixRow: InstallerStateMatrixRow?
    /// Latest shared installer state-matrix plan — consumed by CLI/status/menu surfaces.
    var lastInstallerStateMatrixPlan: [InstallerStateMatrixAction] = []

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

    @ObservationIgnored private var validator: SystemValidator?
    @ObservationIgnored private weak var serviceLifecycle: ServiceLifecycleCoordinator?
    @ObservationIgnored private var onSystemHealthy: (() -> Void)?
    @ObservationIgnored private var hasRunInitialValidation = false

    /// Returns true if configure() has been called.
    /// Use this to assert initialization order invariants.
    var isConfigured: Bool {
        validator != nil
    }

    // MARK: - Validation Cooldown (Optimization: Skip redundant validations on rapid restarts)

    @ObservationIgnored private var lastValidationTime: Date?
    @ObservationIgnored private let validationCooldown: TimeInterval = 30.0 // Skip validation if completed within last 30 seconds

    // MARK: - Validation Log Throttling (avoid flooding the log with repeat cycles)

    /// The distinct log sites that dedup repeat-failure logging. A closed enum
    /// (rather than free-form strings) so a typo at a call site is a compile
    /// error instead of a silently-orphaned dedup bucket.
    private enum ValidationLogSite: Hashable {
        case startupGate
        case validationFailure
    }

    /// Per-log-site dedup state: maps a log site to the signature last logged
    /// in full and how many times it has repeated unchanged since. When an
    /// unchanged failure repeats across periodic revalidation cycles, only the
    /// first occurrence is logged at full WARN/ERROR verbosity; repeats are
    /// collapsed into a single low-noise line. This does not change validation
    /// behavior — only what gets written to the log. See #934 (122 cycles of
    /// WARN+5×ERROR in 9 minutes filled and rotated the 5MB log mid-session).
    @ObservationIgnored private var loggedFailureSignatures: [ValidationLogSite: (signature: String, repeatCount: Int)] = [:]

    /// Returns true if this failure signature should be logged at full verbosity
    /// (first occurrence at this site, or a change from the previously logged
    /// signature at this site). Also updates the per-site repeat counter.
    private func shouldLogValidationFailureInDetail(site: ValidationLogSite, signature: String) -> Bool {
        if let existing = loggedFailureSignatures[site], existing.signature == signature {
            loggedFailureSignatures[site] = (signature, existing.repeatCount + 1)
            return false
        }
        loggedFailureSignatures[site] = (signature, 0)
        return true
    }

    /// Current repeat count for a log site (0 if this is the first occurrence).
    private func repeatCount(forSite site: ValidationLogSite) -> Int {
        loggedFailureSignatures[site]?.repeatCount ?? 0
    }

    /// Reset failure-signature dedup state once validation succeeds again.
    private func resetValidationFailureLogState() {
        loggedFailureSignatures.removeAll()
    }

    // MARK: - Service Health Monitoring (Fix for stale overlay state)

    @ObservationIgnored private var errorDetectionTask: Task<Void, Never>?
    @ObservationIgnored private var lastKnownRuntimeHealthy: Bool?
    @ObservationIgnored private var serviceHealthTask: Task<Void, Never>?
    @ObservationIgnored private var periodicRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let definitiveStartupGracePeriod: TimeInterval = 3.0
    @ObservationIgnored private let transientStartupGracePeriod: TimeInterval =
        RuntimeStartupTiming.gatePollingWindow
    @ObservationIgnored private let startupCheckInterval: TimeInterval = 0.5

    #if DEBUG
        @ObservationIgnored private var startupGateHealthOverride:
            (() async -> KanataHealthSnapshot)?
        @ObservationIgnored private var startupGateTransientWindowOverride:
            (() async -> Bool)?
        @ObservationIgnored private var startupGateTimingOverride:
            (definitiveGrace: TimeInterval, transientGrace: TimeInterval, checkInterval: TimeInterval)?

        func configureStartupGateTestingState(
            healthOverride: (() async -> KanataHealthSnapshot)? = nil,
            transientWindowOverride: (() async -> Bool)? = nil,
            timingOverride: (
                definitiveGrace: TimeInterval,
                transientGrace: TimeInterval,
                checkInterval: TimeInterval
            )? = nil
        ) {
            startupGateHealthOverride = healthOverride
            startupGateTransientWindowOverride = transientWindowOverride
            startupGateTimingOverride = timingOverride
        }

        func resetStartupGateTestingState() {
            startupGateHealthOverride = nil
            startupGateTransientWindowOverride = nil
            startupGateTimingOverride = nil
        }
    #endif

    // MARK: - Initialization

    init() {
        AppLogger.shared.log("🎯 [MainAppStateController] Initialized (Phase 3)")
    }

    // NOTE: No deinit needed - this is a singleton that lives for the app's lifetime.
    // Cleanup would be impossible anyway since deinit is nonisolated and can't access
    // MainActor-isolated properties like task handles.

    /// Inject the shared SystemValidator instance (called from configureWizardDependencies).
    func setValidator(_ shared: SystemValidator) {
        validator = shared
    }

    /// Configure with the specific sub-coordinators needed (not the full RuntimeCoordinator).
    func configure(
        serviceLifecycle: ServiceLifecycleCoordinator,
        onSystemHealthy: @escaping () -> Void
    ) {
        self.serviceLifecycle = serviceLifecycle
        self.onSystemHealthy = onSystemHealthy

        AppLogger.shared.log("🎯 [MainAppStateController] Configured (Phase 3)")

        // Check for orphaned installation (leftover files from manual deletion)
        OrphanDetector.shared.checkForOrphans()

        // Start service health monitoring to fix stale overlay state
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug(
                "🧪 [MainAppStateController] Skipping background monitoring setup in test mode"
            )
        } else {
            subscribeToServiceHealth()
            subscribeToErrorDetection()
            startPeriodicRefresh()
        }
    }

    /// Subscribe to KanataErrorMonitor crash detection to trigger immediate revalidation.
    /// This ensures crashes are detected even if service state hasn't transitioned yet.
    private func subscribeToErrorDetection() {
        errorDetectionTask?.cancel()
        errorDetectionTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .kanataErrorDetected) {
                guard let self, !Task.isCancelled else { break }

                // Log crash for later analysis
                if let error = notification.object as? KanataError {
                    logCrashEvent(error)

                    // Critical errors should bypass cooldown and revalidate immediately
                    if error.severity == .critical {
                        AppLogger.shared.error(
                            "🚨 [MainAppStateController] Critical error detected - triggering immediate revalidation"
                        )
                        await revalidate()
                    }
                }
            }
        }

        AppLogger.shared.log("🔔 [MainAppStateController] Subscribed to crash/error detection")
    }

    /// Log crash events to persistent storage for later analysis.
    /// Crashes are logged to ~/Library/Logs/KeyPath/crashes.log
    /// (redirected to a temp sandbox during tests via AppPaths).
    private func logCrashEvent(_ error: KanataError) {
        let crashLogDir = AppPaths.logsDirectory
        let crashLogPath = AppPaths.crashLogFile

        // Ensure directory exists
        do {
            try Foundation.FileManager().createDirectory(at: crashLogDir, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.warn("⚠️ [MainAppStateController] Failed to create crash log directory: \(error.localizedDescription)")
        }

        // Format crash entry
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: error.timestamp)

        let entry = """
        [\(timestamp)] [\(error.severity.rawValue.uppercased())] \(error.message)
        Pattern: \(error.pattern ?? "unknown")
        Raw: \(error.rawLine)
        ---

        """

        // Append to log file
        if let data = entry.data(using: .utf8) {
            do {
                if Foundation.FileManager().fileExists(atPath: crashLogPath.path) {
                    let handle = try FileHandle(forWritingTo: crashLogPath)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: crashLogPath)
                }
            } catch {
                AppLogger.shared.warn("⚠️ [MainAppStateController] Failed to write crash log: \(error.localizedDescription)")
            }
        }

        AppLogger.shared.error(
            "💥 [CrashLog] Logged crash event: \(error.severity.rawValue) - \(error.message)"
        )
    }

    // MARK: - Service Health Monitoring

    /// Subscribe to runtime state changes to trigger revalidation when runtime health changes.
    /// This fixes the "System Not Ready" stale state bug where the overlay shows stale state.
    private func subscribeToServiceHealth() {
        guard let serviceLifecycle else { return }

        // Cancel any previous polling task to prevent duplicate loops
        serviceHealthTask?.cancel()

        // Poll runtime status for health transitions.
        serviceHealthTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let runtimeStatus = await serviceLifecycle.currentRuntimeStatus()
                let isHealthy = runtimeStatus.isRunning
                let wasHealthy = lastKnownRuntimeHealthy

                if wasHealthy != isHealthy {
                    lastKnownRuntimeHealthy = isHealthy
                    AppLogger.shared.log(
                        "🔄 [MainAppStateController] Runtime health changed: \(wasHealthy.map { String($0) } ?? "nil") → \(isHealthy)"
                    )
                    await revalidate()
                }

                // VHID safety invariant: if kanata is running but VirtualHID daemon
                // is not healthy, emergency-stop kanata to release the keyboard.
                // W3 safety exception: this background mutation only stops remapping
                // to prevent unsafe keyboard capture; it must not perform repair.
                if isHealthy {
                    let vhidHealthy = await ServiceHealthChecker.shared.isServiceHealthy(
                        serviceID: ServiceHealthChecker.vhidDaemonServiceID
                    )
                    if VHIDSafetyCheck.shouldEmergencyStop(
                        kanataRunning: true, vhidDaemonHealthy: vhidHealthy
                    ) {
                        AppLogger.shared.error(
                            "🚨 [MainAppStateController] SAFETY: Kanata running without VirtualHID daemon — emergency stop"
                        )
                        await serviceLifecycle.stopKanata(reason: "Emergency: VirtualHID not running")
                    }
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }

        AppLogger.shared.log("🔄 [MainAppStateController] Subscribed to runtime health changes")
    }

    /// Start periodic background refresh (60s) as a fallback for cases where service state
    /// doesn't change but validation becomes stale.
    private func startPeriodicRefresh() {
        periodicRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60)) // 60 seconds
                guard let self, !Task.isCancelled else { break }

                // Only refresh if validation is stale (>30s since last check)
                if let lastTime = lastValidationTime,
                   Date().timeIntervalSince(lastTime) > 30
                {
                    AppLogger.shared.log("🔄 [MainAppStateController] Periodic refresh triggered (stale state)")
                    await revalidate()
                }
            }
        }

        AppLogger.shared.log("🔄 [MainAppStateController] Started periodic health refresh (60s)")
    }

    // MARK: - Validation Methods

    /// Perform initial validation on app launch
    /// Can be called multiple times - first time waits for service, subsequent times validate immediately
    /// Optimization: Skips validation if completed within cooldown period (30s) to avoid redundant work on rapid restarts
    func performInitialValidation() async {
        guard serviceLifecycle != nil else {
            AppLogger.shared.warnUnlessQuietTest("⚠️ [MainAppStateController] Cannot validate - not configured")
            return
        }

        // Optimization: Skip validation if recently completed (prevents redundant work on rapid restarts)
        if let lastTime = lastValidationTime,
           Date().timeIntervalSince(lastTime) < validationCooldown
        {
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
            AppLogger.shared.log("⏳ [MainAppStateController] Waiting for KeyPath runtime to be ready...")
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
                "✅ [MainAppStateController] Service is ready, proceeding with validation"
            )

            // Clear startup mode flag now that services are ready
            if FeatureFlags.shared.startupModeActive {
                FeatureFlags.shared.deactivateStartupMode()
                AppLogger.shared.log(
                    "🔍 [MainAppStateController] Cleared startup mode flag"
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
            validator?.invalidateCaches()
            AppLogger.shared.log("🔄 [MainAppStateController] Force refresh - cooldown cleared")
        }
        await performValidation()
    }

    /// Invalidate validation cooldown (call when system state may have changed externally)
    /// Called automatically when wizard closes to ensure fresh validation after setup changes
    func invalidateValidationCooldown() {
        lastValidationTime = nil
        validator?.invalidateCaches()
        AppLogger.shared.log("🔄 [MainAppStateController] Validation cooldown invalidated")
    }

    /// Force a fresh validation immediately (clears cooldown and runs)
    func revalidate() async {
        AppLogger.shared.log("🔄 [MainAppStateController] Revalidate requested - clearing cooldown")
        lastValidationTime = nil
        validator?.invalidateCaches()
        await performValidation()
    }

    // MARK: - Private Implementation

    private enum KanataStartupGateResult {
        case ready
        case transientTimeout
        case definitiveFailure
    }

    private func performValidation() async {
        guard let validator else {
            AppLogger.shared.warnUnlessQuietTest("⚠️ [MainAppStateController] Cannot validate - validator not configured")
            validationState = .checking
            issues = []
            lastValidationDate = Date()
            lastValidationTime = Date()
            return
        }

        switch await evaluateKanataStartupGate() {
        case .ready:
            break
        case .transientTimeout:
            if shouldLogValidationFailureInDetail(site: .startupGate, signature: "transientTimeout") {
                AppLogger.shared.warn(
                    "⚠️ [MainAppStateController] Kanata still in transient startup window after \(Int(transientStartupGracePeriod))s - continuing with full validation to avoid false failure"
                )
            } else {
                // Use .info (not .debug) so this remains visible in release-build logs —
                // .debug is below the release default minimum level and would otherwise
                // vanish entirely, defeating "check logs first" debugging (#934).
                AppLogger.shared.info(
                    "⚠️ [MainAppStateController] Kanata still in transient startup window (repeat #\(repeatCount(forSite: .startupGate)), suppressing detailed log)"
                )
            }
        case .definitiveFailure:
            if shouldLogValidationFailureInDetail(site: .startupGate, signature: "definitiveFailure") {
                AppLogger.shared.warn(
                    "⚠️ [MainAppStateController] Kanata service not healthy after \(definitiveStartupGracePeriod)s outside restart window - proceeding with full validation"
                )
            } else {
                AppLogger.shared.info(
                    "⚠️ [MainAppStateController] Kanata still not healthy outside restart window (repeat #\(repeatCount(forSite: .startupGate)), suppressing detailed log)"
                )
            }
        }

        validationState = .checking

        let validationStart = Date()
        AppLogger.shared.log("🎯 [MainAppStateController] Running SystemValidator (Phase 3)")
        AppLogger.shared.log("⏱️ [TIMING] Main screen validation START")

        // SystemValidator owns the canonical capture timeout so every consumer
        // receives the same first-class `.timedOut` snapshot evidence.
        AppLogger.shared.log("🔍 [MainAppStateController] Canonical validation run started")
        let snapshot = await validator.checkSystem()

        let validationDuration = Date().timeIntervalSince(validationStart)
        AppLogger.shared.log(
            "⏱️ [TIMING] Main screen validation COMPLETE: \(String(format: "%.3f", validationDuration))s"
        )
        AppLogger.shared.log(
            "⏱️ [MainAppStateController] Validation completed in \(String(format: "%.3f", validationDuration))s"
        )

        // 📊 LOG RAW SNAPSHOT DATA
        AppLogger.shared.debug("📊 [MainAppStateController] === RAW SNAPSHOT DATA ===")
        AppLogger.shared.debug("📊 [MainAppStateController] Timestamp: \(snapshot.timestamp)")
        AppLogger.shared.debug("📊 [MainAppStateController] isReady: \(snapshot.isReady)")
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Conflicts: \(snapshot.conflicts.hasConflicts)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Health.kanataRunning: \(snapshot.health.kanataRunning)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Health.daemonRunning: \(snapshot.health.karabinerDaemonRunning)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Health.vhidHealthy: \(snapshot.health.vhidHealthy)"
        )
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
            "📊 [MainAppStateController] Components.vhidHealthy: \(snapshot.components.vhidDeviceHealthy)"
        )
        AppLogger.shared.debug(
            "📊 [MainAppStateController] Blocking issues: \(snapshot.blockingIssues.count)"
        )

        // Project the canonical context into wizard presentation state.
        let context = SystemContext(snapshot: snapshot)
        let adapted = SystemStateResult.projecting(context)

        // Update published state
        lastValidatedSystemContext = context
        lastAdaptedState = adapted.state
        lastTCPConfigured = snapshot.health.kanataTCPConfigured ?? false
        let decision = InstallerDecisionPipeline.decide(for: .repair, context: context)
        lastInstallerStateMatrixRow = decision.assessment
        lastInstallerStateMatrixPlan = decision.matrixActions
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
            "📊 [MainAppStateController] Blocking issues after filter: \(blockingIssues.count)"
        )
        for (index, issue) in blockingIssues.enumerated() {
            AppLogger.shared.debug(
                "📊 [MainAppStateController]   Blocking \(index + 1): [\(issue.category)] \(issue.title)"
            )
        }

        // ⭐ Check blocking issues EVEN when Kanata is running to keep UI honest
        switch adapted.state {
        case .active:
            // Kanata is running - but check if there are blocking issues that prevent proper operation
            let tcpConfigured = lastTCPConfigured ?? false

            if blockingIssues.isEmpty, tcpConfigured {
                validationState = .success
                // Clear stale diagnostics when system is healthy
                onSystemHealthy?()
                resetValidationFailureLogState()
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
                let signature = "active:\(reasons.joined(separator: ",")):\(blockingIssues.map(\.title).joined(separator: ","))"
                if shouldLogValidationFailureInDetail(site: .validationFailure, signature: signature) {
                    AppLogger.shared.error(
                        "❌ [MainAppStateController] Validation FAILED - \(reasons.joined(separator: ", "))"
                    )
                    for (index, issue) in blockingIssues.enumerated() {
                        AppLogger.shared.log("   Blocking \(index + 1): \(issue.title)")
                    }
                    if !tcpConfigured {
                        AppLogger.shared.log("   TCP: Communication server not properly configured")
                    }
                } else {
                    // .info, not .debug: repeat failures must stay visible in release-build
                    // logs (.debug is below the release default minimum level) so "check
                    // logs first" debugging still works, just without the full ERROR block
                    // re-emitted every cycle (#934).
                    AppLogger.shared.info(
                        "❌ [MainAppStateController] Validation still FAILED - \(reasons.joined(separator: ", ")) (repeat #\(repeatCount(forSite: .validationFailure)), suppressing detailed log)"
                    )
                }
            }

        case .ready:
            // Everything ready but not running
            validationState = .success
            // Clear stale diagnostics when system is healthy
            onSystemHealthy?()
            resetValidationFailureLogState()
            AppLogger.shared.info(
                "✅ [MainAppStateController] Validation SUCCESS - adapter state is .ready"
            )

        case .initializing, .serviceNotRunning, .daemonNotRunning:
            // Service not running but could be starting
            if blockingIssues.isEmpty {
                validationState = .success
                // Clear stale diagnostics when system is healthy
                onSystemHealthy?()
                resetValidationFailureLogState()
                AppLogger.shared.info("✅ [MainAppStateController] Validation SUCCESS - no blocking issues")
            } else {
                validationState = .failed(
                    blockingCount: blockingIssues.count, totalCount: issues.count
                )
                let signature = "notRunning:\(blockingIssues.map(\.title).joined(separator: ","))"
                if shouldLogValidationFailureInDetail(site: .validationFailure, signature: signature) {
                    AppLogger.shared.error(
                        "❌ [MainAppStateController] Validation FAILED - \(blockingIssues.count) blocking issues"
                    )
                } else {
                    AppLogger.shared.info(
                        "❌ [MainAppStateController] Validation still FAILED - \(blockingIssues.count) blocking issues (repeat #\(repeatCount(forSite: .validationFailure)), suppressing detailed log)"
                    )
                }
            }

        case .conflictsDetected, .missingPermissions, .missingComponents:
            // Definite problems that need fixing
            validationState = .failed(
                blockingCount: blockingIssues.count, totalCount: issues.count
            )
            let signature = "\(adapted.state):\(blockingIssues.map(\.title).joined(separator: ","))"
            if shouldLogValidationFailureInDetail(site: .validationFailure, signature: signature) {
                AppLogger.shared.error(
                    "❌ [MainAppStateController] Validation FAILED - adapter state: \(adapted.state)"
                )
                for issue in blockingIssues {
                    AppLogger.shared.error(
                        "❌ [MainAppStateController]   - \(issue.title): \(issue.description)"
                    )
                }
            } else {
                AppLogger.shared.info(
                    "❌ [MainAppStateController] Validation still FAILED - adapter state: \(adapted.state) (repeat #\(repeatCount(forSite: .validationFailure)), \(blockingIssues.count) blocking issues, suppressing detailed log)"
                )
            }
        }

        // Unified grace period: suppress failures during startup window so all
        // consumers (overlay, Settings, wizard) see .checking instead of .failed.
        if case .failed = validationState, await isInRuntimeStartupWindow() {
            AppLogger.shared.info(
                "⏳ [MainAppStateController] Suppressing .failed → .checking (startup grace window)"
            )
            validationState = .checking
        }
    }

    private func evaluateKanataStartupGate() async -> KanataStartupGateResult {
        let timing = startupGateTiming()
        let start = Date()
        let definitiveDeadline = start.addingTimeInterval(timing.definitiveGrace)
        let transientDeadline = start.addingTimeInterval(timing.transientGrace)
        var checks = 0

        while Date() < transientDeadline {
            let health = await currentKanataStartupHealth()
            let isReady = health.isReady
            if isReady {
                if checks > 0 {
                    AppLogger.shared.log(
                        "✅ [MainAppStateController] Kanata became healthy after \(checks) startup checks"
                    )
                }
                return .ready
            }

            let inTransientWindow = await isInKanataTransientStartupWindow()
            if !inTransientWindow, Date() >= definitiveDeadline {
                return .definitiveFailure
            }

            checks += 1
            AppLogger.shared.debug(
                "⏳ [MainAppStateController] Waiting for Kanata service (\(checks)) transient=\(inTransientWindow), running=\(health.isRunning), responding=\(health.isResponding), inputCaptureReady=\(health.inputCaptureReady)"
            )
            try? await Task.sleep(for: .seconds(timing.checkInterval))
        }

        return .transientTimeout
    }

    private func startupGateTiming()
        -> (definitiveGrace: TimeInterval, transientGrace: TimeInterval, checkInterval: TimeInterval)
    {
        #if DEBUG
            if let override = startupGateTimingOverride {
                return override
            }
        #endif
        return (
            definitiveGrace: definitiveStartupGracePeriod,
            transientGrace: transientStartupGracePeriod,
            checkInterval: startupCheckInterval
        )
    }

    private func currentKanataStartupHealth() async -> KanataHealthSnapshot {
        #if DEBUG
            if let override = startupGateHealthOverride {
                return await override()
            }
        #endif
        return await InstallerEngine().checkKanataServiceHealth()
    }

    /// Whether the runtime is inside the UI grace period that suppresses
    /// alarming "not running" states during startup. Exposed so surfaces
    /// like the overlay health indicator can downgrade a transient failure
    /// to a "checking" state instead of showing "1 Issue".
    func isInRuntimeStartupWindow() async -> Bool {
        await serviceLifecycle?.isInTransientRuntimeStartupWindow() ?? false
    }

    private func isInKanataTransientStartupWindow() async -> Bool {
        #if DEBUG
            if let override = startupGateTransientWindowOverride {
                return await override()
            }
        #endif

        let recentlyRestarted = ServiceBootstrapper.wasRecentlyRestarted(
            ServiceHealthChecker.kanataServiceID,
            within: startupGateTiming().transientGrace
        )
        if recentlyRestarted {
            return true
        }

        let managementState = await KanataDaemonManager.shared.refreshManagementStateInternal()
        return managementState == .smappservicePending
    }

    #if DEBUG
        func evaluateKanataStartupGateForTesting() async -> Bool {
            await evaluateKanataStartupGate() == .ready
        }
    #endif

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

    /// Shared health policy for compact status surfaces.
    ///
    /// Prefer the executable state-matrix row once validation has produced it.
    /// Before the first matrix classification exists, preserve the legacy
    /// validation-state behavior so startup UI does not pessimistically flip red.
    var menuBarSystemHealthy: Bool {
        if let lastInstallerStateMatrixRow {
            return lastInstallerStateMatrixRow == .runningAndTCPResponding
        }
        return (validationState?.isSuccess ?? true) && issues.isEmpty
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

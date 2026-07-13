import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import os.lock
import ServiceManagement

extension RuntimeIdentity {
    static func expectedKeyPathKanata(buildVersion: String = BuildInfo.current().build) -> RuntimeIdentity {
        RuntimeIdentity(
            programIdentifier: KanataRuntimeHost.launcherBundleRelativePath,
            parentBundleIdentifier: KeyPathConstants.Bundle.bundleID,
            parentBundleVersion: buildVersion
        )
    }
}

/// Stateless system validation service
///
/// This replaces StartupValidator + SystemStatusChecker with a single, simple validator.
/// Key design principles:
/// - STATELESS: No @Published properties, no cached results
/// - PULL-BASED: UI explicitly calls checkSystem() when it wants state
/// - NO SIDE EFFECTS: Only inspects system, doesn't change anything
/// - DEFENSIVE: Assertions catch validation spam and other bugs
///
/// The Oracle already has its own 1.5s cache, so we don't need another cache layer.
@MainActor
public class SystemValidator {
    // MARK: - Validation Spam Detection

    /// Track active validations to detect spam (concurrent validations)
    private static var activeValidations = 0

    /// Per-instance validation task - prevents concurrent validations for this instance
    private var inProgressValidation: Task<SystemSnapshot, Never>?
    private var latestSnapshot: SystemSnapshot?
    private static let canonicalSnapshotCacheTTL: TimeInterval = 1.5
    static let canonicalCaptureTimeout: TimeInterval = 12

    /// Track validation timing to detect rapid-fire calls (indicates automatic triggers)
    private static var lastValidationStart: Date?
    private static var validationCount = 0
    /// In test mode, only the "owner" instance contributes to the global counters to prevent cross-test interference.
    private static var countingOwner: ObjectIdentifier?
    // REMOVED: TestGate serialization was causing deadlocks when multiple tests run concurrently.
    // Validation operations are already safe for concurrent execution (async/await, no shared mutable state).

    // MARK: - Dependencies

    // NOTE: launchDaemonInstaller removed - health checks migrated to ServiceHealthChecker
    private let vhidDeviceManager: VHIDDeviceManager
    private let systemStateProvider: SystemStateProvider
    private let conflictDetector: () async throws -> ProcessLifecycleManager.ConflictResolution
    private weak var kanataManager: RuntimeCoordinator?
    private var cachedComponentFacts: ComponentInstallationFacts?

    private struct ComponentInstallationFacts: Sendable {
        let kanataBinaryInstalled: Bool
        let requiredRuntimePayloadPresent: Bool
        let vhidInstalled: Bool
        let vhidVersionMismatch: Bool
        let karabinerDriverExtensionEnabled: Bool
        let vhidDaemonPlistMisconfigured: Bool
        let timestamp: Date

        func isFresh(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    private struct HelperCaptureEvidence: Sendable {
        let status: HelperStatus
        let captureStatus: SystemSnapshotCaptureStatus
    }

    init(
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        processLifecycleManager: ProcessLifecycleManager,
        systemStateProvider: SystemStateProvider = .shared,
        kanataManager: RuntimeCoordinator? = nil,
        conflictDetector: (() async throws -> ProcessLifecycleManager.ConflictResolution)? = nil
    ) {
        self.vhidDeviceManager = vhidDeviceManager
        self.systemStateProvider = systemStateProvider
        self.kanataManager = kanataManager
        self.conflictDetector = conflictDetector ?? {
            try await processLifecycleManager.detectConflicts()
        }

        AppLogger.shared.log("🔍 [SystemValidator] Initialized (stateless, no cache)")

        // In tests, designate the first validator created after resetCounters() as the counting owner
        if TestEnvironment.isRunningTests, Self.countingOwner == nil {
            Self.countingOwner = ObjectIdentifier(self)
        }
    }

    // MARK: - Main Validation Method

    /// Check complete system state
    /// This is the ONLY public method - returns fresh state every time
    ///
    /// If validation is already in progress, this will wait for it to complete
    /// rather than starting a concurrent validation. This prevents validation spam
    /// when multiple UI components request validation simultaneously.
    ///
    /// - Parameter progressCallback: Optional callback that receives progress updates (0.0 to 1.0)
    func checkSystem(progressCallback: @escaping @Sendable (Double) -> Void = { _ in }) async
        -> SystemSnapshot
    {
        // Fast path for tests - return stub immediately without any system calls
        // This dramatically speeds up tests that don't need real system state
        // Use KEYPATH_FORCE_REAL_VALIDATION=1 to override in specific tests
        if TestEnvironment.isRunningTests,
           ProcessInfo.processInfo.environment["KEYPATH_FORCE_REAL_VALIDATION"] != "1"
        {
            AppLogger.shared.log("🧪 [SystemValidator] Test mode - returning stub snapshot")
            progressCallback(1.0)
            let snapshot = Self.makeTestSnapshot()
            cacheIfComplete(snapshot)
            return snapshot
        }

        // If validation is already in progress, wait for it
        if let inProgress = inProgressValidation {
            AppLogger.shared.log(
                "🔍 [SystemValidator] Validation already in progress - waiting for result"
            )
            let snapshot = await inProgress.value
            cacheIfComplete(snapshot)
            return snapshot
        }

        // Start new validation
        let validationTask = Task<SystemSnapshot, Never> { @MainActor in
            await Self.boundedCapture(timeout: Self.canonicalCaptureTimeout) {
                await self.performValidation(progressCallback: progressCallback)
            }
        }

        inProgressValidation = validationTask
        defer { inProgressValidation = nil }

        let snapshot = await validationTask.value
        cacheIfComplete(snapshot)
        return snapshot
    }

    static func boundedCapture(
        timeout: TimeInterval,
        operation: @MainActor @Sendable @escaping () async -> SystemSnapshot
    ) async -> SystemSnapshot {
        let completionState = SystemCaptureCompletionState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completionState.setContinuation(continuation)

                let operationTask = Task { @MainActor in
                    let snapshot = await operation()
                    _ = completionState.complete(with: snapshot)
                }
                completionState.setOperationTask(operationTask)

                let timeoutTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                    } catch {
                        return
                    }
                    let didTimeOut = completionState.complete(with: .unavailable(
                        captureStatus: .timedOut,
                        source: "system-validator-timeout"
                    ))
                    if didTimeOut {
                        let message = "⏱️ [SystemValidator] Canonical capture timed out after \(String(format: "%.2f", timeout))s"
                        if TestEnvironment.isRunningTests {
                            AppLogger.shared.info(message)
                        } else {
                            AppLogger.shared.warn(message)
                        }
                    }
                }
                completionState.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            _ = completionState.complete(with: .unavailable(
                captureStatus: .cancelled,
                source: "system-validator-cancelled"
            ))
        }
    }

    func checkSystem(
        freshness: WizardSystemSnapshotFreshness,
        progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> SystemSnapshot {
        if freshness == .cached,
           let latestSnapshot,
           latestSnapshot.captureStatus.isComplete,
           Date().timeIntervalSince(latestSnapshot.timestamp) <= Self.canonicalSnapshotCacheTTL
        {
            AppLogger.shared.log("🔍 [SystemValidator] Reusing recent canonical snapshot")
            progressCallback(1.0)
            return latestSnapshot
        }

        if freshness == .fresh {
            invalidateCaches()
        }

        return await checkSystem(progressCallback: progressCallback)
    }

    public func invalidateCaches() {
        latestSnapshot = nil
        cachedComponentFacts = nil
        ServiceHealthChecker.shared.invalidateHealthCache()
    }

    private func cacheIfComplete(_ snapshot: SystemSnapshot) {
        guard snapshot.captureStatus.isComplete else { return }
        latestSnapshot = snapshot
    }

    /// Perform the actual validation work
    /// This is called by checkSystem() and should not be called directly
    private func performValidation(progressCallback: @escaping @Sendable (Double) -> Void = { _ in })
        async -> SystemSnapshot
    {
        // Run validations in parallel - safe for concurrent execution
        await performValidationBody(progressCallback: progressCallback)
    }

    private func performValidationBody(
        progressCallback: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> SystemSnapshot {
        // If cancelled before we start, return a minimal snapshot without mutating counters
        if Task.isCancelled {
            return Self.makeCancelledSnapshot()
        }
        Self.activeValidations += 1
        defer { Self.activeValidations -= 1 }

        // Respect cancellation before counting
        if Task.isCancelled { return Self.makeCancelledSnapshot() }
        // Only count owner in tests to avoid cross-test interference
        if !TestEnvironment.isRunningTests || Self.countingOwner == ObjectIdentifier(self) {
            Self.validationCount += 1
        }
        let myID = Self.validationCount

        // 🚨 DEFENSIVE WARNING: Detect rapid-fire validations (indicates automatic triggers)
        if let lastStart = Self.lastValidationStart {
            let interval = Date().timeIntervalSince(lastStart)
            if interval < 0.5 {
                AppLogger.shared.log(
                    """
                    ⚠️ [SystemValidator] RAPID VALIDATION: \(String(format: "%.3f", interval))s since last validation
                    This might indicate automatic triggers. Expected: manual user actions only.
                    """
                )
            }
        }
        Self.lastValidationStart = Date()

        let startTime = Date()
        AppLogger.shared.log("🔍 [SystemValidator] Starting validation #\(myID)")
        let compatibilityResult = SystemRequirements().validateSystemCompatibility()
        let compatibility = SystemCompatibilityStatus(
            macOSVersion: compatibilityResult.macosVersion.versionString,
            driverCompatible: compatibilityResult.isCompatible
        )

        // Check system state in parallel for maximum performance
        // All checks are independent - no dependencies between them
        progressCallback(0.0) // Start: 0%

        // Track completion count for incremental progress updates
        let progressLock = OSAllocatedUnfairLock(initialState: 0)
        let totalSteps = 5.0
        // Capture progressCallback in a nonisolated closure
        let callback = progressCallback
        let updateProgress = { @Sendable (_: Int) in
            let completed = progressLock.withLock { (count: inout Int) -> Int in
                count += 1
                return count
            }
            let progress = Double(completed) / totalSteps
            callback(progress)
            AppLogger.shared.log(
                "📊 [SystemValidator] Progress: \(Int(progress * 100))% (\(completed)/\(Int(totalSteps)) steps)"
            )
        }

        // Track start times for individual step timing
        let helperStart = Date()
        let permissionsStart = Date()
        let componentsStart = Date()
        let conflictsStart = Date()
        let healthStart = Date()

        // Log validation start with structured timing marker
        AppLogger.shared.log(
            "⏱️ [TIMING] Validation #\(myID) START: \(String(format: "%.3f", startTime.timeIntervalSince1970))"
        )

        // Run all checks in parallel, tracking progress as each completes
        // Use a Sendable enum to wrap results
        enum ValidationResult: Sendable {
            case helper(HelperCaptureEvidence)
            case permissions(PermissionOracle.Snapshot)
            case components(ComponentStatus)
            case conflicts(ConflictCaptureEvidence)
            case health(HealthStatus)
        }

        let (helper, permissions, components, conflicts, health) = await withTaskGroup(
            of: ValidationResult.self
        ) { group in
            var helperResult: HelperCaptureEvidence?
            var permissionsResult: PermissionOracle.Snapshot?
            var componentsResult: ComponentStatus?
            var conflictsResult: ConflictCaptureEvidence?
            var healthResult: HealthStatus?

            // Add all tasks to group with progress tracking
            // Log at TASK START (before any async work) to detect scheduling issues
            group.addTask {
                AppLogger.shared.log("🚀 [SystemValidator] Task 1 (Helper) STARTED")
                let start = helperStart
                let result = await self.checkHelper()
                let duration = Date().timeIntervalSince(start)
                AppLogger.shared.log(
                    "⏱️ [TIMING] Step 1 (Helper) completed in \(String(format: "%.3f", duration))s"
                )
                updateProgress(1)
                return .helper(result)
            }
            group.addTask {
                AppLogger.shared.log("🚀 [SystemValidator] Task 2 (Permissions) STARTED")
                let start = permissionsStart
                let result = await self.checkPermissions()
                let duration = Date().timeIntervalSince(start)
                AppLogger.shared.log(
                    "⏱️ [TIMING] Step 2 (Permissions) completed in \(String(format: "%.3f", duration))s"
                )
                updateProgress(2)
                return .permissions(result)
            }
            group.addTask {
                AppLogger.shared.log("🚀 [SystemValidator] Task 3 (Components) STARTED")
                let start = componentsStart
                let result = await self.checkComponents()
                let duration = Date().timeIntervalSince(start)
                AppLogger.shared.log(
                    "⏱️ [TIMING] Step 3 (Components) completed in \(String(format: "%.3f", duration))s"
                )
                updateProgress(3)
                return .components(result)
            }
            group.addTask {
                AppLogger.shared.log("🚀 [SystemValidator] Task 4 (Conflicts) STARTED")
                let start = conflictsStart
                let result = await self.checkConflicts()
                let duration = Date().timeIntervalSince(start)
                AppLogger.shared.log(
                    "⏱️ [TIMING] Step 4 (Conflicts) completed in \(String(format: "%.3f", duration))s"
                )
                updateProgress(4)
                return .conflicts(result)
            }
            group.addTask {
                AppLogger.shared.log("🚀 [SystemValidator] Task 5 (Health) STARTED")
                let start = healthStart
                let result = await self.checkHealth()
                let duration = Date().timeIntervalSince(start)
                AppLogger.shared.log(
                    "⏱️ [TIMING] Step 5 (Health) completed in \(String(format: "%.3f", duration))s"
                )
                updateProgress(5)
                return .health(result)
            }
            AppLogger.shared.log("📋 [SystemValidator] All 5 tasks added to TaskGroup")

            // Collect results as they complete
            for await result in group {
                switch result {
                case let .helper(value): helperResult = value
                case let .permissions(value): permissionsResult = value
                case let .components(value): componentsResult = value
                case let .conflicts(value): conflictsResult = value
                case let .health(value): healthResult = value
                }
            }

            // Extract results with fallback values if cast fails
            return (
                helperResult ?? HelperCaptureEvidence(
                    status: .empty,
                    captureStatus: .failed
                ),
                permissionsResult
                    ?? {
                        let now = Date()
                        let defaultSet = PermissionOracle.PermissionSet(
                            accessibility: .unknown,
                            inputMonitoring: .unknown,
                            source: "fallback",
                            confidence: .low,
                            timestamp: now
                        )
                        return PermissionOracle.Snapshot(
                            keyPath: defaultSet,
                            kanata: defaultSet,
                            timestamp: now
                        )
                    }(),
                componentsResult ?? ComponentStatus.empty,
                conflictsResult ?? ConflictCaptureEvidence(
                    status: .empty,
                    captureStatus: .failed
                ),
                healthResult ?? HealthStatus.empty
            )
        }

        let helperStatus = helper.status
        let conflictStatus = conflicts.status
        let captureStatus = Self.combinedCaptureStatus([
            helper.captureStatus,
            conflicts.captureStatus,
        ])

        progressCallback(1.0) // All done: 100%

        let totalDuration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log(
            "⏱️ [TIMING] Validation #\(myID) COMPLETE: Total duration \(String(format: "%.3f", totalDuration))s"
        )

        let snapshot = SystemSnapshot(
            permissions: permissions,
            components: components,
            conflicts: conflictStatus,
            health: health,
            helper: helperStatus,
            compatibility: compatibility,
            timestamp: Date(),
            captureStatus: captureStatus
        )

        let duration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log(
            "🔍 [SystemValidator] Validation #\(myID) complete in \(String(format: "%.3f", duration))s"
        )
        AppLogger.shared.log(
            "🔍 [SystemValidator] Result: ready=\(snapshot.isReady), blocking=\(snapshot.blockingIssues.count), total=\(snapshot.allIssues.count)"
        )

        // 🚨 DEFENSIVE ASSERTION: Verify snapshot is fresh
        snapshot.validate()

        return snapshot
    }

    static func combinedCaptureStatus(
        _ statuses: [SystemSnapshotCaptureStatus]
    ) -> SystemSnapshotCaptureStatus {
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.cancelled) { return .cancelled }
        if statuses.contains(.timedOut) { return .timedOut }
        return .complete
    }

    // MARK: - Helper Checking

    private func checkHelper() async -> HelperCaptureEvidence {
        AppLogger.shared.log("🔍 [SystemValidator] Checking privileged helper")

        let health = await HelperManager.shared.getHelperHealth()

        switch health {
        case .notInstalled:
            AppLogger.shared.log("🔍 [SystemValidator] Helper state: notInstalled")
            return HelperCaptureEvidence(
                status: HelperStatus(isInstalled: false, version: nil, isWorking: false),
                captureStatus: .complete
            )

        case let .requiresApproval(reason):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state: requiresApproval \(reason ?? "")"
            )
            return HelperCaptureEvidence(
                status: HelperStatus(
                    isInstalled: false,
                    version: nil,
                    isWorking: false,
                    requiresApproval: true
                ),
                captureStatus: .complete
            )

        case let .registeredButUnresponsive(reason):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state: registeredButUnresponsive \(reason ?? "")"
            )
            return HelperCaptureEvidence(
                status: HelperStatus(isInstalled: true, version: nil, isWorking: false),
                captureStatus: .complete
            )

        case let .temporarilyUnavailable(reason):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state temporarily unknown: \(reason ?? "")"
            )
            return HelperCaptureEvidence(
                status: HelperStatus(isInstalled: true, version: nil, isWorking: false),
                captureStatus: .timedOut
            )

        case let .healthy(version):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state: healthy (v\(version ?? "unknown"))"
            )
            return HelperCaptureEvidence(
                status: HelperStatus(isInstalled: true, version: version, isWorking: true),
                captureStatus: .complete
            )
        }
    }

    // MARK: - Permission Checking

    private func checkPermissions() async -> PermissionOracle.Snapshot {
        AppLogger.shared.log("🔍 [SystemValidator] Checking permissions via Oracle")

        // PermissionOracle has its own 1.5s cache - SystemStateProvider centralizes access.
        let snapshot = await SystemStateProvider.shared.currentPermissionSnapshot()

        // 🚨 DEFENSIVE CHECK: Oracle snapshot should be fresh.
        // Originally an `assert` that crashed in debug builds, but under real
        // concurrent load (multiple SMAppService.status IPC calls queued up)
        // the snapshot can legitimately take > 5s to return — the Oracle
        // cache isn't broken, the system is just slow. Log and continue.
        let oracleAge = Date().timeIntervalSince(snapshot.timestamp)
        if oracleAge >= 5.0 {
            AppLogger.shared.log(
                "⚠️ [SystemValidator] Oracle snapshot is \(String(format: "%.1f", oracleAge))s old — likely SMAppService IPC contention, not a cache bug"
            )
        }

        AppLogger.shared.log(
            "🔍 [SystemValidator] Oracle snapshot: ready=\(snapshot.isSystemReady), age=\(String(format: "%.3f", oracleAge))s"
        )

        return snapshot
    }

    // MARK: - Component Checking

    // ⚠️ CONCURRENCY HAZARD: This method runs in a TaskGroup alongside checkHealth().
    // DO NOT call detectConnectionHealth() here - it uses pgrep with 500ms retry sleeps,
    // and concurrent pgrep calls can hang. Use launchctl-based checks from ServiceHealthChecker.
    // See: git log for "concurrent pgrep" fix, November 2024
    private func checkComponents() async -> ComponentStatus {
        AppLogger.shared.log("🔍 [SystemValidator] Checking components")

        let facts = await componentInstallationFacts()

        // Check LaunchDaemon services via ServiceHealthChecker FIRST
        // This uses launchctl (fast) and provides VHID health, avoiding duplicate pgrep calls
        // that could contend with checkHealth()'s detectConnectionHealth() call
        let daemonStatusStart = Date()
        let daemonStatus = await ServiceHealthChecker.shared.getServiceStatus()
        AppLogger.shared.log(
            "⏱️ [TIMING] SystemValidator.checkComponents daemon status completed in \(String(format: "%.3f", Date().timeIntervalSince(daemonStatusStart)))s"
        )
        let vhidServicesHealthy = daemonStatus.vhidServicesHealthy
        // Use launchctl-based VHID daemon health instead of pgrep-based detectConnectionHealth
        // to avoid concurrent pgrep calls that can cause hangs (see checkHealth which also calls it)
        let vhidHealthy = daemonStatus.vhidDaemonServiceHealthy

        // Check Karabiner driver - use extension enabled check for accurate status
        // Treat the driver as installed if either the extension is enabled or a VHID device is present.
        // This avoids false negatives when launchd state is stale but the driver is already active.
        let karabinerDriverInstalled =
            facts.karabinerDriverExtensionEnabled || facts.vhidInstalled || vhidHealthy
        let karabinerDaemonRunning = daemonStatus.vhidDaemonServiceHealthy

        AppLogger.shared
            .log(
                "🔍 [SystemValidator] Components: kanata=\(facts.kanataBinaryInstalled), runtimePayload=\(facts.requiredRuntimePayloadPresent), driver=\(karabinerDriverInstalled), daemon=\(karabinerDaemonRunning), vhid=\(vhidHealthy), vhidServices=\(vhidServicesHealthy), vhidPlistMisconfigured=\(facts.vhidDaemonPlistMisconfigured), vhidVersionMismatch=\(facts.vhidVersionMismatch)"
            )

        return ComponentStatus(
            kanataBinaryInstalled: facts.kanataBinaryInstalled,
            requiredRuntimePayloadPresent: facts.requiredRuntimePayloadPresent,
            karabinerDriverInstalled: karabinerDriverInstalled,
            karabinerDaemonRunning: karabinerDaemonRunning,
            vhidDeviceInstalled: facts.vhidInstalled,
            vhidDeviceHealthy: vhidHealthy,
            vhidServicesHealthy: vhidServicesHealthy,
            vhidDaemonPlistMisconfigured: facts.vhidDaemonPlistMisconfigured,
            vhidVersionMismatch: facts.vhidVersionMismatch
        )
    }

    private func componentInstallationFacts() async -> ComponentInstallationFacts {
        if let cachedComponentFacts,
           cachedComponentFacts.isFresh(ttl: Self.canonicalSnapshotCacheTTL)
        {
            AppLogger.shared.log("🔍 [SystemValidator] Component installation facts CACHE HIT")
            return cachedComponentFacts
        }

        let start = Date()

        // Check Kanata binary installation (canonical identity).
        // The bundled binary at Contents/Library/KeyPath/kanata is the canonical path.
        // TCC permissions survive app rebuilds at /Applications/KeyPath.app.
        let kanataBinaryDetector = KanataBinaryDetector.shared
        let kanataBinaryInstalled = kanataBinaryDetector.isInstalled()
        let requiredRuntimePayloadPresent = Self.requiredRuntimePayloadPresent()

        let vhidStart = Date()
        let vhidInstalled = vhidDeviceManager.detectInstallation()
        let vhidVersionMismatch = vhidDeviceManager.hasVersionMismatch()
        AppLogger.shared.log(
            "⏱️ [TIMING] SystemValidator.checkComponents VHID static facts completed in \(String(format: "%.3f", Date().timeIntervalSince(vhidStart)))s"
        )

        let karabinerStart = Date()
        let karabinerDriverExtensionEnabled =
            await (kanataManager?.isKarabinerDriverExtensionEnabled() ?? false)
        AppLogger.shared.log(
            "⏱️ [TIMING] SystemValidator.checkComponents Karabiner extension check completed in \(String(format: "%.3f", Date().timeIntervalSince(karabinerStart)))s"
        )

        // A VHID daemon plist from before the MAL-57 fix (missing
        // ProcessType=Interactive) keeps the daemon running day-to-day but
        // leaves it vulnerable to starvation under CPU load (stuck-key
        // autorepeat). Surface it so the wizard offers a one-click repair
        // that rewrites the plist — old installs never migrate otherwise.
        // Lives in the cached facts so the plist read doesn't run on every
        // validation cycle; invalidateCaches() refreshes it after repairs.
        let vhidDaemonPlistMisconfigured =
            ServiceHealthChecker.shared.isVHIDDaemonPlistPresentButMisconfigured()

        let facts = ComponentInstallationFacts(
            kanataBinaryInstalled: kanataBinaryInstalled,
            requiredRuntimePayloadPresent: requiredRuntimePayloadPresent,
            vhidInstalled: vhidInstalled,
            vhidVersionMismatch: vhidVersionMismatch,
            karabinerDriverExtensionEnabled: karabinerDriverExtensionEnabled,
            vhidDaemonPlistMisconfigured: vhidDaemonPlistMisconfigured,
            timestamp: Date()
        )
        cachedComponentFacts = facts
        AppLogger.shared.log(
            "⏱️ [TIMING] SystemValidator.checkComponents static facts completed in \(String(format: "%.3f", Date().timeIntervalSince(start)))s"
        )
        return facts
    }

    private static func requiredRuntimePayloadPresent(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Bool {
        let launcherPresent = fileManager.fileExists(
            atPath: WizardSystemPaths.bundledKanataLauncherPath
        )
        let bundledPlistPath = "\(bundle.bundlePath)/Contents/Library/LaunchDaemons/\(KanataDaemonManager.kanataPlistName)"
        let plistPresent = fileManager.fileExists(atPath: bundledPlistPath)
            || bundle.path(forResource: "com.keypath.kanata", ofType: "plist") != nil

        return launcherPresent && plistPresent
    }

    // MARK: - Conflict Detection

    struct ConflictCaptureEvidence: Sendable {
        let status: ConflictStatus
        let captureStatus: SystemSnapshotCaptureStatus
    }

    func checkConflicts() async -> ConflictCaptureEvidence {
        AppLogger.shared.log("🔍 [SystemValidator] Checking for conflicts")

        var allConflicts: [SystemConflict] = []

        // Check for external kanata processes
        let conflictResolution: ProcessLifecycleManager.ConflictResolution
        do {
            conflictResolution = try await conflictDetector()
            allConflicts.append(
                contentsOf: conflictResolution.externalProcesses.map { process in
                    .kanataProcessRunning(pid: Int(process.pid), command: process.command)
                }
            )
        } catch {
            AppLogger.shared.log("❌ [SystemValidator] Process conflict detection failed: \(error)")
            return ConflictCaptureEvidence(status: .empty, captureStatus: .failed)
        }

        // Check for Karabiner-Elements conflicts
        if let manager = kanataManager {
            let karabinerRunning = await manager.isKarabinerElementsRunning()
            if karabinerRunning {
                AppLogger.shared.log(
                    "⚠️ [SystemValidator] Karabiner-Elements grabber is running - conflicts with Kanata"
                )
                // Get PID for karabiner_grabber
                if let pid = await getKarabinerGrabberPID() {
                    allConflicts.append(.karabinerGrabberRunning(pid: pid))
                }
            }
        }

        AppLogger.shared
            .log(
                "🔍 [SystemValidator] Total conflicts: \(allConflicts.count) (\(conflictResolution.externalProcesses.count) kanata, \(allConflicts.count - conflictResolution.externalProcesses.count) karabiner)"
            )

        return ConflictCaptureEvidence(
            status: ConflictStatus(
                conflicts: allConflicts,
                canAutoResolve: conflictResolution.canAutoResolve
            ),
            captureStatus: .complete
        )
    }

    /// Get PID of karabiner_grabber process.
    /// Runs pgrep in a detached task to avoid blocking a cooperative thread
    /// inside the TaskGroup (see ADR-022: no concurrent pgrep).
    func getKarabinerGrabberPID() async -> Int? {
        let pids = await systemStateProvider.processIDs(matching: "karabiner_grabber")
        if let pid = pids.first {
            AppLogger.shared.log("🔍 [SystemValidator] Found karabiner_grabber PID: \(pid)")
            return Int(pid)
        }
        return nil
    }

    // MARK: - Health Checking

    private func checkHealth() async -> HealthStatus {
        AppLogger.shared.log("🔍 [SystemValidator] checkHealth() ENTRY - Starting system health check")
        let startTime = Date()

        async let kanataSMAppServiceStatus = systemStateProvider.cachedSMAppServiceStatus(
            for: KanataDaemonManager.kanataPlistName
        )
        async let helperSMAppServiceStatus = systemStateProvider.cachedSMAppServiceStatus(
            for: HelperManager.helperPlistName
        )

        // Check service health via process detection + TCP probe.
        // kanata-launcher can survive (and even hold the TCP socket) after
        // kanata itself has panicked, so we also verify the kanata binary
        // is running via pgrep.
        AppLogger.shared.log("🔍 [SystemValidator] checkHealth() - About to check Kanata service health...")
        let kanataStart = Date()
        let kanataHealth = await ServiceHealthChecker.shared.checkKanataServiceRuntimeSnapshot(
            tcpPort: PreferencesService.shared.tcpServerPort
        )
        let kanataRunning = kanataHealth.readiness.isReady
        let kanataTCPConfigured = checkTCPConfiguration()
        let stderrDiagnosis = await ServiceHealthChecker.shared.diagnoseDaemonStderr()
        let configParseError = Self.effectiveConfigParseError(
            stderrDiagnosis.configParseError,
            kanataRunning: kanataHealth.isRunning,
            tcpResponding: kanataHealth.isResponding
        )
        let kanataDuration = Date().timeIntervalSince(kanataStart)
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() - Kanata service check complete: hostRunning=\(kanataHealth.isRunning), tcpResponding=\(kanataHealth.isResponding), healthy=\(kanataRunning), inputCaptureReady=\(kanataHealth.inputCaptureReady), permRejected=\(stderrDiagnosis.permissionRejected) (took \(String(format: "%.3f", kanataDuration))s)"
        )

        // Use launchctl-based check instead of unreliable pgrep
        // This aligns with the health check used in ServiceHealthChecker
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() - About to check Karabiner daemon health..."
        )
        let karabinerStart = Date()
        let karabinerDaemonRunning = await ServiceHealthChecker.shared.isServiceHealthy(
            serviceID: "com.keypath.karabiner-vhiddaemon"
        )
        let karabinerDuration = Date().timeIntervalSince(karabinerStart)
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() - Karabiner daemon check complete: \(karabinerDaemonRunning) (took \(String(format: "%.3f", karabinerDuration))s)"
        )

        // Reuse karabinerDaemonRunning for vhidHealthy — both check the same service ID
        // ("com.keypath.karabiner-vhiddaemon"), so there's no need for a second launchctl call.
        let vhidHealthy = karabinerDaemonRunning
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() - VHID daemon health reused from karabinerDaemonRunning: \(vhidHealthy)"
        )

        let totalDuration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() EXIT - Health: kanata=\(kanataRunning), daemon=\(karabinerDaemonRunning) (launchctl), vhid=\(vhidHealthy), permRejected=\(stderrDiagnosis.permissionRejected) (total: \(String(format: "%.3f", totalDuration))s)"
        )

        if stderrDiagnosis.configParseError != nil, configParseError == nil {
            AppLogger.shared.warn(
                "🔍 [SystemValidator] checkHealth() - Ignoring stale stderr config parse error because Kanata is running and TCP-responsive"
            )
        } else if let configError = configParseError {
            AppLogger.shared.error("🔍 [SystemValidator] checkHealth() - Config parse error detected: \(configError)")
        }

        let (kanataSMStatus, helperSMStatus) = await (kanataSMAppServiceStatus, helperSMAppServiceStatus)
        let kanataSMAppServiceRegistered = kanataSMStatus == .enabled || kanataSMStatus == .requiresApproval
        let loginItemsApprovalRequired = kanataSMStatus == .requiresApproval || helperSMStatus == .requiresApproval
        let expectedRuntimeIdentity = RuntimeIdentity.expectedKeyPathKanata()
        let activeRuntimeIdentity = kanataHealth.activeProgramIdentity.map {
            RuntimeIdentity(
                programIdentifier: $0.programIdentifier,
                parentBundleIdentifier: $0.parentBundleIdentifier,
                parentBundleVersion: $0.parentBundleVersion
            )
        }
        let kanataServiceFreshness = kanataRunning
            ? RuntimeFreshness.classify(actual: activeRuntimeIdentity, expected: expectedRuntimeIdentity)
            : .unknown
        let activeRuntimePathTitle: String? = switch kanataServiceFreshness {
        case .fresh: "Bundled runtime"
        case .stale: "Stale runtime"
        case .unknown: nil
        }

        return HealthStatus(
            kanataLaunchdLoaded: !kanataHealth.staleEnabledRegistration &&
                (kanataHealth.launchctlExitCode == 0 || kanataHealth.isRunning),
            kanataProcessRunning: kanataHealth.isRunning,
            kanataTCPResponding: kanataHealth.isResponding,
            kanataTCPConfigured: kanataTCPConfigured,
            kanataRunning: kanataRunning,
            karabinerDaemonRunning: karabinerDaemonRunning,
            vhidHealthy: vhidHealthy,
            kanataInputCaptureReady: kanataHealth.inputCaptureReady,
            kanataInputCaptureIssue: kanataHealth.inputCaptureIssue,
            activeRuntimePathTitle: activeRuntimePathTitle,
            activeRuntimePathDetail: activeRuntimeIdentity?.diagnosticDescription,
            kanataServiceFreshness: kanataServiceFreshness,
            kanataPermissionRejected: stderrDiagnosis.permissionRejected,
            configParseError: configParseError,
            staleEnabledRegistration: kanataHealth.staleEnabledRegistration,
            kanataSMAppServiceRegistered: kanataSMAppServiceRegistered,
            loginItemsApprovalRequired: loginItemsApprovalRequired
        )
    }

    private func checkTCPConfiguration() -> Bool {
        if TestEnvironment.isRunningTests { return true }

        let plistPath = KanataDaemonManager.getActivePlistPath()
        guard let plistData = FileManager.default.contents(atPath: plistPath) else {
            AppLogger.shared.warn(
                "⚠️ [SystemValidator] TCP configuration missing daemon plist at \(plistPath)"
            )
            return false
        }

        let configured = Self.plistHasTCPPortArgument(plistData)
        if !configured {
            AppLogger.shared.warn(
                "⚠️ [SystemValidator] Daemon plist is missing a valid --port argument"
            )
        }
        return configured
    }

    static func plistHasTCPPortArgument(_ data: Data) -> Bool {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let arguments = plist["ProgramArguments"] as? [String],
            let portIndex = arguments.firstIndex(of: "--port"),
            arguments.indices.contains(arguments.index(after: portIndex))
        else {
            return false
        }

        let value = arguments[arguments.index(after: portIndex)]
        return Int(value).map { (1 ... 65535).contains($0) } ?? false
    }

    static func effectiveConfigParseError(
        _ stderrConfigParseError: String?,
        kanataRunning: Bool,
        tcpResponding: Bool
    ) -> String? {
        guard let stderrConfigParseError else { return nil }
        return kanataRunning && tcpResponding ? nil : stderrConfigParseError
    }

    // MARK: - Debug Support

    /// Get current validation stats (for debugging)
    static func getValidationStats() -> (activeCount: Int, totalCount: Int, lastStart: Date?) {
        (activeValidations, validationCount, lastValidationStart)
    }

    /// Reset validation counters (for testing)
    static func resetCounters() {
        activeValidations = 0
        validationCount = 0
        lastValidationStart = nil
        countingOwner = nil
        AppLogger.shared.log("🔍 [SystemValidator] Counters reset")
    }

    /// Create a minimal snapshot for test mode - returns immediately without system calls
    /// This provides realistic-looking stub data for tests that don't need real system state
    private static func makeTestSnapshot() -> SystemSnapshot {
        let now = Date()
        let testPermissions = PermissionOracle.PermissionSet(
            accessibility: .granted,
            inputMonitoring: .granted,
            source: "test-stub",
            confidence: .high,
            timestamp: now
        )
        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot(
                keyPath: testPermissions, kanata: testPermissions, timestamp: now
            ),
            components: ComponentStatus(
                kanataBinaryInstalled: true,
                requiredRuntimePayloadPresent: true,
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(
                kanataTCPConfigured: true,
                kanataRunning: true,
                karabinerDaemonRunning: true,
                vhidHealthy: true
            ),
            helper: HelperStatus(
                isInstalled: true,
                version: KeyPathHelperContract.version,
                isWorking: true
            ),
            compatibility: SystemCompatibilityStatus(macOSVersion: "test", driverCompatible: true),
            timestamp: now
        )
    }

    /// Create a minimal snapshot used when a validation task is cancelled
    private static func makeCancelledSnapshot() -> SystemSnapshot {
        .unavailable(captureStatus: .cancelled, source: "cancelled")
    }
}

private final class SystemCaptureCompletionState: @unchecked Sendable {
    private struct State {
        var result: SystemSnapshot?
        var continuation: CheckedContinuation<SystemSnapshot, Never>?
        var operationTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setContinuation(_ continuation: CheckedContinuation<SystemSnapshot, Never>) {
        let completedResult = state.withLock { state -> SystemSnapshot? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil
        }
        if let completedResult {
            continuation.resume(returning: completedResult)
        }
    }

    func setOperationTask(_ task: Task<Void, Never>) {
        let alreadyCompleted = state.withLock { state -> Bool in
            state.operationTask = task
            return state.result != nil
        }
        if alreadyCompleted { task.cancel() }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        let alreadyCompleted = state.withLock { state -> Bool in
            state.timeoutTask = task
            return state.result != nil
        }
        if alreadyCompleted { task.cancel() }
    }

    func complete(with result: SystemSnapshot) -> Bool {
        let completion = state.withLock { state -> (
            CheckedContinuation<SystemSnapshot, Never>?,
            Task<Void, Never>?,
            Task<Void, Never>?
        )? in
            guard state.result == nil else { return nil }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return (continuation, state.operationTask, state.timeoutTask)
        }
        guard let completion else { return false }
        completion.1?.cancel()
        completion.2?.cancel()
        completion.0?.resume(returning: result)
        return true
    }
}

import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathPermissions
import KeyPathWizardCore
import os.lock

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
    private let processLifecycleManager: ProcessLifecycleManager
    private weak var kanataManager: RuntimeCoordinator?

    init(
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        processLifecycleManager: ProcessLifecycleManager,
        kanataManager: RuntimeCoordinator? = nil
    ) {
        self.vhidDeviceManager = vhidDeviceManager
        self.processLifecycleManager = processLifecycleManager
        self.kanataManager = kanataManager

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
            return Self.makeTestSnapshot()
        }

        // If validation is already in progress, wait for it
        if let inProgress = inProgressValidation {
            AppLogger.shared.log(
                "🔍 [SystemValidator] Validation already in progress - waiting for result"
            )
            return await inProgress.value
        }

        // Start new validation
        let validationTask = Task<SystemSnapshot, Never> { @MainActor in
            await self.performValidation(progressCallback: progressCallback)
        }

        inProgressValidation = validationTask
        defer { inProgressValidation = nil }

        return await validationTask.value
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
            case helper(HelperStatus)
            case permissions(PermissionOracle.Snapshot)
            case components(ComponentStatus)
            case conflicts(ConflictStatus)
            case health(HealthStatus)
        }

        let (helper, permissions, components, conflicts, health) = await withTaskGroup(
            of: ValidationResult.self
        ) { group in
            var helperResult: HelperStatus?
            var permissionsResult: PermissionOracle.Snapshot?
            var componentsResult: ComponentStatus?
            var conflictsResult: ConflictStatus?
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
                helperResult ?? HelperStatus.empty,
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
                conflictsResult ?? ConflictStatus.empty,
                healthResult ?? HealthStatus.empty
            )
        }

        progressCallback(1.0) // All done: 100%

        let totalDuration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log(
            "⏱️ [TIMING] Validation #\(myID) COMPLETE: Total duration \(String(format: "%.3f", totalDuration))s"
        )

        let snapshot = SystemSnapshot(
            permissions: permissions,
            components: components,
            conflicts: conflicts,
            health: health,
            helper: helper,
            timestamp: Date()
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

    // MARK: - Helper Checking

    private func checkHelper() async -> HelperStatus {
        AppLogger.shared.log("🔍 [SystemValidator] Checking privileged helper")

        let health = await HelperManager.shared.getHelperHealth()

        switch health {
        case .notInstalled:
            AppLogger.shared.log("🔍 [SystemValidator] Helper state: notInstalled")
            return HelperStatus(isInstalled: false, version: nil, isWorking: false)

        case let .requiresApproval(reason):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state: requiresApproval \(reason ?? "")"
            )
            return HelperStatus(isInstalled: false, version: nil, isWorking: false)

        case let .registeredButUnresponsive(reason):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state: registeredButUnresponsive \(reason ?? "")"
            )
            return HelperStatus(isInstalled: true, version: nil, isWorking: false)

        case let .healthy(version):
            AppLogger.shared.log(
                "🔍 [SystemValidator] Helper state: healthy (v\(version ?? "unknown"))"
            )
            return HelperStatus(isInstalled: true, version: version, isWorking: true)
        }
    }

    // MARK: - Permission Checking

    private func checkPermissions() async -> PermissionOracle.Snapshot {
        AppLogger.shared.log("🔍 [SystemValidator] Checking permissions via Oracle")

        // Oracle has its own 1.5s cache - we don't add another layer
        let snapshot = await PermissionOracle.shared.currentSnapshot()

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

        // Check Kanata binary installation (canonical identity).
        // The bundled binary at Contents/Library/KeyPath/kanata is the canonical path.
        // TCC permissions survive app rebuilds at /Applications/KeyPath.app.
        let kanataBinaryDetector = KanataBinaryDetector.shared
        let kanataBinaryInstalled = kanataBinaryDetector.isInstalled()

        // Check VirtualHID Device installation (fast sync check)
        let vhidInstalled = vhidDeviceManager.detectInstallation()
        let vhidVersionMismatch = vhidDeviceManager.hasVersionMismatch()

        // Check LaunchDaemon services via ServiceHealthChecker FIRST
        // This uses launchctl (fast) and provides VHID health, avoiding duplicate pgrep calls
        // that could contend with checkHealth()'s detectConnectionHealth() call
        let daemonStatus = await ServiceHealthChecker.shared.getServiceStatus()
        let vhidServicesHealthy = daemonStatus.vhidServicesHealthy
        // Use launchctl-based VHID daemon health instead of pgrep-based detectConnectionHealth
        // to avoid concurrent pgrep calls that can cause hangs (see checkHealth which also calls it)
        let vhidHealthy = daemonStatus.vhidDaemonServiceHealthy

        // Check Karabiner driver - use extension enabled check for accurate status
        // Treat the driver as installed if either the extension is enabled or a VHID device is present.
        // This avoids false negatives when launchd state is stale but the driver is already active.
        let karabinerDriverInstalled =
            await (kanataManager?.isKarabinerDriverExtensionEnabled() ?? false)
                || vhidInstalled || vhidHealthy
        // Use launchctl-based check instead of unreliable pgrep (same as checkHealth)
        let karabinerDaemonRunning = await ServiceHealthChecker.shared.isServiceHealthy(
            serviceID: "com.keypath.karabiner-vhiddaemon"
        )

        AppLogger.shared
            .log(
                "🔍 [SystemValidator] Components: kanata=\(kanataBinaryInstalled), driver=\(karabinerDriverInstalled), daemon=\(karabinerDaemonRunning), vhid=\(vhidHealthy), vhidServices=\(vhidServicesHealthy), vhidVersionMismatch=\(vhidVersionMismatch)"
            )

        return ComponentStatus(
            kanataBinaryInstalled: kanataBinaryInstalled,
            karabinerDriverInstalled: karabinerDriverInstalled,
            karabinerDaemonRunning: karabinerDaemonRunning,
            vhidDeviceInstalled: vhidInstalled,
            vhidDeviceHealthy: vhidHealthy,
            vhidServicesHealthy: vhidServicesHealthy,
            vhidVersionMismatch: vhidVersionMismatch
        )
    }

    // MARK: - Conflict Detection

    private func checkConflicts() async -> ConflictStatus {
        AppLogger.shared.log("🔍 [SystemValidator] Checking for conflicts")

        var allConflicts: [SystemConflict] = []

        // Check for external kanata processes
        let conflictResolution = await processLifecycleManager.detectConflicts()
        allConflicts.append(
            contentsOf: conflictResolution.externalProcesses.map { process in
                .kanataProcessRunning(pid: Int(process.pid), command: process.command)
            }
        )

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

        return ConflictStatus(
            conflicts: allConflicts,
            canAutoResolve: conflictResolution.canAutoResolve
        )
    }

    /// Get PID of karabiner_grabber process.
    /// Runs pgrep in a detached task to avoid blocking a cooperative thread
    /// inside the TaskGroup (see ADR-022: no concurrent pgrep).
    private func getKarabinerGrabberPID() async -> Int? {
        await Task.detached(priority: .utility) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-f", "karabiner_grabber"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let pidString = output.trimmingCharacters(in: .whitespacesAndNewlines)

                if let pid = Int(pidString) {
                    AppLogger.shared.log("🔍 [SystemValidator] Found karabiner_grabber PID: \(pid)")
                    return pid
                }
            } catch {
                AppLogger.shared.log("❌ [SystemValidator] Error getting karabiner_grabber PID: \(error)")
            }

            return nil
        }.value
    }

    // MARK: - Health Checking

    private func checkHealth() async -> HealthStatus {
        AppLogger.shared.log("🔍 [SystemValidator] checkHealth() ENTRY - Starting system health check")
        let startTime = Date()

        // Check service health via process detection + TCP probe.
        // kanata-launcher can survive (and even hold the TCP socket) after
        // kanata itself has panicked, so we also verify the kanata binary
        // is running via pgrep.
        AppLogger.shared.log("🔍 [SystemValidator] checkHealth() - About to check Kanata service health...")
        let kanataStart = Date()
        let kanataHealth = await ServiceHealthChecker.shared.checkKanataServiceHealth(
            tcpPort: PreferencesService.shared.tcpServerPort
        )
        let kanataRunning = kanataHealth.isRunning
        let kanataInputCapture = await ServiceHealthChecker.shared.checkKanataInputCaptureStatus()
        let kanataDuration = Date().timeIntervalSince(kanataStart)
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() - Kanata service check complete: hostRunning=\(kanataHealth.isRunning), tcpResponding=\(kanataHealth.isResponding), healthy=\(kanataRunning), inputCaptureReady=\(kanataInputCapture.isReady) (took \(String(format: "%.3f", kanataDuration))s)"
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

        // When kanata isn't running, check daemon stderr for permission rejection.
        // TCC can report "granted" from a stale entry after a rebuild, but macOS
        // actually rejects the binary at runtime. Detect this from the crash output.
        let permissionRejected = Self.checkDaemonStderrForPermissionFailure()

        let totalDuration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log(
            "🔍 [SystemValidator] checkHealth() EXIT - Health: kanata=\(kanataRunning), daemon=\(karabinerDaemonRunning) (launchctl), vhid=\(vhidHealthy), permRejected=\(permissionRejected) (total: \(String(format: "%.3f", totalDuration))s)"
        )

        // When the daemon was rejected for Accessibility, the "cannot open keyboard"
        // stderr line is a symptom of the AX issue, not a separate IM problem.
        // Suppress the input capture issue to avoid double-counting under Input Monitoring.
        let effectiveInputCaptureReady = permissionRejected ? true : kanataInputCapture.isReady
        let effectiveInputCaptureIssue: String? = permissionRejected ? nil : kanataInputCapture.issue

        return HealthStatus(
            kanataRunning: kanataRunning,
            karabinerDaemonRunning: karabinerDaemonRunning,
            vhidHealthy: vhidHealthy,
            kanataInputCaptureReady: effectiveInputCaptureReady,
            kanataInputCaptureIssue: effectiveInputCaptureIssue,
            kanataPermissionRejected: permissionRejected
        )
    }

    private static let kanataStderrPath = "/var/log/com.keypath.kanata.stderr.log"

    /// Read the tail of the kanata daemon stderr log and check for the
    /// macOS Accessibility permission rejection message.
    private static func checkDaemonStderrForPermissionFailure() -> Bool {
        guard let data = try? Data(
            contentsOf: URL(fileURLWithPath: kanataStderrPath),
            options: .mappedIfSafe
        ) else { return false }

        // Only check the last 2KB to avoid reading a huge log
        let tailSize = min(data.count, 2048)
        let tail = data.suffix(tailSize)
        guard let text = String(data: tail, encoding: .utf8) else { return false }

        return text.contains("kanata needs macOS Accessibility permission")
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
                karabinerDriverInstalled: true,
                karabinerDaemonRunning: true,
                vhidDeviceInstalled: true,
                vhidDeviceHealthy: true,
                vhidServicesHealthy: true,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(kanataRunning: true, karabinerDaemonRunning: true, vhidHealthy: true),
            helper: HelperStatus(isInstalled: true, version: "1.0.0", isWorking: true),
            timestamp: now
        )
    }

    /// Create a minimal snapshot used when a validation task is cancelled
    private static func makeCancelledSnapshot() -> SystemSnapshot {
        let now = Date()
        let placeholder = PermissionOracle.PermissionSet(
            accessibility: .unknown,
            inputMonitoring: .unknown,
            source: "cancelled",
            confidence: .low,
            timestamp: now
        )
        return SystemSnapshot(
            permissions: PermissionOracle.Snapshot(
                keyPath: placeholder, kanata: placeholder, timestamp: now
            ),
            components: ComponentStatus(
                kanataBinaryInstalled: false,
                karabinerDriverInstalled: false,
                karabinerDaemonRunning: false,
                vhidDeviceInstalled: false,
                vhidDeviceHealthy: false,
                vhidServicesHealthy: false,
                vhidVersionMismatch: false
            ),
            conflicts: ConflictStatus(conflicts: [], canAutoResolve: false),
            health: HealthStatus(kanataRunning: false, karabinerDaemonRunning: false, vhidHealthy: false),
            helper: HelperStatus(isInstalled: false, version: nil, isWorking: false),
            timestamp: now
        )
    }
}

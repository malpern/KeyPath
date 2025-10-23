import Foundation

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
class SystemValidator {
    // MARK: - Validation Spam Detection

    /// Track active validations to detect spam (concurrent validations)
    private static var activeValidations = 0

    /// Shared validation task - if validation is already running, concurrent calls wait for it
    private static var inProgressValidation: Task<SystemSnapshot, Never>?

    /// Track validation timing to detect rapid-fire calls (indicates automatic triggers)
    private static var lastValidationStart: Date?
    private static var validationCount = 0

    // MARK: - Dependencies

    private let launchDaemonInstaller: LaunchDaemonInstaller
    private let vhidDeviceManager: VHIDDeviceManager
    private let processLifecycleManager: ProcessLifecycleManager
    private weak var kanataManager: KanataManager?

    init(
        launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller(),
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        processLifecycleManager: ProcessLifecycleManager,
        kanataManager: KanataManager? = nil
    ) {
        self.launchDaemonInstaller = launchDaemonInstaller
        self.vhidDeviceManager = vhidDeviceManager
        self.processLifecycleManager = processLifecycleManager
        self.kanataManager = kanataManager

        AppLogger.shared.log("🔍 [SystemValidator] Initialized (stateless, no cache)")
    }

    // MARK: - Main Validation Method

    /// Check complete system state
    /// This is the ONLY public method - returns fresh state every time
    ///
    /// If validation is already in progress, this will wait for it to complete
    /// rather than starting a concurrent validation. This prevents validation spam
    /// when multiple UI components request validation simultaneously.
    func checkSystem() async -> SystemSnapshot {
        // If validation is already in progress, wait for it
        if let inProgress = Self.inProgressValidation {
            AppLogger.shared.log("🔍 [SystemValidator] Validation already in progress - waiting for result")
            return await inProgress.value
        }

        // Start new validation
        let validationTask = Task<SystemSnapshot, Never> { @MainActor in
            await self.performValidation()
        }

        Self.inProgressValidation = validationTask
        defer { Self.inProgressValidation = nil }

        return await validationTask.value
    }

    /// Perform the actual validation work
    /// This is called by checkSystem() and should not be called directly
    private func performValidation() async -> SystemSnapshot {
        Self.activeValidations += 1
        defer { Self.activeValidations -= 1 }

        Self.validationCount += 1
        let myID = Self.validationCount

        // 🚨 DEFENSIVE WARNING: Detect rapid-fire validations (indicates automatic triggers)
        if let lastStart = Self.lastValidationStart {
            let interval = Date().timeIntervalSince(lastStart)
            if interval < 0.5 {
                AppLogger.shared.log("""
                    ⚠️ [SystemValidator] RAPID VALIDATION: \(String(format: "%.3f", interval))s since last validation
                    This might indicate automatic triggers. Expected: manual user actions only.
                    """)
            }
        }
        Self.lastValidationStart = Date()

        let startTime = Date()
        AppLogger.shared.log("🔍 [SystemValidator] Starting validation #\(myID)")

        // Check system state (calls existing services)
        let permissions = await checkPermissions()
        let components = await checkComponents()
        let conflicts = await checkConflicts()
        let health = await checkHealth()

        let snapshot = SystemSnapshot(
            permissions: permissions,
            components: components,
            conflicts: conflicts,
            health: health,
            timestamp: Date()
        )

        let duration = Date().timeIntervalSince(startTime)
        AppLogger.shared.log("🔍 [SystemValidator] Validation #\(myID) complete in \(String(format: "%.3f", duration))s")
        AppLogger.shared.log("🔍 [SystemValidator] Result: ready=\(snapshot.isReady), blocking=\(snapshot.blockingIssues.count), total=\(snapshot.allIssues.count)")

        // 🚨 DEFENSIVE ASSERTION: Verify snapshot is fresh
        snapshot.validate()

        return snapshot
    }

    // MARK: - Permission Checking

    private func checkPermissions() async -> PermissionOracle.Snapshot {
        AppLogger.shared.log("🔍 [SystemValidator] Checking permissions via Oracle")

        // Oracle has its own 1.5s cache - we don't add another layer
        let snapshot = await PermissionOracle.shared.currentSnapshot()

        // 🚨 DEFENSIVE ASSERTION 4: Verify Oracle snapshot is fresh
        let oracleAge = Date().timeIntervalSince(snapshot.timestamp)
        assert(oracleAge < 5.0,
            "Oracle snapshot is \(String(format: "%.1f", oracleAge))s old - Oracle cache may be broken")

        AppLogger.shared.log("🔍 [SystemValidator] Oracle snapshot: ready=\(snapshot.isSystemReady), age=\(String(format: "%.3f", oracleAge))s")

        return snapshot
    }

    // MARK: - Component Checking

    private func checkComponents() async -> ComponentStatus {
        AppLogger.shared.log("🔍 [SystemValidator] Checking components")

        // Check Kanata binary installation
        let kanataBinaryDetector = KanataBinaryDetector.shared
        let binaryResult = kanataBinaryDetector.detectCurrentStatus()
        let kanataBinaryInstalled = binaryResult.status == .systemInstalled

        // Check Karabiner driver - use extension enabled check for accurate status
        let karabinerDriverInstalled = kanataManager?.isKarabinerDriverExtensionEnabled() ?? false
        let karabinerDaemonRunning = kanataManager?.isKarabinerDaemonRunning() ?? false

        // Check VirtualHID Device
        let vhidInstalled = vhidDeviceManager.detectInstallation()
        let vhidHealthy = vhidDeviceManager.detectConnectionHealth()

        // Check LaunchDaemon services
        let daemonStatus = launchDaemonInstaller.getServiceStatus()
        let launchDaemonServicesHealthy = daemonStatus.allServicesHealthy

        AppLogger.shared.log("🔍 [SystemValidator] Components: kanata=\(kanataBinaryInstalled), driver=\(karabinerDriverInstalled), daemon=\(karabinerDaemonRunning), vhid=\(vhidHealthy)")

        return ComponentStatus(
            kanataBinaryInstalled: kanataBinaryInstalled,
            karabinerDriverInstalled: karabinerDriverInstalled,
            karabinerDaemonRunning: karabinerDaemonRunning,
            vhidDeviceInstalled: vhidInstalled,
            vhidDeviceHealthy: vhidHealthy,
            launchDaemonServicesHealthy: launchDaemonServicesHealthy
        )
    }

    // MARK: - Conflict Detection

    private func checkConflicts() async -> ConflictStatus {
        AppLogger.shared.log("🔍 [SystemValidator] Checking for conflicts")

        var allConflicts: [SystemConflict] = []

        // Check for external kanata processes
        let conflictResolution = await processLifecycleManager.detectConflicts()
        allConflicts.append(contentsOf: conflictResolution.externalProcesses.map { process in
            .kanataProcessRunning(pid: Int(process.pid), command: process.command)
        })

        // Check for Karabiner-Elements conflicts
        if let manager = kanataManager {
            let karabinerRunning = manager.karabinerConflictService.isKarabinerElementsRunning()
            if karabinerRunning {
                AppLogger.shared.log("⚠️ [SystemValidator] Karabiner-Elements grabber is running - conflicts with Kanata")
                // Get PID for karabiner_grabber
                if let pid = getKarabinerGrabberPID() {
                    allConflicts.append(.karabinerGrabberRunning(pid: pid))
                }
            }
        }

        AppLogger.shared.log("🔍 [SystemValidator] Total conflicts: \(allConflicts.count) (\(conflictResolution.externalProcesses.count) kanata, \(allConflicts.count - conflictResolution.externalProcesses.count) karabiner)")

        return ConflictStatus(
            conflicts: allConflicts,
            canAutoResolve: conflictResolution.canAutoResolve
        )
    }

    /// Get PID of karabiner_grabber process
    private func getKarabinerGrabberPID() -> Int? {
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
    }

    // MARK: - Health Checking

    private func checkHealth() async -> HealthStatus {
        AppLogger.shared.log("🔍 [SystemValidator] Checking system health")

        let kanataRunning = kanataManager?.isRunning ?? false
        let karabinerDaemonRunning = kanataManager?.isKarabinerDaemonRunning() ?? false
        let vhidHealthy = vhidDeviceManager.detectConnectionHealth()

        AppLogger.shared.log("🔍 [SystemValidator] Health: kanata=\(kanataRunning), daemon=\(karabinerDaemonRunning), vhid=\(vhidHealthy)")

        return HealthStatus(
            kanataRunning: kanataRunning,
            karabinerDaemonRunning: karabinerDaemonRunning,
            vhidHealthy: vhidHealthy
        )
    }

    // MARK: - Debug Support

    /// Get current validation stats (for debugging)
    static func getValidationStats() -> (activeCount: Int, totalCount: Int, lastStart: Date?) {
        return (activeValidations, validationCount, lastValidationStart)
    }

    /// Reset validation counters (for testing)
    static func resetCounters() {
        activeValidations = 0
        validationCount = 0
        lastValidationStart = nil
        inProgressValidation = nil
        AppLogger.shared.log("🔍 [SystemValidator] Counters reset")
    }
}
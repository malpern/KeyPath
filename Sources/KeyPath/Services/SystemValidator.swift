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
    func checkSystem() async -> SystemSnapshot {
        // 🚨 DEFENSIVE ASSERTION 1: Detect validation spam (concurrent validations)
        let currentActive = Self.activeValidations
        precondition(currentActive == 0,
            """
            🚨 VALIDATION SPAM DETECTED!
            Concurrent validation detected: \(currentActive) validation(s) already running.
            This indicates automatic reactivity triggers that should have been removed.
            Check for: Combine publishers, SwiftUI onChange, NotificationCenter auto-triggers.
            """)

        Self.activeValidations += 1
        defer { Self.activeValidations -= 1 }

        Self.validationCount += 1
        let myID = Self.validationCount

        // 🚨 DEFENSIVE ASSERTION 2: Detect rapid-fire validations (indicates automatic triggers)
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

        // 🚨 DEFENSIVE ASSERTION 3: Verify snapshot is fresh
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

        // Check Karabiner driver
        let karabinerDriverInstalled = kanataManager?.isKarabinerDriverInstalled() ?? false
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

        let conflictResolution = await processLifecycleManager.detectConflicts()

        AppLogger.shared.log("🔍 [SystemValidator] Conflicts: \(conflictResolution.externalProcesses.count) external processes")

        return ConflictStatus(
            conflicts: conflictResolution.externalProcesses.map { process in
                .kanataProcessRunning(pid: Int(process.pid), command: process.command)
            },
            canAutoResolve: conflictResolution.canAutoResolve
        )
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
        AppLogger.shared.log("🔍 [SystemValidator] Counters reset")
    }
}
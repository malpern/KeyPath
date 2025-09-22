import ApplicationServices
import Foundation

/// Error types for system detection operations
enum SystemDetectionError: Error {
    case timeout
}

/// Helper function for timeout operations in system detection
private func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SystemDetectionError.timeout
        }
        guard let result = try await group.next() else {
            throw SystemDetectionError.timeout
        }
        group.cancelAll()
        return result
    }
}

/// Unified system status checker that handles all wizard detection logic
///
/// FEATURES:
/// - Comprehensive permission detection with TCC database integration
/// - Functional verification through service log analysis and TCP connectivity
/// - Component installation and health checking
/// - Conflict detection and resolution
/// - Automatic issue generation with actionable fixes
/// - Performance optimized with intelligent caching
/// - Shared instance pattern for consistent status across all components
@MainActor
class SystemStatusChecker {
    // MARK: - Shared Instance

    @MainActor private static var sharedInstance: SystemStatusChecker?

    /// Get or create the shared SystemStatusChecker instance
    @MainActor
    static func shared(kanataManager: KanataManager) -> SystemStatusChecker {
        if let existing = sharedInstance {
            return existing
        }

        let newInstance = SystemStatusChecker(kanataManager: kanataManager)
        sharedInstance = newInstance
        AppLogger.shared.log("🔍 [SystemStatusChecker] Created shared instance")
        return newInstance
    }

    /// Reset the shared instance (primarily for testing)
    static func resetSharedInstance() {
        sharedInstance = nil
        AppLogger.shared.log("🔍 [SystemStatusChecker] Shared instance reset")
    }

    private let kanataManager: KanataManager
    private let vhidDeviceManager: VHIDDeviceManager
    private let launchDaemonInstaller: LaunchDaemonInstaller
    private let processLifecycleManager: ProcessLifecycleManager
    private let issueGenerator: IssueGenerator

    // MARK: - Cache Properties

    private var cachedStateResult: SystemStateResult?
    private var cacheTimestamp: Date?
    private let cacheValidDuration: TimeInterval = 2.0 // 2-second cache

    // MARK: - Debouncing State (from SystemStateDetector)

    private var lastConflictState: Bool = false
    private var lastStateChange: Date = .init()
    private let stateChangeDebounceTime: TimeInterval = 0.5 // 500ms

    @MainActor
    init(kanataManager: KanataManager) {
        self.kanataManager = kanataManager
        vhidDeviceManager = VHIDDeviceManager()
        launchDaemonInstaller = LaunchDaemonInstaller()
        processLifecycleManager = ProcessLifecycleManager(kanataManager: kanataManager)
        issueGenerator = IssueGenerator()
    }

    // MARK: - Debug Support

    /// Debug flag to force Input Monitoring issues for testing purposes
    @MainActor static var debugForceInputMonitoringIssues = false

    // MARK: - Cache Management

    /// Clear the cached state to force a fresh detection
    func clearCache() {
        cachedStateResult = nil
        cacheTimestamp = nil
        AppLogger.shared.log("🔍 [SystemStatusChecker] Cache cleared")
    }

    // MARK: - Component-Specific Refresh Methods

    /// Check only permissions without full system scan
    func checkPermissionsOnly() async -> PermissionCheckResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Quick permission check only")
        return await checkPermissionsInternal()
    }

    /// Check only components without full system scan
    func checkComponentsOnly() async -> ComponentCheckResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Quick component check only")
        return await checkComponentsInternal()
    }

    /// Check only conflicts without full system scan
    func checkConflictsOnly() async -> ConflictDetectionResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Quick conflict check only")
        return await checkConflictsInternal()
    }

    /// Check only system health without full system scan
    func checkHealthOnly() async -> HealthCheckResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Quick health check only")
        return await performSystemHealthCheck()
    }

    // MARK: - Main Detection Method

    func detectCurrentState() async -> SystemStateResult {
        // Invalidate Oracle cache when wizard detection starts to ensure fresh status
        AppLogger.shared.log("🔍 [SystemStatusChecker] Invalidating Oracle cache for fresh wizard detection")
        await PermissionOracle.shared.invalidateCache()

        // Check cache first
        if let cached = cachedStateResult,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidDuration {
            AppLogger.shared.log("🔍 [SystemStatusChecker] Returning cached state (age: \(String(format: "%.1f", Date().timeIntervalSince(timestamp)))s)")
            return cached
        }

        let detectionID = UUID()
        AppLogger.shared.log("🔍 [SystemStatusChecker] Starting comprehensive system state detection (detectionID: \(detectionID))")

        // Debug override for testing Input Monitoring page
        if SystemStatusChecker.debugForceInputMonitoringIssues {
            AppLogger.shared.log(
                "🧪 [SystemStatusChecker] DEBUG: Forcing Input Monitoring issues for testing")
            return createDebugInputMonitoringState()
        }

        do {
            // Add comprehensive timeout protection for the entire detection process
            let result = try await withTimeout(seconds: 15.0) {
                await self.performSystemDetection()
            }
            return result
        } catch {
            AppLogger.shared.log("⚠️ [SystemStatusChecker] System detection timed out or failed: \(error)")
            AppLogger.shared.log("⚠️ [SystemStatusChecker] Returning fallback state to prevent wizard hanging")
            return createFallbackSystemState()
        }
    }
    
    /// Perform the actual system detection (wrapped in timeout protection)
    private func performSystemDetection() async -> SystemStateResult {
        // 1. Check system compatibility
        let compatibilityResult = checkSystemCompatibility()

        // 2. Check permissions
        let permissionResult = await checkPermissionsInternal()

        // 3. Check component installation
        let componentResult = await checkComponentsInternal()

        // 4. Check for conflicts
        let conflictResult = await checkConflictsInternal()

        // 5. Check system health
        let healthStatus = await performSystemHealthCheck()

        // Generate issues based on results
        var allIssues: [WizardIssue] = []
        allIssues.append(
            contentsOf: issueGenerator.createSystemRequirementIssues(from: compatibilityResult))
        allIssues.append(contentsOf: issueGenerator.createConflictIssues(from: conflictResult))
        allIssues.append(contentsOf: issueGenerator.createPermissionIssues(from: permissionResult))
        allIssues.append(contentsOf: issueGenerator.createComponentIssues(from: componentResult))

        // Add daemon issue if needed
        if !healthStatus.isKarabinerDaemonHealthy {
            allIssues.append(issueGenerator.createDaemonIssue())
        }

        // Check if log rotation should be recommended
        let needsLogRotation = await shouldInstallLogRotation()
        if needsLogRotation {
            allIssues.append(issueGenerator.createLogRotationIssue())
        }

        // Determine system state
        let systemState = await determineSystemState(
            compatibility: compatibilityResult,
            permissions: permissionResult,
            components: componentResult,
            conflicts: conflictResult,
            health: healthStatus
        )

        // Determine available auto-fix actions
        let autoFixableActions = determineAutoFixActions(
            conflicts: conflictResult,
            permissions: permissionResult,
            components: componentResult,
            health: healthStatus,
            needsLogRotation: needsLogRotation
        )

        AppLogger.shared.log(
            "🔍 [SystemStatusChecker] Detection complete: \(systemState), \(allIssues.count) issues, \(autoFixableActions.count) auto-fixes"
        )

        let result = SystemStateResult(
            state: systemState,
            issues: allIssues,
            autoFixActions: autoFixableActions,
            detectionTimestamp: Date()
        )

        // Update cache
        cachedStateResult = result
        cacheTimestamp = Date()
        AppLogger.shared.log("🔍 [SystemStatusChecker] Cache updated with fresh state")

        return result
    }
    
    /// Create a fallback system state when detection times out
    private func createFallbackSystemState() -> SystemStateResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Creating fallback system state due to timeout")
        
        // Return a safe fallback state that doesn't assume any specific issues
        // This allows the wizard to proceed without hanging
        let fallbackIssues: [WizardIssue] = [
            WizardIssue(
                identifier: .daemon,
                severity: .warning,
                category: .daemon,
                title: "System Detection Timeout",
                description: "System detection took too long to complete. Some features may need manual setup.",
                autoFixAction: nil,
                userAction: "Please try refreshing the wizard or check system logs for issues."
            )
        ]
        
        return SystemStateResult(
            state: .initializing,
            issues: fallbackIssues,
            autoFixActions: [],
            detectionTimestamp: Date()
        )
    }

    // MARK: - System Compatibility

    private func checkSystemCompatibility() -> SystemRequirements.ValidationResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Validating system compatibility")

        // Use the SystemRequirements class for proper compatibility checking
        let systemRequirements = SystemRequirements()
        return systemRequirements.validateSystemCompatibility()
    }

    // MARK: - Permission Checking

    private func checkPermissionsInternal() async -> PermissionCheckResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Checking system permissions")

        var granted: [PermissionRequirement] = []
        var missing: [PermissionRequirement] = []

        // Resolve kanata path once and use consistently
        let kanataPath = WizardSystemPaths.kanataActiveBinary
        AppLogger.shared.log("🔍 [SystemStatusChecker] Using kanata binary for permission checks: \(kanataPath)")

        // 🔮 Use Oracle for authoritative permission detection
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        AppLogger.shared.log("🔍 [SystemStatusChecker] Using Oracle snapshot from \(snapshot.timestamp) (detectionID: \(detectionID))")

        // KeyPath permissions (from Apple APIs)
        if snapshot.keyPath.inputMonitoring.isReady {
            granted.append(.keyPathInputMonitoring)
        } else {
            missing.append(.keyPathInputMonitoring)
        }

        if snapshot.keyPath.accessibility.isReady {
            granted.append(.keyPathAccessibility)
        } else {
            missing.append(.keyPathAccessibility)
        }

        // Kanata permissions via Oracle (with TCC fallback to break chicken-and-egg problem)
        let kanataIMStatus = snapshot.kanata.inputMonitoring
        let kanataAXStatus = snapshot.kanata.accessibility

        AppLogger.shared.log(
            "🔮 [SystemStatusChecker] Oracle permission detection: source=\(snapshot.kanata.source), confidence=\(snapshot.kanata.confidence), hasAll=\(snapshot.kanata.hasAllPermissions)"
        )

        // Log any blocking issues
        if let issue = snapshot.blockingIssue {
            AppLogger.shared.log("⚠️ [SystemStatusChecker] Oracle detected blocking issue: \(issue)")
        }

        // Input Monitoring - only block on definitively denied/error status, not unknown
        if kanataIMStatus.isReady {
            granted.append(.kanataInputMonitoring)
            AppLogger.shared.log("✅ [SystemStatusChecker] Kanata Input Monitoring: Oracle confirmed granted")
        } else if kanataIMStatus.isBlocking {
            // Only mark as missing if we're confident it's denied (not just unknown)
            missing.append(.kanataInputMonitoring)
            AppLogger.shared.log("❌ [SystemStatusChecker] Kanata Input Monitoring: Oracle reports blocked")
        } else {
            // Unknown status is inconclusive; don't block wizard - let service startup resolve it
            AppLogger.shared.log("🟡 [SystemStatusChecker] Kanata Input Monitoring: Oracle inconclusive (unknown)")
        }

        // Accessibility - same logic as Input Monitoring
        if kanataAXStatus.isReady {
            granted.append(.kanataAccessibility)
            AppLogger.shared.log("✅ [SystemStatusChecker] Kanata Accessibility: Oracle confirmed granted")
        } else if kanataAXStatus.isBlocking {
            // Only mark as missing if we're confident it's denied (not just unknown)
            missing.append(.kanataAccessibility)
            AppLogger.shared.log("❌ [SystemStatusChecker] Kanata Accessibility: Oracle reports blocked")
        } else {
            // Unknown status is inconclusive; don't block wizard - let service startup resolve it
            AppLogger.shared.log("🟡 [SystemStatusChecker] Kanata Accessibility: Oracle inconclusive (unknown)")
        }

        // 🚨🚨🚨 CRITICAL: NEVER ADD ORACLE OVERRIDES HERE 🚨🚨🚨
        //
        // ⚠️  REGRESSION PREVENTION (September 1, 2025):
        //     This exact location previously contained Oracle overrides that broke
        //     permission detection consistency between main screen and wizard.
        //
        // 🚫 DO NOT ADD:
        //    - "TCC Domain Mismatch" logic
        //    - "HARD EVIDENCE OVERRIDE" log parsing
        //    - Any logic that modifies `granted`/`missing` arrays after Oracle results
        //    - SystemStatusChecker-specific permission detection
        //
        // ✅ WHY ORACLE IS AUTHORITATIVE:
        //    - Oracle uses corrected Apple API priority hierarchy (commit 8445b36)
        //    - Oracle handles TCC fallback properly for chicken-and-egg scenarios
        //    - Oracle is the SINGLE SOURCE OF TRUTH for all permission detection
        //
        // 🔍 HISTORY:
        //    - Commit 7f68821: Added overrides (BROKE consistency)
        //    - Commit 8445b36: Fixed Oracle architecture
        //    - Commit bbdd053: Removed overrides (RESTORED consistency)
        //
        // 🎯 RESULT:
        //    Main screen (StartupValidator) and wizard (SystemStatusChecker) now show
        //    identical permission status because both trust Oracle without modification.
        //
        // SystemStatusChecker trusts Oracle results without any overrides or modifications
        AppLogger.shared.log("🔮 [SystemStatusChecker] Oracle permission detection complete - trusting authoritative results")

        // Check system extensions (not part of PermissionService - different category)
        let systemRequirements = SystemRequirements()
        let driverEnabled = await systemRequirements.checkDriverExtensionEnabled()
        if driverEnabled {
            granted.append(.driverExtensionEnabled)
        } else {
            missing.append(.driverExtensionEnabled)
        }

        // Check background services (not part of PermissionService - different category)
        let backgroundServicesEnabled = await systemRequirements.checkBackgroundServicesEnabled()
        if backgroundServicesEnabled {
            granted.append(.backgroundServicesEnabled)
        } else {
            missing.append(.backgroundServicesEnabled)
        }

        AppLogger.shared.log("🔍 [SystemStatusChecker] Permission check complete:")
        AppLogger.shared.log("  - Granted: \(granted.count) permissions")
        AppLogger.shared.log("  - Missing: \(missing.count) permissions")

        return PermissionCheckResult(
            missing: missing,
            granted: granted,
            needsUserAction: !missing.isEmpty
        )
    }

    // MARK: - Component Checking

    private func checkComponentsInternal() async -> ComponentCheckResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Checking system components")

        var installed: [ComponentRequirement] = []
        var missing: [ComponentRequirement] = []

        // Use KanataBinaryDetector for unified kanata binary detection
        let binaryDetector = KanataBinaryDetector.shared
        installed.append(contentsOf: binaryDetector.getInstalledComponents())
        missing.append(contentsOf: binaryDetector.getMissingComponents())
        
        let detectionResult = binaryDetector.detectCurrentStatus()
        AppLogger.shared.log("🔍 [SystemStatusChecker] Unified kanata detection: \(detectionResult.status) at \(detectionResult.path ?? "none")")

        // Check VHIDDevice Manager components
        if vhidDeviceManager.detectInstallation() {
            installed.append(.vhidDeviceManager)
        } else {
            missing.append(.vhidDeviceManager)
        }

        if vhidDeviceManager.detectActivation() {
            installed.append(.vhidDeviceActivation)
        } else {
            missing.append(.vhidDeviceActivation)
        }

        // Check both daemon running AND connection health (like ComponentDetector)
        let daemonRunning = vhidDeviceManager.detectRunning()
        let connectionHealthy = vhidDeviceManager.detectConnectionHealth()

        if daemonRunning, connectionHealthy {
            installed.append(.vhidDeviceRunning)
        } else {
            missing.append(.vhidDeviceRunning)

            // Add specific diagnostic if daemon is running but connection is unhealthy
            if daemonRunning, !connectionHealthy {
                AppLogger.shared.log(
                    "⚠️ [SystemStatusChecker] VirtualHID daemon running but connection unhealthy")
            }
        }

        // Check LaunchDaemon services - handle mixed scenarios properly (same logic as ComponentDetector)
        let daemonStatus = launchDaemonInstaller.getServiceStatus()
        if daemonStatus.allServicesHealthy {
            installed.append(.launchDaemonServices)
        } else {
            // Check if any services are loaded but unhealthy (priority over not installed)
            let hasLoadedButUnhealthy =
                (daemonStatus.kanataServiceLoaded && !daemonStatus.kanataServiceHealthy)
                    || (daemonStatus.vhidDaemonServiceLoaded && !daemonStatus.vhidDaemonServiceHealthy)
                    || (daemonStatus.vhidManagerServiceLoaded && !daemonStatus.vhidManagerServiceHealthy)

            if hasLoadedButUnhealthy {
                // At least one service is loaded but crashing - prioritize restart over install
                missing.append(.launchDaemonServicesUnhealthy)
                AppLogger.shared.log(
                    "🔍 [SystemStatusChecker] MIXED SCENARIO: Some LaunchDaemon services loaded but unhealthy: \(daemonStatus.description)"
                )
            } else {
                // No services are loaded/installed
                missing.append(.launchDaemonServices)
                AppLogger.shared.log(
                    "🔍 [SystemStatusChecker] LaunchDaemon services not installed: \(daemonStatus.description)"
                )
            }
        }

        // Verify VHID daemon plist is correctly configured to DriverKit path
        if !launchDaemonInstaller.isVHIDDaemonConfiguredCorrectly() {
            missing.append(.vhidDaemonMisconfigured)
        }

        // Check Karabiner driver components
        if await MainActor.run(body: { kanataManager.isKarabinerDriverInstalled() }) {
            installed.append(.karabinerDriver)
        } else {
            missing.append(.karabinerDriver)
        }

        if await MainActor.run(body: { kanataManager.isKarabinerDaemonRunning() }) {
            installed.append(.karabinerDaemon)
        } else {
            missing.append(.karabinerDaemon)
        }

        // Check Kanata service configuration (both service files AND config file)
        let serviceStatus = launchDaemonInstaller.getServiceStatus()
        let configPath = WizardSystemPaths.userConfigPath
        let userConfigExists = FileManager.default.fileExists(atPath: configPath)

        AppLogger.shared.log("🔍 [SystemStatusChecker] Checking config at: \(configPath) (exists: \(userConfigExists))")

        if serviceStatus.kanataServiceLoaded, userConfigExists, serviceStatus.kanataServiceHealthy {
            // Service is loaded, config exists, AND service is healthy
            installed.append(.kanataService)
            AppLogger.shared.log(
                "✅ [SystemStatusChecker] Kanata service: service loaded, healthy AND config file exists")
        } else if serviceStatus.kanataServiceLoaded, !serviceStatus.kanataServiceHealthy {
            // Service loaded but unhealthy - let LaunchDaemonServicesUnhealthy handle this
            AppLogger.shared.log(
                "🔍 [SystemStatusChecker] Kanata service loaded but unhealthy - will be handled by LaunchDaemonServicesUnhealthy"
            )
        } else {
            // Service not loaded or config missing
            missing.append(.kanataService)
            let reason = !serviceStatus.kanataServiceLoaded ? "service not loaded" : "config file missing"
            AppLogger.shared.log("❌ [SystemStatusChecker] Kanata service missing: \(reason)")
        }

        // Check Kanata TCP server configuration and status
        await checkUDPConfiguration(missing: &missing, installed: &installed)

        AppLogger.shared.log("🔍 [SystemStatusChecker] Component check complete:")
        AppLogger.shared.log("  - Installed: \(installed.count) components")
        AppLogger.shared.log("  - Missing: \(missing.count) components")

        return ComponentCheckResult(
            missing: missing,
            installed: installed,
            canAutoInstall: !missing.isEmpty // Can auto-install if something is missing
        )
    }

    // MARK: - Conflict Detection

    private func checkConflictsInternal() async -> ConflictDetectionResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Detecting conflicts...")

        let conflictResolution = await processLifecycleManager.detectConflicts()
        let conflicts = convertToSystemConflicts(conflictResolution.externalProcesses)

        return ConflictDetectionResult(
            conflicts: conflicts,
            canAutoResolve: conflictResolution.canAutoResolve,
            description: conflicts.isEmpty
                ? "No conflicts detected" : "\(conflicts.count) conflict(s) detected"
        )
    }

    private func convertToSystemConflicts(_ processes: [ProcessLifecycleManager.ProcessInfo])
        -> [SystemConflict] {
        // With PID file tracking, all external processes are conflicts
        // The ProcessLifecycleManager already filtered out our owned process
        processes.map { process in
            .kanataProcessRunning(pid: Int(process.pid), command: process.command)
        }
    }

    // MARK: - Health Checking

    private func performSystemHealthCheck() async -> HealthCheckResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Performing system health checks")

        let kanataHealthy = await isKanataServiceFunctional()
        let vhidHealthy = isVirtualHIDHealthy()
        let daemonHealthy = isKarabinerDaemonHealthy()

        let overallHealthy = kanataHealthy && vhidHealthy && daemonHealthy

        AppLogger.shared.log("🔍 [SystemStatusChecker] Health check results:")
        AppLogger.shared.log("  - Kanata service: \(kanataHealthy)")
        AppLogger.shared.log("  - VirtualHID: \(vhidHealthy)")
        AppLogger.shared.log("  - Karabiner daemon: \(daemonHealthy)")
        AppLogger.shared.log("  - Overall: \(overallHealthy)")

        return HealthCheckResult(
            isKanataFunctional: kanataHealthy,
            isVirtualHIDHealthy: vhidHealthy,
            isKarabinerDaemonHealthy: daemonHealthy,
            overallHealthy: overallHealthy
        )
    }

    private func isKanataServiceFunctional() async -> Bool {
        // If Kanata isn't running, it's definitely not functional
        guard kanataManager.isRunning else {
            AppLogger.shared.log("🔍 [SystemStatusChecker] Kanata not running - not functional")
            return false
        }

        // Check if there are active diagnostics indicating problems
        let hasActiveErrors = kanataManager.diagnostics.contains { diagnostic in
            diagnostic.severity == .error
                && (diagnostic.category == .conflict || diagnostic.category == .permissions
                    || diagnostic.category == .process)
        }

        if hasActiveErrors {
            AppLogger.shared.log(
                "🔍 [SystemStatusChecker] Kanata has active error diagnostics - not functional")
            return false
        }

        // Use VirtualHID connection health as a proxy for Kanata functionality
        let vhidHealth = vhidDeviceManager.detectConnectionHealth()
        if !vhidHealth {
            AppLogger.shared.log(
                "🔍 [SystemStatusChecker] VirtualHID connection unhealthy - Kanata not functional")
            return false
        }

        AppLogger.shared.log("🔍 [SystemStatusChecker] Kanata service appears functional")
        return true
    }

    private func isVirtualHIDHealthy() -> Bool {
        let status = vhidDeviceManager.getDetailedStatus()
        let isHealthy = status.isFullyOperational

        AppLogger.shared.log("🔍 [SystemStatusChecker] VirtualHID health status: \(isHealthy)")
        AppLogger.shared.log("🔍 [SystemStatusChecker] \(status.description)")

        return isHealthy
    }

    private func isKarabinerDaemonHealthy() -> Bool {
        let daemonRunning = kanataManager.isKarabinerDaemonRunning()
        AppLogger.shared.log("🔍 [SystemStatusChecker] Karabiner daemon health: \(daemonRunning)")
        return daemonRunning
    }

    // MARK: - Auto-Fix Action Determination

    private func determineAutoFixActions(
        conflicts: ConflictDetectionResult,
        permissions _: PermissionCheckResult,
        components: ComponentCheckResult,
        health: HealthCheckResult,
        needsLogRotation: Bool = false
    ) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        if conflicts.hasConflicts, conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check if we need to install bundled kanata binary
        let kanataNeeded = components.missing.contains(.kanataBinaryMissing)

        if kanataNeeded {
            actions.append(.installBundledKanata)
        }

        if components.canAutoInstall {
            actions.append(.installMissingComponents)
        }

        if !health.isKarabinerDaemonHealthy {
            actions.append(.startKarabinerDaemon)
        }

        // Check if VHIDDevice Manager needs activation
        if components.missing.contains(.vhidDeviceActivation),
           components.installed.contains(.vhidDeviceManager) {
            actions.append(.activateVHIDDeviceManager)
        }

        // Check if LaunchDaemon services need installation
        if components.missing.contains(.launchDaemonServices) {
            actions.append(.installLaunchDaemonServices)
        }

        // Check if log rotation should be installed
        if needsLogRotation {
            actions.append(.installLogRotation)
        }

        return actions
    }

    // MARK: - State Determination

    private func determineSystemState(
        compatibility: SystemRequirements.ValidationResult,
        permissions: PermissionCheckResult,
        components: ComponentCheckResult,
        conflicts: ConflictDetectionResult,
        health: HealthCheckResult
    ) async -> WizardSystemState {
        // If system is not compatible
        if !compatibility.isCompatible {
            return .initializing // Use initializing for compatibility issues
        }

        // If there are conflicts that need resolution
        if !conflicts.conflicts.isEmpty {
            return .conflictsDetected(conflicts: conflicts.conflicts)
        }

        // If permissions are missing
        if !permissions.missing.isEmpty {
            return .missingPermissions(missing: permissions.missing)
        }

        // If components are missing
        if !components.missing.isEmpty {
            return .missingComponents(missing: components.missing)
        }

        // Check specific service states
        if !health.isKarabinerDaemonHealthy {
            return .daemonNotRunning
        }

        // Check if Kanata is running, regardless of health
        // This ensures consistency between summary and detail pages
        if await MainActor.run(body: { kanataManager.isRunning }) {
            return .active // Show as active even if unhealthy
        }

        // If not running but everything else is ready
        if !health.isKanataFunctional {
            return .serviceNotRunning
        }

        // All components installed but service not running
        return .ready
    }

    // MARK: - UDP Server Status

    /// Check UDP server configuration and status with detailed detection
    private func checkUDPConfiguration(missing: inout [ComponentRequirement], installed: inout [ComponentRequirement]) async {
        let commConfig = PreferencesService.communicationSnapshot()

        // If UDP is disabled in preferences, mark as installed (no issue)
        guard commConfig.shouldUseUDP else {
            installed.append(.kanataUDPServer)
            AppLogger.shared.log("📡 [SystemStatusChecker] UDP server disabled in preferences - no issue")
            return
        }

        AppLogger.shared.log("📡 [SystemStatusChecker] UDP server enabled in preferences (port \(commConfig.udpPort))")

        // First, check if kanata service is actually healthy - UDP requires kanata to be running
        let serviceStatus = launchDaemonInstaller.getServiceStatus()
        guard serviceStatus.kanataServiceLoaded, serviceStatus.kanataServiceHealthy else {
            AppLogger.shared.log("⚠️ [SystemStatusChecker] Skipping UDP checks - kanata service not healthy (loaded: \(serviceStatus.kanataServiceLoaded), healthy: \(serviceStatus.kanataServiceHealthy))")
            AppLogger.shared.log("💡 [SystemStatusChecker] UDP server requires kanata to be running - fix service issues first")
            return // Don't report UDP issues if the underlying service isn't working
        }

        AppLogger.shared.log("✅ [SystemStatusChecker] Kanata service is healthy, proceeding with UDP diagnostics")

        // Check if LaunchDaemon plist has matching UDP configuration
        guard launchDaemonInstaller.isServiceConfigurationCurrent() else {
            missing.append(.udpServerConfiguration)
            AppLogger.shared.log("❌ [SystemStatusChecker] UDP server configuration mismatch - plist needs regeneration")
            return
        }

        AppLogger.shared.log("✅ [SystemStatusChecker] UDP configuration matches LaunchDaemon plist")

        // Use comprehensive communication testing for detailed status
        let commTestResult = await checkComprehensiveCommunicationStatus()
        AppLogger.shared.log("📡 [SystemStatusChecker] Comprehensive communication test result: \(commTestResult)")

        switch commTestResult {
        case .fullyFunctional:
            installed.append(.kanataUDPServer)
            AppLogger.shared.log("✅ [SystemStatusChecker] UDP server fully functional on port \(commConfig.udpPort)")
        case .serviceUnhealthy:
            // Don't add as issue - service health issues are handled by other components
            // This prevents false UDP errors when the underlying service needs fixing first
            AppLogger.shared.log("⚠️ [SystemStatusChecker] Service unhealthy - UDP testing skipped (no false UDP errors)")
        case .configurationOutdated:
            // Configuration issue - matches what checkUDPConfiguration already detected
            missing.append(.udpServerConfiguration)
            AppLogger.shared.log("❌ [SystemStatusChecker] UDP configuration outdated - comprehensive test confirms checkUDPConfiguration")
        case .notResponding:
            missing.append(.udpServerNotResponding)
            AppLogger.shared.log("❌ [SystemStatusChecker] UDP server not responding on port \(commConfig.udpPort)")
        case .authenticationRequired, .reloadFailed:
            // These are functional issues but server is responding
            missing.append(.udpServerNotResponding) // Will be handled by communication page for setup
            AppLogger.shared.log("❌ [SystemStatusChecker] UDP server has authentication/reload issues: \(commTestResult)")
        case .notEnabled:
            // This shouldn't happen since we checked shouldUseUDP above, but handle gracefully
            installed.append(.kanataUDPServer) // No issue if UDP is supposed to be disabled
            AppLogger.shared.log("⚠️ [SystemStatusChecker] UDP server not enabled (unexpected at this point)")
        }
    }

    /// Comprehensive communication test result
    enum CommunicationTestResult {
        case notEnabled
        case serviceUnhealthy
        case configurationOutdated
        case notResponding
        case authenticationRequired
        case reloadFailed
        case fullyFunctional

        var isWorking: Bool {
            self == .fullyFunctional
        }
    }

    /// Check if Kanata UDP server is responding with comprehensive testing
    private func checkUDPServerStatus() async -> Bool {
        let result = await checkComprehensiveCommunicationStatus()
        return result.isWorking
    }

    /// Comprehensive communication status check that mirrors WizardCommunicationPage testing
    func checkComprehensiveCommunicationStatus() async -> CommunicationTestResult {
        let commConfig = PreferencesService.communicationSnapshot()

        // If UDP is disabled in preferences, not enabled
        guard commConfig.shouldUseUDP else {
            AppLogger.shared.log("📡 [SystemStatusChecker] UDP server disabled in preferences")
            return .notEnabled
        }

        // CRITICAL: Check service health before UDP tests to match checkUDPConfiguration logic
        let serviceStatus = launchDaemonInstaller.getServiceStatus()
        guard serviceStatus.kanataServiceLoaded, serviceStatus.kanataServiceHealthy else {
            AppLogger.shared.log("⚠️ [SystemStatusChecker] Service unhealthy (loaded: \(serviceStatus.kanataServiceLoaded), healthy: \(serviceStatus.kanataServiceHealthy)) - cannot test UDP")
            return .serviceUnhealthy
        }

        // CRITICAL: Check configuration currency - this is what causes summary/detail inconsistency
        guard launchDaemonInstaller.isServiceConfigurationCurrent() else {
            AppLogger.shared.log("❌ [SystemStatusChecker] UDP configuration outdated - plist needs regeneration before testing")
            return .configurationOutdated
        }

        // Check if kanata service is actually running with UDP port
        if !kanataManager.isRunning {
            AppLogger.shared.log("📡 [SystemStatusChecker] WARNING: KanataManager.isRunning=false but service is healthy, proceeding with UDP check")
        } else {
            AppLogger.shared.log("📡 [SystemStatusChecker] KanataManager.isRunning=true and service healthy, proceeding with UDP check")
        }

        // Use SharedUDPClientService to check server status
        let sharedService = SharedUDPClientService.shared
        let client = sharedService.getClient(port: commConfig.udpPort)
        AppLogger.shared.log("🧪 [SystemStatusChecker] Testing UDP server on port \(commConfig.udpPort) with race-free implementation...")
        let serverResponding = await client.checkServerStatus()
        AppLogger.shared.log("🧪 [SystemStatusChecker] SharedUDPClientService client.checkServerStatus() returned: \(serverResponding)")

        guard serverResponding else {
            AppLogger.shared.log("📡 [SystemStatusChecker] UDP server status check: port \(commConfig.udpPort) - not responding")
            return .notResponding
        }

        AppLogger.shared.log("📡 [SystemStatusChecker] UDP server responding, testing authentication...")

        // Test authentication like WizardCommunicationPage does
        return await testUDPAuthentication(client: client)
    }

    /// Test UDP authentication and config reload capability
    private func testUDPAuthentication(client: KanataUDPClient) async -> CommunicationTestResult {
        let preferences = PreferencesService.shared
        let authToken = preferences.udpAuthToken

        // Check if we have an auth token
        guard !authToken.isEmpty else {
            AppLogger.shared.log("🔐 [SystemStatusChecker] No auth token available - authentication required")
            return .authenticationRequired
        }

        // Try existing token
        AppLogger.shared.log("🔐 [SystemStatusChecker] Testing existing auth token...")
        let authenticated = await client.authenticate(token: authToken)
        guard authenticated else {
            AppLogger.shared.log("🔐 [SystemStatusChecker] Existing auth token failed - authentication required")
            return .authenticationRequired
        }

        AppLogger.shared.log("✅ [SystemStatusChecker] Authentication successful, testing config reload...")

        // Test config reload capability to ensure full functionality
        let result = await client.reloadConfig()
        switch result {
        case .success:
            AppLogger.shared.log("✅ [SystemStatusChecker] Config reload test successful - fully functional")
            return .fullyFunctional
        case .authenticationRequired:
            AppLogger.shared.log("❌ [SystemStatusChecker] Config reload requires fresh auth - authentication required")
            return .authenticationRequired
        case .failure, .networkError:
            AppLogger.shared.log("❌ [SystemStatusChecker] Config reload test failed - reload capability broken")
            return .reloadFailed
        }
    }

    // MARK: - Log Rotation Detection

    /// Check if log rotation should be installed (for new users or when logs exceed size limits)
    private func shouldInstallLogRotation() async -> Bool {
        // Check if log rotation service is already installed
        if launchDaemonInstaller.isLogRotationServiceInstalled() {
            AppLogger.shared.log("📝 [LogRotation] Log rotation service already installed")
            return false
        }

        // Check current Kanata log size (fast check)
        let logPath = "/var/log/kanata.log"
        guard FileManager.default.fileExists(atPath: logPath) else {
            AppLogger.shared.log("📝 [LogRotation] No Kanata log found yet - recommending installation for new users")
            return true // Install for new users
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logPath)
            let fileSize = attributes[.size] as? Int ?? 0
            let sizeMB = fileSize / (1024 * 1024)

            // Recommend installation if log is large, OR if log is very small (proactive installation for new systems)
            if sizeMB >= 5 {
                AppLogger.shared.log("📝 [LogRotation] Kanata log is \(sizeMB)MB - recommending log rotation installation")
                return true
            } else if fileSize < 1024 { // Less than 1KB - likely a fresh system
                AppLogger.shared.log("📝 [LogRotation] Kanata log is very small (\(fileSize) bytes) - recommending proactive log rotation installation")
                return true
            } else {
                AppLogger.shared.log("📝 [LogRotation] Kanata log is \(sizeMB)MB - within size limits, not recommending")
                return false
            }
        } catch {
            AppLogger.shared.log("📝 [LogRotation] Error checking log size: \(error) - recommending installation")
            return true // Install if we can't check size
        }
    }

    // MARK: - Debug Methods

    /// Create a debug state that forces Input Monitoring issues for testing
    private func createDebugInputMonitoringState() -> SystemStateResult {
        let debugIssues: [WizardIssue] = [
            WizardIssue(
                identifier: .permission(.keyPathInputMonitoring),
                severity: .error,
                category: .permissions,
                title: "KeyPath Input Monitoring Required",
                description: "KeyPath needs Input Monitoring permission to record keyboard shortcuts.",
                autoFixAction: nil,
                userAction: "Grant permission in System Settings > Privacy & Security > Input Monitoring"
            ),
            WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .error,
                category: .permissions,
                title: "Kanata Input Monitoring Required",
                description: "Kanata binary needs Input Monitoring permission to intercept keystrokes.",
                autoFixAction: nil,
                userAction: "Grant permission in System Settings > Privacy & Security > Input Monitoring"
            )
        ]

        return SystemStateResult(
            state: .missingPermissions(missing: [.keyPathInputMonitoring, .kanataInputMonitoring]),
            issues: debugIssues,
            autoFixActions: [],
            detectionTimestamp: Date()
        )
    }
}

// MARK: - Supporting Types

/// Health check results
struct HealthCheckResult {
    let isKanataFunctional: Bool
    let isVirtualHIDHealthy: Bool
    let isKarabinerDaemonHealthy: Bool
    let overallHealthy: Bool
}

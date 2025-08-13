import ApplicationServices
import Foundation

/// Unified system status checker that consolidates all detection logic
/// Replaces: ComponentDetector, SystemHealthChecker, SystemRequirements, SystemStateDetector
@MainActor
class SystemStatusChecker {
    private let kanataManager: KanataManager
    private let vhidDeviceManager: VHIDDeviceManager
    private let launchDaemonInstaller: LaunchDaemonInstaller
    private let packageManager: PackageManager
    private let processLifecycleManager: ProcessLifecycleManager
    private let issueGenerator: IssueGenerator

    init(kanataManager: KanataManager) {
        self.kanataManager = kanataManager
        vhidDeviceManager = VHIDDeviceManager()
        launchDaemonInstaller = LaunchDaemonInstaller()
        packageManager = PackageManager()
        processLifecycleManager = ProcessLifecycleManager(kanataManager: kanataManager)
        issueGenerator = IssueGenerator()
    }

    // MARK: - Debug Support

    /// Debug flag to force Input Monitoring issues for testing purposes
    static var debugForceInputMonitoringIssues = false

    // MARK: - Main Detection Method

    func detectCurrentState() async -> SystemStateResult {
        AppLogger.shared.log("🔍 [SystemStatusChecker] Starting comprehensive system state detection")

        // Debug override for testing Input Monitoring page
        if SystemStatusChecker.debugForceInputMonitoringIssues {
            AppLogger.shared.log(
                "🧪 [SystemStatusChecker] DEBUG: Forcing Input Monitoring issues for testing")
            return createDebugInputMonitoringState()
        }

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

        // Determine system state
        let systemState = determineSystemState(
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
            health: healthStatus
        )

        AppLogger.shared.log(
            "🔍 [SystemStatusChecker] Detection complete: \(systemState), \(allIssues.count) issues, \(autoFixableActions.count) auto-fixes"
        )

        return SystemStateResult(
            state: systemState,
            issues: allIssues,
            autoFixActions: autoFixableActions,
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

        // Use simplified PermissionService
        let systemStatus = PermissionService.shared.checkSystemPermissions(
            kanataBinaryPath: WizardSystemPaths.kanataActiveBinary)

        // KeyPath permissions (these are reliable)
        if systemStatus.keyPath.hasInputMonitoring {
            granted.append(.keyPathInputMonitoring)
        } else {
            missing.append(.keyPathInputMonitoring)
        }

        if systemStatus.keyPath.hasAccessibility {
            granted.append(.keyPathAccessibility)
        } else {
            missing.append(.keyPathAccessibility)
        }

        // Kanata permissions - we assume they're OK and will detect on actual use
        // This prevents false negatives from TCC database delays
        // Always mark kanata permissions as granted to avoid wizard getting stuck
        granted.append(.kanataInputMonitoring)
        granted.append(.kanataAccessibility)

        AppLogger.shared.log(
            "ℹ️ [SystemStatusChecker] Kanata permissions assumed OK (will verify on start)")

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

        // Check Kanata binary - use KanataManager's method for consistency
        if kanataManager.isInstalled() {
            installed.append(.kanataBinary)
        } else {
            missing.append(.kanataBinary)
        }

        // Check package manager (Homebrew) - use PackageManager's method
        if packageManager.isInstalled() {
            installed.append(.packageManager)
        } else {
            missing.append(.packageManager)
        }

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

        // Check LaunchDaemon services - use proper service status method
        let daemonStatus = launchDaemonInstaller.getServiceStatus()
        if daemonStatus.allServicesLoaded {
            installed.append(.launchDaemonServices)
        } else {
            missing.append(.launchDaemonServices)
        }

        // Verify VHID daemon plist is correctly configured to DriverKit path
        if !launchDaemonInstaller.isVHIDDaemonConfiguredCorrectly() {
            missing.append(.vhidDaemonMisconfigured)
        }

        // Check Karabiner driver components
        if kanataManager.isKarabinerDriverInstalled() {
            installed.append(.karabinerDriver)
        } else {
            missing.append(.karabinerDriver)
        }

        if kanataManager.isKarabinerDaemonRunning() {
            installed.append(.karabinerDaemon)
        } else {
            missing.append(.karabinerDaemon)
        }

        // Check Kanata service configuration (both service files AND config file)
        let serviceStatus = launchDaemonInstaller.getServiceStatus()
        let systemConfigExists = FileManager.default.fileExists(atPath: WizardSystemPaths.systemConfigPath)

        if serviceStatus.kanataServiceLoaded, systemConfigExists {
            installed.append(.kanataService)
            AppLogger.shared.log("✅ [SystemStatusChecker] Kanata service: service loaded AND config file exists")
        } else {
            missing.append(.kanataService)
            let reason = !serviceStatus.kanataServiceLoaded ? "service not loaded" : "config file missing"
            AppLogger.shared.log("❌ [SystemStatusChecker] Kanata service missing: \(reason)")
        }

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
        -> [SystemConflict]
    {
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
        health: HealthCheckResult
    ) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        if conflicts.hasConflicts, conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check if we can install missing packages via Homebrew
        let homebrewAvailable = components.installed.contains(.packageManager)
        let kanataNeeded = components.missing.contains(.kanataBinary)

        if homebrewAvailable, kanataNeeded {
            actions.append(.installViaBrew)
        }

        if components.canAutoInstall {
            actions.append(.installMissingComponents)
        }

        if !health.isKarabinerDaemonHealthy {
            actions.append(.startKarabinerDaemon)
        }

        // Check if VHIDDevice Manager needs activation
        if components.missing.contains(.vhidDeviceActivation),
           components.installed.contains(.vhidDeviceManager)
        {
            actions.append(.activateVHIDDeviceManager)
        }

        // Check if LaunchDaemon services need installation
        if components.missing.contains(.launchDaemonServices) {
            actions.append(.installLaunchDaemonServices)
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
    ) -> WizardSystemState {
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

        if !health.isKanataFunctional {
            return .serviceNotRunning
        }

        // All good!
        if kanataManager.isRunning {
            return .active
        } else {
            return .ready
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
            ),
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

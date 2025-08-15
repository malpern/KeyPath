import ApplicationServices
import Foundation

/// Orchestrates system state detection using specialized detector classes
/// Coordinates between different detection areas and provides unified results
@MainActor
class SystemStateDetector: SystemStateDetecting {
    private let systemRequirements: SystemRequirements
    private let healthChecker: SystemHealthChecker
    private let componentDetector: ComponentDetector
    private let processLifecycleManager: ProcessLifecycleManager
    private let issueGenerator: IssueGenerator
    private let launchDaemonInstaller: LaunchDaemonInstaller

    // MARK: - Debouncing State

    private var lastConflictState: Bool = false
    private var lastStateChange: Date = .init()
    private let stateChangeDebounceTime: TimeInterval = 0.5 // 500ms

    init(
        kanataManager: KanataManager,
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller(),
        systemRequirements: SystemRequirements = SystemRequirements(),
        packageManager: PackageManager = PackageManager()
    ) {
        self.systemRequirements = systemRequirements
        healthChecker = SystemHealthChecker(
            kanataManager: kanataManager,
            vhidDeviceManager: vhidDeviceManager
        )
        componentDetector = ComponentDetector(
            kanataManager: kanataManager,
            vhidDeviceManager: vhidDeviceManager,
            launchDaemonInstaller: launchDaemonInstaller,
            systemRequirements: systemRequirements,
            packageManager: packageManager
        )
        processLifecycleManager = ProcessLifecycleManager(kanataManager: kanataManager)
        issueGenerator = IssueGenerator()
        self.launchDaemonInstaller = launchDaemonInstaller
    }

    // MARK: - Main Detection Method

    func detectCurrentState() async -> SystemStateResult {
        AppLogger.shared.log("🔍 [StateDetector] Starting comprehensive system state detection")

        // Check system compatibility first
        let compatibilityResult = systemRequirements.validateSystemCompatibility()

        // Use specialized detectors for each area
        let conflictResult = await detectConflictsUsingProcessLifecycleManager()
        let permissionResult = await componentDetector.checkPermissions()
        var componentResult = await componentDetector.checkComponents()
        let healthStatus = await healthChecker.performSystemHealthCheck()
        let configPathResult = await detectConfigPathMismatch()

        // Check for orphaned Kanata processes and compute recommended action
        let orphanedAutoFix = await computeOrphanedProcessAutoFix()
        if let orphanedProcessRequirement = await detectOrphanedKanataProcess() {
            AppLogger.shared.log("🔍 [StateDetector] Adding orphaned process to missing components")
            componentResult = ComponentCheckResult(
                missing: componentResult.missing + [orphanedProcessRequirement],
                installed: componentResult.installed,
                canAutoInstall: true // Orphaned processes can be auto-fixed
            )
        }

        // Service and daemon status from health checker
        let serviceRunning = healthStatus.kanataServiceFunctional
        let daemonRunning = healthStatus.karabinerDaemonHealthy

        // Determine overall state
        let state = determineOverallState(
            compatibility: compatibilityResult,
            conflicts: conflictResult,
            permissions: permissionResult,
            components: componentResult,
            serviceRunning: serviceRunning,
            daemonRunning: daemonRunning
        )

        // Generate issues using specialized issue generator
        var issues: [WizardIssue] = []
        issues.append(
            contentsOf: issueGenerator.createSystemRequirementIssues(from: compatibilityResult))
        issues.append(contentsOf: issueGenerator.createConflictIssues(from: conflictResult))
        issues.append(contentsOf: issueGenerator.createPermissionIssues(from: permissionResult))
        issues.append(contentsOf: issueGenerator.createComponentIssues(from: componentResult))
        issues.append(contentsOf: issueGenerator.createConfigPathIssues(from: configPathResult))

        if !daemonRunning {
            issues.append(issueGenerator.createDaemonIssue())
        }

        // Determine available auto-fix actions including orphaned process fix
        let autoFixActions = determineAutoFixActions(
            conflicts: conflictResult,
            permissions: permissionResult,
            components: componentResult,
            configPaths: configPathResult,
            daemonRunning: daemonRunning,
            orphanedAutoFix: orphanedAutoFix
        )

        let result = SystemStateResult(
            state: state,
            issues: issues,
            autoFixActions: autoFixActions,
            detectionTimestamp: Date()
        )

        AppLogger.shared.log(
            "🔍 [StateDetector] Detection complete: \(state), \(issues.count) issues, \(autoFixActions.count) auto-fixes"
        )
        return result
    }

    // MARK: - State Determination

    private func determineOverallState(
        compatibility: SystemRequirements.ValidationResult,
        conflicts: ConflictDetectionResult,
        permissions: PermissionCheckResult,
        components: ComponentCheckResult,
        serviceRunning: Bool,
        daemonRunning: Bool
    ) -> WizardSystemState {
        // Priority order: compatibility > conflicts > missing components > missing permissions > daemon > service > ready

        // System compatibility is the highest priority
        if !compatibility.isCompatible {
            return .initializing // Use initializing state for compatibility issues since we don't have a specific state
        }

        if conflicts.hasConflicts {
            return .conflictsDetected(conflicts: conflicts.conflicts)
        }

        if !components.allInstalled {
            return .missingComponents(missing: components.missing)
        }

        if !permissions.allGranted {
            return .missingPermissions(missing: permissions.missing)
        }

        if !daemonRunning {
            return .daemonNotRunning
        }

        if !serviceRunning {
            return .serviceNotRunning
        }

        return .active
    }

    // MARK: - Auto-Fix Action Determination

    private func determineAutoFixActions(
        conflicts: ConflictDetectionResult,
        permissions _: PermissionCheckResult,
        components: ComponentCheckResult,
        configPaths: ConfigPathMismatchResult,
        daemonRunning: Bool,
        orphanedAutoFix: AutoFixAction?
    ) -> [AutoFixAction] {
        var actions: [AutoFixAction] = []

        if conflicts.hasConflicts, conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }

        // Check if config path synchronization is needed
        if configPaths.hasMismatches, configPaths.canAutoResolve {
            actions.append(.synchronizeConfigPaths)
        }

        // Include orphaned process auto-fix recommendation
        if let orphanedFix = orphanedAutoFix {
            actions.append(orphanedFix)
            AppLogger.shared.log("🔍 [StateDetector] Including orphaned process auto-fix: \(orphanedFix)")
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

        if !daemonRunning {
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

        return actions
    }

    // MARK: - SystemStateDetecting Protocol Methods

    func detectConflicts() async -> ConflictDetectionResult {
        await detectConflictsUsingProcessLifecycleManager()
    }

    func checkPermissions() async -> PermissionCheckResult {
        await componentDetector.checkPermissions()
    }

    func checkComponents() async -> ComponentCheckResult {
        await componentDetector.checkComponents()
    }

    // MARK: - ProcessLifecycleManager Integration

    /// Adapter method to convert ProcessLifecycleManager conflicts to SystemStateDetector format
    /// Includes debouncing to prevent rapid state changes that cause UI flicker
    private func detectConflictsUsingProcessLifecycleManager() async -> ConflictDetectionResult {
        let conflicts = await processLifecycleManager.detectConflicts()

        // Convert ProcessLifecycleManager ProcessInfo to SystemConflict
        let systemConflicts: [SystemConflict] = conflicts.externalProcesses.map { processInfo in
            .kanataProcessRunning(pid: Int(processInfo.pid), command: processInfo.command)
        }

        let hasConflicts = !systemConflicts.isEmpty

        // Apply debouncing logic to prevent rapid state changes
        let shouldUpdateState = shouldUpdateConflictState(hasConflicts)
        if !shouldUpdateState {
            // Return previous state to prevent flicker
            AppLogger.shared.log("🔄 [StateDetector] Debouncing conflict state change - maintaining previous state: \(lastConflictState)")

            // Create result based on previous state
            let debouncedConflicts = lastConflictState ? systemConflicts : []
            let description = debouncedConflicts.isEmpty
                ? "No conflicts detected (debounced)"
                : "Found \(debouncedConflicts.count) external processes (debounced): "
                + debouncedConflicts.map { conflict in
                    switch conflict {
                    case let .kanataProcessRunning(pid, _):
                        "Kanata process (PID: \(pid))"
                    case let .karabinerGrabberRunning(pid):
                        "Karabiner grabber (PID: \(pid))"
                    case let .karabinerVirtualHIDDeviceRunning(pid, processName):
                        "\(processName) (PID: \(pid))"
                    case let .karabinerVirtualHIDDaemonRunning(pid):
                        "Karabiner daemon (PID: \(pid))"
                    case let .exclusiveDeviceAccess(device):
                        "Device access: \(device)"
                    }
                }.joined(separator: "; ")

            return ConflictDetectionResult(
                conflicts: debouncedConflicts,
                canAutoResolve: conflicts.canAutoResolve,
                description: description,
                managedProcesses: conflicts.managedProcesses
            )
        }

        let description =
            systemConflicts.isEmpty
                ? "No conflicts detected"
                : "Found \(systemConflicts.count) external processes: "
                + systemConflicts.map { conflict in
                    switch conflict {
                    case let .kanataProcessRunning(pid, _):
                        "Kanata process (PID: \(pid))"
                    case let .karabinerGrabberRunning(pid):
                        "Karabiner grabber (PID: \(pid))"
                    case let .karabinerVirtualHIDDeviceRunning(pid, processName):
                        "\(processName) (PID: \(pid))"
                    case let .karabinerVirtualHIDDaemonRunning(pid):
                        "Karabiner daemon (PID: \(pid))"
                    case let .exclusiveDeviceAccess(device):
                        "Device access: \(device)"
                    }
                }.joined(separator: "; ")

        return ConflictDetectionResult(
            conflicts: systemConflicts,
            canAutoResolve: conflicts.canAutoResolve,
            description: description,
            managedProcesses: conflicts.managedProcesses
        )
    }

    /// Check if conflict state should be updated based on debouncing logic
    private func shouldUpdateConflictState(_ newState: Bool) -> Bool {
        let timeSinceLastChange = Date().timeIntervalSince(lastStateChange)

        // If state hasn't changed, always allow update
        if newState == lastConflictState {
            return true
        }

        // If state changed but not enough time has passed, debounce it
        if timeSinceLastChange < stateChangeDebounceTime {
            AppLogger.shared.log("🔄 [StateDetector] Debouncing state change: \(lastConflictState) -> \(newState) (only \(String(format: "%.1f", timeSinceLastChange * 1000))ms elapsed)")
            return false
        }

        // Enough time has passed, allow the state change
        lastConflictState = newState
        lastStateChange = Date()
        AppLogger.shared.log("🔄 [StateDetector] State change allowed: \(lastConflictState) -> \(newState) (after \(String(format: "%.1f", timeSinceLastChange * 1000))ms)")
        return true
    }

    // MARK: - Config Path Mismatch Detection

    /// Detect if Kanata is running with a different config path than KeyPath expects
    private func detectConfigPathMismatch() async -> ConfigPathMismatchResult {
        AppLogger.shared.log("🔍 [ConfigPath] Checking for config path mismatches")

        // Get the expected KeyPath config path
        let expectedPath = normalizedPath(WizardSystemPaths.userConfigPath)

        // Check what config path Kanata is actually using
        let kanataProcesses = await processLifecycleManager.detectConflicts()
        let allKanataProcesses = kanataProcesses.managedProcesses + kanataProcesses.externalProcesses

        var mismatches: [ConfigPathMismatch] = []

        for process in allKanataProcesses {
            // Parse the command line to extract --cfg parameter
            let command = process.command
            if let configPath = extractConfigPath(from: command) {
                let normalizedActualPath = normalizedPath(configPath)
                if normalizedActualPath != expectedPath {
                    let mismatch = ConfigPathMismatch(
                        processPID: process.pid,
                        processCommand: command,
                        actualConfigPath: configPath,
                        expectedConfigPath: WizardSystemPaths.userConfigPath
                    )
                    mismatches.append(mismatch)
                    AppLogger.shared.log(
                        "⚠️ [ConfigPath] Mismatch detected - Process \(process.pid) using '\(normalizedActualPath)' but KeyPath expects '\(expectedPath)'"
                    )
                }
            }
        }

        if mismatches.isEmpty {
            AppLogger.shared.log("✅ [ConfigPath] No config path mismatches detected")
        } else {
            AppLogger.shared.log("🚨 [ConfigPath] Found \(mismatches.count) config path mismatch(es)")
        }

        return ConfigPathMismatchResult(
            mismatches: mismatches,
            canAutoResolve: !mismatches.isEmpty
        )
    }

    /// Extract config path from Kanata command line with robust parsing
    private func extractConfigPath(from command: String) -> String? {
        // Handle quoted arguments properly
        let components = parseCommandLine(command)

        // Look for --cfg parameter
        for i in 0 ..< components.count - 1 {
            if components[i] == "--cfg" {
                return components[i + 1]
            }
        }

        return nil
    }

    /// Parse command line arguments handling quotes, spaces, and escapes
    private func parseCommandLine(_ command: String) -> [String] {
        var components: [String] = []
        var current = ""
        var inQuotes = false
        var i = command.startIndex

        while i < command.endIndex {
            let char = command[i]

            if char == "\\", !inQuotes {
                // Handle escaped characters (like escaped spaces)
                i = command.index(after: i)
                if i < command.endIndex {
                    current.append(command[i])
                }
            } else if char == "\"" {
                inQuotes.toggle()
            } else if char == " ", !inQuotes {
                if !current.isEmpty {
                    components.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }

            i = command.index(after: i)
        }

        if !current.isEmpty {
            components.append(current)
        }

        return components
    }

    /// Normalize file paths for reliable comparison
    private func normalizedPath(_ path: String) -> String {
        // First expand tilde if present
        let expandedPath = NSString(string: path).expandingTildeInPath
        // Then standardize the path (resolve .., ., etc.)
        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    // MARK: - Orphaned Process Detection

    /// Compute the recommended auto-fix action for orphaned processes
    private func computeOrphanedProcessAutoFix() async -> AutoFixAction? {
        AppLogger.shared.log("🔍 [OrphanedProcess] Computing auto-fix recommendation")

        let conflicts = await processLifecycleManager.detectConflicts()

        // No orphaned process if no external processes
        if conflicts.externalProcesses.isEmpty {
            AppLogger.shared.log("🔍 [OrphanedProcess] No external processes found")
            return nil
        }

        // Not orphaned if managed processes exist (this is a conflict case)
        if !conflicts.managedProcesses.isEmpty {
            AppLogger.shared.log("🔍 [OrphanedProcess] Managed processes exist - this is a conflict, not orphaned")
            return nil
        }

        // Check service installation status using LaunchDaemonInstaller
        let serviceStatus = launchDaemonInstaller.getServiceStatus()
        let plistPresent = launchDaemonInstaller.isKanataPlistInstalled()

        AppLogger.shared.log("🔍 [OrphanedProcess] Service status: plistPresent=\(plistPresent), loaded=\(serviceStatus.kanataServiceLoaded)")
        AppLogger.shared.log("🔍 [OrphanedProcess] External processes: \(conflicts.externalProcesses.count)")

        // Analyze config paths of external processes
        let expectedPath = normalizedPath(WizardSystemPaths.userConfigPath)
        var usesExpectedConfigPath = false

        for process in conflicts.externalProcesses {
            if let configPath = extractConfigPath(from: process.command) {
                let normalizedActual = normalizedPath(configPath)
                if normalizedActual == expectedPath {
                    usesExpectedConfigPath = true
                    AppLogger.shared.log("🔍 [OrphanedProcess] Process \(process.pid) uses expected config path")
                    break
                }
            }
        }

        // Multiple external processes - prefer replace for safety
        if conflicts.externalProcesses.count > 1 {
            AppLogger.shared.log("✅ [OrphanedProcess] Multiple external processes detected - recommending replace")
            return .replaceOrphanedProcess
        }

        // Decision matrix based on service state and config path usage
        let recommendation: AutoFixAction?

        if !plistPresent {
            // No plist installed - safe to adopt if using expected config, otherwise replace
            recommendation = usesExpectedConfigPath ? .adoptOrphanedProcess : .replaceOrphanedProcess
            AppLogger.shared.log("✅ [OrphanedProcess] No plist present - recommending \(recommendation == .adoptOrphanedProcess ? "adopt" : "replace") based on config path")
        } else if plistPresent, !serviceStatus.kanataServiceLoaded {
            // Plist exists but not loaded - replace to converge to managed state
            recommendation = .replaceOrphanedProcess
            AppLogger.shared.log("✅ [OrphanedProcess] Plist present but not loaded - recommending replace")
        } else if serviceStatus.kanataServiceLoaded {
            // Loaded but external exists (unusual) - replace to converge
            recommendation = .replaceOrphanedProcess
            AppLogger.shared.log("✅ [OrphanedProcess] Service loaded but external process exists - recommending replace")
        } else {
            recommendation = nil
        }

        return recommendation
    }

    /// Detect Kanata processes running without LaunchDaemon management
    private func detectOrphanedKanataProcess() async -> ComponentRequirement? {
        let autoFixAction = await computeOrphanedProcessAutoFix()
        if autoFixAction != nil {
            AppLogger.shared.log("✅ [OrphanedProcess] Detected orphaned Kanata process requiring management")
            return .orphanedKanataProcess
        } else {
            AppLogger.shared.log("✅ [OrphanedProcess] No orphaned processes detected")
            return nil
        }
    }
}

// MARK: - Testing Extensions

#if DEBUG
    extension SystemStateDetector {
        /// Test helper to expose normalizedPath for unit testing
        func testNormalizedPath(_ path: String) -> String {
            normalizedPath(path)
        }

        /// Test helper to expose parseCommandLine for unit testing
        func testParseCommandLine(_ command: String) -> [String] {
            parseCommandLine(command)
        }

        /// Test helper to expose extractConfigPath for unit testing
        func testExtractConfigPath(from command: String) -> String? {
            extractConfigPath(from: command)
        }

        /// Test helper to expose orphaned process detection logic with mocked dependencies
        func testComputeOrphanedProcessAutoFixWithMocks(
            externalProcesses: [ProcessLifecycleManager.ProcessInfo],
            managedProcesses: [ProcessLifecycleManager.ProcessInfo],
            plistPresent: Bool,
            serviceLoaded: Bool
        ) async -> AutoFixAction? {
            AppLogger.shared.log("🔍 [OrphanedProcess] Testing with mocked dependencies")

            // No orphaned process if no external processes
            if externalProcesses.isEmpty {
                AppLogger.shared.log("🔍 [OrphanedProcess] No external processes found")
                return nil
            }

            // Not orphaned if managed processes exist (this is a conflict case)
            if !managedProcesses.isEmpty {
                AppLogger.shared.log("🔍 [OrphanedProcess] Managed processes exist - this is a conflict, not orphaned")
                return nil
            }

            AppLogger.shared.log("🔍 [OrphanedProcess] Testing: plistPresent=\(plistPresent), serviceLoaded=\(serviceLoaded)")
            AppLogger.shared.log("🔍 [OrphanedProcess] External processes: \(externalProcesses.count)")

            // Analyze config paths of external processes
            let expectedPath = normalizedPath(WizardSystemPaths.userConfigPath)
            var usesExpectedConfigPath = false

            for process in externalProcesses {
                if let configPath = extractConfigPath(from: process.command) {
                    let normalizedActual = normalizedPath(configPath)
                    if normalizedActual == expectedPath {
                        usesExpectedConfigPath = true
                        AppLogger.shared.log("🔍 [OrphanedProcess] Process \(process.pid) uses expected config path")
                        break
                    }
                }
            }

            // Multiple external processes - prefer replace for safety
            if externalProcesses.count > 1 {
                AppLogger.shared.log("✅ [OrphanedProcess] Multiple external processes detected - recommending replace")
                return .replaceOrphanedProcess
            }

            // Decision matrix based on service state and config path usage
            let recommendation: AutoFixAction?

            if !plistPresent {
                // No plist installed - safe to adopt if using expected config, otherwise replace
                recommendation = usesExpectedConfigPath ? .adoptOrphanedProcess : .replaceOrphanedProcess
                AppLogger.shared.log("✅ [OrphanedProcess] No plist present - recommending \(recommendation == .adoptOrphanedProcess ? "adopt" : "replace") based on config path")
            } else if plistPresent, !serviceLoaded {
                // Plist exists but not loaded - replace to converge to managed state
                recommendation = .replaceOrphanedProcess
                AppLogger.shared.log("✅ [OrphanedProcess] Plist present but not loaded - recommending replace")
            } else if serviceLoaded {
                // Loaded but external exists (unusual) - replace to converge
                recommendation = .replaceOrphanedProcess
                AppLogger.shared.log("✅ [OrphanedProcess] Service loaded but external process exists - recommending replace")
            } else {
                recommendation = nil
            }

            return recommendation
        }
    }
#endif

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
  }

  // MARK: - Main Detection Method

  func detectCurrentState() async -> SystemStateResult {
    AppLogger.shared.log("🔍 [StateDetector] Starting comprehensive system state detection")

    // Check system compatibility first
    let compatibilityResult = systemRequirements.validateSystemCompatibility()

    // Use specialized detectors for each area
    let conflictResult = await detectConflictsUsingProcessLifecycleManager()
    let permissionResult = await componentDetector.checkPermissions()
    let componentResult = await componentDetector.checkComponents()
    let healthStatus = await healthChecker.performSystemHealthCheck()
    let configPathResult = await detectConfigPathMismatch()

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

    // Determine available auto-fix actions
    let autoFixActions = determineAutoFixActions(
      conflicts: conflictResult,
      permissions: permissionResult,
      components: componentResult,
      configPaths: configPathResult,
      daemonRunning: daemonRunning
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
      return .initializing  // Use initializing state for compatibility issues since we don't have a specific state
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
    daemonRunning: Bool
  ) -> [AutoFixAction] {
    var actions: [AutoFixAction] = []

    if conflicts.hasConflicts, conflicts.canAutoResolve {
      actions.append(.terminateConflictingProcesses)
    }
    
    // Check if config path synchronization is needed
    if configPaths.hasMismatches, configPaths.canAutoResolve {
      actions.append(.synchronizeConfigPaths)
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
    return await detectConflictsUsingProcessLifecycleManager()
  }

  func checkPermissions() async -> PermissionCheckResult {
    return await componentDetector.checkPermissions()
  }

  func checkComponents() async -> ComponentCheckResult {
    return await componentDetector.checkComponents()
  }

  // MARK: - ProcessLifecycleManager Integration

  /// Adapter method to convert ProcessLifecycleManager conflicts to SystemStateDetector format
  private func detectConflictsUsingProcessLifecycleManager() async -> ConflictDetectionResult {
    let conflicts = await processLifecycleManager.detectConflicts()

    // Convert ProcessLifecycleManager ProcessInfo to SystemConflict
    let systemConflicts: [SystemConflict] = conflicts.externalProcesses.map { processInfo in
      .kanataProcessRunning(pid: Int(processInfo.pid), command: processInfo.command)
    }

    let description =
      systemConflicts.isEmpty
      ? "No conflicts detected"
      : "Found \(systemConflicts.count) external processes: "
        + systemConflicts.map { conflict in
          switch conflict {
          case let .kanataProcessRunning(pid, _):
            return "Kanata process (PID: \(pid))"
          case let .karabinerGrabberRunning(pid):
            return "Karabiner grabber (PID: \(pid))"
          case let .karabinerVirtualHIDDeviceRunning(pid, processName):
            return "\(processName) (PID: \(pid))"
          case let .karabinerVirtualHIDDaemonRunning(pid):
            return "Karabiner daemon (PID: \(pid))"
          case let .exclusiveDeviceAccess(device):
            return "Device access: \(device)"
          }
        }.joined(separator: "; ")

    return ConflictDetectionResult(
      conflicts: systemConflicts,
      canAutoResolve: conflicts.canAutoResolve,
      description: description,
      managedProcesses: conflicts.managedProcesses
    )
  }

  // MARK: - Config Path Mismatch Detection

  /// Detect if Kanata is running with a different config path than KeyPath expects
  private func detectConfigPathMismatch() async -> ConfigPathMismatchResult {
    AppLogger.shared.log("🔍 [ConfigPath] Checking for config path mismatches")
    
    // Get the expected KeyPath config path
    let expectedPath = WizardSystemPaths.userConfigPath
    
    // Check what config path Kanata is actually using
    let kanataProcesses = await processLifecycleManager.detectConflicts()
    let allKanataProcesses = kanataProcesses.managedProcesses + kanataProcesses.externalProcesses
    
    var mismatches: [ConfigPathMismatch] = []
    
    for process in allKanataProcesses {
      // Parse the command line to extract --cfg parameter
      let command = process.command
      if let configPath = extractConfigPath(from: command) {
        if configPath != expectedPath {
          let mismatch = ConfigPathMismatch(
            processPID: process.pid,
            processCommand: command,
            actualConfigPath: configPath,
            expectedConfigPath: expectedPath
          )
          mismatches.append(mismatch)
          AppLogger.shared.log(
            "⚠️ [ConfigPath] Mismatch detected - Process \(process.pid) using '\(configPath)' but KeyPath expects '\(expectedPath)'"
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
  
  /// Extract config path from Kanata command line
  private func extractConfigPath(from command: String) -> String? {
    let components = command.split(separator: " ").map(String.init)
    
    // Look for --cfg parameter
    for i in 0..<components.count-1 {
      if components[i] == "--cfg" {
        return components[i+1]
      }
    }
    
    return nil
  }
}

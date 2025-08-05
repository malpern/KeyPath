import ApplicationServices
import Foundation

/// Orchestrates system state detection using specialized detector classes
/// Coordinates between different detection areas and provides unified results
class SystemStateDetector: SystemStateDetecting {
  private let systemRequirements: SystemRequirements
  private let healthChecker: SystemHealthChecker
  private let componentDetector: ComponentDetector
  private let conflictDetector: ConflictDetector
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
    conflictDetector = ConflictDetector(kanataManager: kanataManager)
    issueGenerator = IssueGenerator()
  }

  // MARK: - Main Detection Method

  func detectCurrentState() async -> SystemStateResult {
    AppLogger.shared.log("🔍 [StateDetector] Starting comprehensive system state detection")

    // Check system compatibility first
    let compatibilityResult = systemRequirements.validateSystemCompatibility()

    // Use specialized detectors for each area
    let conflictResult = await conflictDetector.detectConflicts()
    let permissionResult = await componentDetector.checkPermissions()
    let componentResult = await componentDetector.checkComponents()
    let healthStatus = await healthChecker.performSystemHealthCheck()

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

    if !daemonRunning {
      issues.append(issueGenerator.createDaemonIssue())
    }

    // Determine available auto-fix actions
    let autoFixActions = determineAutoFixActions(
      conflicts: conflictResult,
      permissions: permissionResult,
      components: componentResult,
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
    daemonRunning: Bool
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
    return await conflictDetector.detectConflicts()
  }

  func checkPermissions() async -> PermissionCheckResult {
    return await componentDetector.checkPermissions()
  }

  func checkComponents() async -> ComponentCheckResult {
    return await componentDetector.checkComponents()
  }
}

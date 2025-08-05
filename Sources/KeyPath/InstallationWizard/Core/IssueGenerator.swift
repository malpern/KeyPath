import Foundation

/// Responsible for generating WizardIssue objects from detection results
/// Converts detection data into user-facing issue descriptions
class IssueGenerator {
  // MARK: - Issue Creation

  func createSystemRequirementIssues(from result: SystemRequirements.ValidationResult)
    -> [WizardIssue] {
    var issues: [WizardIssue] = []

    // Create issues for each compatibility problem
    if !result.isCompatible {
      for issue in result.issues {
        issues.append(
          WizardIssue(
            identifier: .component(.karabinerDriver),  // Use existing identifier for now
            severity: .critical,
            category: .systemRequirements,
            title: "System Compatibility Issue",
            description: issue,
            autoFixAction: nil,  // No auto-fix for system compatibility issues
            userAction: result.recommendations.first
          ))
      }
    }

    // Add informational issue about driver type requirements (always show this)
    let driverInfo = WizardIssue(
      identifier: .component(.karabinerDriver),
      severity: .info,
      category: .systemRequirements,
      title: "Driver Type: \(result.requiredDriverType.displayName)",
      description: "This system requires \(result.requiredDriverType.description)",
      autoFixAction: nil,
      userAction: nil
    )
    issues.append(driverInfo)

    return issues
  }

  func createConflictIssues(from result: ConflictDetectionResult) -> [WizardIssue] {
    guard result.hasConflicts else { return [] }

    // Create issues for each specific conflict
    return result.conflicts.map { conflict in
      WizardIssue(
        identifier: .conflict(conflict),
        severity: .error,
        category: .conflicts,
        title: WizardConstants.Titles.conflictingProcesses,
        description: result.description,
        autoFixAction: .terminateConflictingProcesses,
        userAction: nil
      )
    }
  }

  func createPermissionIssues(from result: PermissionCheckResult) -> [WizardIssue] {
    AppLogger.shared.log(
      "🔍 [IssueGenerator] Creating issues for \(result.missing.count) missing permissions:")
    for permission in result.missing {
      AppLogger.shared.log("🔍 [IssueGenerator]   - Missing: \(permission)")
    }

    return result.missing.map { permission in
      // Background services get their own category and page
      let category: WizardIssue.IssueCategory =
        permission == .backgroundServicesEnabled ? .backgroundServices : .permissions
      let title = permissionTitle(for: permission)

      AppLogger.shared.log(
        "🔍 [IssueGenerator] Creating issue: category=\(category), title='\(title)'")

      return WizardIssue(
        identifier: .permission(permission),
        severity: .warning,
        category: category,
        title: title,
        description: permissionDescription(for: permission),
        autoFixAction: nil,
        userAction: userActionForPermission(permission)
      )
    }
  }

  func createComponentIssues(from result: ComponentCheckResult) -> [WizardIssue] {
    return result.missing.map { component in
      let autoFixAction = getAutoFixAction(for: component)
      AppLogger.shared.log(
        "🔧 [IssueGenerator] Creating component issue: '\(componentTitle(for: component))' with autoFixAction: \(autoFixAction != nil ? String(describing: autoFixAction!) : "nil")"
      )

      return WizardIssue(
        identifier: .component(component),
        severity: .error,
        category: .installation,
        title: componentTitle(for: component),
        description: componentDescription(for: component),
        autoFixAction: autoFixAction,
        userAction: getUserAction(for: component)
      )
    }
  }

  func createDaemonIssue() -> WizardIssue {
    WizardIssue(
      identifier: .daemon,
      severity: .warning,
      category: .daemon,
      title: WizardConstants.Titles.daemonNotRunning,
      description:
        "The Karabiner Virtual HID Device Daemon needs to be running for keyboard remapping.",
      autoFixAction: .startKarabinerDaemon,
      userAction: nil
    )
  }

  // MARK: - Helper Methods

  private func permissionTitle(for permission: PermissionRequirement) -> String {
    switch permission {
    case .kanataInputMonitoring: return WizardConstants.Titles.kanataInputMonitoring
    case .kanataAccessibility: return WizardConstants.Titles.kanataAccessibility
    case .driverExtensionEnabled: return WizardConstants.Titles.driverExtensionDisabled
    case .backgroundServicesEnabled: return WizardConstants.Titles.backgroundServicesDisabled
    case .keyPathInputMonitoring: return "KeyPath Input Monitoring"
    case .keyPathAccessibility: return "KeyPath Accessibility"
    }
  }

  private func permissionDescription(for permission: PermissionRequirement) -> String {
    switch permission {
    case .kanataInputMonitoring:
      return "The kanata binary needs Input Monitoring permission to process keys."
    case .kanataAccessibility:
      return "The kanata binary needs Accessibility permission for system access."
    case .driverExtensionEnabled:
      return "Karabiner driver extension must be enabled in System Settings."
    case .backgroundServicesEnabled:
      return
        "Karabiner background services must be enabled for HID functionality. These may need to be manually added as Login Items."
    case .keyPathInputMonitoring:
      return "KeyPath needs Input Monitoring permission to capture keyboard events."
    case .keyPathAccessibility:
      return "KeyPath needs Accessibility permission for full keyboard control functionality."
    }
  }

  private func userActionForPermission(_ permission: PermissionRequirement) -> String {
    switch permission {
    case .kanataInputMonitoring:
      return "Grant permission in System Settings > Privacy & Security > Input Monitoring"
    case .kanataAccessibility:
      return "Grant permission in System Settings > Privacy & Security > Accessibility"
    case .driverExtensionEnabled:
      return "Enable in System Settings > Privacy & Security > Driver Extensions"
    case .backgroundServicesEnabled:
      return
        "Add Karabiner services to Login Items in System Settings > General > Login Items & Extensions"
    case .keyPathInputMonitoring:
      return "Grant permission in System Settings > Privacy & Security > Input Monitoring"
    case .keyPathAccessibility:
      return "Grant permission in System Settings > Privacy & Security > Accessibility"
    }
  }

  private func componentTitle(for component: ComponentRequirement) -> String {
    switch component {
    case .kanataBinary: return WizardConstants.Titles.kanataBinaryMissing
    case .kanataService: return "Kanata Service Missing"
    case .karabinerDriver: return WizardConstants.Titles.karabinerDriverMissing
    case .karabinerDaemon: return WizardConstants.Titles.daemonNotRunning
    case .vhidDeviceManager: return "VirtualHIDDevice Manager Missing"
    case .vhidDeviceActivation: return "VirtualHIDDevice Manager Not Activated"
    case .vhidDeviceRunning: return "VirtualHIDDevice Daemon Not Running"
    case .launchDaemonServices: return "LaunchDaemon Services Not Installed"
    case .packageManager: return "Package Manager (Homebrew) Missing"
    }
  }

  private func componentDescription(for component: ComponentRequirement) -> String {
    switch component {
    case .kanataBinary:
      return
        "The kanata binary is not installed or not found in expected locations. Checked paths: /opt/homebrew/bin/kanata, /usr/local/bin/kanata, ~/.cargo/bin/kanata"
    case .kanataService:
      return "Kanata service configuration is missing."
    case .karabinerDriver:
      return "Karabiner-Elements driver is required for virtual HID functionality."
    case .karabinerDaemon:
      return "Karabiner Virtual HID Device Daemon is not running."
    case .vhidDeviceManager:
      return
        "The Karabiner VirtualHIDDevice Manager application is not installed. This is required for keyboard remapping functionality."
    case .vhidDeviceActivation:
      return
        "The VirtualHIDDevice Manager needs to be activated to enable virtual HID functionality."
    case .vhidDeviceRunning:
      return
        "The VirtualHIDDevice daemon is not running properly or has connection issues. This may indicate the manager needs activation, restart, or there are VirtualHID connection failures preventing keyboard remapping."
    case .launchDaemonServices:
      return
        "LaunchDaemon services are not installed or loaded. These provide reliable system-level service management for KeyPath components."
    case .packageManager:
      return
        "Homebrew package manager is not installed. This is needed to automatically install missing dependencies like Kanata. Install from https://brew.sh"
    }
  }

  private func getAutoFixAction(for component: ComponentRequirement) -> AutoFixAction? {
    switch component {
    case .karabinerDriver, .vhidDeviceManager, .packageManager:
      return nil  // These require manual installation
    case .vhidDeviceActivation:
      return .activateVHIDDeviceManager
    case .vhidDeviceRunning:
      return .restartVirtualHIDDaemon
    case .launchDaemonServices:
      return .installLaunchDaemonServices
    case .kanataBinary:
      return .installViaBrew  // Can be installed via Homebrew if available
    default:
      return .installMissingComponents
    }
  }

  private func getUserAction(for component: ComponentRequirement) -> String? {
    switch component {
    case .karabinerDriver:
      return "Install Karabiner-Elements from website"
    case .vhidDeviceManager:
      return "Install Karabiner-VirtualHIDDevice from website"
    case .packageManager:
      return "Install Homebrew from https://brew.sh"
    case .kanataBinary:
      return "Install Homebrew, then run: brew install kanata"
    default:
      return nil
    }
  }

  private func getComponentUserAction(for component: ComponentRequirement) -> String? {
    switch component {
    case .vhidDeviceManager:
      return "Install Karabiner-VirtualHIDDevice from website"
    case .packageManager:
      return "Install Homebrew from https://brew.sh"
    case .kanataBinary:
      return "Install Homebrew, then run: brew install kanata"
    default:
      return nil
    }
  }
}

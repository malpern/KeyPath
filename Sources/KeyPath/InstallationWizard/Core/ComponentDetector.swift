import ApplicationServices
import Foundation

/// Responsible for detecting component installation and permissions
/// Handles all system component checking logic
class ComponentDetector {
  private let kanataManager: KanataManager
  private let vhidDeviceManager: VHIDDeviceManager
  private let launchDaemonInstaller: LaunchDaemonInstaller
  private let systemRequirements: SystemRequirements
  private let packageManager: PackageManager

  init(
    kanataManager: KanataManager,
    vhidDeviceManager: VHIDDeviceManager,
    launchDaemonInstaller: LaunchDaemonInstaller,
    systemRequirements: SystemRequirements,
    packageManager: PackageManager
  ) {
    self.kanataManager = kanataManager
    self.vhidDeviceManager = vhidDeviceManager
    self.launchDaemonInstaller = launchDaemonInstaller
    self.systemRequirements = systemRequirements
    self.packageManager = packageManager
  }

  // MARK: - Permission Checking

  func checkPermissions() async -> PermissionCheckResult {
    AppLogger.shared.log("🔍 [ComponentDetector] Checking system permissions")

    var granted: [PermissionRequirement] = []
    var missing: [PermissionRequirement] = []

    // Check Input Monitoring permissions for each app individually
    let keyPathHasInputMonitoring = kanataManager.hasInputMonitoringPermission()
    let kanataHasInputMonitoring = kanataManager.checkTCCForInputMonitoring(
      path: WizardSystemPaths.kanataActiveBinary)

    if keyPathHasInputMonitoring {
      granted.append(.keyPathInputMonitoring)
    } else {
      missing.append(.keyPathInputMonitoring)
    }

    if kanataHasInputMonitoring {
      granted.append(.kanataInputMonitoring)
    } else {
      missing.append(.kanataInputMonitoring)
    }

    // Check Accessibility permissions
    let keyPathHasAccessibility = kanataManager.hasAccessibilityPermission()
    let kanataHasAccessibility = kanataManager.checkTCCForAccessibility(
      path: WizardSystemPaths.kanataActiveBinary)

    if keyPathHasAccessibility {
      granted.append(.keyPathAccessibility)
    } else {
      missing.append(.keyPathAccessibility)
    }

    if kanataHasAccessibility {
      granted.append(.kanataAccessibility)
    } else {
      missing.append(.kanataAccessibility)
    }

    // Check system extensions
    let driverEnabled = await systemRequirements.checkDriverExtensionEnabled()
    if driverEnabled {
      granted.append(.driverExtensionEnabled)
    } else {
      missing.append(.driverExtensionEnabled)
    }

    // Check background services
    let backgroundServicesEnabled = await systemRequirements.checkBackgroundServicesEnabled()
    if backgroundServicesEnabled {
      granted.append(.backgroundServicesEnabled)
    } else {
      missing.append(.backgroundServicesEnabled)
    }

    let needsUserAction = !missing.isEmpty

    AppLogger.shared.log("🔍 [ComponentDetector] Permission check complete:")
    AppLogger.shared.log("  - Granted: \(granted.count) permissions")
    AppLogger.shared.log("  - Missing: \(missing.count) permissions")

    return PermissionCheckResult(
      missing: missing,
      granted: granted,
      needsUserAction: needsUserAction
    )
  }

  // MARK: - Component Detection

  func checkComponents() async -> ComponentCheckResult {
    AppLogger.shared.log("🔍 [ComponentDetector] Checking system components")

    var missing: [ComponentRequirement] = []
    var installed: [ComponentRequirement] = []

    // Check Kanata binary
    if kanataManager.isInstalled() {
      installed.append(.kanataBinary)
    } else {
      missing.append(.kanataBinary)
    }

    // Check package manager (Homebrew)
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

    // Check both daemon running AND connection health
    let daemonRunning = vhidDeviceManager.detectRunning()
    let connectionHealthy = vhidDeviceManager.detectConnectionHealth()

    if daemonRunning && connectionHealthy {
      installed.append(.vhidDeviceRunning)
    } else {
      missing.append(.vhidDeviceRunning)

      // Add specific diagnostic if daemon is running but connection is unhealthy
      if daemonRunning && !connectionHealthy {
        AppLogger.shared.log(
          "⚠️ [ComponentDetector] VirtualHID daemon running but connection unhealthy")
      }
    }

    // Check LaunchDaemon services
    let daemonStatus = launchDaemonInstaller.getServiceStatus()
    if daemonStatus.allServicesLoaded {
      installed.append(.launchDaemonServices)
    } else {
      missing.append(.launchDaemonServices)
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

    AppLogger.shared.log("🔍 [ComponentDetector] Component check complete:")
    AppLogger.shared.log("  - Installed: \(installed.count) components")
    AppLogger.shared.log("  - Missing: \(missing.count) components")

    // Determine if missing components can be auto-installed
    let homebrewAvailable = installed.contains(.packageManager)
    let canAutoInstall =
      homebrewAvailable
      && missing.contains { component in
        // Components that can be auto-installed via Homebrew or other automated means
        switch component {
        case .kanataBinary: return true
        case .vhidDeviceActivation, .launchDaemonServices: return true
        default: return false
        }
      }

    return ComponentCheckResult(
      missing: missing,
      installed: installed,
      canAutoInstall: canAutoInstall
    )
  }
}

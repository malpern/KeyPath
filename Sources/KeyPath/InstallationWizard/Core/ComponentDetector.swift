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

        // Use unified PermissionService for consistent permission checking
        let systemStatus = PermissionService.shared.checkSystemPermissions(
            kanataBinaryPath: WizardSystemPaths.kanataActiveBinary)

        // Map PermissionService results to ComponentDetector requirements
        if systemStatus.keyPath.hasInputMonitoring {
            granted.append(.keyPathInputMonitoring)
        } else {
            missing.append(.keyPathInputMonitoring)
        }

        if systemStatus.kanata.hasInputMonitoring {
            granted.append(.kanataInputMonitoring)
        } else {
            missing.append(.kanataInputMonitoring)
        }

        if systemStatus.keyPath.hasAccessibility {
            granted.append(.keyPathAccessibility)
        } else {
            missing.append(.keyPathAccessibility)
        }

        if systemStatus.kanata.hasAccessibility {
            granted.append(.kanataAccessibility)
        } else {
            missing.append(.kanataAccessibility)
        }

        // Check system extensions (not part of PermissionService - different category)
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

        if daemonRunning, connectionHealthy {
            installed.append(.vhidDeviceRunning)
        } else {
            missing.append(.vhidDeviceRunning)

            // Add specific diagnostic if daemon is running but connection is unhealthy
            if daemonRunning, !connectionHealthy {
                AppLogger.shared.log(
                    "⚠️ [ComponentDetector] VirtualHID daemon running but connection unhealthy")
            }
        }

        // Check LaunchDaemon services - handle mixed scenarios properly
        let daemonStatus = launchDaemonInstaller.getServiceStatus()
        
        // Check Kanata service configuration specifically
        if daemonStatus.kanataServiceLoaded && daemonStatus.kanataServiceHealthy {
            installed.append(.kanataService)
        } else {
            missing.append(.kanataService)
        }
        if daemonStatus.allServicesHealthy {
            installed.append(.launchDaemonServices)
        } else {
            // Check if any services are loaded but unhealthy (priority over not installed)
            let hasLoadedButUnhealthy =
                (daemonStatus.kanataServiceLoaded && !daemonStatus.kanataServiceHealthy)
                    || (daemonStatus.vhidDaemonServiceLoaded && !daemonStatus.vhidDaemonServiceHealthy)
                    || (daemonStatus.vhidManagerServiceLoaded && !daemonStatus.vhidManagerServiceHealthy)

            if hasLoadedButUnhealthy {
                // If we just restarted, treat as warming-up instead of unhealthy
                if LaunchDaemonInstaller.hadRecentRestart() {
                    installed.append(.launchDaemonServices)
                    AppLogger.shared.log(
                        "ℹ️ [ComponentDetector] LaunchDaemon services recently restarted; treating as warming up (not unhealthy). Status: \(daemonStatus.description)"
                    )
                } else {
                    // At least one service is loaded but crashing - prioritize restart over install
                    missing.append(.launchDaemonServicesUnhealthy)
                    AppLogger.shared.log(
                        "🔍 [ComponentDetector] MIXED SCENARIO: Some LaunchDaemon services loaded but unhealthy: \(daemonStatus.description)"
                    )
                    AppLogger.shared.log(
                        "🔍 [ComponentDetector] *** WILL TRIGGER: LaunchDaemon Services Failing -> restartUnhealthyServices ***"
                    )
                }
            } else {
                // No services are loaded/installed
                missing.append(.launchDaemonServices)
                AppLogger.shared.log(
                    "🔍 [ComponentDetector] LaunchDaemon services not installed: \(daemonStatus.description)")
                AppLogger.shared.log(
                    "🔍 [ComponentDetector] *** WILL TRIGGER: LaunchDaemon Services Not Installed -> installLaunchDaemonServices ***"
                )
            }
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
                    case .kanataBinary: true
                    case .vhidDeviceActivation, .launchDaemonServices: true
                    default: false
                    }
                }

        return ComponentCheckResult(
            missing: missing,
            installed: installed,
            canAutoInstall: canAutoInstall
        )
    }
}

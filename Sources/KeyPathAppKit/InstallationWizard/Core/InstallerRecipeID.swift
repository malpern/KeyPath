import Foundation

/// Centralized recipe IDs to avoid string drift across the InstallerEngine stack.
///
/// Keep this minimal: only IDs that are referenced from multiple files should live here.
enum InstallerRecipeID {
    static let installLaunchDaemonServices = "install-launch-daemon-services"
    static let installBundledKanata = "install-bundled-kanata"
    static let installCorrectVHIDDriver = "install-correct-vhid-driver"
    static let installLogRotation = "install-log-rotation"
    static let installPrivilegedHelper = "install-privileged-helper"
    static let reinstallPrivilegedHelper = "reinstall-privileged-helper"
    static let startKarabinerDaemon = "start-karabiner-daemon"
    static let restartUnhealthyServices = "restart-unhealthy-services"
    static let terminateConflictingProcesses = "terminate-conflicting-processes"
    static let fixDriverVersionMismatch = "fix-driver-version-mismatch"
    static let installMissingComponents = "install-missing-components"
    static let createConfigDirectories = "create-config-directories"
    static let activateVHIDManager = "activate-vhid-manager"
    static let repairVHIDDaemonServices = "repair-vhid-daemon-services"
    static let enableTCPServer = "enable-tcp-server"
    static let setupTCPAuthentication = "setup-tcp-authentication"
    static let regenerateCommServiceConfig = "regenerate-comm-service-config"
    static let restartCommServer = "restart-comm-server"
    static let adoptOrphanedProcess = "adopt-orphaned-process"
    static let replaceOrphanedProcess = "replace-orphaned-process"
    static let replaceKanataWithBundled = "replace-kanata-with-bundled"
    static let synchronizeConfigPaths = "synchronize-config-paths"
}


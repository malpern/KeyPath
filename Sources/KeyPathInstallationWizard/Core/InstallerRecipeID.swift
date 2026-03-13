import Foundation

/// Centralized recipe IDs to avoid string drift across the InstallerEngine stack.
///
/// Keep this minimal: only IDs that are referenced from multiple files should live here.
public enum InstallerRecipeID {
    public static let installRequiredRuntimeServices = "install-required-runtime-services"
    public static let installCorrectVHIDDriver = "install-correct-vhid-driver"
    public static let installLogRotation = "install-log-rotation"
    public static let installPrivilegedHelper = "install-privileged-helper"
    public static let reinstallPrivilegedHelper = "reinstall-privileged-helper"
    public static let startKarabinerDaemon = "start-karabiner-daemon"
    public static let terminateConflictingProcesses = "terminate-conflicting-processes"
    public static let fixDriverVersionMismatch = "fix-driver-version-mismatch"
    public static let installMissingComponents = "install-missing-components"
    public static let createConfigDirectories = "create-config-directories"
    public static let activateVHIDManager = "activate-vhid-manager"
    public static let repairVHIDDaemonServices = "repair-vhid-daemon-services"
    public static let enableTCPServer = "enable-tcp-server"
    public static let setupTCPAuthentication = "setup-tcp-authentication"
    public static let regenerateCommServiceConfig = "regenerate-comm-service-config"
    public static let regenerateServiceConfig = "regenerate-service-config"
    public static let restartCommServer = "restart-comm-server"
    public static let synchronizeConfigPaths = "synchronize-config-paths"
}

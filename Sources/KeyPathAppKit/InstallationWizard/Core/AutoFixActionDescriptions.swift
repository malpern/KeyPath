import KeyPathWizardCore

// MARK: - Auto-Fix Action Descriptions

/// User-friendly descriptions for auto-fix actions
///
/// Keep this free of logging so it can be called from SwiftUI view updates.
enum AutoFixActionDescriptions {
    static func describe(_ action: AutoFixAction) -> String {
        switch action {
        case .installPrivilegedHelper:
            "Install privileged helper for system operations"
        case .reinstallPrivilegedHelper:
            "Reinstall privileged helper to restore functionality"
        case .terminateConflictingProcesses:
            "Terminate conflicting processes"
        case .startKarabinerDaemon:
            "Start Karabiner daemon"
        case .restartVirtualHIDDaemon:
            "Fix VirtualHID connection issues"
        case .installMissingComponents:
            "Install missing components"
        case .createConfigDirectories:
            "Create configuration directories"
        case .activateVHIDDeviceManager:
            "Activate VirtualHID Device Manager"
        case .installLaunchDaemonServices:
            "Install LaunchDaemon services"
        case .adoptOrphanedProcess:
            "Connect existing Kanata to KeyPath management"
        case .replaceOrphanedProcess:
            "Replace orphaned process with managed service"
        case .installBundledKanata:
            "Install Kanata binary"
        case .repairVHIDDaemonServices:
            "Repair VHID LaunchDaemon services"
        case .synchronizeConfigPaths:
            "Fix config path mismatch between KeyPath and Kanata"
        case .restartUnhealthyServices:
            "Restart failing system services"
        case .installLogRotation:
            "Install log rotation to keep logs under 10MB"
        case .replaceKanataWithBundled:
            "Replace kanata with Developer ID signed version"
        case .enableTCPServer:
            "Enable TCP server"
        case .setupTCPAuthentication:
            "Setup TCP authentication for secure communication"
        case .regenerateCommServiceConfiguration:
            "Update TCP service configuration"
        case .regenerateServiceConfiguration:
            "Regenerate service configuration"
        case .restartCommServer:
            "Restart Service with Authentication"
        case .fixDriverVersionMismatch:
            "Fix Karabiner driver version (v6 → v5)"
        case .installCorrectVHIDDriver:
            "Install Karabiner VirtualHID driver"
        }
    }

    /// Get detailed error message for specific auto-fix failures
    static func errorMessage(for action: AutoFixAction) -> String {
        switch action {
        case .installLaunchDaemonServices:
            "Failed to install system services. Check that you provided admin password and try again."
        case .activateVHIDDeviceManager:
            "Failed to activate driver extensions. Please manually approve in System Settings > General > Login Items & Extensions."
        case .installBundledKanata:
            "Failed to install Kanata binary. Check admin permissions and try again."
        case .startKarabinerDaemon:
            "Failed to start system daemon."
        case .createConfigDirectories:
            "Failed to create configuration directories. Check file system permissions."
        case .restartVirtualHIDDaemon:
            "Failed to restart Virtual HID daemon."
        case .restartUnhealthyServices:
            "Failed to restart system services. This usually means:\n\n• Admin password was not provided when prompted\n"
                + "• Missing services could not be installed\n• System permission denied for service restart\n\n"
                + "Try the Fix button again and provide admin password when prompted."
        default:
            "Failed to \(describe(action).lowercased()). Check logs for details and try again."
        }
    }
}

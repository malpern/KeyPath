import Foundation
import KeyPathCore
import KeyPathWizardCore

/// Responsible for generating WizardIssue objects from detection results
/// Converts detection data into user-facing issue descriptions
class IssueGenerator {
    // MARK: - Issue Creation

    func createSystemRequirementIssues(from result: SystemRequirements.ValidationResult)
        -> [WizardIssue]
    {
        var issues: [WizardIssue] = []

        // Create issues for each compatibility problem
        if !result.isCompatible {
            for issue in result.issues {
                issues.append(
                    WizardIssue(
                        identifier: .component(.karabinerDriver), // Use existing identifier for now
                        severity: .critical,
                        category: .systemRequirements,
                        title: "System Compatibility Issue",
                        description: issue,
                        autoFixAction: nil, // No auto-fix for system compatibility issues
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

        // Group conflicts by type to avoid duplicates
        let groupedConflicts = Dictionary(grouping: result.conflicts) { conflict in
            switch conflict {
            case .kanataProcessRunning:
                "kanata"
            case .karabinerGrabberRunning:
                "karabiner_grabber"
            case .karabinerVirtualHIDDeviceRunning:
                "karabiner_vhid"
            case .karabinerVirtualHIDDaemonRunning:
                "karabiner_daemon"
            case .exclusiveDeviceAccess:
                "device_access"
            }
        }

        // Create one issue per conflict type with all instances listed
        return groupedConflicts.compactMap { conflictType, conflicts in
            guard let firstConflict = conflicts.first else { return nil }

            let combinedDescription = createGroupedConflictDescription(
                conflictType: conflictType, conflicts: conflicts
            )

            return WizardIssue(
                identifier: .conflict(firstConflict),
                severity: .error,
                category: .conflicts,
                title: WizardConstants.Titles.conflictingProcesses,
                description: combinedDescription,
                autoFixAction: .terminateConflictingProcesses,
                userAction: nil
            )
        }
    }

    private func createGroupedConflictDescription(conflictType: String, conflicts: [SystemConflict])
        -> String
    {
        let count = conflicts.count
        let plural = count > 1 ? "es" : ""

        switch conflictType {
        case "kanata":
            var description = "Kanata process\(plural) running"
            if count > 1 { description += " (\(count) instances)" }
            description += ":\n"
            for conflict in conflicts {
                if case let .kanataProcessRunning(pid, command) = conflict {
                    description += "• PID: \(pid) - \(command)\n"
                }
            }
            return description.trimmingCharacters(in: .whitespacesAndNewlines)

        case "karabiner_grabber":
            var description = "Karabiner Elements grabber process\(plural)"
            if count > 1 { description += " (\(count) instances)" }
            description += ":\n"
            for conflict in conflicts {
                if case let .karabinerGrabberRunning(pid) = conflict {
                    description += "• PID: \(pid) - Keyboard input capture daemon\n"
                }
            }
            description += "This process captures keyboard input and conflicts with KeyPath."
            return description

        case "karabiner_vhid":
            var description = "Karabiner VirtualHID Device process\(plural)"
            if count > 1 { description += " (\(count) instances)" }
            description += ":\n"
            for conflict in conflicts {
                if case let .karabinerVirtualHIDDeviceRunning(pid, processName) = conflict {
                    description += "• PID: \(pid) - \(processName)\n"
                }
            }
            description += "Virtual device driver conflicts with KeyPath's remapping."
            return description

        case "karabiner_daemon":
            var description = "Karabiner VirtualHIDDevice Daemon"
            if count > 1 { description += " (\(count) instances)" }
            description += ":\n"
            for conflict in conflicts {
                if case let .karabinerVirtualHIDDaemonRunning(pid) = conflict {
                    description += "• PID: \(pid) - VirtualHIDDevice daemon\n"
                }
            }
            description += "This daemon manages virtual devices and conflicts with KeyPath."
            return description

        case "device_access":
            var description = "Exclusive device access conflict"
            if count > 1 { description += "s (\(count) devices)" }
            description += ":\n"
            for conflict in conflicts {
                if case let .exclusiveDeviceAccess(device) = conflict {
                    description += "• \(device)\n"
                }
            }
            description += "Another process has exclusive access to input device(s)."
            return description

        default:
            return "Unknown conflict type: \(conflictType)"
        }
    }

    private func createIndividualConflictDescription(_ conflict: SystemConflict) -> String {
        switch conflict {
        case let .kanataProcessRunning(pid, command):
            "Kanata process running (PID: \(pid))\nCommand: \(command)"
        case let .karabinerGrabberRunning(pid):
            "Karabiner Elements grabber running (PID: \(pid))\nThis process captures keyboard input and conflicts with KeyPath."
        case let .karabinerVirtualHIDDeviceRunning(pid, processName):
            "Karabiner VirtualHID Device running: \(processName) (PID: \(pid))\nThis virtual device driver conflicts with KeyPath's remapping."
        case let .karabinerVirtualHIDDaemonRunning(pid):
            "Karabiner VirtualHIDDevice Daemon running (PID: \(pid))\nThis daemon manages virtual devices and conflicts with KeyPath."
        case let .exclusiveDeviceAccess(device):
            "Exclusive device access conflict: \(device)\nAnother process has exclusive access to this input device."
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
        result.missing.map { component in
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

    func createLogRotationIssue() -> WizardIssue {
        WizardIssue(
            identifier: .component(.logRotation),
            severity: .info,
            category: .installation,
            title: "Log Rotation Recommended",
            description: "Install log rotation to automatically manage Kanata logs and keep them under 10MB total. This prevents performance issues from large log files.",
            autoFixAction: .installLogRotation,
            userAction: nil
        )
    }

    func createConfigPathIssues(from result: ConfigPathMismatchResult) -> [WizardIssue] {
        var issues: [WizardIssue] = []

        for mismatch in result.mismatches {
            let issue = WizardIssue(
                identifier: .component(.kanataService), // Use existing identifier
                severity: .error,
                category: .installation,
                title: "Config Path Mismatch",
                description: """
                Kanata is running with a different config file than KeyPath expects.

                • Kanata process (PID \(mismatch.processPID)) is using: \(mismatch.actualConfigPath)
                • KeyPath is saving changes to: \(mismatch.expectedConfigPath)

                This prevents configuration updates from working. When you change keyboard mappings in KeyPath, the changes won't be applied because Kanata is reading from a different file.
                """,
                autoFixAction: .synchronizeConfigPaths,
                userAction: "Use the Fix button to synchronize the config paths"
            )
            issues.append(issue)
        }

        return issues
    }

    // MARK: - Helper Methods

    private func permissionTitle(for permission: PermissionRequirement) -> String {
        switch permission {
        case .kanataInputMonitoring: WizardConstants.Titles.kanataInputMonitoring
        case .kanataAccessibility: WizardConstants.Titles.kanataAccessibility
        case .driverExtensionEnabled: WizardConstants.Titles.driverExtensionDisabled
        case .backgroundServicesEnabled: WizardConstants.Titles.backgroundServicesDisabled
        case .keyPathInputMonitoring: "KeyPath Input Monitoring"
        case .keyPathAccessibility: "KeyPath Accessibility"
        }
    }

    private func permissionDescription(for permission: PermissionRequirement) -> String {
        switch permission {
        case .kanataInputMonitoring:
            "The kanata binary needs Input Monitoring permission to process keys."
        case .kanataAccessibility:
            "The kanata binary needs Accessibility permission for system access."
        case .driverExtensionEnabled:
            "Karabiner driver extension must be enabled in System Settings."
        case .backgroundServicesEnabled:
            "Karabiner background services must be enabled for HID functionality. These may need to be manually added as Login Items."
        case .keyPathInputMonitoring:
            "KeyPath needs Input Monitoring permission to capture keyboard events."
        case .keyPathAccessibility:
            "KeyPath needs Accessibility permission for full keyboard control functionality."
        }
    }

    private func userActionForPermission(_ permission: PermissionRequirement) -> String {
        switch permission {
        case .kanataInputMonitoring:
            "Grant permission in System Settings > Privacy & Security > Input Monitoring"
        case .kanataAccessibility:
            "Grant permission in System Settings > Privacy & Security > Accessibility"
        case .driverExtensionEnabled:
            "Enable in System Settings > Privacy & Security > Driver Extensions"
        case .backgroundServicesEnabled:
            "Add Karabiner services to Login Items in System Settings > General > Login Items & Extensions"
        case .keyPathInputMonitoring:
            "Grant permission in System Settings > Privacy & Security > Input Monitoring"
        case .keyPathAccessibility:
            "Grant permission in System Settings > Privacy & Security > Accessibility"
        }
    }

    private func componentTitle(for component: ComponentRequirement) -> String {
        switch component {
        case .privilegedHelper: "Privileged Helper Not Installed"
        case .privilegedHelperUnhealthy: "Privileged Helper Not Working"
        case .kanataBinaryMissing: WizardConstants.Titles.kanataBinaryMissing
        case .kanataService: "Kanata Service Missing"
        case .karabinerDriver: WizardConstants.Titles.karabinerDriverMissing
        case .karabinerDaemon: WizardConstants.Titles.daemonNotRunning
        case .vhidDeviceManager: "VirtualHIDDevice Manager Missing"
        case .vhidDeviceActivation: "VirtualHIDDevice Manager Not Activated"
        case .vhidDeviceRunning: "VirtualHIDDevice Daemon"
        case .vhidDaemonMisconfigured: "VirtualHIDDevice Daemon Misconfigured"
        case .vhidDriverVersionMismatch: "Karabiner Driver Version Incompatible"
        case .launchDaemonServices: "LaunchDaemon Services Not Installed"
        case .launchDaemonServicesUnhealthy: "LaunchDaemon Services Failing"
        case .kanataTCPServer: "TCP Server Not Responding"
        case .orphanedKanataProcess: "Orphaned Kanata Process"
        case .communicationServerConfiguration: "Communication Server Configuration Outdated"
        case .communicationServerNotResponding: "Communication Server Not Responding"
        case .tcpServerConfiguration: "TCP Server Configuration Outdated"
        case .tcpServerNotResponding: "TCP Server Not Responding"
        case .logRotation: "Log Rotation Recommended"
        }
    }

    private func componentDescription(for component: ComponentRequirement) -> String {
        switch component {
        case .privilegedHelper:
            "The privileged helper allows system-level operations without repeated sudo password prompts. Install it to streamline setup and maintenance tasks."
        case .privilegedHelperUnhealthy:
            "The privileged helper is installed but not responding. Try reinstalling it to restore functionality."
        case .kanataBinaryMissing:
            "The kanata binary needs to be installed to system location from KeyPath's bundled Developer ID signed version. This ensures proper code signing for Input Monitoring permission."
        case .kanataService:
            "Kanata service configuration is missing."
        case .karabinerDriver:
            "Karabiner-Elements driver is required for virtual HID functionality."
        case .karabinerDaemon:
            "Karabiner Virtual HID Device Daemon is not running."
        case .vhidDeviceManager:
            "The Karabiner VirtualHIDDevice Manager application is not installed. This is required for keyboard remapping functionality."
        case .vhidDeviceActivation:
            "The VirtualHIDDevice Manager needs to be activated to enable virtual HID functionality."
        case .vhidDeviceRunning:
            "The VirtualHIDDevice daemon is not running properly or has connection issues. " +
                "This may indicate the manager needs activation, restart, or there are VirtualHID " +
                "connection failures preventing keyboard remapping."
        case .vhidDaemonMisconfigured:
            "The installed LaunchDaemon for the VirtualHID daemon points to a legacy path. It should use the DriverKit daemon path."
        case .vhidDriverVersionMismatch:
            "The installed Karabiner-DriverKit-VirtualHIDDevice version is incompatible with the current version of Kanata. Kanata v1.9.0 requires driver v5.0.0, but a different version is installed. KeyPath can automatically download and install the correct version."
        case .launchDaemonServices:
            "LaunchDaemon services are not installed or loaded. These provide reliable system-level service management for KeyPath components."
        case .launchDaemonServicesUnhealthy:
            "LaunchDaemon services are loaded but crashing or failing. This usually indicates a configuration problem or permission issue that can be fixed by restarting the services."
        case .kanataTCPServer:
            "Kanata TCP server is not responding on the configured port. This is used for config validation and external integration. Service may need restart with TCP enabled."
        case .orphanedKanataProcess:
            """
            Kanata is running outside of LaunchDaemon management. This prevents reliable lifecycle control and hot-reload functionality.

            KeyPath can fix this by either:
            • **Adopt** (Recommended): Install management without interrupting your current session
            • **Replace**: Stop current process and start a managed one (cleaner but interrupts current mappings)

            The wizard will automatically choose the best option based on your configuration.
            """
        case .communicationServerConfiguration:
            """
            The communication server is enabled in KeyPath preferences but the system service is not configured with the current settings.

            This happens when communication preferences are changed but the service hasn't been updated. The service needs to be regenerated with the current protocol configuration.
            """
        case .communicationServerNotResponding:
            """
            The communication server is properly configured but not responding.

            This prevents reliable permission detection and may affect external integrations. The service may need to be restarted.
            """
        case .tcpServerConfiguration:
            """
            The TCP server is enabled in KeyPath preferences but the system service is not configured with the current TCP settings.

            This happens when TCP preferences are changed but the service hasn't been updated. The service needs to be regenerated with the current TCP port configuration.
            """
        case .tcpServerNotResponding:
            """
            The TCP server is not responding on port 37001.

            This prevents low-latency communication and may affect external integrations. The service may need to be restarted.
            """
        case .logRotation:
            "Install log rotation to automatically manage Kanata logs and keep them under 10MB total. This prevents performance issues from large log files."
        }
    }

    private func getAutoFixAction(for component: ComponentRequirement) -> AutoFixAction? {
        switch component {
        case .karabinerDriver, .vhidDeviceManager:
            nil // These require manual installation
        case .vhidDeviceActivation:
            .activateVHIDDeviceManager
        case .vhidDeviceRunning:
            .restartVirtualHIDDaemon
        case .vhidDaemonMisconfigured:
            .repairVHIDDaemonServices
        case .vhidDriverVersionMismatch:
            .fixDriverVersionMismatch
        case .launchDaemonServices:
            .installLaunchDaemonServices
        case .launchDaemonServicesUnhealthy:
            .restartUnhealthyServices
        case .kanataBinaryMissing:
            .installBundledKanata // Install bundled kanata binary to system location
        case .kanataService:
            .installLaunchDaemonServices // Service configuration files
        case .kanataTCPServer:
            .restartUnhealthyServices // TCP server requires service restart with updated config
        case .orphanedKanataProcess:
            .adoptOrphanedProcess // Default to adopting the orphaned process
        case .communicationServerConfiguration:
            .regenerateCommServiceConfiguration // Update LaunchDaemon plist with communication settings
        case .communicationServerNotResponding:
            .restartCommServer // Restart service to enable communication functionality
        case .tcpServerConfiguration:
            .enableTCPServer // Enable TCP server
        case .tcpServerNotResponding:
            .enableTCPServer // Enable TCP server functionality
        case .logRotation:
            .installLogRotation
        default:
            .installMissingComponents
        }
    }

    private func getUserAction(for component: ComponentRequirement) -> String? {
        switch component {
        case .karabinerDriver:
            "Install Karabiner-Elements from website"
        case .vhidDeviceManager:
            "Install Karabiner-VirtualHIDDevice from website"
        case .kanataBinaryMissing:
            "Use the Installation Wizard to install Kanata automatically"
        case .communicationServerConfiguration:
            "Click 'Fix' to update the service with current communication settings"
        case .communicationServerNotResponding:
            "Click 'Fix' to restart the service with communication functionality"
        case .tcpServerConfiguration:
            "Click 'Fix' to enable TCP server"
        case .tcpServerNotResponding:
            "Click 'Fix' to restart the service with TCP functionality"
        case .logRotation:
            "Click 'Fix' to install log rotation service"
        default:
            nil
        }
    }

    private func getComponentUserAction(for component: ComponentRequirement) -> String? {
        switch component {
        case .vhidDeviceManager:
            "Install Karabiner-VirtualHIDDevice from website"
        case .kanataBinaryMissing:
            "Use the Installation Wizard to install Kanata automatically"
        default:
            nil
        }
    }
}

import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathWizardCore

/// Pure function that inspects a SystemContext and returns what's wrong.
/// No side effects, no async, no dependencies — just data in, data out.
public enum SystemInspector {
    /// Inspect the system and return the current state plus all detected issues.
    public static func inspect(context: SystemContext) -> (WizardSystemState, [WizardIssue]) {
        let state = determineState(context)
        let issues = generateIssues(context)
        return (state, issues)
    }

    // MARK: - State Determination

    static func determineState(_ context: SystemContext) -> WizardSystemState {
        if context.timedOut {
            return .serviceNotRunning
        }

        if context.conflicts.hasConflicts {
            return .conflictsDetected(conflicts: context.conflicts.conflicts)
        }

        let missingComponents = findMissingComponents(context)
        if !missingComponents.isEmpty {
            return .missingComponents(missing: missingComponents)
        }

        let missingPerms = findMissingPermissions(context)
        if !missingPerms.isEmpty {
            return .missingPermissions(missing: missingPerms)
        }

        if !context.services.kanataInputCaptureReady {
            return .missingPermissions(missing: [.kanataInputMonitoring])
        }

        if context.services.kanataPermissionRejected {
            return .missingPermissions(missing: [.kanataAccessibility])
        }

        if context.services.kanataRunning {
            return .active
        }

        if !context.services.karabinerDaemonRunning {
            return .daemonNotRunning
        }

        return .serviceNotRunning
    }

    // MARK: - Issue Generation

    static func generateIssues(_ context: SystemContext) -> [WizardIssue] {
        if context.timedOut {
            return [WizardIssue(
                identifier: .validationTimeout,
                severity: .warning,
                category: .daemon,
                title: "Status check timed out",
                description: "System validation exceeded the 12s watchdog. This is usually transient — the next check should succeed.",
                autoFixAction: nil,
                userAction: "If this persists, try restarting KeyPath."
            )]
        }

        var issues: [WizardIssue] = []

        appendPermissionIssues(context, into: &issues)
        appendComponentIssues(context, into: &issues)
        appendConflictIssues(context, into: &issues)
        appendServiceIssues(context, into: &issues)
        appendHelperIssues(context, into: &issues)

        return issues
    }

    // MARK: - Permission Issues

    private static func appendPermissionIssues(_ context: SystemContext, into issues: inout [WizardIssue]) {
        appendPermissionIssue(
            context.permissions.keyPath.inputMonitoring,
            identifier: .permission(.keyPathInputMonitoring),
            title: "Input Monitoring Permission Required",
            deniedDescription: "KeyPath needs Input Monitoring permission to function",
            userAction: "Grant Input Monitoring permission in System Settings",
            includeUnknown: false,
            into: &issues
        )
        appendPermissionIssue(
            context.permissions.keyPath.accessibility,
            identifier: .permission(.keyPathAccessibility),
            title: "Accessibility Permission Required",
            deniedDescription: "KeyPath needs Accessibility permission to function",
            userAction: "Grant Accessibility permission in System Settings",
            includeUnknown: false,
            into: &issues
        )
        appendPermissionIssue(
            context.permissions.kanata.inputMonitoring,
            identifier: .permission(.kanataInputMonitoring),
            title: "Kanata Engine Input Monitoring Permission",
            deniedDescription: "The Kanata engine used by KeyPath needs Input Monitoring permission",
            userAction: "Grant Input Monitoring permission to the Kanata engine binary in System Settings",
            includeUnknown: true,
            into: &issues
        )
        appendPermissionIssue(
            context.permissions.kanata.accessibility,
            identifier: .permission(.kanataAccessibility),
            title: "Kanata Engine Accessibility Permission",
            deniedDescription: "The Kanata engine used by KeyPath needs Accessibility permission",
            userAction: "Grant Accessibility permission to the Kanata engine binary in System Settings",
            includeUnknown: true,
            into: &issues
        )

        if !context.services.kanataInputCaptureReady,
           !issues.contains(where: { $0.identifier == .permission(.kanataInputMonitoring) })
        {
            issues.append(WizardIssue(
                identifier: .permission(.kanataInputMonitoring),
                severity: .error,
                category: .permissions,
                title: "KeyPath Runtime Cannot Open Built-In Keyboard",
                description: "KeyPath Runtime is running but cannot open the built-in keyboard device, so remapping will not work on this laptop.",
                autoFixAction: nil,
                userAction: "Regrant Input Monitoring for the KeyPath runtime binary and restart KeyPath"
            ))
        }
    }

    private static func appendPermissionIssue(
        _ status: PermissionOracle.Status,
        identifier: IssueIdentifier,
        title: String,
        deniedDescription: String,
        userAction: String,
        includeUnknown: Bool,
        into issues: inout [WizardIssue]
    ) {
        let shouldInclude: Bool = switch status {
        case .granted: false
        case .denied, .error: true
        case .unknown: includeUnknown
        }
        guard shouldInclude else { return }

        let severity: WizardIssue.IssueSeverity = (status == .unknown) ? .warning : .error
        let description: String = {
            if status == .unknown {
                return switch identifier {
                case .permission(.kanataInputMonitoring):
                    "Not verified (grant Full Disk Access to verify). If remapping doesn't work, add the KeyPath runtime binary in System Settings > Privacy & Security > Input Monitoring."
                case .permission(.kanataAccessibility):
                    "Not verified (grant Full Disk Access to verify). If remapping doesn't work, add the KeyPath runtime binary in System Settings > Privacy & Security > Accessibility."
                default:
                    "Not verified (grant Full Disk Access to verify)."
                }
            }
            return deniedDescription
        }()
        let userActionText = (status == .unknown)
            ? "Add kanata manually in System Settings, or enable Enhanced Diagnostics to verify"
            : userAction

        issues.append(WizardIssue(
            identifier: identifier,
            severity: severity,
            category: .permissions,
            title: title,
            description: description,
            autoFixAction: nil,
            userAction: userActionText
        ))
    }

    // MARK: - Component Issues

    private static func appendComponentIssues(_ context: SystemContext, into issues: inout [WizardIssue]) {
        if !context.components.karabinerDriverInstalled {
            issues.append(WizardIssue(
                identifier: .component(.karabinerDriver),
                severity: .error,
                category: .installation,
                title: "Karabiner Driver Missing",
                description: "Karabiner VirtualHID driver is not installed",
                autoFixAction: .installMissingComponents,
                userAction: nil
            ))
        }
        if context.components.vhidVersionMismatch {
            issues.append(WizardIssue(
                identifier: .component(.vhidDriverVersionMismatch),
                severity: .error,
                category: .installation,
                title: "Driver Version Mismatch",
                description: "Karabiner VirtualHID driver version mismatch",
                autoFixAction: .fixDriverVersionMismatch,
                userAction: nil
            ))
        }
        if !context.components.vhidDeviceHealthy {
            issues.append(WizardIssue(
                identifier: .component(.vhidDeviceRunning),
                severity: .error,
                category: .installation,
                title: "VirtualHID Device Unhealthy",
                description: "Karabiner VirtualHID device is not healthy",
                autoFixAction: .restartVirtualHIDDaemon,
                userAction: nil
            ))
        }
        if !context.components.vhidServicesHealthy {
            issues.append(WizardIssue(
                identifier: .component(.vhidDeviceManager),
                severity: .error,
                category: .installation,
                title: "VHID Services Unhealthy",
                description: "Karabiner VirtualHID services (daemon and manager) are not healthy",
                autoFixAction: .installRequiredRuntimeServices,
                userAction: nil
            ))
        }
    }

    // MARK: - Conflict Issues

    private static func appendConflictIssues(_ context: SystemContext, into issues: inout [WizardIssue]) {
        for conflict in context.conflicts.conflicts {
            issues.append(WizardIssue(
                identifier: .conflict(conflict),
                severity: .error,
                category: .conflicts,
                title: "Process Conflict",
                description: "Terminate conflicting process",
                autoFixAction: context.conflicts.canAutoResolve ? .terminateConflictingProcesses : nil,
                userAction: "Terminate process"
            ))
        }
    }

    // MARK: - Service Issues

    private static func appendServiceIssues(_ context: SystemContext, into issues: inout [WizardIssue]) {
        if !context.services.karabinerDaemonRunning {
            issues.append(WizardIssue(
                identifier: .component(.karabinerDaemon),
                severity: .error,
                category: .daemon,
                title: "Karabiner Daemon Not Running",
                description: "Karabiner daemon is not running",
                autoFixAction: .startKarabinerDaemon,
                userAction: nil
            ))
        }

        if !context.services.kanataRunning, context.components.vhidServicesHealthy,
           context.services.kanataInputCaptureReady
        {
            if context.services.kanataPermissionRejected {
                issues.append(WizardIssue(
                    identifier: .permission(.kanataAccessibility),
                    severity: .error,
                    category: .permissions,
                    title: "Kanata Engine Accessibility Permission",
                    description: "macOS rejected Kanata Engine after a rebuild. Remove and re-add the Kanata Engine entry in System Settings > Privacy & Security > Accessibility.",
                    autoFixAction: nil,
                    userAction: "Re-grant Accessibility permission for Kanata Engine in System Settings"
                ))
            } else {
                issues.append(WizardIssue(
                    identifier: .component(.keyPathRuntime),
                    severity: .error,
                    category: .daemon,
                    title: "KeyPath Runtime Not Running",
                    description: "KeyPath keyboard remapping runtime is not running",
                    autoFixAction: nil,
                    userAction: "Start KeyPath Runtime from the wizard or app status controls"
                ))
            }
        }
    }

    // MARK: - Helper Issues

    private static func appendHelperIssues(_ context: SystemContext, into issues: inout [WizardIssue]) {
        if !context.helper.isReady {
            issues.append(WizardIssue(
                identifier: .component(
                    context.helper.isInstalled ? .privilegedHelperUnhealthy : .privilegedHelper
                ),
                severity: .error,
                category: .backgroundServices,
                title: "Privileged Helper Not Ready",
                description: "Privileged helper is not installed or not working",
                autoFixAction: context.helper.isInstalled
                    ? .reinstallPrivilegedHelper : .installPrivilegedHelper,
                userAction: nil
            ))
        }
    }

    // MARK: - Helpers

    private static func findMissingPermissions(_ context: SystemContext) -> [PermissionRequirement] {
        var missing: [PermissionRequirement] = []
        if context.permissions.keyPath.inputMonitoring.isBlocking { missing.append(.keyPathInputMonitoring) }
        if context.permissions.keyPath.accessibility.isBlocking { missing.append(.keyPathAccessibility) }
        if context.permissions.kanata.inputMonitoring.isBlocking { missing.append(.kanataInputMonitoring) }
        if context.permissions.kanata.accessibility.isBlocking { missing.append(.kanataAccessibility) }
        return missing
    }

    private static func findMissingComponents(_ context: SystemContext) -> [ComponentRequirement] {
        var missing: [ComponentRequirement] = []
        if !context.components.karabinerDriverInstalled { missing.append(.karabinerDriver) }
        if !context.components.karabinerDaemonRunning { missing.append(.karabinerDaemon) }
        if context.components.vhidVersionMismatch { missing.append(.vhidDriverVersionMismatch) }
        if !context.components.vhidDeviceHealthy { missing.append(.vhidDeviceRunning) }
        return missing
    }
}

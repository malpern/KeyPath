import AppKit
import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore
import os

// MARK: - InstallerEngine abstraction for WizardAutoFixer

protocol WizardInstallerEngineProtocol: AnyObject, Sendable {
    func runSingleAction(_ action: AutoFixAction, using broker: PrivilegeBroker) async -> InstallerReport
}

extension InstallerEngine: WizardInstallerEngineProtocol {}

/// Handles automatic fixing of detected issues by delegating to the InstallerEngine façade.
class WizardAutoFixer {
    private let kanataManager: RuntimeCoordinator
    private let vhidDeviceManager: VHIDDeviceManager
    private let packageManager: PackageManager
    private let installerEngine: WizardInstallerEngineProtocol
    private let statusReporter: @MainActor (String) -> Void

    @MainActor
    init(
        kanataManager: RuntimeCoordinator,
        vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(),
        packageManager: PackageManager = PackageManager(),
        installerEngine: WizardInstallerEngineProtocol = InstallerEngine(),
        statusReporter: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.kanataManager = kanataManager
        self.vhidDeviceManager = vhidDeviceManager
        self.packageManager = packageManager
        self.installerEngine = installerEngine
        self.statusReporter = statusReporter
    }

    // MARK: - Error Analysis (retained)

    @MainActor
    func analyzeStartupError(_ error: String) -> (issue: WizardIssue?, canAutoFix: Bool) {
        let analysis = PermissionService.analyzeKanataError(error)

        if analysis.isPermissionError {
            // NOTE: Kanata doesn't need TCC permissions (uses Karabiner driver), but if we get
            // a permission-like error from Kanata, it's likely a driver/VHID issue, not TCC.
            // Map to a generic component issue that can guide the user to the right fix.
            let issue = WizardIssue(
                identifier: .component(.vhidDeviceRunning),
                severity: .error,
                category: .permissions,
                title: "Driver Permission Issue",
                description: analysis.suggestedFix ?? "Restart the Karabiner VirtualHID driver",
                autoFixAction: .startKarabinerDaemon,
                userAction: analysis.suggestedFix
            )
            return (issue, true) // Can auto-fix by restarting driver
        }

        if error.lowercased().contains("address already in use") {
            let issue = WizardIssue(
                identifier: .conflict(.kanataProcessRunning(pid: 0, command: "unknown")),
                severity: .error,
                category: .conflicts,
                title: "Process Conflict",
                description: "Another kanata process is already running",
                autoFixAction: .terminateConflictingProcesses,
                userAction: "Stop the conflicting process"
            )
            return (issue, true)
        }

        if error.lowercased().contains("device not configured") {
            let issue = WizardIssue(
                identifier: .component(.vhidDeviceRunning),
                severity: .error,
                category: .permissions,
                title: "VirtualHID Issue",
                description: "Karabiner VirtualHID driver needs to be restarted",
                autoFixAction: .startKarabinerDaemon,
                userAction: "Restart the Karabiner daemon"
            )
            return (issue, true)
        }

        return (nil, false)
    }

    // MARK: - AutoFixCapable protocol (delegation only)

    func canAutoFix(_ action: AutoFixAction) -> Bool {
        switch action {
        case .activateVHIDDeviceManager:
            vhidDeviceManager.detectInstallation()
        case .fixDriverVersionMismatch:
            vhidDeviceManager.hasVersionMismatch()
        default:
            true
        }
    }

    @MainActor
    func performAutoFix(_ action: AutoFixAction) async -> Bool {
        await _performAutoFix(action)
    }

    @MainActor
    private func _performAutoFix(_ action: AutoFixAction) async -> Bool {
        AppLogger.shared.log("🔧 [AutoFixer] Attempting auto-fix via façade: \(action)")
        return await runViaInstallerEngine(action)
    }

    /// Backward-compat reset hook used by Settings; delegates to façade repair action.
    @MainActor
    func resetEverything() async -> Bool {
        let report = await installerEngine.runSingleAction(.restartUnhealthyServices, using: PrivilegeBroker())
        return report.success
    }

    @MainActor
    private func runViaInstallerEngine(_ action: AutoFixAction) async -> Bool {
        let report = await installerEngine.runSingleAction(action, using: PrivilegeBroker())
        return report.success
    }
}

// MARK: - AutoFixCapable Conformance

extension WizardAutoFixer: AutoFixCapable {}

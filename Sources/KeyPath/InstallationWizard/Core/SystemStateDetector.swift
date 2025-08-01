import Foundation
import ApplicationServices

/// Pure system state detection logic - no side effects, no auto-fixing
class SystemStateDetector: SystemStateDetecting {
    private let kanataManager: KanataManager
    private let vhidDeviceManager: VHIDDeviceManager
    private let launchDaemonInstaller: LaunchDaemonInstaller
    
    init(kanataManager: KanataManager, vhidDeviceManager: VHIDDeviceManager = VHIDDeviceManager(), launchDaemonInstaller: LaunchDaemonInstaller = LaunchDaemonInstaller()) {
        self.kanataManager = kanataManager
        self.vhidDeviceManager = vhidDeviceManager
        self.launchDaemonInstaller = launchDaemonInstaller
    }
    
    // MARK: - Main Detection Method
    
    func detectCurrentState() async -> SystemStateResult {
        AppLogger.shared.log("🔍 [StateDetector] Starting comprehensive system state detection")
        
        // Detect all aspects of system state
        let conflictResult = await detectConflicts()
        let permissionResult = await checkPermissions()
        let componentResult = await checkComponents()
        let serviceRunning = kanataManager.isRunning
        let daemonRunning = kanataManager.isKarabinerDaemonRunning()
        
        // Determine overall state
        let state = determineOverallState(
            conflicts: conflictResult,
            permissions: permissionResult,
            components: componentResult,
            serviceRunning: serviceRunning,
            daemonRunning: daemonRunning
        )
        
        // Collect all issues
        var issues: [WizardIssue] = []
        issues.append(contentsOf: createConflictIssues(from: conflictResult))
        issues.append(contentsOf: createPermissionIssues(from: permissionResult))
        issues.append(contentsOf: createComponentIssues(from: componentResult))
        
        if !daemonRunning {
            issues.append(createDaemonIssue())
        }
        
        // Service status is handled by systemState on the summary page
        // No need to create separate service issues since the summary page
        // provides a "Start Kanata Service" button based on systemState
        
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
        
        AppLogger.shared.log("🔍 [StateDetector] Detection complete: \(state), \(issues.count) issues, \(autoFixActions.count) auto-fixes")
        return result
    }
    
    // MARK: - Conflict Detection
    
    func detectConflicts() async -> ConflictDetectionResult {
        AppLogger.shared.log("🔍 [StateDetector] Detecting system conflicts")
        
        var conflicts: [SystemConflict] = []
        
        // Check for running Kanata processes
        let kanataConflicts = await detectKanataProcessConflicts()
        conflicts.append(contentsOf: kanataConflicts)
        
        // Check for Karabiner grabber conflicts
        if kanataManager.isKarabinerElementsRunning() {
            // Note: We don't get PID from isKarabinerElementsRunning, so we use a placeholder
            conflicts.append(.karabinerGrabberRunning(pid: -1))
        }
        
        let canAutoResolve = !conflicts.isEmpty // We can auto-terminate processes
        let description = createConflictDescription(conflicts)
        
        return ConflictDetectionResult(
            conflicts: conflicts,
            canAutoResolve: canAutoResolve,
            description: description
        )
    }
    
    private func detectKanataProcessConflicts() async -> [SystemConflict] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "kanata"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        var conflicts: [SystemConflict] = []
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                
                for line in lines {
                    let components = line.components(separatedBy: " ")
                    guard let pidString = components.first,
                          let pid = Int(pidString),
                          components.count > 1 else {
                        continue
                    }
                    
                    let command = components.dropFirst().joined(separator: " ")
                    
                    // Filter out non-relevant processes
                    if command.contains("pgrep") || 
                       command.contains("/bin/zsh") || 
                       command.contains("/bin/sh") {
                        continue
                    }
                    
                    // Only include actual kanata processes
                    if command.contains("/usr/local/bin/kanata") || 
                       command.contains("/opt/homebrew/bin/kanata") ||
                       command.starts(with: "kanata") {
                        conflicts.append(.kanataProcessRunning(pid: pid, command: command))
                    }
                }
            }
        } catch {
            AppLogger.shared.log("❌ [StateDetector] Error detecting Kanata conflicts: \(error)")
        }
        
        return conflicts
    }
    
    private func createConflictDescription(_ conflicts: [SystemConflict]) -> String {
        guard !conflicts.isEmpty else { return "" }
        
        var description = "Found \(conflicts.count) conflicting process\(conflicts.count == 1 ? "" : "es"):\n"
        
        for conflict in conflicts {
            switch conflict {
            case .kanataProcessRunning(let pid, let command):
                description += "• Process ID: \(pid) - \(command)\n"
            case .karabinerGrabberRunning(let pid):
                if pid > 0 {
                    description += "• Karabiner grabber (PID: \(pid))\n"
                } else {
                    description += "• Karabiner grabber process\n"
                }
            case .exclusiveDeviceAccess(let device):
                description += "• Exclusive access conflict: \(device)\n"
            }
        }
        
        return description
    }
    
    // MARK: - Permission Checking
    
    func checkPermissions() async -> PermissionCheckResult {
        AppLogger.shared.log("🔍 [StateDetector] Checking system permissions")
        
        var missing: [PermissionRequirement] = []
        var granted: [PermissionRequirement] = []
        
        // Check Input Monitoring permissions for each app individually
        let keyPathHasInputMonitoring = kanataManager.hasInputMonitoringPermission()
        let kanataHasInputMonitoring = kanataManager.checkTCCForInputMonitoring(path: "/usr/local/bin/kanata")
        
        AppLogger.shared.log("🔍 [StateDetector] Input Monitoring - KeyPath: \(keyPathHasInputMonitoring), Kanata: \(kanataHasInputMonitoring)")
        
        // For Input Monitoring, we need BOTH apps to have permission for the system to work properly
        if keyPathHasInputMonitoring && kanataHasInputMonitoring {
            granted.append(.kanataInputMonitoring)
            AppLogger.shared.log("🔍 [StateDetector] ✅ Input Monitoring GRANTED")
        } else {
            missing.append(.kanataInputMonitoring)
            AppLogger.shared.log("🔍 [StateDetector] ❌ Input Monitoring MISSING")
        }
        
        // Check accessibility permissions for both apps
        // For KeyPath app, use the system's current accessibility check
        let keyPathAccessibility = AXIsProcessTrusted()
        let kanataAccessibility = kanataManager.checkAccessibilityForPath("/usr/local/bin/kanata")
        
        AppLogger.shared.log("🔍 [StateDetector] Accessibility - KeyPath: \(keyPathAccessibility), Kanata: \(kanataAccessibility)")
        
        // For Accessibility, we need BOTH apps to have permission  
        if keyPathAccessibility && kanataAccessibility {
            granted.append(.kanataAccessibility)
            AppLogger.shared.log("🔍 [StateDetector] ✅ Accessibility GRANTED")
        } else {
            missing.append(.kanataAccessibility)
            AppLogger.shared.log("🔍 [StateDetector] ❌ Accessibility MISSING")
        }
        
        // Check driver extension
        if kanataManager.isKarabinerDriverExtensionEnabled() {
            granted.append(.driverExtensionEnabled)
        } else {
            missing.append(.driverExtensionEnabled)
        }
        
        // Check background services
        if kanataManager.areKarabinerBackgroundServicesEnabled() {
            granted.append(.backgroundServicesEnabled)
        } else {
            missing.append(.backgroundServicesEnabled)
        }
        
        let needsUserAction = !missing.isEmpty
        
        return PermissionCheckResult(
            missing: missing,
            granted: granted,
            needsUserAction: needsUserAction
        )
    }
    
    // MARK: - Component Checking
    
    func checkComponents() async -> ComponentCheckResult {
        AppLogger.shared.log("🔍 [StateDetector] Checking system components")
        
        var missing: [ComponentRequirement] = []
        var installed: [ComponentRequirement] = []
        
        // Check Kanata binary
        if kanataManager.isInstalled() {
            installed.append(.kanataBinary)
        } else {
            missing.append(.kanataBinary)
        }
        
        // Service is always available with direct execution
        installed.append(.kanataService)
        
        // Check Karabiner driver
        if kanataManager.isKarabinerDriverInstalled() {
            installed.append(.karabinerDriver)
        } else {
            missing.append(.karabinerDriver)
        }
        
        // Check Karabiner daemon
        if kanataManager.isKarabinerDaemonRunning() {
            installed.append(.karabinerDaemon)
        } else {
            missing.append(.karabinerDaemon)
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
        
        if vhidDeviceManager.detectRunning() {
            installed.append(.vhidDeviceRunning)
        } else {
            missing.append(.vhidDeviceRunning)
        }
        
        // Check LaunchDaemon services
        let daemonStatus = launchDaemonInstaller.getServiceStatus()
        if daemonStatus.allServicesLoaded {
            installed.append(.launchDaemonServices)
        } else {
            missing.append(.launchDaemonServices)
        }
        
        let canAutoInstall = !missing.isEmpty && 
                           !missing.contains(.karabinerDriver) && // Driver requires manual installation
                           !missing.contains(.vhidDeviceManager) // VHIDDevice Manager requires manual installation
        
        return ComponentCheckResult(
            missing: missing,
            installed: installed,
            canAutoInstall: canAutoInstall
        )
    }
    
    // MARK: - State Determination
    
    private func determineOverallState(
        conflicts: ConflictDetectionResult,
        permissions: PermissionCheckResult,
        components: ComponentCheckResult,
        serviceRunning: Bool,
        daemonRunning: Bool
    ) -> WizardSystemState {
        
        // Priority order: conflicts > missing components > missing permissions > daemon > service > ready
        
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
    
    // MARK: - Issue Creation
    
    private func createConflictIssues(from result: ConflictDetectionResult) -> [WizardIssue] {
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
    
    private func createPermissionIssues(from result: PermissionCheckResult) -> [WizardIssue] {
        AppLogger.shared.log("🔍 [StateDetector] Creating issues for \(result.missing.count) missing permissions:")
        for permission in result.missing {
            AppLogger.shared.log("🔍 [StateDetector]   - Missing: \(permission)")
        }
        
        return result.missing.map { permission in
            // Background services get their own category and page
            let category: WizardIssue.IssueCategory = permission == .backgroundServicesEnabled ? .backgroundServices : .permissions
            let title = permissionTitle(for: permission)
            
            AppLogger.shared.log("🔍 [StateDetector] Creating issue: category=\(category), title='\(title)'")
            
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
    
    private func createComponentIssues(from result: ComponentCheckResult) -> [WizardIssue] {
        return result.missing.map { component in
            WizardIssue(
                identifier: .component(component),
                severity: .error,
                category: .installation,
                title: componentTitle(for: component),
                description: componentDescription(for: component),
                autoFixAction: getAutoFixAction(for: component),
                userAction: getUserAction(for: component)
            )
        }
    }
    
    private func createDaemonIssue() -> WizardIssue {
        WizardIssue(
            identifier: .daemon,
            severity: .warning,
            category: .daemon,
            title: WizardConstants.Titles.daemonNotRunning,
            description: "The Karabiner Virtual HID Device Daemon needs to be running for keyboard remapping.",
            autoFixAction: .startKarabinerDaemon,
            userAction: nil
        )
    }
    
    
    // MARK: - Auto-Fix Action Determination
    
    private func determineAutoFixActions(
        conflicts: ConflictDetectionResult,
        permissions: PermissionCheckResult,
        components: ComponentCheckResult,
        daemonRunning: Bool
    ) -> [AutoFixAction] {
        
        var actions: [AutoFixAction] = []
        
        if conflicts.hasConflicts && conflicts.canAutoResolve {
            actions.append(.terminateConflictingProcesses)
        }
        
        if components.canAutoInstall {
            actions.append(.installMissingComponents)
        }
        
        if !daemonRunning {
            actions.append(.startKarabinerDaemon)
        }
        
        // Check if VHIDDevice Manager needs activation
        if components.missing.contains(.vhidDeviceActivation) && 
           components.installed.contains(.vhidDeviceManager) {
            actions.append(.activateVHIDDeviceManager)
        }
        
        // Check if LaunchDaemon services need installation
        if components.missing.contains(.launchDaemonServices) {
            actions.append(.installLaunchDaemonServices)
        }
        
        return actions
    }
    
    // MARK: - Helper Methods
    
    private func permissionTitle(for permission: PermissionRequirement) -> String {
        switch permission {
        case .kanataInputMonitoring: return WizardConstants.Titles.kanataInputMonitoring
        case .kanataAccessibility: return WizardConstants.Titles.kanataAccessibility
        case .driverExtensionEnabled: return WizardConstants.Titles.driverExtensionDisabled
        case .backgroundServicesEnabled: return WizardConstants.Titles.backgroundServicesDisabled
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
            return "Karabiner background services must be enabled for HID functionality. These may need to be manually added as Login Items."
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
            return "Add Karabiner services to Login Items in System Settings > General > Login Items & Extensions"
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
        }
    }
    
    private func componentDescription(for component: ComponentRequirement) -> String {
        switch component {
        case .kanataBinary:
            return "The kanata binary is not installed or not found in expected locations."
        case .kanataService:
            return "Kanata service configuration is missing."
        case .karabinerDriver:
            return "Karabiner-Elements driver is required for virtual HID functionality."
        case .karabinerDaemon:
            return "Karabiner Virtual HID Device Daemon is not running."
        case .vhidDeviceManager:
            return "The Karabiner VirtualHIDDevice Manager application is not installed. This is required for keyboard remapping functionality."
        case .vhidDeviceActivation:
            return "The VirtualHIDDevice Manager needs to be activated to enable virtual HID functionality."
        case .vhidDeviceRunning:
            return "The VirtualHIDDevice daemon processes are not running. This may indicate the manager needs activation or restart."
        case .launchDaemonServices:
            return "LaunchDaemon services are not installed or loaded. These provide reliable system-level service management for KeyPath components."
        }
    }
    
    private func getAutoFixAction(for component: ComponentRequirement) -> AutoFixAction? {
        switch component {
        case .karabinerDriver, .vhidDeviceManager:
            return nil // These require manual installation
        case .vhidDeviceActivation:
            return .activateVHIDDeviceManager
        case .launchDaemonServices:
            return .installLaunchDaemonServices
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
        default:
            return nil
        }
    }
}
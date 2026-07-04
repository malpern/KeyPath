import AppKit
import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore

public struct SystemFacade: Sendable {
    typealias RuntimeSnapshot = ServiceHealthChecker.KanataServiceRuntimeSnapshot

    private let subprocessRunner: any SubprocessRunning
    private let runtimeSnapshotProvider: @Sendable () async -> RuntimeSnapshot
    private let runtimeTransitionTimeoutSeconds: TimeInterval
    private let pollDelayNanoseconds: UInt64
    private let restartDelayNanoseconds: UInt64

    public init() {
        self.init(
            subprocessRunner: SubprocessRunner.shared,
            runtimeSnapshotProvider: {
                await ServiceHealthChecker.shared.checkKanataServiceRuntimeSnapshot()
            }
        )
    }

    init(
        subprocessRunner: any SubprocessRunning,
        runtimeSnapshotProvider: @escaping @Sendable () async -> RuntimeSnapshot,
        runtimeTransitionTimeoutSeconds: TimeInterval = 5,
        pollDelayNanoseconds: UInt64 = 200_000_000,
        restartDelayNanoseconds: UInt64 = 500_000_000
    ) {
        self.subprocessRunner = subprocessRunner
        self.runtimeSnapshotProvider = runtimeSnapshotProvider
        self.runtimeTransitionTimeoutSeconds = runtimeTransitionTimeoutSeconds
        self.pollDelayNanoseconds = pollDelayNanoseconds
        self.restartDelayNanoseconds = restartDelayNanoseconds
    }

    // MARK: - Service Lifecycle

    public func startService() async -> Bool {
        do {
            let result = try await subprocessRunner.launchctl("kickstart", ["system/com.keypath.kanata"])
            guard result.exitCode == 0 else { return false }
            return await waitForRuntime(timeoutSeconds: runtimeTransitionTimeoutSeconds) { snapshot in
                snapshot.isRunning && snapshot.isResponding
            }
        } catch {
            return false
        }
    }

    public func stopService() async -> Bool {
        do {
            let result = try await subprocessRunner.launchctl("kill", ["SIGTERM", "system/com.keypath.kanata"])
            guard result.exitCode == 0 else { return false }
            return await waitForRuntime(timeoutSeconds: runtimeTransitionTimeoutSeconds) { snapshot in
                !snapshot.isRunning && !snapshot.isResponding
            }
        } catch {
            return false
        }
    }

    public func restartService() async -> Bool {
        guard await stopService() else { return false }
        if restartDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: restartDelayNanoseconds)
        }
        return await startService()
    }

    private func waitForRuntime(
        timeoutSeconds: TimeInterval,
        matches predicate: (RuntimeSnapshot) -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            let snapshot = await runtimeSnapshotProvider()
            if predicate(snapshot) {
                return true
            }
            if pollDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: pollDelayNanoseconds)
            }
        } while Date() < deadline

        return false
    }

    public func serviceLogs(lines: Int = 50) -> [String] {
        let logPath = KeyPathConstants.Logs.userDebugLog
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return []
        }
        let allLines = content.components(separatedBy: .newlines)
        return Array(allLines.suffix(lines))
    }

    // MARK: - Status

    @MainActor
    public func runStatus() async -> CLIStatusResult {
        CLIRuntimeBootstrap.ensureConfigured()
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        return CLIStatusResult(
            isOperational: context.permissions.isSystemReady
                && context.helper.isReady
                && context.components.hasAllRequired
                && context.services.isHealthy
                && !context.conflicts.hasConflicts,
            helperInstalled: context.helper.isInstalled,
            helperWorking: context.helper.isWorking,
            helperVersion: context.helper.version,
            keyPathAccessibility: context.permissions.keyPath.accessibility.isReady,
            keyPathInputMonitoring: context.permissions.keyPath.inputMonitoring.isReady,
            kanataAccessibility: context.permissions.kanata.accessibility.isReady,
            kanataInputMonitoring: context.permissions.kanata.inputMonitoring.isReady,
            kanataBinaryInstalled: context.components.kanataBinaryInstalled,
            karabinerDriverInstalled: context.components.karabinerDriverInstalled,
            vhidDeviceHealthy: context.components.vhidDeviceHealthy,
            kanataRunning: context.services.kanataRunning,
            karabinerDaemonRunning: context.services.karabinerDaemonRunning,
            vhidHealthy: context.services.vhidHealthy,
            activeRuntimePathTitle: context.services.activeRuntimePathTitle,
            activeRuntimePathDetail: context.services.activeRuntimePathDetail,
            hasConflicts: context.conflicts.hasConflicts,
            timestamp: context.timestamp
        )
    }

    // MARK: - Installer

    @MainActor
    public func runInstall(dryRun: Bool = false) async -> CLIInstallerReport {
        CLIRuntimeBootstrap.ensureConfigured()
        if let bundleIssue = Self.systemRepairBundleIssue() {
            return CLIInstallerReport(bundleIssue: bundleIssue, dryRun: dryRun, title: "Installation")
        }
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .install, context: context)
        if dryRun {
            return CLIInstallerReport(
                dryRunPlan: plan,
                context: context,
                title: "Installation"
            )
        }
        let broker = PrivilegeBroker()
        let report = await engine.execute(plan: plan, using: broker)
        let finalContext = report.success ? await engine.inspectSystem() : nil
        return CLIInstallerReport(
            from: report,
            initialContext: context,
            finalContext: finalContext,
            plan: plan,
            title: "Installation"
        )
    }

    @MainActor
    public func runRepair(dryRun: Bool = false) async -> CLIInstallerReport {
        CLIRuntimeBootstrap.ensureConfigured()
        if let bundleIssue = Self.systemRepairBundleIssue() {
            return CLIInstallerReport(bundleIssue: bundleIssue, dryRun: dryRun, title: "Repair")
        }
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .repair, context: context)
        if dryRun {
            return CLIInstallerReport(
                dryRunPlan: plan,
                context: context,
                title: "Repair"
            )
        }

        let initialIssues = Self.issues(from: context)
        let initialUserActionIssues = initialIssues.filter { !$0.canAutoFix }
        if !initialUserActionIssues.isEmpty, plan.recipes.isEmpty {
            return CLIInstallerReport(
                success: false,
                failureReason: Self.userActionFailureReason(initialUserActionIssues, prefix: "Repair requires user action"),
                steps: [],
                fastRepair: false,
                dryRun: false,
                userActionRequired: true,
                issues: initialIssues,
                plannedRecipes: [],
                unmetRequirements: plan.blockedBy.map { [$0.name] } ?? [],
                logs: []
            )
        }

        let broker = PrivilegeBroker()
        let report = await engine.execute(plan: plan, using: broker)
        let finalContext = report.success ? await engine.inspectSystem() : nil
        return CLIInstallerReport(
            from: report,
            initialContext: context,
            finalContext: finalContext,
            plan: plan,
            title: "Repair"
        )
    }

    @MainActor
    public func runUninstall(deleteConfig: Bool) async -> CLIInstallerReport {
        CLIRuntimeBootstrap.ensureConfigured()
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.uninstall(deleteConfig: deleteConfig, using: broker)
        return CLIInstallerReport(from: report)
    }

    @MainActor
    public func runInspect(planIntent: InstallIntent = .repair) async -> CLIInspectResult {
        CLIRuntimeBootstrap.ensureConfigured()
        if let bundleIssue = Self.systemRepairBundleIssue() {
            return CLIInspectResult(
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                driverCompatible: false,
                planStatus: "blocked",
                blockedBy: "Valid KeyPath.app bundle",
                plannedRecipes: [],
                planIntent: "\(planIntent)",
                isOperational: false,
                userActionRequired: true,
                promptsNeeded: false,
                issues: [bundleIssue]
            )
        }
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: planIntent, context: context)

        let planStatus: String
        var blockedBy: String?
        switch plan.status {
        case .ready:
            planStatus = "ready"
        case let .blocked(requirement):
            planStatus = "blocked"
            blockedBy = requirement.name
        }

        return CLIInspectResult(
            macOSVersion: context.system.macOSVersion,
            driverCompatible: context.system.driverCompatible,
            planStatus: planStatus,
            blockedBy: blockedBy,
            plannedRecipes: plan.recipes.map { "\($0.id) (\($0.type))" },
            planIntent: "\(planIntent)",
            isOperational: Self.isOperational(context),
            userActionRequired: Self.issues(from: context).contains { !$0.canAutoFix },
            promptsNeeded: plan.metadata.promptsNeeded,
            issues: Self.issues(from: context)
        )
    }

    @MainActor
    public func openFirstRemediationURL(in issues: [CLISystemIssue]) -> Bool {
        guard let rawURL = issues.compactMap(\.remediationURL).first,
              let url = URL(string: rawURL)
        else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    fileprivate static func isOperational(_ context: SystemContext) -> Bool {
        context.permissions.isSystemReady
            && context.helper.isReady
            && context.components.hasAllRequired
            && context.services.isHealthy
            && !context.conflicts.hasConflicts
    }

    fileprivate static func systemRepairBundleIssue() -> CLISystemIssue? {
        let bundlePath = Bundle.main.bundlePath
        let requiredPaths = [
            "\(bundlePath)/Contents/MacOS/keypath-cli",
            "\(bundlePath)/Contents/Library/LaunchDaemons/com.keypath.kanata.plist",
            "\(bundlePath)/Contents/Library/HelperTools/KeyPathHelper",
            WizardSystemPaths.bundledKanataPath,
            WizardSystemPaths.bundledKanataLauncherPath,
        ]
        if requiredPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
            return nil
        }

        return CLISystemIssue(
            title: "System repair requires the app-bundled CLI",
            category: "bundle",
            action: "Open KeyPath and choose File > Install Command Line Tool, or run /Applications/KeyPath.app/Contents/MacOS/keypath-cli",
            canAutoFix: false
        )
    }

    fileprivate static func issues(from context: SystemContext) -> [CLISystemIssue] {
        var issues: [CLISystemIssue] = []

        if !context.helper.isInstalled {
            issues.append(.init(
                title: "Privileged Helper not installed",
                category: "helper",
                action: "Install or repair KeyPath services",
                canAutoFix: true
            ))
        } else if !context.helper.isWorking {
            issues.append(.init(
                title: "Privileged Helper unhealthy",
                category: "helper",
                action: "Reinstall the privileged helper",
                canAutoFix: true
            ))
        }

        appendPermissionIssues(from: context, to: &issues)

        for conflict in context.conflicts.conflicts {
            issues.append(.init(
                title: Self.conflictTitle(conflict),
                category: "conflict",
                action: "Terminate conflicting process",
                canAutoFix: context.conflicts.canAutoResolve
            ))
        }

        if !context.components.kanataBinaryInstalled {
            issues.append(.init(
                title: "Kanata binary not installed",
                category: "component",
                action: "Reinstall KeyPath; the bundled Kanata engine is missing",
                canAutoFix: false
            ))
        }
        if !context.components.karabinerDriverInstalled {
            issues.append(.init(
                title: "Karabiner VirtualHID driver not installed",
                category: "component",
                action: "Install the bundled VirtualHID driver",
                canAutoFix: true
            ))
        }
        if context.components.vhidVersionMismatch {
            issues.append(.init(
                title: "Karabiner VirtualHID driver version incompatible",
                category: "component",
                action: "Install the compatible bundled VirtualHID driver",
                canAutoFix: true
            ))
        }
        if !context.components.vhidDeviceHealthy {
            issues.append(.init(
                title: "VirtualHID device unhealthy",
                category: "component",
                action: "Repair VirtualHID services",
                canAutoFix: true
            ))
        }

        if !context.services.isHealthy {
            if !context.services.kanataRunning, let configError = context.services.configParseError {
                issues.append(.init(
                    title: "Configuration error prevents remapping",
                    category: "configuration",
                    action: configError,
                    canAutoFix: false
                ))
            } else if !context.services.kanataRunning, context.services.kanataPermissionRejected {
                issues.append(.init(
                    title: "Kanata needs Accessibility permission",
                    category: "permissions",
                    action: "Re-grant Accessibility for Kanata Engine in System Settings",
                    canAutoFix: false
                ))
            } else if !context.services.kanataRunning {
                issues.append(.init(
                    title: "Kanata service not running",
                    category: "service",
                    action: "Start or reinstall the Kanata service",
                    canAutoFix: true
                ))
            }
            if !context.services.karabinerDaemonRunning {
                issues.append(.init(
                    title: "Karabiner VirtualHID daemon not running",
                    category: "service",
                    action: "Start or repair the VirtualHID daemon",
                    canAutoFix: true
                ))
            }
        }

        return issues
    }

    private static func appendPermissionIssues(from context: SystemContext, to issues: inout [CLISystemIssue]) {
        if !context.permissions.keyPath.accessibility.isReady {
            issues.append(.init(
                title: "KeyPath needs Accessibility permission",
                category: "permissions",
                action: "Open KeyPath.app and grant Accessibility in System Settings > Privacy & Security > Accessibility",
                canAutoFix: false,
                remediationURL: WizardSystemPaths.accessibilitySettings
            ))
        }
        if !context.permissions.keyPath.inputMonitoring.isReady {
            issues.append(.init(
                title: "KeyPath needs Input Monitoring permission",
                category: "permissions",
                action: "Open KeyPath.app and grant Input Monitoring in System Settings > Privacy & Security > Input Monitoring",
                canAutoFix: false,
                remediationURL: WizardSystemPaths.inputMonitoringSettings
            ))
        }
        if !context.permissions.kanata.accessibility.isReady {
            issues.append(.init(
                title: "Kanata needs Accessibility permission",
                category: "permissions",
                action: "Open the KeyPath Installation Wizard to grant Kanata Engine Accessibility",
                canAutoFix: false,
                remediationURL: WizardSystemPaths.accessibilitySettings
            ))
        }
        if !context.permissions.kanata.inputMonitoring.isReady {
            issues.append(.init(
                title: "Kanata needs Input Monitoring permission",
                category: "permissions",
                action: "Open the KeyPath Installation Wizard to grant Kanata Engine Input Monitoring",
                canAutoFix: false,
                remediationURL: WizardSystemPaths.inputMonitoringSettings
            ))
        }
        if !context.services.kanataInputCaptureReady {
            let vhidDriverNotActivated = context.services.kanataInputCaptureIssue
                == ServiceHealthChecker.inputCaptureVHIDDriverNotActivatedReason
            issues.append(.init(
                title: vhidDriverNotActivated
                    ? "Karabiner VirtualHIDDevice driver is not activated"
                    : "Kanata cannot capture keyboard input",
                category: vhidDriverNotActivated ? "service" : "permissions",
                action: vhidDriverNotActivated
                    ? "Activate and repair the VirtualHID daemon services"
                    : context.services.kanataInputCaptureIssue
                    ?? "Re-grant Input Monitoring for Kanata Engine in System Settings",
                canAutoFix: vhidDriverNotActivated,
                remediationURL: vhidDriverNotActivated ? nil : WizardSystemPaths.inputMonitoringSettings
            ))
        }
    }

    private static func conflictTitle(_ conflict: SystemConflict) -> String {
        switch conflict {
        case let .kanataProcessRunning(pid, _):
            "Conflicting Kanata process running (PID \(pid))"
        case let .karabinerGrabberRunning(pid):
            "Karabiner Grabber running (PID \(pid))"
        case let .karabinerVirtualHIDDeviceRunning(pid, _):
            "Karabiner VirtualHID process running (PID \(pid))"
        case let .karabinerVirtualHIDDaemonRunning(pid):
            "Karabiner VirtualHID daemon running (PID \(pid))"
        case let .exclusiveDeviceAccess(device):
            "Device in exclusive use: \(device)"
        }
    }

    fileprivate static func userActionFailureReason(_ issues: [CLISystemIssue], prefix: String) -> String {
        guard let first = issues.first else { return prefix }
        return "\(prefix): \(first.title). \(first.action)"
    }

    fileprivate static func requiresManualApproval(_ failureReason: String) -> Bool {
        let normalized = failureReason.lowercased()
        return normalized.contains("waiting for macos approval")
            || normalized.contains("system settings > privacy & security")
    }
}

// MARK: - System Types

public struct CLIStatusResult: Codable, Sendable {
    public let isOperational: Bool
    public let helperInstalled: Bool
    public let helperWorking: Bool
    public let helperVersion: String?
    public let keyPathAccessibility: Bool
    public let keyPathInputMonitoring: Bool
    public let kanataAccessibility: Bool
    public let kanataInputMonitoring: Bool
    public let kanataBinaryInstalled: Bool
    public let karabinerDriverInstalled: Bool
    public let vhidDeviceHealthy: Bool
    public let kanataRunning: Bool
    public let karabinerDaemonRunning: Bool
    public let vhidHealthy: Bool
    public let activeRuntimePathTitle: String?
    public let activeRuntimePathDetail: String?
    public let hasConflicts: Bool
    public let timestamp: Date
}

public struct CLIInstallerReport: Codable, Sendable {
    public let success: Bool
    public let failureReason: String?
    public let steps: [CLIInstallerStep]
    public let fastRepair: Bool
    public let dryRun: Bool?
    public let userActionRequired: Bool?
    public let issues: [CLISystemIssue]?
    public let plannedRecipes: [String]?
    public let unmetRequirements: [String]?
    public let logs: [String]?

    init(from report: InstallerReport) {
        success = report.success
        failureReason = report.failureReason
        steps = report.executedRecipes.map {
            CLIInstallerStep(name: $0.recipeID, success: $0.success, error: $0.error)
        }
        fastRepair = false
        dryRun = nil
        userActionRequired = nil
        issues = nil
        plannedRecipes = nil
        unmetRequirements = nil
        logs = nil
    }

    init(
        from report: InstallerReport,
        initialContext: SystemContext,
        finalContext: SystemContext?,
        plan: InstallPlan,
        title: String
    ) {
        let finalIssues = SystemFacade.issues(from: finalContext ?? initialContext)
        let finalUserActionIssues = finalIssues.filter { !$0.canAutoFix }
        let finalOperational = finalContext.map(SystemFacade.isOperational) ?? false
        let completedButStillBlocked = report.success && !finalOperational && !finalIssues.isEmpty
        let failedForManualApproval = report.failureReason.map(SystemFacade.requiresManualApproval) ?? false

        success = report.success && !completedButStillBlocked
        if let reportFailure = report.failureReason {
            failureReason = reportFailure
        } else if !finalUserActionIssues.isEmpty {
            failureReason = SystemFacade.userActionFailureReason(
                finalUserActionIssues,
                prefix: "\(title) requires user action"
            )
        } else if completedButStillBlocked {
            failureReason = "Repair completed but system still has blocking issue(s)"
        } else {
            failureReason = nil
        }
        steps = report.executedRecipes.map {
            CLIInstallerStep(name: $0.recipeID, success: $0.success, error: $0.error)
        }
        fastRepair = false
        dryRun = false
        userActionRequired = !finalUserActionIssues.isEmpty || plan.metadata.promptsNeeded || failedForManualApproval
        issues = finalIssues
        plannedRecipes = plan.recipes.map { "\($0.id) (\($0.type))" }
        unmetRequirements = report.unmetRequirements.map(\.name)
        logs = report.logs
    }

    init(dryRunPlan plan: InstallPlan, context: SystemContext, title: String) {
        let contextIssues = SystemFacade.issues(from: context)
        let userActionIssues = contextIssues.filter { !$0.canAutoFix }
        let blockedBy = plan.blockedBy.map { [$0.name] } ?? []

        success = blockedBy.isEmpty && userActionIssues.isEmpty
        if !blockedBy.isEmpty {
            failureReason = "Plan blocked by requirement: \(blockedBy.joined(separator: ", "))"
        } else if !userActionIssues.isEmpty {
            failureReason = SystemFacade.userActionFailureReason(
                userActionIssues,
                prefix: "\(title) requires user action"
            )
        } else {
            failureReason = nil
        }
        steps = []
        fastRepair = false
        dryRun = true
        userActionRequired = !userActionIssues.isEmpty || plan.metadata.promptsNeeded
        issues = contextIssues
        plannedRecipes = plan.recipes.map { "\($0.id) (\($0.type))" }
        unmetRequirements = blockedBy
        logs = nil
    }

    init(success: Bool, failureReason: String?, steps: [CLIInstallerStep], fastRepair: Bool) {
        self.success = success
        self.failureReason = failureReason
        self.steps = steps
        self.fastRepair = fastRepair
        dryRun = nil
        userActionRequired = nil
        issues = nil
        plannedRecipes = nil
        unmetRequirements = nil
        logs = nil
    }

    init(bundleIssue: CLISystemIssue, dryRun: Bool, title: String) {
        success = false
        failureReason = "\(title) requires the signed KeyPath.app bundle. \(bundleIssue.action)"
        steps = []
        fastRepair = false
        self.dryRun = dryRun
        userActionRequired = true
        issues = [bundleIssue]
        plannedRecipes = []
        unmetRequirements = ["Valid KeyPath.app bundle"]
        logs = nil
    }

    init(
        success: Bool,
        failureReason: String?,
        steps: [CLIInstallerStep],
        fastRepair: Bool,
        dryRun: Bool?,
        userActionRequired: Bool?,
        issues: [CLISystemIssue]?,
        plannedRecipes: [String]?,
        unmetRequirements: [String]?,
        logs: [String]?
    ) {
        self.success = success
        self.failureReason = failureReason
        self.steps = steps
        self.fastRepair = fastRepair
        self.dryRun = dryRun
        self.userActionRequired = userActionRequired
        self.issues = issues
        self.plannedRecipes = plannedRecipes
        self.unmetRequirements = unmetRequirements
        self.logs = logs
    }
}

public struct CLIInstallerStep: Codable, Sendable {
    public let name: String
    public let success: Bool
    public let error: String?
}

public struct CLIInspectResult: Codable, Sendable {
    public let macOSVersion: String
    public let driverCompatible: Bool
    public let planStatus: String
    public let blockedBy: String?
    public let plannedRecipes: [String]
    public let planIntent: String?
    public let isOperational: Bool?
    public let userActionRequired: Bool?
    public let promptsNeeded: Bool?
    public let issues: [CLISystemIssue]?
}

public struct CLISystemIssue: Codable, Sendable {
    public let title: String
    public let category: String
    public let action: String
    public let canAutoFix: Bool
    public let remediationURL: String?

    public init(
        title: String,
        category: String,
        action: String,
        canAutoFix: Bool,
        remediationURL: String? = nil
    ) {
        self.title = title
        self.category = category
        self.action = action
        self.canAutoFix = canAutoFix
        self.remediationURL = remediationURL
    }
}

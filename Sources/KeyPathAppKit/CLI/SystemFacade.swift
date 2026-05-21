import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore

public struct SystemFacade: Sendable {
    public init() {}

    // MARK: - Service Lifecycle

    public func startService() async -> Bool {
        do {
            try await SubprocessRunner.shared.launchctl("kickstart", ["system/com.keypath.kanata"])
            return true
        } catch {
            return false
        }
    }

    public func stopService() async -> Bool {
        do {
            try await SubprocessRunner.shared.launchctl("kill", ["SIGTERM", "system/com.keypath.kanata"])
            return true
        } catch {
            return false
        }
    }

    public func restartService() async -> Bool {
        _ = await stopService()
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await startService()
    }

    public func serviceLogs(lines: Int = 50) -> [String] {
        let logPath = NSString("~/Library/Logs/KeyPath/keypath-debug.log").expandingTildeInPath
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return []
        }
        let allLines = content.components(separatedBy: .newlines)
        return Array(allLines.suffix(lines))
    }

    // MARK: - Status

    @MainActor
    public func runStatus() async -> CLIStatusResult {
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
    public func runInstall() async -> CLIInstallerReport {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .install, using: broker)
        return CLIInstallerReport(from: report)
    }

    @MainActor
    public func runRepair() async -> CLIInstallerReport {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .repair, using: broker)
        return CLIInstallerReport(from: report)
    }

    @MainActor
    public func runUninstall(deleteConfig: Bool) async -> CLIInstallerReport {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.uninstall(deleteConfig: deleteConfig, using: broker)
        return CLIInstallerReport(from: report)
    }

    @MainActor
    public func runInspect() async -> CLIInspectResult {
        let engine = InstallerEngine()
        let context = await engine.inspectSystem()
        let plan = await engine.makePlan(for: .inspectOnly, context: context)

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
            plannedRecipes: plan.recipes.map { "\($0.id) (\($0.type))" }
        )
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

    init(from report: InstallerReport) {
        success = report.success
        failureReason = report.failureReason
        steps = report.executedRecipes.map {
            CLIInstallerStep(name: $0.recipeID, success: $0.success, error: $0.error)
        }
        fastRepair = false
    }

    init(success: Bool, failureReason: String?, steps: [CLIInstallerStep], fastRepair: Bool) {
        self.success = success
        self.failureReason = failureReason
        self.steps = steps
        self.fastRepair = fastRepair
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
}

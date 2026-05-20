import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore

// MARK: - Service Lifecycle, Config, TCP, Status, Installer

extension CLIFacade {
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

    @MainActor
    public func currentConfig() async -> String {
        let service = ConfigurationService()
        let config = await service.current()
        return config.content
    }

    @MainActor
    public func configPath() -> String {
        ConfigurationService().configurationPath
    }

    @MainActor
    public func validateConfig() async -> CLIValidationResult {
        let service = ConfigurationService()
        let config = await service.current()
        if config.content.isEmpty {
            return CLIValidationResult(isValid: false, errors: ["No configuration generated yet. Run 'keypath apply' first."])
        }
        let result = await service.validateConfiguration(config.content)
        return CLIValidationResult(isValid: result.isValid, errors: result.errors)
    }

    public func applyConfiguration() async throws -> CLIApplyResult {
        let collections = await RuleCollectionStore.shared.loadCollections()
        let customRules = await CustomRulesStore.shared.loadRules()
        let enabledCount = collections.filter(\.isEnabled).count

        let service = await MainActor.run { ConfigurationService() }
        try await service.saveConfiguration(
            ruleCollections: collections,
            customRules: customRules
        )

        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        let client = KanataTCPClient(port: port)
        let result = await client.reloadConfig()
        let reloadSuccess = if case .success = result {
            true
        } else {
            false
        }

        let changeset = CLIApplyChangeset(
            enabledCollections: collections.filter(\.isEnabled).map(\.name),
            disabledCollections: collections.filter { !$0.isEnabled }.map(\.name),
            customRules: customRules.filter(\.isEnabled).map { "\($0.input) → \($0.action.outputString)" }
        )

        return CLIApplyResult(
            collectionsCount: collections.count,
            enabledCount: enabledCount,
            customRulesCount: customRules.count,
            reloadSuccess: reloadSuccess,
            changeset: changeset
        )
    }

    func tcpClient() async -> KanataTCPClient {
        let port = await MainActor.run { PreferencesService.shared.tcpServerPort }
        return KanataTCPClient(port: port)
    }

    public func tcpCheckHealth() async -> Bool {
        let client = await tcpClient()
        return await client.checkServerStatus()
    }

    public func tcpGetLayers() async throws -> [String] {
        let client = await tcpClient()
        return try await client.requestLayerNames()
    }

    public func tcpReload() async -> Bool {
        let client = await tcpClient()
        let result = await client.reloadConfig()
        if case .success = result { return true }
        return false
    }

    public func tcpGetHrmStats() async throws -> CLIHrmStats {
        let client = await tcpClient()
        let stats = try await client.requestHrmStats()
        return CLIHrmStats(
            totalDecisions: stats.decisionsTotal,
            tapCount: stats.tapCount,
            holdCount: stats.holdCount
        )
    }

    public func tcpResetHrmStats() async throws {
        let client = await tcpClient()
        try await client.resetHrmStats()
    }

    public func tcpChangeLayer(_ layerName: String) async -> Bool {
        let client = await tcpClient()
        let result = await client.changeLayer(layerName)
        if case .success = result { return true }
        return false
    }

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

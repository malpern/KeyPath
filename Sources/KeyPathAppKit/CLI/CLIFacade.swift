import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathWizardCore

/// Public facade exposing KeyPathAppKit internals for the CLI binary.
/// This is the stable API boundary between the CLI and the app library.
public struct CLIFacade: Sendable {
    public init() {}

    // MARK: - Custom Rules

    public func loadCustomRules() async -> [CLICustomRule] {
        let rules = await CustomRulesStore.shared.loadRules()
        return rules.map { CLICustomRule(input: $0.input, output: $0.output, behavior: $0.behavior.map(Self.describeBehavior)) }
    }

    private static func describeBehavior(_ behavior: MappingBehavior) -> String {
        switch behavior {
        case let .dualRole(d):
            "tap-hold: tap=\(d.tapAction), hold=\(d.holdAction), timeout=\(d.tapTimeout)ms"
        case .tapOrTapDance(.tap):
            "tap"
        case let .tapOrTapDance(.tapDance(td)):
            "tap-dance: \(td.steps.map(\.action).joined(separator: ", "))"
        case let .macro(m):
            "macro: \(m.text ?? m.outputs.joined(separator: " "))"
        case let .chord(c):
            "chord: \(c.keys.joined(separator: "+")) → \(c.output)"
        }
    }

    /// Add a simple key remap. Returns `true` if an existing mapping for the input key was replaced.
    @discardableResult
    public func addSimpleRemap(input: String, output: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
        rules.removeAll { $0.input == input }
        let rule = CustomRule(input: input, output: output)
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
        return hadExisting
    }

    /// Add a tap-hold remap. Returns `true` if an existing mapping for the input key was replaced.
    @discardableResult
    public func addTapHoldRemap(input: String, tap: String, hold: String, timeout: Int = 200) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
        rules.removeAll { $0.input == input }
        let rule = CustomRule(
            input: input,
            output: tap,
            behavior: .dualRole(DualRoleBehavior(
                tapAction: tap,
                holdAction: hold,
                tapTimeout: timeout
            ))
        )
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
        return hadExisting
    }

    public func removeRemap(input: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let before = rules.count
        rules.removeAll { $0.input == input }
        if rules.count == before { return false }
        try await CustomRulesStore.shared.saveRules(rules)
        return true
    }

    // MARK: - Rule Collections

    public func loadRuleCollections() async -> [CLIRuleCollection] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        return collections.map { CLIRuleCollection(from: $0) }
    }

    /// Enable a collection by name or ID. Returns the name, or nil if not found. Throws on ambiguous match.
    public func enableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        collections[index].isEnabled = true
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    /// Disable a collection by name or ID. Returns the name, or nil if not found. Throws on ambiguous match.
    public func disableCollection(nameOrId: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        collections[index].isEnabled = false
        try await RuleCollectionStore.shared.saveCollections(collections)
        return collections[index].name
    }

    /// Show a collection by name or ID. Returns nil if not found. Throws on ambiguous match.
    public func showCollection(nameOrId: String) async throws -> CLIRuleCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIRuleCollection(from: collections[index])
    }

    // MARK: - Configuration

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

    /// Validate configuration content using kanata --check.
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

    // MARK: - Apply Pipeline

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

        return CLIApplyResult(
            collectionsCount: collections.count,
            enabledCount: enabledCount,
            customRulesCount: customRules.count,
            reloadSuccess: reloadSuccess
        )
    }

    // MARK: - TCP

    private func tcpClient() async -> KanataTCPClient {
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

    // MARK: - Status

    /// ⚠️ inspectSystem() calls SMAppService.status which does synchronous IPC —
    /// can take 10-30s under launchd load. Callers should be aware of potential latency.
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

    // MARK: - Installer Operations

    /// Run install via InstallerEngine. Requires privileged helper.
    @MainActor
    public func runInstall() async -> CLIInstallerReport {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .install, using: broker)
        return CLIInstallerReport(from: report)
    }

    /// Run repair via InstallerEngine.
    @MainActor
    public func runRepair() async -> CLIInstallerReport {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.run(intent: .repair, using: broker)
        return CLIInstallerReport(from: report)
    }

    /// Run uninstall via InstallerEngine.
    @MainActor
    public func runUninstall(deleteConfig: Bool) async -> CLIInstallerReport {
        let engine = InstallerEngine()
        let broker = PrivilegeBroker()
        let report = await engine.uninstall(deleteConfig: deleteConfig, using: broker)
        return CLIInstallerReport(from: report)
    }

    /// Inspect system and generate an install plan without executing it.
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

    // MARK: - Key Validation

    /// Validate a key name against the Kanata key set. Returns the canonical form, or nil if invalid.
    public func validateKey(_ key: String) -> String? {
        guard CustomRuleValidator.isValidKey(key) else { return nil }
        return CustomRuleValidator.normalizeKey(key)
    }

    // MARK: - Helpers

    /// Resolve a collection by name or UUID. Returns nil if not found. Throws `AmbiguousCollectionMatch` on multiple matches.
    func resolveCollectionIndex(nameOrId: String, in collections: [RuleCollection]) throws -> Int? {
        // Exact UUID match
        if let index = collections.firstIndex(where: { $0.id.uuidString == nameOrId }) {
            return index
        }

        // Exact name match (case-insensitive)
        let exactMatches = collections.enumerated().filter {
            $0.element.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 {
            return exactMatches[0].offset
        }
        if exactMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: exactMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) },
                hint: "Multiple collections share this name. Use the ID to disambiguate."
            )
        }

        // Substring match as fallback
        let substringMatches = collections.enumerated().filter {
            $0.element.name.localizedCaseInsensitiveContains(nameOrId)
        }
        if substringMatches.count == 1 {
            return substringMatches[0].offset
        }
        if substringMatches.count > 1 {
            throw AmbiguousCollectionMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.element.name, id: $0.element.id.uuidString) }
            )
        }

        return nil
    }
}

/// Thrown when a collection name/ID query matches multiple collections.
public struct AmbiguousCollectionMatch: Error, CustomStringConvertible {
    public struct Match: Sendable {
        public let name: String
        public let id: String
    }

    public let query: String
    public let matches: [Match]
    public let hint: String

    public init(query: String, matches: [Match], hint: String = "Use the full name or ID to disambiguate.") {
        self.query = query
        self.matches = matches
        self.hint = hint
    }

    public var description: String {
        var lines = ["Found \(matches.count) collections matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Version

/// Shared version constant for the CLI binary.
/// Reads from the KeyPath.app bundle, checking /Applications and ~/Applications,
/// falling back to a hardcoded value.
public enum CLIVersion {
    public static let current: String = {
        let candidates = [
            "/Applications/KeyPath.app",
            NSString("~/Applications/KeyPath.app").expandingTildeInPath
        ]
        for path in candidates {
            if let bundle = Bundle(path: path),
               let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            {
                return version
            }
        }
        return "1.0.0"
    }()
}

// MARK: - Public CLI Types

public struct CLICustomRule: Codable, Sendable {
    public let input: String
    public let output: String
    public let behavior: String?
}

public struct CLIRuleCollection: Codable, Sendable {
    public let id: String
    public let name: String
    public let isEnabled: Bool
    public let mappingCount: Int
    public let summary: String

    public init(from collection: RuleCollection) {
        id = collection.id.uuidString
        name = collection.name
        isEnabled = collection.isEnabled
        mappingCount = collection.mappings.count
        summary = collection.summary
    }
}

public struct CLIApplyResult: Codable, Sendable {
    public let collectionsCount: Int
    public let enabledCount: Int
    public let customRulesCount: Int
    public let reloadSuccess: Bool
}

public struct CLIHrmStats: Codable, Sendable {
    public let totalDecisions: Int
    public let tapCount: Int
    public let holdCount: Int
}

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

public struct CLIValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let errors: [String]
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

// MARK: - Stderr Helper

/// Write a diagnostic message to stderr. Use for errors and warnings so stdout stays clean for scripts.
public func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

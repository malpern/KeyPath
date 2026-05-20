import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore

/// Public facade exposing KeyPathAppKit internals for the CLI binary.
/// This is the stable API boundary between the CLI and the app library.
public struct CLIFacade: Sendable {
    public init() {}

    // MARK: - Custom Rules

    public func loadCustomRules() async -> [CLICustomRule] {
        let rules = await CustomRulesStore.shared.loadRules()
        return rules.map { CLICustomRule(input: $0.input, output: $0.action.outputString, behavior: $0.behavior.map(Self.describeBehavior)) }
    }

    private static func describeBehavior(_ behavior: MappingBehavior) -> String {
        switch behavior {
        case let .dualRole(d):
            "tap-hold: tap=\(d.tapActionString), hold=\(d.holdActionString), timeout=\(d.tapTimeout)ms"
        case .tapOrTapDance(.tap):
            "tap"
        case let .tapOrTapDance(.tapDance(td)):
            "tap-dance: \(td.steps.map(\.actionString).joined(separator: ", "))"
        case let .macro(m):
            "macro: \(m.text ?? m.outputs.joined(separator: " "))"
        case let .chord(c):
            "chord: \(c.keys.joined(separator: "+")) → \(c.outputString)"
        }
    }

    /// Add a simple key remap. Returns `true` if an existing mapping for the input key was replaced.
    @discardableResult
    public func addSimpleRemap(input: String, output: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
        rules.removeAll { $0.input == input }
        let rule = CustomRule(input: input, action: .keystroke(key: output))
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
            action: .keystroke(key: tap),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: tap),
                holdAction: .keystroke(key: hold),
                tapTimeout: timeout
            ))
        )
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
        return hadExisting
    }

    /// Add a rule with full KeyAction and optional MappingBehavior. Supports all 13 action variants.
    public func addRule(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior? = nil,
        shiftedOutput: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        targetLayer: String? = nil,
        deviceOverrides: [DeviceKeyOverride]? = nil,
        onConflict: CLIConflictStrategy = .fail
    ) async throws -> RuleAddResult {
        var rules = await CustomRulesStore.shared.loadRules()
        let existingIndex = rules.firstIndex(where: { $0.input == input })

        if let existingIndex {
            switch onConflict {
            case .fail:
                throw CLIConflictError(input: input)
            case .skip:
                return .skipped
            case .replace:
                rules.removeAll { $0.input == input }
            case .merge:
                let existing = rules[existingIndex]
                let merged = try Self.mergeRules(existing: existing, newAction: action, newBehavior: behavior)
                rules[existingIndex] = merged
                try await CustomRulesStore.shared.saveRules(rules)
                return .merged(CLIRuleDetail(from: merged))
            }
        }

        let layer: RuleCollectionLayer = if let targetLayer {
            Self.parseLayer(targetLayer)
        } else {
            .base
        }

        let rule = CustomRule(
            title: title ?? "",
            input: input,
            action: action,
            shiftedOutput: shiftedOutput,
            notes: notes,
            behavior: behavior,
            targetLayer: layer,
            deviceOverrides: deviceOverrides
        )
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)

        let detail = CLIRuleDetail(from: rule)
        return existingIndex != nil ? .replaced(detail) : .created(detail)
    }

    /// List all custom rules with full detail.
    public func listRules(enabledOnly: Bool = false) async -> [CLIRuleDetail] {
        let rules = await CustomRulesStore.shared.loadRules()
        let filtered = enabledOnly ? rules.filter(\.isEnabled) : rules
        return filtered.map { CLIRuleDetail(from: $0) }
    }

    /// Show a single rule by input key. Returns nil if not found.
    public func showRule(input: String) async -> CLIRuleDetail? {
        let rules = await CustomRulesStore.shared.loadRules()
        guard let rule = rules.first(where: { $0.input == input }) else { return nil }
        return CLIRuleDetail(from: rule)
    }

    public func removeRemap(input: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let before = rules.count
        rules.removeAll { $0.input == input }
        if rules.count == before { return false }
        try await CustomRulesStore.shared.saveRules(rules)
        return true
    }

    /// Enable a rule by input key. Returns the rule's display title, or nil if not found.
    public func enableRule(input: String) async throws -> String? {
        var rules = await CustomRulesStore.shared.loadRules()
        guard let index = rules.firstIndex(where: { $0.input.caseInsensitiveCompare(input) == .orderedSame }) else {
            return nil
        }
        rules[index].isEnabled = true
        try await CustomRulesStore.shared.saveRules(rules)
        return rules[index].displayTitle
    }

    /// Disable a rule by input key. Returns the rule's display title, or nil if not found.
    public func disableRule(input: String) async throws -> String? {
        var rules = await CustomRulesStore.shared.loadRules()
        guard let index = rules.firstIndex(where: { $0.input.caseInsensitiveCompare(input) == .orderedSame }) else {
            return nil
        }
        rules[index].isEnabled = false
        try await CustomRulesStore.shared.saveRules(rules)
        return rules[index].displayTitle
    }

    private static func parseLayer(_ name: String) -> RuleCollectionLayer {
        switch name.lowercased() {
        case "base": .base
        case "nav", "navigation": .navigation
        default: .custom(name)
        }
    }

    static func mergeRules(existing: CustomRule, newAction: KeyAction, newBehavior: MappingBehavior?) throws -> CustomRule {
        let existingIsSimple = existing.behavior == nil
        let newIsSimple = newBehavior == nil

        if existingIsSimple && newIsSimple {
            throw CLIMergeError(
                input: existing.input,
                reason: "both rules are simple remaps with different outputs — ambiguous"
            )
        }

        var merged = existing

        if existingIsSimple, case let .dualRole(newDual) = newBehavior {
            // Existing simple remap becomes tap, new hold action stays
            merged.behavior = .dualRole(DualRoleBehavior(
                tapAction: existing.action,
                holdAction: newDual.holdAction,
                tapTimeout: newDual.tapTimeout,
                holdTimeout: newDual.holdTimeout,
                activateHoldOnOtherKey: newDual.activateHoldOnOtherKey
            ))
            merged.action = existing.action
            return merged
        }

        if case .dualRole(var existingDual) = existing.behavior, newIsSimple {
            // Existing tap-hold keeps hold, new simple remap updates tap
            existingDual.tapAction = newAction
            merged.behavior = .dualRole(existingDual)
            merged.action = newAction
            return merged
        }

        if case let .dualRole(existingDual) = existing.behavior,
           case let .dualRole(newDual) = newBehavior
        {
            // Both tap-hold: new values override
            merged.behavior = .dualRole(DualRoleBehavior(
                tapAction: newDual.tapAction,
                holdAction: newDual.holdAction,
                tapTimeout: newDual.tapTimeout,
                holdTimeout: existingDual.holdTimeout,
                activateHoldOnOtherKey: newDual.activateHoldOnOtherKey
            ))
            merged.action = newDual.tapAction
            return merged
        }

        throw CLIMergeError(
            input: existing.input,
            reason: "incompatible behavior types cannot be merged"
        )
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
        if let owner = await InstalledPackTracker.shared.packManagingCollection(collections[index].id) {
            throw PackManagedCollectionError(
                collectionName: collections[index].name,
                packName: owner.packName,
                packID: owner.packID
            )
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
        if let owner = await InstalledPackTracker.shared.packManagingCollection(collections[index].id) {
            throw PackManagedCollectionError(
                collectionName: collections[index].name,
                packName: owner.packName,
                packID: owner.packID
            )
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

    /// Create a new empty collection.
    public func createCollection(name: String, category: String?, summary: String?) async throws -> CLIRuleCollection {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let cat: RuleCollectionCategory = if let category {
            RuleCollectionCategory(rawValue: category) ?? .custom
        } else {
            .custom
        }
        let collection = RuleCollection(
            name: name,
            summary: summary ?? "",
            category: cat,
            mappings: []
        )
        collections.append(collection)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: collection)
    }

    /// Rename a collection. Returns the old name, or nil if not found.
    public func renameCollection(nameOrId: String, newName: String) async throws -> String? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        let oldName = collections[index].name
        collections[index].name = newName
        try await RuleCollectionStore.shared.saveCollections(collections)
        return oldName
    }

    /// Delete a collection. Returns true if deleted, false if not found.
    public func deleteCollection(nameOrId: String) async throws -> Bool {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return false
        }
        collections.remove(at: index)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return true
    }

    /// Duplicate a collection with an optional new name.
    public func duplicateCollection(nameOrId: String, newName: String?) async throws -> CLIRuleCollection? {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        var duplicate = collections[index]
        duplicate = RuleCollection(
            name: newName ?? "\(duplicate.name) (Copy)",
            summary: duplicate.summary,
            category: duplicate.category,
            mappings: duplicate.mappings,
            isEnabled: false
        )
        collections.insert(duplicate, at: index + 1)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: duplicate)
    }

    /// Reorder a collection to a new position (0-indexed).
    public func reorderCollection(nameOrId: String, position: Int) async throws -> Bool {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return false
        }
        let collection = collections.remove(at: index)
        let targetIndex = min(max(0, position), collections.count)
        collections.insert(collection, at: targetIndex)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return true
    }

    // MARK: - Export / Import

    /// Export a single collection as portable JSON.
    public func exportCollection(nameOrId: String) async throws -> CLIExportedCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIExportedCollection(from: collections[index])
    }

    /// Export all collections as portable JSON.
    public func exportAllCollections() async -> [CLIExportedCollection] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        return collections.map { CLIExportedCollection(from: $0) }
    }

    /// Import a collection from portable JSON. Returns the imported collection info.
    public func importCollection(_ exported: CLIExportedCollection, onConflict: CLIConflictStrategy = .fail) async throws -> CLIRuleCollection {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let existingIndex = collections.firstIndex(where: { $0.name == exported.name })

        if let existingIndex {
            switch onConflict {
            case .fail:
                throw AmbiguousCollectionMatch(
                    query: exported.name,
                    matches: [.init(name: collections[existingIndex].name, id: collections[existingIndex].id.uuidString)],
                    hint: "Use --on-conflict=replace to overwrite or --on-conflict=skip to no-op"
                )
            case .skip:
                return CLIRuleCollection(from: collections[existingIndex])
            case .replace, .merge:
                collections.remove(at: existingIndex)
            }
        }

        let collection = exported.toRuleCollection()
        collections.append(collection)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: collection)
    }

    // MARK: - Karabiner Import

    /// Parse a Karabiner-Elements configuration and return importable collections.
    /// Handles both full karabiner.json and standalone complex_modifications rule files.
    public func importFromKarabiner(data: Data, collectionName: String?, profileIndex: Int?) throws -> CLIKarabinerImportResult {
        let service = KarabinerConverterService()

        let result: KarabinerConversionResult
        do {
            result = try service.convert(data: data, profileIndex: profileIndex)
        } catch {
            if let complexResult = try? convertComplexModsFile(data: data, service: service) {
                result = complexResult
            } else {
                throw error
            }
        }

        let exportedCollections: [CLIExportedCollection]
        if let name = collectionName {
            let allMappings = result.collections.flatMap(\.mappings)
            let merged = RuleCollection(
                name: name,
                summary: "Imported from Karabiner profile: \(result.profileName)",
                category: .custom,
                mappings: allMappings
            )
            exportedCollections = [CLIExportedCollection(from: merged)]
        } else {
            exportedCollections = result.collections.map { CLIExportedCollection(from: $0) }
        }

        var warnings = result.warnings

        if !result.appKeymaps.isEmpty {
            let count = result.appKeymaps.map(\.overrides.count).reduce(0, +)
            warnings.append("\(count) app-specific override(s) found -- use the GUI to configure app keymaps")
        }

        if !result.launcherMappings.isEmpty {
            warnings.append("\(result.launcherMappings.count) launcher mapping(s) found -- use the GUI to configure launcher shortcuts")
        }

        let skipped = result.skippedRules.map {
            CLISkippedRule(description: $0.description, reason: $0.reason)
        }

        return CLIKarabinerImportResult(
            profileName: result.profileName,
            collections: exportedCollections,
            skippedRules: skipped,
            warnings: warnings
        )
    }

    /// List profiles available in a Karabiner configuration file.
    public func listKarabinerProfiles(data: Data) throws -> [CLIKarabinerProfile] {
        let service = KarabinerConverterService()
        let profiles = try service.getProfiles(from: data)
        return profiles.map {
            CLIKarabinerProfile(name: $0.name, index: $0.index, isSelected: $0.isSelected)
        }
    }

    private func convertComplexModsFile(data: Data, service: KarabinerConverterService) throws -> KarabinerConversionResult {
        struct ComplexModsFile: Decodable {
            let title: String?
            let rules: [KarabinerRule]
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["rules"] != nil
        else {
            throw KarabinerImportError.invalidJSON("Not a recognized Karabiner format")
        }

        let title = json["title"] as? String ?? "Imported Rules"
        let wrapped: [String: Any] = [
            "profiles": [[
                "name": title,
                "selected": true,
                "complex_modifications": json,
            ]],
        ]

        let wrappedData = try JSONSerialization.data(withJSONObject: wrapped)
        return try service.convert(data: wrappedData, profileIndex: 0)
    }

    // MARK: - Simulate

    /// Simulate a key sequence and return structured events.
    /// Uses the real SimulatorService by default, or an injected provider for tests.
    public func simulate(
        keys: [CLISimulatorKeyTap],
        configPath: String?,
        simulatorProvider: CLISimulatorProvider? = nil
    ) async throws -> CLISimulationResult {
        let config: String
        if let configPath {
            config = configPath
        } else {
            config = await MainActor.run { ConfigurationService().configurationPath }
        }

        let provider = simulatorProvider ?? RealSimulatorProvider()
        return try await provider.simulate(taps: keys, configPath: config)
    }

    // MARK: - Layer CRUD

    /// Get all layers defined by rule collections (unique targetLayer values).
    public func listDefinedLayers() async -> [String] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        var layers = Set<String>()
        layers.insert("base")
        for collection in collections {
            layers.insert(collection.targetLayer.kanataName)
        }
        return layers.sorted()
    }

    /// Create a layer by creating an empty collection targeting it.
    public func createLayer(name: String) async throws -> CLIRuleCollection {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let layer: RuleCollectionLayer = switch name.lowercased() {
        case "base": .base
        case "nav", "navigation": .navigation
        default: .custom(name)
        }
        let collection = RuleCollection(
            name: "\(name) Layer",
            summary: "Rules for the \(name) layer",
            category: .layers,
            mappings: [],
            targetLayer: layer
        )
        collections.append(collection)
        try await RuleCollectionStore.shared.saveCollections(collections)
        return CLIRuleCollection(from: collection)
    }

    /// Delete all collections targeting a layer. Returns count of deleted collections.
    public func deleteLayer(name: String) async throws -> Int {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let targetName = Self.parseLayer(name).kanataName
        let before = collections.count
        collections.removeAll { $0.targetLayer.kanataName == targetName }
        let removed = before - collections.count
        if removed > 0 {
            try await RuleCollectionStore.shared.saveCollections(collections)
        }
        return removed
    }

    /// Rename a layer by updating all collections that target it.
    public func renameLayer(oldName: String, newName: String) async throws -> Int {
        var collections = await RuleCollectionStore.shared.loadCollections()
        let oldLayerName = Self.parseLayer(oldName).kanataName
        let newLayer = Self.parseLayer(newName)
        var updated = 0
        for i in collections.indices {
            if collections[i].targetLayer.kanataName == oldLayerName {
                collections[i].targetLayer = newLayer
                updated += 1
            }
        }
        if updated > 0 {
            try await RuleCollectionStore.shared.saveCollections(collections)
        }
        return updated
    }

    // MARK: - Service Lifecycle

    /// Start the Kanata service via launchctl kickstart.
    public func startService() async -> Bool {
        do {
            try await SubprocessRunner.shared.launchctl("kickstart", ["system/com.keypath.kanata"])
            return true
        } catch {
            return false
        }
    }

    /// Stop the Kanata service via launchctl kill.
    public func stopService() async -> Bool {
        do {
            try await SubprocessRunner.shared.launchctl("kill", ["SIGTERM", "system/com.keypath.kanata"])
            return true
        } catch {
            return false
        }
    }

    /// Restart the Kanata service (stop + start).
    public func restartService() async -> Bool {
        _ = await stopService()
        try? await Task.sleep(nanoseconds: 500_000_000)
        return await startService()
    }

    /// Read the last N lines from the debug log.
    public func serviceLogs(lines: Int = 50) -> [String] {
        let logPath = NSString("~/Library/Logs/KeyPath/keypath-debug.log").expandingTildeInPath
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return []
        }
        let allLines = content.components(separatedBy: .newlines)
        return Array(allLines.suffix(lines))
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

// MARK: - Phase 1A Rule Detail Types

public struct CLIRuleDetail: Codable, Sendable {
    public let input: String
    public let action: KeyAction
    public let behavior: MappingBehavior?
    public let shiftedOutput: String?
    public let title: String?
    public let notes: String?
    public let targetLayer: String
    public let deviceOverrides: [CLIDeviceOverride]?
    public let isEnabled: Bool
    public let createdAt: Date

    public init(from rule: CustomRule) {
        input = rule.input
        action = rule.action
        behavior = rule.behavior
        shiftedOutput = rule.shiftedOutput
        title = rule.title.isEmpty ? nil : rule.title
        notes = rule.notes
        targetLayer = rule.targetLayer.kanataName
        deviceOverrides = rule.deviceOverrides?.map { CLIDeviceOverride(from: $0) }
        isEnabled = rule.isEnabled
        createdAt = rule.createdAt
    }

    public static func dryRunPreview(
        input: String,
        action: KeyAction?,
        behavior: MappingBehavior?,
        shiftedOutput: String?,
        title: String?,
        notes: String?,
        targetLayer: String?
    ) -> CLIRuleDetail {
        CLIRuleDetail(
            input: input,
            action: action ?? .empty,
            behavior: behavior,
            shiftedOutput: shiftedOutput,
            title: title,
            notes: notes,
            targetLayer: targetLayer ?? "base",
            deviceOverrides: nil,
            isEnabled: true,
            createdAt: Date()
        )
    }

    public init(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior?,
        shiftedOutput: String?,
        title: String?,
        notes: String?,
        targetLayer: String,
        deviceOverrides: [CLIDeviceOverride]?,
        isEnabled: Bool,
        createdAt: Date
    ) {
        self.input = input
        self.action = action
        self.behavior = behavior
        self.shiftedOutput = shiftedOutput
        self.title = title
        self.notes = notes
        self.targetLayer = targetLayer
        self.deviceOverrides = deviceOverrides
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

public struct CLIDeviceOverride: Codable, Sendable {
    public let deviceHash: String
    public let action: KeyAction
    public let behavior: MappingBehavior?

    public init(from override: DeviceKeyOverride) {
        deviceHash = override.deviceHash
        action = override.output
        behavior = override.behavior
    }
}

public enum RuleAddResult: Codable, Sendable {
    case created(CLIRuleDetail)
    case replaced(CLIRuleDetail)
    case merged(CLIRuleDetail)
    case skipped

    private enum CodingKeys: String, CodingKey {
        case status
        case rule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "created":
            let rule = try container.decode(CLIRuleDetail.self, forKey: .rule)
            self = .created(rule)
        case "replaced":
            let rule = try container.decode(CLIRuleDetail.self, forKey: .rule)
            self = .replaced(rule)
        case "merged":
            let rule = try container.decode(CLIRuleDetail.self, forKey: .rule)
            self = .merged(rule)
        case "skipped":
            self = .skipped
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown status: \(status)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .created(rule):
            try container.encode("created", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case let .replaced(rule):
            try container.encode("replaced", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case let .merged(rule):
            try container.encode("merged", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case .skipped:
            try container.encode("skipped", forKey: .status)
        }
    }
}

public enum CLIConflictStrategy: String, Sendable {
    case fail
    case replace
    case skip
    case merge
}

public struct CLIMergeError: Error, CustomStringConvertible {
    public let input: String
    public let reason: String
    public var description: String { "Cannot merge rules for '\(input)': \(reason)" }
}

public struct CLIConflictError: Error, CustomStringConvertible {
    public let input: String
    public var description: String { "Rule already exists for '\(input)'" }
}

// MARK: - Karabiner Import Types

public struct CLIKarabinerImportResult: Codable, Sendable {
    public let profileName: String
    public let collections: [CLIExportedCollection]
    public let skippedRules: [CLISkippedRule]
    public let warnings: [String]
}

public struct CLISkippedRule: Codable, Sendable {
    public let description: String
    public let reason: String
}

public struct CLIKarabinerProfile: Codable, Sendable {
    public let name: String
    public let index: Int
    public let isSelected: Bool
}

// MARK: - Export/Import Types

public struct CLIExportedCollection: Codable, Sendable {
    public let name: String
    public let summary: String
    public let category: String
    public let isEnabled: Bool
    public let targetLayer: String
    public let mappings: [CLIExportedMapping]

    public init(from collection: RuleCollection) {
        name = collection.name
        summary = collection.summary
        category = collection.category.rawValue
        isEnabled = collection.isEnabled
        targetLayer = collection.targetLayer.kanataName
        mappings = collection.mappings.map { CLIExportedMapping(from: $0) }
    }

    public func toRuleCollection() -> RuleCollection {
        let cat = RuleCollectionCategory(rawValue: category) ?? .custom
        let layer: RuleCollectionLayer = switch targetLayer {
        case "base": .base
        case "nav": .navigation
        default: .custom(targetLayer)
        }
        return RuleCollection(
            name: name,
            summary: summary,
            category: cat,
            mappings: mappings.map { $0.toKeyMapping() },
            isEnabled: isEnabled,
            targetLayer: layer
        )
    }
}

public struct CLIExportedMapping: Codable, Sendable {
    public let input: String
    public let action: KeyAction
    public let shiftedOutput: String?
    public let behavior: MappingBehavior?

    public init(from mapping: KeyMapping) {
        input = mapping.input
        action = mapping.action
        shiftedOutput = mapping.shiftedOutput
        behavior = mapping.behavior
    }

    public func toKeyMapping() -> KeyMapping {
        KeyMapping(input: input, action: action, shiftedOutput: shiftedOutput, behavior: behavior)
    }
}

// MARK: - Simulator Types

public struct CLISimulatorKeyTap: Sendable {
    public let key: String
    public let delayMs: UInt64
    public let isHold: Bool

    public init(key: String, delayMs: UInt64 = 200, isHold: Bool = false) {
        self.key = key
        self.delayMs = delayMs
        self.isHold = isHold
    }
}

public struct CLISimulationResult: Codable, Sendable {
    public let events: [CLISimEvent]
    public let finalLayer: String
    public let durationMs: UInt64
}

public struct CLISimEvent: Codable, Sendable {
    public let type: String
    public let timeMs: UInt64
    public let action: String?
    public let key: String?

    public init(type: String, timeMs: UInt64, action: String? = nil, key: String? = nil) {
        self.type = type
        self.timeMs = timeMs
        self.action = action
        self.key = key
    }
}

/// Protocol for simulator injection — allows mock implementations in tests.
public protocol CLISimulatorProvider: Sendable {
    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult
}

/// Default provider that delegates to the real SimulatorService actor.
struct RealSimulatorProvider: CLISimulatorProvider {
    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult {
        let service = SimulatorService()
        let internalTaps = taps.map {
            SimulatorKeyTap(kanataKey: $0.key, displayLabel: $0.key, delayAfterMs: $0.delayMs, isHold: $0.isHold)
        }
        let result = try await service.simulate(taps: internalTaps, configPath: configPath)
        let events = result.events.map { event -> CLISimEvent in
            switch event {
            case let .input(t, action, key):
                CLISimEvent(type: "input", timeMs: t, action: action.rawValue, key: key)
            case let .output(t, action, key):
                CLISimEvent(type: "output", timeMs: t, action: action.rawValue, key: key)
            case let .layer(t, from, to):
                CLISimEvent(type: "layer", timeMs: t, key: "\(from) -> \(to)")
            case let .unicode(t, char):
                CLISimEvent(type: "unicode", timeMs: t, key: char)
            case let .mouse(t, action, data):
                CLISimEvent(type: "mouse", timeMs: t, action: action.rawValue, key: data)
            }
        }
        return CLISimulationResult(events: events, finalLayer: result.finalLayer ?? "base", durationMs: result.durationMs)
    }
}

// MARK: - Pack Management

extension CLIFacade {
    /// List all available packs with their install status.
    public func listPacks() async -> [CLIPack] {
        let allPacks = PackRegistry.starterKit
        let installed = await InstalledPackTracker.shared.allInstalled()
        let installedMap = Dictionary(uniqueKeysWithValues: installed.map { ($0.packID, $0) })

        return allPacks.map { pack in
            let record = installedMap[pack.id]
            return CLIPack(
                id: pack.id,
                name: pack.name,
                version: pack.version,
                category: pack.category,
                tagline: pack.tagline,
                isInstalled: record != nil,
                installedAt: record?.installedAt
            )
        }
    }

    /// Show detailed information about a pack.
    public func showPack(nameOrId: String) async throws -> CLIPackDetail? {
        guard let pack = try resolvePack(nameOrId: nameOrId) else { return nil }
        let record = await InstalledPackTracker.shared.record(for: pack.id)
        return CLIPackDetail(from: pack, record: record)
    }

    /// Install a pack with optional quick setting overrides.
    @MainActor
    public func installPack(
        nameOrId: String,
        settingValues: [String: Int] = [:],
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        guard let pack = try resolvePack(nameOrId: nameOrId) else {
            throw CLIPackNotFound(query: nameOrId)
        }

        let isAlready = await InstalledPackTracker.shared.isInstalled(packID: pack.id)
        if isAlready {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "already-installed",
                warnings: [],
                quickSettingValues: [:]
            )
        }

        // Validate quick setting keys
        for key in settingValues.keys {
            guard pack.quickSettings.contains(where: { $0.id == key }) else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: key,
                    validKeys: pack.quickSettings.map(\.id)
                )
            }
        }

        if dryRun {
            var warnings: [String] = []
            let installedIDs = Set(await InstalledPackTracker.shared.allInstalled().map(\.packID))
            let suggestions = PackDependencyChecker.suggestions(for: pack.id, installedPackIDs: installedIDs)
            for dep in suggestions {
                let depName = PackRegistry.pack(id: dep.packID)?.name ?? dep.packID
                warnings.append("Enhanced by '\(depName)' — install it for best results")
            }
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "would-install",
                warnings: warnings,
                quickSettingValues: settingValues
            )
        }

        let manager = await makePackManager()
        let record = try await PackInstaller.shared.install(
            pack,
            quickSettingValues: settingValues,
            manager: manager
        )

        var warnings: [String] = []
        let installedIDs = Set(await InstalledPackTracker.shared.allInstalled().map(\.packID))
        let suggestions = PackDependencyChecker.suggestions(for: pack.id, installedPackIDs: installedIDs)
        for dep in suggestions {
            let depName = PackRegistry.pack(id: dep.packID)?.name ?? dep.packID
            warnings.append("Enhanced by '\(depName)' — install it for best results")
        }

        return CLIPackInstallResult(
            packID: pack.id,
            packName: pack.name,
            action: "installed",
            warnings: warnings,
            quickSettingValues: record.quickSettingValues
        )
    }

    /// Uninstall a pack.
    @MainActor
    public func uninstallPack(
        nameOrId: String,
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        guard let pack = try resolvePack(nameOrId: nameOrId) else {
            throw CLIPackNotFound(query: nameOrId)
        }

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: pack.id)
        guard isInstalled else {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "not-installed",
                warnings: [],
                quickSettingValues: [:]
            )
        }

        if dryRun {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "would-uninstall",
                warnings: [],
                quickSettingValues: [:]
            )
        }

        let manager = await makePackManager()
        try await PackInstaller.shared.uninstall(packID: pack.id, manager: manager)

        return CLIPackInstallResult(
            packID: pack.id,
            packName: pack.name,
            action: "uninstalled",
            warnings: [],
            quickSettingValues: [:]
        )
    }

    /// Update quick settings on an installed pack.
    @MainActor
    public func configurePack(
        nameOrId: String,
        settingValues: [String: Int],
        dryRun: Bool = false
    ) async throws -> CLIPackInstallResult {
        guard let pack = try resolvePack(nameOrId: nameOrId) else {
            throw CLIPackNotFound(query: nameOrId)
        }

        let isInstalled = await InstalledPackTracker.shared.isInstalled(packID: pack.id)
        guard isInstalled else {
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "not-installed",
                warnings: ["Pack must be installed before configuring settings."],
                quickSettingValues: [:]
            )
        }

        guard !pack.quickSettings.isEmpty else {
            throw CLIPackSettingError(
                packName: pack.name,
                settingKey: settingValues.keys.first ?? "",
                validKeys: []
            )
        }

        for key in settingValues.keys {
            guard pack.quickSettings.contains(where: { $0.id == key }) else {
                throw CLIPackSettingError(
                    packName: pack.name,
                    settingKey: key,
                    validKeys: pack.quickSettings.map(\.id)
                )
            }
        }

        if dryRun {
            let current = await PackInstaller.shared.quickSettings(for: pack.id)
            var merged = current
            for (k, v) in settingValues { merged[k] = v }
            return CLIPackInstallResult(
                packID: pack.id,
                packName: pack.name,
                action: "would-configure",
                warnings: [],
                quickSettingValues: merged
            )
        }

        let manager = await makePackManager()
        try await PackInstaller.shared.updateQuickSettings(
            packID: pack.id,
            newValues: settingValues,
            manager: manager
        )

        let updatedSettings = await PackInstaller.shared.quickSettings(for: pack.id)

        return CLIPackInstallResult(
            packID: pack.id,
            packName: pack.name,
            action: "configured",
            warnings: [],
            quickSettingValues: updatedSettings
        )
    }

    // MARK: - Pack Name Resolution

    /// Resolve a pack by ID, slug, name, or substring. Returns nil if not found.
    /// Throws `AmbiguousPackMatch` on multiple matches.
    func resolvePack(nameOrId: String) throws -> Pack? {
        let allPacks = PackRegistry.starterKit

        // 1. Exact ID match
        if let pack = allPacks.first(where: { $0.id == nameOrId }) {
            return pack
        }

        // 2. Slug match (strip com.keypath.pack. prefix)
        let prefix = "com.keypath.pack."
        let slugMatches = allPacks.filter { pack in
            guard pack.id.hasPrefix(prefix) else { return false }
            let slug = String(pack.id.dropFirst(prefix.count))
            return slug.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if slugMatches.count == 1 { return slugMatches[0] }
        if slugMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: slugMatches.map { .init(name: $0.name, id: $0.id) },
                hint: "Multiple packs match this slug. Use the full ID to disambiguate."
            )
        }

        // 3. Exact name match (case-insensitive)
        let exactMatches = allPacks.filter {
            $0.name.caseInsensitiveCompare(nameOrId) == .orderedSame
        }
        if exactMatches.count == 1 { return exactMatches[0] }
        if exactMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: exactMatches.map { .init(name: $0.name, id: $0.id) },
                hint: "Multiple packs share this name. Use the ID to disambiguate."
            )
        }

        // 4. Substring fallback
        let substringMatches = allPacks.filter {
            $0.name.localizedCaseInsensitiveContains(nameOrId)
        }
        if substringMatches.count == 1 { return substringMatches[0] }
        if substringMatches.count > 1 {
            throw AmbiguousPackMatch(
                query: nameOrId,
                matches: substringMatches.map { .init(name: $0.name, id: $0.id) }
            )
        }

        return nil
    }

    // MARK: - Pack Manager Helper

    /// Create a lightweight RuleCollectionsManager for install/uninstall.
    /// Loads current state from stores without running full bootstrap (which
    /// would regenerate config unnecessarily).
    @MainActor
    private func makePackManager() async -> RuleCollectionsManager {
        let configService = ConfigurationService()
        let manager = RuleCollectionsManager(
            ruleCollectionStore: .shared,
            customRulesStore: .shared,
            configurationService: configService
        )
        let collections = await RuleCollectionStore.shared.loadCollections()
        let customRules = await CustomRulesStore.shared.loadRules()
        manager.ruleCollections = RuleCollectionDeduplicator.dedupe(collections)
        manager.customRules = customRules
        return manager
    }
}

// MARK: - Pack CLI Types

public struct CLIPack: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let isInstalled: Bool
    public let installedAt: Date?
}

public struct CLIPackDetail: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: String
    public let tagline: String
    public let shortDescription: String
    public let longDescription: String
    public let author: String
    public let isInstalled: Bool
    public let installedAt: Date?
    public let visualOnly: Bool
    public let bindings: [CLIPackBinding]
    public let quickSettings: [CLIPackQuickSetting]
    public let dependencies: [CLIPackDep]
    public let quickSettingValues: [String: Int]

    public init(from pack: Pack, record: InstalledPackRecord?) {
        id = pack.id
        name = pack.name
        version = pack.version
        category = pack.category
        tagline = pack.tagline
        shortDescription = pack.shortDescription
        longDescription = pack.longDescription
        author = pack.author
        isInstalled = record != nil
        installedAt = record?.installedAt
        visualOnly = pack.visualOnly
        bindings = pack.bindings.map { CLIPackBinding(input: $0.input, output: $0.output, holdOutput: $0.holdOutput) }
        quickSettings = pack.quickSettings.map { CLIPackQuickSetting(from: $0) }
        dependencies = pack.dependencies.map { CLIPackDep(from: $0) }
        quickSettingValues = record?.quickSettingValues ?? [:]
    }
}

public struct CLIPackBinding: Codable, Sendable {
    public let input: String
    public let output: String
    public let holdOutput: String?
}

public struct CLIPackQuickSetting: Codable, Sendable {
    public let id: String
    public let label: String
    public let defaultValue: Int
    public let min: Int
    public let max: Int
    public let step: Int
    public let unitSuffix: String

    public init(from setting: PackQuickSetting) {
        id = setting.id
        label = setting.label
        switch setting.kind {
        case let .slider(defaultValue, min, max, step, unitSuffix):
            self.defaultValue = defaultValue
            self.min = min
            self.max = max
            self.step = step
            self.unitSuffix = unitSuffix
        }
    }
}

public struct CLIPackDep: Codable, Sendable {
    public let packID: String
    public let kind: String
    public let description: String?

    public init(from dep: PackDependency) {
        packID = dep.packID
        kind = dep.kind.rawValue
        description = dep.description
    }
}

public struct CLIPackInstallResult: Codable, Sendable {
    public let packID: String
    public let packName: String
    public let action: String
    public let warnings: [String]
    public let quickSettingValues: [String: Int]
}

/// Thrown when a pack name/ID query matches multiple packs.
public struct AmbiguousPackMatch: Error, CustomStringConvertible {
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
        var lines = ["Found \(matches.count) packs matching \"\(query)\":"]
        for match in matches {
            lines.append("  - \(match.name) (id: \(match.id))")
        }
        lines.append(hint)
        return lines.joined(separator: "\n")
    }
}

public struct CLIPackNotFound: Error, CustomStringConvertible {
    public let query: String
    public var description: String { "No pack found matching \"\(query)\"" }
}

public struct CLIPackSettingError: Error, CustomStringConvertible {
    public let packName: String
    public let settingKey: String
    public let validKeys: [String]
    public var description: String {
        if validKeys.isEmpty {
            return "Pack '\(packName)' has no quick settings, but --setting \(settingKey) was provided"
        }
        return "Unknown setting '\(settingKey)' for pack '\(packName)'. Valid keys: \(validKeys.joined(separator: ", "))"
    }
}

public struct PackManagedCollectionError: Error, CustomStringConvertible {
    public let collectionName: String
    public let packName: String
    public let packID: String
    public var description: String {
        let slug = packName.lowercased().replacingOccurrences(of: " ", with: "-")
        return "'\(collectionName)' is managed by pack '\(packName)'. Run 'keypath pack uninstall \(slug)' to release it."
    }
}

// MARK: - Stderr Helper

/// Write a diagnostic message to stderr. Use for errors and warnings so stdout stays clean for scripts.
public func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

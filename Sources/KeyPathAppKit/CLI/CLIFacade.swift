import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathInstallationWizard
import KeyPathWizardCore

/// Public facade exposing KeyPathAppKit internals for the CLI binary.
/// This is the stable API boundary between the CLI and the app library.
///
/// Method groups live in extension files:
/// - CLIFacade+Rules.swift — Custom rules CRUD
/// - CLIFacade+Collections.swift — Rule collections CRUD
/// - CLIFacade+Service.swift — Service lifecycle, config, TCP, status, installer
/// - CLIFacade+Packs.swift — Pack management
public struct CLIFacade: Sendable {
    public init() {}

    // MARK: - Export / Import

    public func exportCollection(nameOrId: String) async throws -> CLIExportedCollection? {
        let collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = try resolveCollectionIndex(nameOrId: nameOrId, in: collections) else {
            return nil
        }
        return CLIExportedCollection(from: collections[index])
    }

    public func exportAllCollections() async -> [CLIExportedCollection] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        return collections.map { CLIExportedCollection(from: $0) }
    }

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

    public func listDefinedLayers() async -> [String] {
        let collections = await RuleCollectionStore.shared.loadCollections()
        var layers = Set<String>()
        layers.insert("base")
        for collection in collections {
            layers.insert(collection.targetLayer.kanataName)
        }
        return layers.sorted()
    }

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

    // MARK: - Key Validation

    public func validateKey(_ key: String) -> String? {
        guard CustomRuleValidator.isValidKey(key) else { return nil }
        return CustomRuleValidator.normalizeKey(key)
    }

    // MARK: - Helpers

    func resolveCollectionIndex(nameOrId: String, in collections: [RuleCollection]) throws -> Int? {
        if let index = collections.firstIndex(where: { $0.id.uuidString == nameOrId }) {
            return index
        }

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

// MARK: - Ambiguous Match Errors

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

public enum CLIVersion {
    public static let current: String = {
        let candidates = [
            "/Applications/KeyPath.app",
            NSString("~/Applications/KeyPath.app").expandingTildeInPath,
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
    public let changeset: CLIApplyChangeset?
}

public struct CLIApplyChangeset: Codable, Sendable {
    public let enabledCollections: [String]
    public let disabledCollections: [String]
    public let customRules: [String]
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
    public let configPath: String?
    public let configBytes: Int?
    public let collectionsCount: Int?
    public let customRulesCount: Int?

    public init(isValid: Bool, errors: [String], configPath: String? = nil, configBytes: Int? = nil, collectionsCount: Int? = nil, customRulesCount: Int? = nil) {
        self.isValid = isValid
        self.errors = errors
        self.configPath = configPath
        self.configBytes = configBytes
        self.collectionsCount = collectionsCount
        self.customRulesCount = customRulesCount
    }
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

// MARK: - Rule Detail Types

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

public protocol CLISimulatorProvider: Sendable {
    func simulate(taps: [CLISimulatorKeyTap], configPath: String) async throws -> CLISimulationResult
}

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

public func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
